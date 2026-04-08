param(
    [string]$BridgeHost = "127.0.0.1",
    [int]$BridgePort = 18790,
    [string]$DeviceId = "godot-bridge-test",
    [string]$MessageText = "",
    [int]$ReceiveTimeoutSeconds = 30,
    [string]$TraceLogPath = "",
    [switch]$TraceSummaryOnly
)

$ErrorActionPreference = "Stop"
$utf8Encoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = $utf8Encoding
try {
    [Console]::InputEncoding = $utf8Encoding
    [Console]::OutputEncoding = $utf8Encoding
}
catch {
}

if (-not $PSBoundParameters.ContainsKey("MessageText")) {
    $MessageText = -join @(
        [char]0x8BF7
        [char]0x81EA
        [char]0x6211
        [char]0x4ECB
        [char]0x7ECD
        [char]0x4E0B
    )
}

$scriptRoot = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $PSScriptRoot
}
elseif (-not [string]::IsNullOrWhiteSpace($MyInvocation.MyCommand.Path)) {
    [System.IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Path)
}
else {
    [System.IO.Directory]::GetCurrentDirectory()
}

if ([string]::IsNullOrWhiteSpace($TraceLogPath)) {
    $TraceLogPath = Join-Path $scriptRoot ("test-bridge-guest.trace.{0}.jsonl" -f (Get-Date).ToString("yyyyMMdd_HHmmss"))
}

$script:TraceSequence = 0

function Get-TraceTimestamp {
    (Get-Date).ToUniversalTime().ToString("o")
}

function Get-TraceTextSummary {
    param(
        [AllowNull()]
        [string]$Text
    )
    if ($null -eq $Text) {
        return $null
    }
    $previewLength = 120
    $preview = $Text
    if ($preview.Length -gt $previewLength) {
        $preview = $preview.Substring(0, $previewLength)
    }
    return [ordered]@{
        length = $Text.Length
        lineCount = ($Text -split "`r?`n").Count
        preview = $preview
        truncated = ($preview.Length -lt $Text.Length)
    }
}

function Convert-TraceValue {
    param(
        [string]$KeyName,
        $Value
    )
    if (-not $TraceSummaryOnly) {
        return $Value
    }
    if ($null -eq $Value) {
        return $null
    }
    if ($Value -is [string]) {
        if (
            $KeyName -match '(?i)(text|message|detail|raw|json|aggregate|final|delta|content)' -or
            $Value.Length -gt 200 -or
            $Value.Contains("`n") -or
            $Value.Contains("`r")
        ) {
            return Get-TraceTextSummary -Text $Value
        }
        return $Value
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in $Value.Keys) {
            $result[$key] = Convert-TraceValue -KeyName ([string]$key) -Value $Value[$key]
        }
        return $result
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = New-Object System.Collections.Generic.List[object]
        foreach ($item in $Value) {
            $items.Add((Convert-TraceValue -KeyName $KeyName -Value $item))
        }
        return @($items.ToArray())
    }
    $properties = @($Value.PSObject.Properties)
    if ($properties.Count -gt 0) {
        $result = [ordered]@{}
        foreach ($property in $properties) {
            $result[$property.Name] = Convert-TraceValue -KeyName $property.Name -Value $property.Value
        }
        return $result
    }
    return $Value
}

function Write-TraceRecord {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Kind,
        [hashtable]$Data = @{}
    )
    $script:TraceSequence++
    $record = [ordered]@{
        ts = Get-TraceTimestamp
        seq = $script:TraceSequence
        kind = $Kind
    }
    if ($TraceSummaryOnly) {
        $record["summaryOnly"] = $true
    }
    foreach ($key in $Data.Keys) {
        $record[$key] = Convert-TraceValue -KeyName $key -Value $Data[$key]
    }
    $line = ($record | ConvertTo-Json -Depth 12 -Compress)
    [System.IO.File]::AppendAllText($TraceLogPath, "$line`n", $utf8Encoding)
}

[System.IO.File]::WriteAllText($TraceLogPath, "", $utf8Encoding)
Write-TraceRecord -Kind "script.start" -Data @{
    bridgeHost = $BridgeHost
    bridgePort = $BridgePort
    deviceId = $DeviceId
    receiveTimeoutSeconds = $ReceiveTimeoutSeconds
    messageText = $MessageText
    traceLogPath = $TraceLogPath
}

function Get-TimeStampText {
    (Get-Date).ToString("HH:mm:ss.fff")
}

function Write-Log {
    param(
        [string]$Category,
        [string]$Text,
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )
    Write-Host "[$(Get-TimeStampText)] [$Category] $Text" -ForegroundColor $Color
}

function Get-ExceptionDetailLines {
    param(
        [Parameter(Mandatory = $true)]
        [System.Exception]$Exception
    )
    $lines = New-Object System.Collections.Generic.List[string]
    $visited = New-Object System.Collections.Generic.HashSet[string]
    $queue = New-Object System.Collections.Generic.Queue[object]
    $queue.Enqueue([pscustomobject]@{
        Exception = $Exception
        Prefix = "root"
    })

    while ($queue.Count -gt 0) {
        $item = $queue.Dequeue()
        $current = $item.Exception
        $prefix = $item.Prefix
        if ($null -eq $current) {
            continue
        }

        $exceptionKey = "{0}:{1}" -f $current.GetType().FullName, $current.Message
        if (-not $visited.Add($exceptionKey)) {
            continue
        }

        $typeName = $current.GetType().FullName
        $messageText = [string]$current.Message
        $classification = "generic_error"
        if ($typeName -match "WebSocketException") {
            $classification = "websocket_exception"
        }
        elseif ($typeName -match "WebException") {
            $classification = "web_request_exception"
        }
        elseif ($typeName -match "TaskCanceledException|TimeoutException" -or $messageText -match "timed out|timeout") {
            $classification = "timeout"
        }
        elseif ($messageText -match "closed|close") {
            $classification = "remote_closed"
        }
        elseif ($messageText -match "socket|Socket") {
            $classification = "socket_closed"
        }

        $lines.Add(("{0} [{1}] {2}: {3}" -f $prefix, $classification, $current.GetType().FullName, $current.Message))

        if ($current -is [System.AggregateException]) {
            $index = 0
            foreach ($inner in $current.InnerExceptions) {
                $queue.Enqueue([pscustomobject]@{
                    Exception = $inner
                    Prefix = "${prefix}.aggregate[$index]"
                })
                $index++
            }
        }

        if ($null -ne $current.InnerException) {
            $queue.Enqueue([pscustomobject]@{
                Exception = $current.InnerException
                Prefix = "${prefix}.inner"
            })
        }
    }

    return ,$lines.ToArray()
}

function Write-Section {
    param([string]$Text)
    Write-Host ""
    Write-Host "[$(Get-TimeStampText)] ==== $Text ====" -ForegroundColor Cyan
    Write-TraceRecord -Kind "section" -Data @{
        text = $Text
    }
}

function Invoke-BridgeGet {
    param([string]$Path)
    $url = "http://$BridgeHost`:$BridgePort$Path"
    try {
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $resp = Invoke-RestMethod -Method Get -Uri $url -TimeoutSec 5
        $watch.Stop()
        Write-Log "HTTP" ("GET {0} -> OK ({1}ms)" -f $Path, $watch.ElapsedMilliseconds) Green
        Write-TraceRecord -Kind "http.get" -Data @{
            path = $Path
            url = $url
            ok = $true
            elapsedMs = $watch.ElapsedMilliseconds
            response = $resp
        }
        $resp | ConvertTo-Json -Depth 8
    }
    catch {
        Write-Log "HTTP" "GET $Path -> FAILED" Red
        Write-Log "HTTP" $_.Exception.Message Yellow
        Write-TraceRecord -Kind "http.get" -Data @{
            path = $Path
            url = $url
            ok = $false
            error = $_.Exception.Message
            detailLines = @(Get-ExceptionDetailLines -Exception $_.Exception)
        }
    }
}

function Get-JsonPropertyValue {
    param(
        [Parameter(Mandatory = $true)]
        $Object,
        [Parameter(Mandatory = $true)]
        [string[]]$Names,
        $Default = $null
    )
    if ($null -eq $Object) {
        return $Default
    }
    foreach ($name in $Names) {
        if ($Object -is [System.Collections.IDictionary] -and $Object.Contains($name)) {
            return $Object[$name]
        }
        $property = $Object.PSObject.Properties[$name]
        if ($null -ne $property) {
            return $property.Value
        }
    }
    return $Default
}

function New-RequestState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequestId,
        [Parameter(Mandatory = $true)]
        [string]$SessionKey
    )
    return [pscustomobject]@{
        RequestId = $RequestId
        SessionKey = $SessionKey
        RunId = ""
        Status = "thinking"
        AggregateText = ""
        FinalText = ""
        ErrorText = ""
        StartedAt = Get-Date
        FirstPacketAt = $null
        FirstDeltaAt = $null
        LastEventAt = $null
        CompletedAt = $null
        IsEnded = $false
    }
}

function Receive-WebSocketEvent {
    param(
        [System.Net.WebSockets.ClientWebSocket]$Socket,
        [int]$TimeoutSeconds = 4
    )
    $buffer = New-Object byte[] 8192
    $builder = New-Object System.Text.StringBuilder
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $cts = [System.Threading.CancellationTokenSource]::new()
    $cts.CancelAfter([TimeSpan]::FromSeconds($TimeoutSeconds))

    if ($Socket.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
        $watch.Stop()
        $cts.Dispose()
        return [pscustomobject]@{
            Status = "socket_not_open"
            Message = $null
            ElapsedMs = $watch.ElapsedMilliseconds
            Detail = "socket state: $($Socket.State)"
            DetailLines = @()
        }
    }

    try {
        while ($true) {
            $segment = New-Object System.ArraySegment[byte] -ArgumentList (, $buffer)
            $result = $Socket.ReceiveAsync($segment, $cts.Token).GetAwaiter().GetResult()

            if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                $watch.Stop()
                return [pscustomobject]@{
                    Status = "closed_by_remote"
                    Message = $null
                    ElapsedMs = $watch.ElapsedMilliseconds
                    Detail = "close frame received"
                    DetailLines = @()
                }
            }
            if ($result.Count -gt 0) {
                $chunk = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
                [void]$builder.Append($chunk)
            }
            if ($result.EndOfMessage) {
                $watch.Stop()
                return [pscustomobject]@{
                    Status = "message"
                    Message = $builder.ToString()
                    ElapsedMs = $watch.ElapsedMilliseconds
                    Detail = ""
                    DetailLines = @()
                    Payload = $null
                }
            }
        }
    }
    catch {
        $watch.Stop()
        $detailLines = Get-ExceptionDetailLines -Exception $_.Exception
        $status = "receive_error"
        $detail = $_.Exception.Message
        if ($cts.IsCancellationRequested) {
            $status = "timeout"
            $detail = "no message received within ${TimeoutSeconds}s"
        }
        return [pscustomobject]@{
            Status = $status
            Message = $null
            ElapsedMs = $watch.ElapsedMilliseconds
            Detail = $detail
            DetailLines = $detailLines
            Payload = $null
        }
    }
    finally {
        $cts.Dispose()
    }
}

function Convert-EventResultToJson {
    param($Result)
    if ($Result.Status -ne "message" -or [string]::IsNullOrWhiteSpace($Result.Message)) {
        return $Result
    }
    try {
        $payload = $Result.Message | ConvertFrom-Json
        $Result.Payload = $payload
        return $Result
    }
    catch {
        $Result.Status = "json_parse_error"
        $Result.Detail = $_.Exception.Message
        $Result.DetailLines = Get-ExceptionDetailLines -Exception $_.Exception
        return $Result
    }
}

function Get-BridgeEventType {
    param($Payload)
    $typeValue = [string](Get-JsonPropertyValue -Object $Payload -Names @("type") -Default "")
    $eventValue = [string](Get-JsonPropertyValue -Object $Payload -Names @("event") -Default "")
    if ($typeValue.Trim() -eq "event" -and -not [string]::IsNullOrWhiteSpace($eventValue)) {
        return $eventValue.Trim()
    }
    if (-not [string]::IsNullOrWhiteSpace($typeValue)) {
        return $typeValue.Trim()
    }
    return $eventValue.Trim()
}

function Get-BridgeEventPayload {
    param($Payload)
    return Get-JsonPropertyValue -Object $Payload -Names @("payload", "data") -Default $null
}

function Get-BridgeEventText {
    param($Payload)
    $payloadObject = Get-BridgeEventPayload -Payload $Payload
    $textValue = $null
    if ($null -ne $payloadObject) {
        $textValue = Get-JsonPropertyValue -Object $payloadObject -Names @("delta", "text", "content", "message") -Default $null
    }
    if ($null -eq $textValue) {
        $textValue = Get-JsonPropertyValue -Object $Payload -Names @("delta", "text", "content", "message") -Default ""
    }
    if ($textValue -isnot [string]) {
        $textValue = [string]$textValue
    }
    return $textValue
}

function Get-BridgeEventError {
    param($Payload)
    $payloadObject = Get-BridgeEventPayload -Payload $Payload
    $errorValue = $null
    if ($null -ne $payloadObject) {
        $errorValue = Get-JsonPropertyValue -Object $payloadObject -Names @("error", "message", "text") -Default $null
    }
    if ($null -eq $errorValue) {
        $errorValue = Get-JsonPropertyValue -Object $Payload -Names @("error", "message", "text") -Default ""
    }
    if ($errorValue -isnot [string]) {
        $errorValue = [string]$errorValue
    }
    return $errorValue
}

function Get-TraceRawPayloadText {
    param($Payload)
    if ($null -eq $Payload) {
        return ""
    }
    return Get-BridgeEventText -Payload $Payload
}

function Update-RequestStateFromPayload {
    param(
        [Parameter(Mandatory = $true)]
        $State,
        [Parameter(Mandatory = $true)]
        $Payload,
        [int]$ElapsedMs = 0
    )
    $eventType = Get-BridgeEventType -Payload $Payload
    $incomingRequestId = [string](Get-JsonPropertyValue -Object $Payload -Names @("requestId", "request_id") -Default "")
    if (-not [string]::IsNullOrWhiteSpace($incomingRequestId) -and $incomingRequestId -ne $State.RequestId) {
        return [pscustomobject]@{
            Action = "ignore"
            Detail = "unmatched requestId=$incomingRequestId"
            EventType = $eventType
            Delta = ""
        }
    }

    $runId = [string](Get-JsonPropertyValue -Object $Payload -Names @("runId", "run_id") -Default "")
    if (-not [string]::IsNullOrWhiteSpace($runId)) {
        $State.RunId = $runId
    }
    $sessionKey = [string](Get-JsonPropertyValue -Object $Payload -Names @("sessionKey", "session_key") -Default "")
    if (-not [string]::IsNullOrWhiteSpace($sessionKey)) {
        $State.SessionKey = $sessionKey
    }
    $State.LastEventAt = Get-Date
    if ($null -eq $State.FirstPacketAt) {
        $State.FirstPacketAt = $State.LastEventAt
    }

    switch ($eventType) {
        "assistant.delta" {
            $deltaText = Get-BridgeEventText -Payload $Payload
            if ([string]::IsNullOrWhiteSpace($deltaText)) {
                return [pscustomobject]@{
                    Action = "ignore"
                    Detail = "empty delta"
                    EventType = $eventType
                    Delta = ""
                }
            }
            if ($null -eq $State.FirstDeltaAt) {
                $State.FirstDeltaAt = Get-Date
            }
            $State.Status = "streaming"
            $State.AggregateText += $deltaText
            return [pscustomobject]@{
                Action = "delta"
                Detail = $deltaText
                EventType = $eventType
                Delta = $deltaText
            }
        }
        "assistant.final" {
            $finalText = Get-BridgeEventText -Payload $Payload
            if (-not [string]::IsNullOrWhiteSpace($finalText)) {
                $State.AggregateText = $finalText
                $State.FinalText = $finalText
            }
            else {
                $State.FinalText = $State.AggregateText
            }
            $State.Status = "completed"
            $State.IsEnded = $true
            $State.CompletedAt = Get-Date
            return [pscustomobject]@{
                Action = "final"
                Detail = $State.FinalText
                EventType = $eventType
                Delta = ""
            }
        }
        "assistant.error" {
            $errorText = Get-BridgeEventError -Payload $Payload
            if ([string]::IsNullOrWhiteSpace($errorText)) {
                $errorText = "assistant.error"
            }
            $State.ErrorText = $errorText
            $State.Status = "error"
            $State.IsEnded = $true
            $State.CompletedAt = Get-Date
            return [pscustomobject]@{
                Action = "error"
                Detail = $errorText
                EventType = $eventType
                Delta = ""
            }
        }
        "response" {
            $errorText = Get-BridgeEventError -Payload $Payload
            $responseText = Get-BridgeEventText -Payload $Payload
            if (-not [string]::IsNullOrWhiteSpace($errorText)) {
                $State.ErrorText = $errorText
                $State.Status = "error"
                $State.IsEnded = $true
                $State.CompletedAt = Get-Date
                return [pscustomobject]@{
                    Action = "error"
                    Detail = $errorText
                    EventType = $eventType
                    Delta = ""
                }
            }
            $State.AggregateText = $responseText
            $State.FinalText = $responseText
            $State.Status = "completed"
            $State.IsEnded = $true
            $State.CompletedAt = Get-Date
            return [pscustomobject]@{
                Action = "final"
                Detail = $responseText
                EventType = $eventType
                Delta = ""
            }
        }
        default {
            return [pscustomobject]@{
                Action = "ignore"
                Detail = "eventType=$eventType"
                EventType = $eventType
                Delta = ""
            }
        }
    }
}

function Send-WebSocketJson {
    param(
        [System.Net.WebSockets.ClientWebSocket]$Socket,
        [hashtable]$Payload
    )
    $json = $Payload | ConvertTo-Json -Depth 8 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $segment = New-Object System.ArraySegment[byte] -ArgumentList (, $bytes)
    $Socket.SendAsync(
        $segment,
        [System.Net.WebSockets.WebSocketMessageType]::Text,
        $true,
        [Threading.CancellationToken]::None
    ).GetAwaiter().GetResult() | Out-Null
    Write-Log "WS" "SEND $json" Green
    Write-TraceRecord -Kind "ws.send" -Data @{
        socketState = [string]$Socket.State
        payload = $Payload
        json = $json
        raw_payload_text = (Get-TraceRawPayloadText -Payload $Payload)
    }
}

function Show-WebSocketReceiveResult {
    param(
        [string]$Stage,
        $Result
    )
    switch ($Result.Status) {
        "message" {
            Write-Log "WS" "$Stage -> message in $($Result.ElapsedMs)ms :: $($Result.Message)" Yellow
        }
        "timeout" {
            Write-Log "WS" "$Stage -> timeout after $($Result.ElapsedMs)ms :: $($Result.Detail)" DarkYellow
        }
        "closed_by_remote" {
            Write-Log "WS" "$Stage -> remote closed after $($Result.ElapsedMs)ms :: $($Result.Detail)" Magenta
        }
        "socket_not_open" {
            Write-Log "WS" "$Stage -> socket not open after $($Result.ElapsedMs)ms :: $($Result.Detail)" Red
        }
        default {
            Write-Log "WS" "$Stage -> error after $($Result.ElapsedMs)ms :: $($Result.Detail)" Red
        }
    }
    Write-TraceRecord -Kind "ws.receive" -Data @{
        stage = $Stage
        status = $Result.Status
        elapsedMs = $Result.ElapsedMs
        detail = $Result.Detail
        detailLines = @($Result.DetailLines)
        rawMessage = $Result.Message
        payload = $Result.Payload
        raw_payload_text = (Get-TraceRawPayloadText -Payload $Result.Payload)
    }
    foreach ($detailLine in ($Result.DetailLines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        Write-Log "WS" "$Stage detail :: $detailLine" DarkGray
    }
}

function Show-StreamEventResult {
    param(
        [string]$Stage,
        [Parameter(Mandatory = $true)]
        $Result,
        [Parameter(Mandatory = $true)]
        $RequestState
    )
    if ($Result.Status -ne "message") {
        Show-WebSocketReceiveResult -Stage $Stage -Result $Result
        return
    }
    if ($null -eq $Result.Payload) {
        Show-WebSocketReceiveResult -Stage $Stage -Result $Result
        return
    }

    $eventUpdate = Update-RequestStateFromPayload -State $RequestState -Payload $Result.Payload -ElapsedMs $Result.ElapsedMs
    Write-TraceRecord -Kind "stream.event" -Data @{
        stage = $Stage
        action = $eventUpdate.Action
        eventType = $eventUpdate.EventType
        elapsedMs = $Result.ElapsedMs
        detail = $eventUpdate.Detail
        delta = $eventUpdate.Delta
        requestId = $RequestState.RequestId
        sessionKey = $RequestState.SessionKey
        runId = $RequestState.RunId
        aggregateText = $RequestState.AggregateText
        finalText = $RequestState.FinalText
        errorText = $RequestState.ErrorText
        rawMessage = $Result.Message
        payload = $Result.Payload
        raw_payload_text = (Get-TraceRawPayloadText -Payload $Result.Payload)
    }
    switch ($eventUpdate.Action) {
        "delta" {
            Write-Log "STREAM" ("{0} -> delta in {1}ms :: +{2}" -f $Stage, $Result.ElapsedMs, $eventUpdate.Detail) Yellow
            Write-Log "STREAM" ("aggregate[{0}] :: {1}" -f $RequestState.RequestId, $RequestState.AggregateText) DarkYellow
        }
        "final" {
            Write-Log "STREAM" ("{0} -> final in {1}ms :: {2}" -f $Stage, $Result.ElapsedMs, $eventUpdate.Detail) Green
        }
        "error" {
            Write-Log "STREAM" ("{0} -> error in {1}ms :: {2}" -f $Stage, $Result.ElapsedMs, $eventUpdate.Detail) Red
        }
        default {
            $compact = $Result.Message
            Write-Log "STREAM" ("{0} -> ignored event :: {1}" -f $Stage, $compact) DarkGray
        }
    }
}

Write-Section "Bridge HTTP Probe"
Invoke-BridgeGet -Path "/health"
Invoke-BridgeGet -Path "/status"
Invoke-BridgeGet -Path "/devices"

Write-Section "Bridge WebSocket Probe"
$wsUrl = "ws://$BridgeHost`:$BridgePort/ws"
$socket = [System.Net.WebSockets.ClientWebSocket]::new()

try {
    $connectWatch = [System.Diagnostics.Stopwatch]::StartNew()
    $socket.ConnectAsync([Uri]$wsUrl, [Threading.CancellationToken]::None).GetAwaiter().GetResult() | Out-Null
    $connectWatch.Stop()
    Write-Log "WS" ("Connected: {0} ({1}ms)" -f $wsUrl, $connectWatch.ElapsedMilliseconds) Green
    Write-TraceRecord -Kind "ws.connect" -Data @{
        url = $wsUrl
        elapsedMs = $connectWatch.ElapsedMilliseconds
        socketState = [string]$socket.State
    }

    Send-WebSocketJson -Socket $socket -Payload @{
        type = "register"
        deviceId = $DeviceId
        capabilities = @("text")
        metadata = @{
            platform = "powershell"
            source = "bridge-smoke-test"
        }
    }
    $ack1 = Convert-EventResultToJson (Receive-WebSocketEvent -Socket $socket -TimeoutSeconds $ReceiveTimeoutSeconds)
    Show-WebSocketReceiveResult -Stage "register" -Result $ack1
    if ($ack1.Status -ne "message") {
        throw "register did not complete successfully"
    }

    Send-WebSocketJson -Socket $socket -Payload @{
        type = "heartbeat"
        deviceId = $DeviceId
        status = "online"
    }
    $ack2 = Convert-EventResultToJson (Receive-WebSocketEvent -Socket $socket -TimeoutSeconds $ReceiveTimeoutSeconds)
    Show-WebSocketReceiveResult -Stage "heartbeat" -Result $ack2
    if ($ack2.Status -ne "message") {
        throw "heartbeat did not complete successfully"
    }

    $requestId = "req_{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 12))
    $sessionKey = "session_$DeviceId"
    $requestState = New-RequestState -RequestId $requestId -SessionKey $sessionKey
    Write-Log "STREAM" ("request created :: requestId={0} sessionKey={1}" -f $requestId, $sessionKey) Cyan
    Write-TraceRecord -Kind "stream.request_created" -Data @{
        requestId = $requestId
        sessionKey = $sessionKey
        deviceId = $DeviceId
        messageText = $MessageText
    }

    Send-WebSocketJson -Socket $socket -Payload @{
        type = "message"
        deviceId = $DeviceId
        text = $MessageText
        requestId = $requestId
        sessionKey = $sessionKey
    }
    while (-not $requestState.IsEnded) {
        $streamResult = Convert-EventResultToJson (Receive-WebSocketEvent -Socket $socket -TimeoutSeconds $ReceiveTimeoutSeconds)
        Show-StreamEventResult -Stage "message" -Result $streamResult -RequestState $requestState
        if ($streamResult.Status -ne "message") {
            $requestState.Status = "error"
            $requestState.ErrorText = $streamResult.Detail
            $requestState.IsEnded = $true
            $requestState.CompletedAt = Get-Date
            break
        }
        if ($null -eq $streamResult.Payload) {
            $requestState.Status = "error"
            $requestState.ErrorText = $streamResult.Detail
            $requestState.IsEnded = $true
            $requestState.CompletedAt = Get-Date
            break
        }
    }

    $firstDeltaMs = ""
    $firstPacketMs = ""
    if ($null -ne $requestState.FirstPacketAt) {
        $firstPacketMs = [int](($requestState.FirstPacketAt - $requestState.StartedAt).TotalMilliseconds)
    }
    if ($null -ne $requestState.FirstDeltaAt) {
        $firstDeltaMs = [int](($requestState.FirstDeltaAt - $requestState.StartedAt).TotalMilliseconds)
    }
    $totalMs = ""
    if ($null -ne $requestState.CompletedAt) {
        $totalMs = [int](($requestState.CompletedAt - $requestState.StartedAt).TotalMilliseconds)
    }
    Write-Log "STREAM" ("summary :: requestId={0} status={1} runId={2} firstPacketMs={3} firstDeltaMs={4} totalMs={5}" -f $requestState.RequestId, $requestState.Status, $requestState.RunId, $firstPacketMs, $firstDeltaMs, $totalMs) Cyan
    Write-Log "STREAM" ("first packet ms :: {0}" -f $firstPacketMs) Cyan
    Write-TraceRecord -Kind "stream.summary" -Data @{
        requestId = $requestState.RequestId
        sessionKey = $requestState.SessionKey
        runId = $requestState.RunId
        status = $requestState.Status
        firstPacketMs = $firstPacketMs
        firstDeltaMs = $firstDeltaMs
        totalMs = $totalMs
        aggregateText = $requestState.AggregateText
        finalText = $requestState.FinalText
        errorText = $requestState.ErrorText
    }
    if (-not [string]::IsNullOrWhiteSpace($requestState.FinalText)) {
        Write-Log "STREAM" ("final text :: {0}" -f $requestState.FinalText) Green
    }
    elseif (-not [string]::IsNullOrWhiteSpace($requestState.AggregateText)) {
        Write-Log "STREAM" ("aggregate text :: {0}" -f $requestState.AggregateText) Yellow
    }
    if (-not [string]::IsNullOrWhiteSpace($requestState.ErrorText)) {
        Write-Log "STREAM" ("error text :: {0}" -f $requestState.ErrorText) Red
    }
}
catch {
    Write-Log "WS" "FAILED" Red
    Write-Log "WS" $_.Exception.Message Yellow
    Write-TraceRecord -Kind "script.failure" -Data @{
        error = $_.Exception.Message
        detailLines = @(Get-ExceptionDetailLines -Exception $_.Exception)
    }
    foreach ($detailLine in Get-ExceptionDetailLines -Exception $_.Exception) {
        Write-Log "WS" "failure detail :: $detailLine" DarkGray
    }
}
finally {
    $finalSocketState = [string]$socket.State
    if ($socket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
        $socket.CloseAsync(
            [System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,
            "done",
            [Threading.CancellationToken]::None
        ).GetAwaiter().GetResult() | Out-Null
        $finalSocketState = [string]$socket.State
    }
    Write-TraceRecord -Kind "script.end" -Data @{
        socketState = $finalSocketState
    }
    $socket.Dispose()
}

Write-Section "Done"

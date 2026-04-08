param(
    [string]$GodotExe = $env:GODOT_EXE,
    [string]$ProjectPath = "d:\QQPAL\godot-app",
    [string]$UserDataDir = ".\userdata",
    [switch]$Editor,
    [switch]$DryRun
)

function Find-GodotExe {
    $fixedCandidates = @(
        "C:\Program Files\Godot\godot_console.exe",
        "C:\Program Files\Godot\godot.exe",
        "D:\Program Files\Godot\godot_console.exe",
        "D:\Program Files\Godot\godot.exe",
        "D:\Tools\Godot\godot_console.exe",
        "D:\Tools\Godot\godot.exe"
    )
    foreach ($p in $fixedCandidates) {
        if (Test-Path -LiteralPath $p -PathType Leaf) {
            return (Resolve-Path -LiteralPath $p).Path
        }
    }

    $scanRoots = @(
        ("C:\Users\{0}\Desktop" -f $env:USERNAME),
        ("C:\Users\{0}\Downloads" -f $env:USERNAME),
        "D:\Tools"
    )
    $names = @("godot_console.exe", "godot.exe")
    foreach ($root in $scanRoots) {
        if (Test-Path -LiteralPath $root -PathType Container) {
            $hit = Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $names -contains $_.Name } |
                Select-Object -First 1
            if ($hit) {
                return $hit.FullName
            }
        }
    }
    return $null
}

function Find-PythonCommand {
    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($python) {
        return [pscustomobject]@{
            FilePath = $python.Source
            Arguments = @()
        }
    }

    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py) {
        return [pscustomobject]@{
            FilePath = $py.Source
            Arguments = @("-3")
        }
    }

    return $null
}

function Test-RuntimeOnline {
    try {
        $health = Invoke-RestMethod -Method Get -Uri "http://127.0.0.1:8765/health" -TimeoutSec 2
        return ($health.status -eq "ok")
    }
    catch {
        return $false
    }
}

function Get-RuntimeProcessIds {
    $ids = @()
    try {
        $listenConnections = Get-NetTCPConnection -LocalAddress "127.0.0.1" -LocalPort 8765 -State Listen -ErrorAction Stop
        $ids += $listenConnections | Select-Object -ExpandProperty OwningProcess
    }
    catch {
    }
    if (-not $ids) {
        try {
            $listenConnections = Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction Stop
            $ids += $listenConnections | Select-Object -ExpandProperty OwningProcess
        }
        catch {
        }
    }
    return @($ids | Where-Object { $_ -gt 0 } | Sort-Object -Unique)
}

function Stop-RuntimeIfRunning {
    param(
        [switch]$DryRunMode
    )

    if (-not (Test-RuntimeOnline)) {
        return $true
    }

    $runtimePids = Get-RuntimeProcessIds
    if (-not $runtimePids) {
        Write-Host "runtime-core is online but no process was found on port 8765."
        return $false
    }

    if ($DryRunMode) {
        Write-Host ("RuntimeRestart: would stop running runtime PID(s): {0}" -f ($runtimePids -join ","))
        return $true
    }

    Write-Host ("runtime-core is running. Restarting PID(s): {0}" -f ($runtimePids -join ","))
    try {
        Stop-Process -Id $runtimePids -Force -ErrorAction Stop
    }
    catch {
        Write-Host ("failed to stop runtime process: {0}" -f $_.Exception.Message)
        return $false
    }

    $deadline = (Get-Date).AddSeconds(8)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 300
        if (-not (Test-RuntimeOnline)) {
            return $true
        }
    }
    return (-not (Test-RuntimeOnline))
}

function Clear-StartupNotice {
    param(
        [string]$NoticePath,
        [switch]$DryRunMode
    )
    if ($DryRunMode) {
        return
    }
    if (Test-Path -LiteralPath $NoticePath -PathType Leaf) {
        Remove-Item -LiteralPath $NoticePath -Force -ErrorAction SilentlyContinue
    }
}

function Write-StartupNotice {
    param(
        [string]$NoticePath,
        [string]$Code,
        [string]$Detail,
        [switch]$DryRunMode
    )
    if ($DryRunMode) {
        Write-Host ("StartupNotice: code={0} detail={1}" -f $Code, $Detail)
        return
    }
    $directory = Split-Path -Parent $NoticePath
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $payload = @{
        code = $Code
        detail = $Detail
        ts = (Get-Date).ToString("o")
    } | ConvertTo-Json -Compress
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($NoticePath, $payload, $utf8)
}

function Reset-QuickChatTrace {
    param(
        [string]$TracePath,
        [switch]$DryRunMode
    )
    if ($DryRunMode) {
        Write-Host ("QuickChatTrace: would clear {0}" -f $TracePath)
        return
    }
    $directory = Split-Path -Parent $TracePath
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($TracePath, "", $utf8)
}

function Ensure-RuntimeStarted {
    param(
        [string]$ScriptRoot,
        [string]$StartupNoticePath,
        [switch]$DryRunMode
    )

    $runtimeMainPath = Join-Path $ScriptRoot "runtime-core\src\main.py"
    $runtimeWorkingDir = Split-Path -Parent $runtimeMainPath

    if (Test-RuntimeOnline) {
        $stopped = Stop-RuntimeIfRunning -DryRunMode:$DryRunMode
        if (-not $stopped) {
            Write-StartupNotice -NoticePath $StartupNoticePath -Code "runtime_restart_failed" -Detail "stop_failed" -DryRunMode:$DryRunMode
            Write-Host "runtime-core restart failed at stop phase."
            return
        }
    }

    if (-not (Test-Path -LiteralPath $runtimeMainPath -PathType Leaf)) {
        Write-StartupNotice -NoticePath $StartupNoticePath -Code "runtime_entrypoint_missing" -Detail $runtimeMainPath -DryRunMode:$DryRunMode
        Write-Host ("runtime-core entrypoint not found: {0}" -f $runtimeMainPath)
        return
    }

    $pythonCommand = Find-PythonCommand
    if (-not $pythonCommand) {
        Write-StartupNotice -NoticePath $StartupNoticePath -Code "python_missing" -Detail "python" -DryRunMode:$DryRunMode
        Write-Host "Python was not found. Cannot auto-start runtime-core."
        return
    }

    $runtimeArgs = @() + $pythonCommand.Arguments + @("main.py")
    if ($DryRunMode) {
        Write-Host ("RuntimeCmd: {0} {1}" -f $pythonCommand.FilePath, ($runtimeArgs -join " "))
        Write-Host ("RuntimeCwd: {0}" -f $runtimeWorkingDir)
        return
    }

    Write-Host "starting runtime-core..."
    $process = Start-Process -FilePath $pythonCommand.FilePath -ArgumentList $runtimeArgs -WorkingDirectory $runtimeWorkingDir -PassThru
    $deadline = (Get-Date).AddSeconds(12)

    do {
        Start-Sleep -Milliseconds 500
        if (Test-RuntimeOnline) {
            Clear-StartupNotice -NoticePath $StartupNoticePath -DryRunMode:$DryRunMode
            Write-Host ("runtime-core started, PID={0}" -f $process.Id)
            return
        }
    } while ((Get-Date) -lt $deadline -and -not $process.HasExited)

    if (Test-RuntimeOnline) {
        Clear-StartupNotice -NoticePath $StartupNoticePath -DryRunMode:$DryRunMode
        Write-Host ("runtime-core started, PID={0}" -f $process.Id)
        return
    }

    $detail = if ($process.HasExited) {
        "process_exited"
    }
    else {
        "start_timeout"
    }
    Write-StartupNotice -NoticePath $StartupNoticePath -Code "runtime_start_failed" -Detail $detail -DryRunMode:$DryRunMode
    Write-Host "runtime-core start timed out. Godot will still launch."
}

if ($GodotExe) {
    if (Test-Path -LiteralPath $GodotExe -PathType Leaf) {
        $GodotExe = (Resolve-Path -LiteralPath $GodotExe).Path
    }
    else {
        $cmd = Get-Command $GodotExe -ErrorAction SilentlyContinue
        if ($cmd) {
            $GodotExe = $cmd.Source
        }
        else {
            Write-Host ("Ignoring invalid GODOT_EXE: {0}" -f $GodotExe)
            $GodotExe = $null
        }
    }
}

if (-not $GodotExe) {
    $cmd = Get-Command godot_console.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        $GodotExe = $cmd.Source
    }
}

if (-not $GodotExe) {
    $cmd = Get-Command godot.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        $GodotExe = $cmd.Source
    }
}

if (-not $GodotExe) {
    $GodotExe = Find-GodotExe
}

if ($GodotExe) {
    $env:GODOT_EXE = $GodotExe
}

if (-not $GodotExe) {
    Write-Host "Godot executable was not found."
    Write-Host "Set GODOT_EXE to the real godot_console.exe path first."
    Write-Host "Example: D:\Tools\Godot\godot_console.exe"
    Write-Host "Then run: .\run-godot.ps1"
    exit 1
}

$scriptRoot = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $PSScriptRoot
}
else {
    Split-Path -Parent $MyInvocation.MyCommand.Path
}

$resolvedProjectPath = (Resolve-Path $ProjectPath).Path
if ([System.IO.Path]::IsPathRooted($UserDataDir)) {
    $resolvedUserDataDir = [System.IO.Path]::GetFullPath($UserDataDir)
}
else {
    $resolvedUserDataDir = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $UserDataDir))
}
$startupNoticePath = Join-Path $resolvedUserDataDir "runtime_startup_notice.json"
$quickChatTracePath = Join-Path $resolvedUserDataDir "quick-chat.trace.jsonl"

$args = @("--path", $resolvedProjectPath, "--user-data-dir", $resolvedUserDataDir)
if ($Editor) {
    $args = @("-e") + $args
}

Reset-QuickChatTrace -TracePath $quickChatTracePath -DryRunMode:$DryRun
Ensure-RuntimeStarted -ScriptRoot $scriptRoot -StartupNoticePath $startupNoticePath -DryRunMode:$DryRun

if ($DryRun) {
    $argText = ($args -join ' ')
    Write-Host ("GodotExe: {0}" -f $GodotExe)
    Write-Host ("Args: {0}" -f $argText)
    exit 0
}

& $GodotExe @args
$stoppedAfterQuit = Stop-RuntimeIfRunning
if ($stoppedAfterQuit) {
    Write-Host "runtime-core stopped after Godot exit."
}
else {
    Write-Host "runtime-core stop after Godot exit failed."
}

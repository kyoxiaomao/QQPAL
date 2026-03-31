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

if ($GodotExe) {
    if (Test-Path -LiteralPath $GodotExe -PathType Leaf) {
        $GodotExe = (Resolve-Path -LiteralPath $GodotExe).Path
    } else {
        $cmd = Get-Command $GodotExe -ErrorAction SilentlyContinue
        if ($cmd) {
            $GodotExe = $cmd.Source
        } else {
            Write-Host ("忽略无效 GODOT_EXE: {0}" -f $GodotExe)
            $GodotExe = $null
        }
    }
}

if (-not $GodotExe) {
    $cmd = Get-Command godot_console.exe -ErrorAction SilentlyContinue
    if ($cmd) { $GodotExe = $cmd.Source }
}

if (-not $GodotExe) {
    $cmd = Get-Command godot.exe -ErrorAction SilentlyContinue
    if ($cmd) { $GodotExe = $cmd.Source }
}

if (-not $GodotExe) {
    $GodotExe = Find-GodotExe
}

if ($GodotExe) {
    $env:GODOT_EXE = $GodotExe
}

if (-not $GodotExe) {
    Write-Host "未找到 Godot 可执行文件。"
    Write-Host "先设置环境变量 GODOT_EXE 为真实的 godot_console.exe 路径。"
    Write-Host "例如：D:\Tools\Godot\godot_console.exe"
    Write-Host "然后执行：.\run-godot.ps1"
    exit 1
}

$resolvedProjectPath = (Resolve-Path $ProjectPath).Path
if ([System.IO.Path]::IsPathRooted($UserDataDir)) {
    $resolvedUserDataDir = [System.IO.Path]::GetFullPath($UserDataDir)
} else {
    $resolvedUserDataDir = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $UserDataDir))
}

$args = @("--path", $resolvedProjectPath, "--user-data-dir", $resolvedUserDataDir)
if ($Editor) {
    $args = @("-e") + $args
}

if ($DryRun) {
    Write-Host ("GodotExe: {0}" -f $GodotExe)
    Write-Host ("Args: {0}" -f ($args -join " "))
    exit 0
}

& $GodotExe @args

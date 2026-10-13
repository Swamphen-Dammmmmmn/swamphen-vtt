$ErrorActionPreference = 'Stop'
$taskProjectRoot = Split-Path -Parent $PSScriptRoot
$taskGodotPath = Join-Path $env:LOCALAPPDATA 'Programs\Godot\Godot_v4.7.2-stable_win64.exe'
if (-not (Test-Path -LiteralPath $taskGodotPath)) {
    throw "未找到 Godot：$taskGodotPath。可在编辑器中运行 dev/ground_sandbox.tscn。"
}
$taskLogDirectory = Join-Path $taskProjectRoot 'artifacts'
New-Item -ItemType Directory -Path $taskLogDirectory -Force | Out-Null
$taskLogPath = Join-Path $taskLogDirectory 'ground-sandbox.log'
Start-Process -FilePath $taskGodotPath -ArgumentList @('--path', ('"' + $taskProjectRoot + '"'), '--rendering-method', 'forward_plus', '--log-file', ('"' + $taskLogPath + '"'), 'res://dev/ground_sandbox.tscn') -WorkingDirectory $taskProjectRoot -WindowStyle Normal

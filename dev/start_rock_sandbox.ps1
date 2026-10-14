param([int]$QuitAfter = 0, [ValidateRange(0,2)][int]$Category = 0)
$ErrorActionPreference = 'Stop'
$taskProjectRoot = Split-Path -Parent $PSScriptRoot
$taskLogDirectory = Join-Path $taskProjectRoot 'logs'
New-Item -ItemType Directory -Path $taskLogDirectory -Force | Out-Null
$taskLogName = if ($Category -eq 0) { 'rock-sandbox.log' } else { 'rock-sandbox-kind' + $Category + '.log' }
& (Join-Path $taskProjectRoot 'tools/start_godot.ps1') -Scene 'res://dev/rock_sandbox.tscn' -RockCategory $Category -LogFile (Join-Path $taskLogDirectory $taskLogName) -QuitAfter $QuitAfter

param(
    [switch]$Editor,
    [string]$Page = '',
    [string]$LogFile = '',
    [string]$ExportPath = '',
    [string]$SettingsTab = '',
    [string]$PortableExecutable = '',
    [int]$QuitAfter = 0,
    [switch]$AdvancedToken
)
$ErrorActionPreference = 'Stop'
$taskProject = Split-Path -Parent $PSScriptRoot
$taskEngine = Join-Path $env:LOCALAPPDATA 'Programs\Godot\Godot_v4.7.2-stable_win64.exe'
if (-not (Test-Path -LiteralPath $taskEngine)) { throw 'Godot executable not found.' }
$taskArguments = '--path "' + $taskProject + '"'
if ($PortableExecutable) {
    $taskPortable = [System.IO.Path]::GetFullPath($PortableExecutable)
    $taskBuild = [System.IO.Path]::GetFullPath((Join-Path $taskProject 'build')) + '\'
    if (-not $taskPortable.StartsWith($taskBuild,[System.StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $taskPortable)) { throw 'Portable executable must be inside project build output.' }
    $taskEngine = $taskPortable
    $taskArguments = ''
}
if ($ExportPath) {
    $taskConsoleEngine = Join-Path $env:LOCALAPPDATA 'Programs\Godot\Godot_v4.7.2-stable_win64_console.exe'
    if (Test-Path -LiteralPath $taskConsoleEngine) { $taskEngine = $taskConsoleEngine }
    $taskArguments += ' --headless --export-release Windows "' + $ExportPath + '"'
}
if ($Editor) { $taskArguments += ' --editor' }
if (-not $LogFile) {
    $taskLogDirectory = Join-Path $taskProject 'logs'
    New-Item -ItemType Directory -Path $taskLogDirectory -Force | Out-Null
    $LogFile = Join-Path $taskLogDirectory ('godot-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
}
$taskArguments += ' --log-file "' + $LogFile + '"'
if ($QuitAfter -gt 0) { $taskArguments += ' --quit-after ' + $QuitAfter }
if ($Page) {
    if ($Page -notin @('home','join','network_settings','identity','map_library','map_create','platform_library','platform_create','token_library','token_customize','settings','adventure_library','adventure_create','adventures','adventure_play')) { throw 'Unknown startup page.' }
    $taskArguments += ' -- --page=' + $Page
}
if ($AdvancedToken) {
    if ($Page -ne 'token_customize') { throw 'AdvancedToken requires token_customize page.' }
    $taskArguments += ' --advanced-token'
}
if ($SettingsTab) {
    if ($Page -ne 'settings' -or $SettingsTab -notin @('video','interface','camera','tutorial','audio','network','updates')) { throw 'Invalid settings page.' }
    $taskArguments += ' --settings-tab=' + $SettingsTab
}
# The desktop's COM object runs in Explorer, outside the caller's package identity.
$taskShell = New-Object -ComObject Shell.Application
$taskHwnd = 0
$taskDesktop = $taskShell.Windows().FindWindowSW(0,0,8,[ref]$taskHwnd,1)
if ($null -eq $taskDesktop) { throw 'Explorer desktop is unavailable; Godot was not started.' }
$taskDesktop.Document.Application.ShellExecute($taskEngine,$taskArguments,$taskProject,'open',1)

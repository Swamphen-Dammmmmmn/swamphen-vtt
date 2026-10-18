param(
    [switch]$Editor,
    [switch]$Headless,
    [string]$Page = '',
    [string]$LogFile = '',
    [string]$ExportPath = '',
    [ValidateSet('Windows','Android ARM64 Test')][string]$ExportPreset = 'Windows',
    [switch]$ExportDebug,
    [string]$SettingsTab = '',
    [string]$Scene = '',
    [ValidateRange(0,2)][int]$RockCategory = 0,
    [string]$PortableExecutable = '',
    [int]$QuitAfter = 0,
    [switch]$MobilePreview,
    [switch]$AdvancedToken
)
$ErrorActionPreference = 'Stop'
$taskProject = Split-Path -Parent $PSScriptRoot
$taskEngine = Join-Path $env:LOCALAPPDATA 'Programs\Godot\Godot_v4.7.2-stable_win64.exe'
if (-not (Test-Path -LiteralPath $taskEngine)) { throw 'Godot executable not found.' }
$taskArguments = '--path "' + $taskProject + '"'
if ($Headless) {
    if (-not $Scene -or $Editor -or $PortableExecutable -or $ExportPath) { throw 'Headless is only available for standalone developer scenes.' }
    $taskArguments += ' --headless'
}
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
    $taskExportFlag = if ($ExportDebug) { '--export-debug' } else { '--export-release' }
    $taskArguments += ' --headless ' + $taskExportFlag + ' "' + $ExportPreset + '" "' + $ExportPath + '"'
}
if ($Editor) { $taskArguments += ' --editor' }
if ($Scene) {
    if ($Editor -or $ExportPath -or $Page -or $PortableExecutable) { throw 'Scene cannot be combined with editor, export, page or portable startup.' }
    if ($Scene -notmatch '^res://dev/[a-z0-9_]+\.tscn$') { throw 'Only a development sandbox scene is allowed.' }
    $taskScenePath = Join-Path $taskProject ($Scene.Substring(6))
    if (-not (Test-Path -LiteralPath $taskScenePath)) { throw 'Sandbox scene was not found.' }
    $taskArguments += ' "' + $Scene + '"'
}
if (-not $LogFile) {
    $taskLogDirectory = Join-Path $taskProject 'logs'
    New-Item -ItemType Directory -Path $taskLogDirectory -Force | Out-Null
    $LogFile = Join-Path $taskLogDirectory ('godot-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
}
$taskArguments += ' --log-file "' + $LogFile + '"'
if ($QuitAfter -gt 0) { $taskArguments += ' --quit-after ' + $QuitAfter }
if ($MobilePreview -and -not $Page) { $Page = "home" }
if ($Page) {
    if ($Page -notin @('home','customize','join','network_settings','identity','map_library','map_create','platform_library','platform_create','token_library','token_customize','settings','adventure_library','adventure_create','adventures','adventure_play')) { throw 'Unknown startup page.' }
    $taskArguments += ' -- --page=' + $Page
}
if ($MobilePreview) { $taskArguments += " --mobile-preview" }
if ($AdvancedToken) {
    if ($Page -ne 'token_customize') { throw 'AdvancedToken requires token_customize page.' }
    $taskArguments += ' --advanced-token'
}
if ($SettingsTab) {
    if ($Page -ne 'settings' -or $SettingsTab -notin @('video','interface','camera','tutorial','audio','network','updates')) { throw 'Invalid settings page.' }
    $taskArguments += ' --settings-tab=' + $SettingsTab
}
if ($Scene -eq 'res://dev/rock_sandbox.tscn') {
    $taskArguments += ' -- --rock-category=' + $RockCategory
} elseif ($RockCategory -ne 0) {
    throw 'RockCategory is only available for the rock sandbox.'
}
# The desktop's COM object runs in Explorer, outside the caller's package identity.
$taskShell = New-Object -ComObject Shell.Application
$taskHwnd = 0
$taskDesktop = $taskShell.Windows().FindWindowSW(0,0,8,[ref]$taskHwnd,1)
if ($null -eq $taskDesktop) { throw 'Explorer desktop is unavailable; Godot was not started.' }
$taskDesktop.Document.Application.ShellExecute($taskEngine,$taskArguments,$taskProject,'open',1)

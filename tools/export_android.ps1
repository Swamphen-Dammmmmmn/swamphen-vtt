param([string]$OutputPath = '', [switch]$DesktopContext)
$ErrorActionPreference = 'Stop'
if (-not $DesktopContext) {
    $taskShell = New-Object -ComObject Shell.Application
    $taskHwnd = 0
    $taskDesktop = $taskShell.Windows().FindWindowSW(0,0,8,[ref]$taskHwnd,1)
    if ($null -eq $taskDesktop) { throw 'Explorer desktop is unavailable.' }
    $taskPowerShell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
    $taskArguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -DesktopContext'
    if ($OutputPath) { $taskArguments += ' -OutputPath "' + $OutputPath + '"' }
    $taskDesktop.Document.Application.ShellExecute($taskPowerShell,$taskArguments,$PSScriptRoot,'open',0)
    Write-Output 'Android setup and export dispatched to the Windows desktop environment.'
    return
}
$taskProject = Split-Path -Parent $PSScriptRoot
$taskToolchain = Join-Path $taskProject 'artifacts/android-toolchain'
$taskJava = Get-ChildItem -LiteralPath (Join-Path $taskToolchain 'java') -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'bin/java.exe') } | Select-Object -First 1
if ($null -eq $taskJava) { throw 'JDK17 is missing from artifacts/android-toolchain/java.' }
$taskSdk = Join-Path $taskToolchain 'sdk'
if (-not (Test-Path -LiteralPath (Join-Path $taskSdk 'build-tools/35.0.1/apksigner.bat'))) { throw 'Android build tools are missing.' }
if (-not (Test-Path -LiteralPath (Join-Path $taskProject 'artifacts/export-templates/android_debug.apk'))) { throw 'Godot4.7.2 Android debug template is missing.' }
$taskKeystore = Join-Path $taskToolchain 'debug.keystore'
if (-not (Test-Path -LiteralPath $taskKeystore)) {
    & (Join-Path $taskJava.FullName 'bin/keytool.exe') -genkeypair -keystore $taskKeystore -storepass android -keypass android -alias androiddebugkey -dname 'CN=Android Debug,O=Android,C=US' -keyalg RSA -keysize 2048 -validity 10000
    if ($LASTEXITCODE -ne 0) { throw 'Debug keystore generation failed.' }
}
$taskSettingsPath = Join-Path $env:APPDATA 'Godot/editor_settings-4.7.tres'
$taskSettings = Get-Content -LiteralPath $taskSettingsPath -Raw -Encoding UTF8
$taskOptions = @{
    'export/android/java_sdk_path' = $taskJava.FullName.Replace('\','/')
    'export/android/android_sdk_path' = $taskSdk.Replace('\','/')
    'export/android/debug_keystore' = $taskKeystore.Replace('\','/')
    'export/android/debug_keystore_user' = 'androiddebugkey'
    'export/android/debug_keystore_pass' = 'android'
}
foreach ($taskKey in $taskOptions.Keys) {
    $taskLine = $taskKey + '="' + $taskOptions[$taskKey] + '"'
    $taskPattern = '(?m)^' + [regex]::Escape($taskKey) + '\s*=.*$'
    if ($taskSettings -match $taskPattern) { $taskSettings = [regex]::Replace($taskSettings,$taskPattern,[Text.RegularExpressions.MatchEvaluator]{ param($match) $taskLine }) }
    else { $taskSettings += "`n" + $taskLine + "`n" }
}
[IO.File]::WriteAllText($taskSettingsPath,$taskSettings,[Text.UTF8Encoding]::new($false))
$taskOutputDirectory = Join-Path $taskProject 'build/android'
New-Item -ItemType Directory -Path $taskOutputDirectory -Force | Out-Null
if (-not $OutputPath) {
    $taskProjectSettings = Get-Content -LiteralPath (Join-Path $taskProject 'project.godot') -Raw -Encoding UTF8
    $taskVersion = [regex]::Match($taskProjectSettings,'config/version="([^"]+)"').Groups[1].Value
    if (-not $taskVersion) { throw 'Project version is missing.' }
    $OutputPath = Join-Path $taskOutputDirectory ('svtt-' + $taskVersion + '-android-arm64-test.apk')
}
& (Join-Path $PSScriptRoot 'start_godot.ps1') -ExportPreset 'Android ARM64 Test' -ExportDebug -ExportPath $OutputPath -LogFile (Join-Path $taskProject 'logs/android-export.log')
Write-Output 'Android export started. Completion is recorded in logs/android-export.log.'

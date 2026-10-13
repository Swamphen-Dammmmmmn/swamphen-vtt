param([Parameter(Mandatory=$true)][string]$SourceDirectory)
$ErrorActionPreference = 'Stop'
$taskDestination = Join-Path $env:APPDATA '紫水鸡棋盘'
$taskLog = Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\userdata-recovery.log'
$taskLines = @("Source: $SourceDirectory", "Destination: $taskDestination")
$taskFiles = @()
$taskProducts = Join-Path $SourceDirectory 'products'
if (Test-Path -LiteralPath $taskProducts) { $taskFiles += Get-ChildItem -LiteralPath $taskProducts -Recurse -File -Force }
$taskFiles += Get-ChildItem -LiteralPath $SourceDirectory -File -Filter '*.cfg' -Force
foreach ($taskFile in $taskFiles) {
    $taskRelative = $taskFile.FullName.Substring($SourceDirectory.TrimEnd('\').Length + 1)
    $taskTarget = Join-Path $taskDestination $taskRelative
    if (Test-Path -LiteralPath $taskTarget) {
        $taskSame = (Get-FileHash -LiteralPath $taskTarget).Hash -eq (Get-FileHash -LiteralPath $taskFile.FullName).Hash
        $taskLines += $(if ($taskSame) { "UNCHANGED $taskRelative" } else { "CONFLICT PRESERVED $taskRelative" })
        continue
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $taskTarget) -Force | Out-Null
    Copy-Item -LiteralPath $taskFile.FullName -Destination $taskTarget
    if ((Get-FileHash -LiteralPath $taskTarget).Hash -ne (Get-FileHash -LiteralPath $taskFile.FullName).Hash) { throw "Copy verification failed: $taskRelative" }
    $taskLines += "COPIED $taskRelative"
}
$taskLines | Out-File -LiteralPath $taskLog -Encoding utf8

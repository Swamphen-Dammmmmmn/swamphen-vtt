param([switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
$taskProject = Split-Path -Parent $PSScriptRoot
$taskPython = Join-Path $taskProject 'artifacts/network-check-env/Scripts/python.exe'
$taskPlan = Get-Content -LiteralPath (Join-Path $taskProject 'artifacts/v012-publish-plan.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$env:PYTHONUTF8 = '1'
$env:PYTHONUNBUFFERED = '1'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
Set-Location -LiteralPath $taskProject
if ($CheckOnly) {
    & $taskPython -c "import sys;sys.path.insert(0,'tools');import build_release;from pathlib import Path;build_release.verify(Path(sys.argv[1]),'0.1.2');print('Release files verified; no upload.')" $taskPlan.directory
} else {
    & $taskPython tools/publish_release.py --version 0.1.2 --source-commit $taskPlan.source_commit --directory $taskPlan.directory --notes-file $taskPlan.notes --progress --publish
}
if ($LASTEXITCODE -ne 0) { throw 'Release failed. The draft remains private; rerun the same command to continue.' }

param(
    [Parameter(Mandatory=$true)][string]$Version,
    [ValidateSet('all','windows','android')][string]$Platform='all',
    [ValidateSet('build','draft','publish','prepare')][string]$Mode='publish',
    [ValidateSet('testing','stable')][string]$Channel='testing',
    [int]$AndroidCode=0,
    [switch]$SyncSource,
    [switch]$SkipStartup,
    [string]$ReuseRun='0',
    [Parameter(Mandatory=$true)][string]$Notes
)
$ErrorActionPreference='Stop'
$taskProject=Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $taskProject
$taskPython=Join-Path $taskProject 'artifacts/network-check-env/Scripts/python.exe'
if (!(Test-Path -LiteralPath $taskPython)) { throw 'Local release Python environment is missing.' }
$taskScript=@'
import base64,json,os,pathlib,re,subprocess,sys
sys.path.insert(0,'tools')
from publish_release import publishing_environment,REPO
from ci_release import public_source
version,platform,mode,channel,code,notes,sync,reuse,skip_startup=sys.argv[1:]
if reuse=='0':reuse=''
sys.path.insert(0,'launcher')
import core
core.version(version)
if reuse and (not reuse.isdigit() or mode=='prepare'):raise SystemExit('-ReuseRun requires a numeric run ID and build/draft/publish mode.')
config=pathlib.Path('artifacts/github-release-cli')
if (config/'hosts.yml').exists():os.environ['GH_CONFIG_DIR']=str(config.resolve())
env=publishing_environment()
head=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
dirty=subprocess.check_output(['git','status','--porcelain','--untracked-files=normal'],text=True)
if dirty.strip():raise SystemExit('Uncommitted changes exist. Commit and synchronize the tested public source first; no remote build was triggered.')
record=json.loads(subprocess.check_output(['gh','api',f'repos/{REPO}/commits/main'],env=env,text=True,encoding='utf-8'))
remote=record['sha']
tree=subprocess.check_output(['git','rev-parse','HEAD^{tree}'],text=True).strip()
if record['commit']['tree']['sha']!=tree:
 if sync!='True':raise SystemExit('Local source differs from public main. Use -SyncSource after local testing; no remote build was triggered.')
 public_source('HEAD')
 token=env.get('GH_TOKEN') or subprocess.check_output(['gh','auth','token'],env=env,text=True).strip()
 pushenv=env.copy()
 pushenv['GIT_CONFIG_COUNT']='1';pushenv['GIT_CONFIG_KEY_0']='http.https://github.com/.extraheader'
 pushenv['GIT_CONFIG_VALUE_0']='AUTHORIZATION: basic '+base64.b64encode(('x-access-token:'+token).encode()).decode()
 subprocess.run(['git','fetch','origin','main'],env=pushenv,check=True)
 fetched=subprocess.check_output(['git','rev-parse','FETCH_HEAD'],text=True).strip()
 if fetched!=remote:raise SystemExit('Public main changed during synchronization. Retry after reviewing it.')
 remote=subprocess.check_output(['git','commit-tree',tree,'-p',remote,'-m',f'Synchronize tested source for v{version}'],text=True).strip()
 subprocess.run(['git','update-ref','refs/heads/codex/public-main',remote],check=True)
 subprocess.run(['git','push','origin','codex/public-main:main'],env=pushenv,check=True)
plan={'ref':'main','inputs':{'version':version,'platform':platform,'mode':mode,'channel':channel,'android_code':code,'notes':notes,'reuse_run':reuse,'skip_startup':skip_startup=='True'}}
subprocess.run(['gh','api','--method','POST',f'repos/{REPO}/actions/workflows/release.yml/dispatches','--input','-'],input=json.dumps(plan),env=env,text=True,check=True)
print(f'Triggered {mode} for {remote}. Progress: https://github.com/{REPO}/actions/workflows/release.yml')
'@
$taskScript | & $taskPython - $Version $Platform $Mode $Channel $AndroidCode $Notes $SyncSource.IsPresent $ReuseRun $SkipStartup.IsPresent
if ($LASTEXITCODE -ne 0) { throw 'Remote build was not triggered.' }

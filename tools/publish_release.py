"""Publish already-verified assets through a draft, then verify GitHub digests."""
import argparse,json,os,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(ROOT/'launcher'))
import core
REPO=core.REPOSITORY

release_env=None

def publishing_environment():
    env=os.environ.copy()
    env['GODEBUG']=env.get('GODEBUG','')+',http2client=0'
    def writable():
        p=subprocess.run(['gh','repo','view',REPO,'--json','viewerPermission'],cwd=ROOT,env=env,capture_output=True,text=True,encoding='utf-8')
        return p.returncode==0 and json.loads(p.stdout)['viewerPermission'] in ['ADMIN','MAINTAIN','WRITE']
    if writable():return env
    # Reuse this repository's existing Git credential without changing global gh login.
    env['GIT_TERMINAL_PROMPT']='0';env['GCM_INTERACTIVE']='Never'
    p=subprocess.run(['git','credential','fill'],input='url=https://github.com/'+REPO+'.git\n\n',cwd=ROOT,env=env,capture_output=True,text=True,encoding='utf-8')
    credential=dict(line.split('=',1) for line in p.stdout.splitlines() if '=' in line)
    if p.returncode!=0 or not credential.get('password'):raise SystemExit('Repository write credential unavailable; no release was created.')
    env['GH_TOKEN']=credential['password']
    if not writable():raise SystemExit('Release account has no repository write permission; no release was created.')
    return env

def gh(*args):return subprocess.check_output(['gh',*map(str,args),'--repo',REPO],cwd=ROOT,env=release_env,text=True,encoding='utf-8')
def main():
 global release_env
 release_env=publishing_environment()
 p=argparse.ArgumentParser();p.add_argument('--version',required=True);p.add_argument('--source-commit',required=True);p.add_argument('--notes-file',type=Path,required=True);p.add_argument('--publish',action='store_true');args=p.parse_args()
 core.version(args.version);directory=ROOT/'build/releases'/('v'+args.version)
 checks=json.loads((directory/'build-check.json').read_text(encoding='utf-8'))
 public=(ROOT/'assets/updates/release-public.pem').read_bytes()
 manifest=core.verified((directory/'release.json').read_bytes(),(directory/'release.sig').read_bytes(),public)
 assert manifest['version']==args.version and checks['version']==args.version
 # Refuse developer docs, local data and private keys in the tagged source tree.
 paths=subprocess.check_output(['git','-c','core.quotepath=false','ls-tree','-r','--name-only',args.source_commit],cwd=ROOT,text=True,encoding='utf-8').splitlines()
 forbidden=[n for n in paths if n.startswith(('docs/','artifacts/','build/','userdata/','cache/','logs/')) or n.endswith(('.keystore','.key','.jks','.p12','private.pem')) or (n.lower().endswith(('.md','.rst','.pdf','.docx')) and n!='README.md' and Path(n).name.upper()!='LICENSE.MD')]
 if forbidden:raise SystemExit('Forbidden public source paths: '+repr(forbidden[:10]))
 assets=[]
 for name,meta in checks['assets'].items():
  file=directory/name
  assert file.stat().st_size==meta['size'] and core.sha(file)==meta['sha256']
  assets.append(file)
 assets.append(directory/'SHA256SUMS.txt')
 tag='v'+args.version
 gh('release','create',tag,*assets,'--draft','--prerelease','--target',args.source_commit,'--title',tag+' · Windows / Android 测试版','--notes-file',args.notes_file)
 view=json.loads(gh('release','view',tag,'--json','assets,isDraft,isPrerelease,url'))
 assert view['isDraft'] and view['isPrerelease']
 remote={a['name']:a for a in view['assets']}
 for file in assets:
  assert remote[file.name]['size']==file.stat().st_size
  assert remote[file.name].get('digest')=='sha256:'+core.sha(file)
 if args.publish:
  gh('release','edit',tag,'--draft=false','--prerelease')
  final=json.loads(gh('release','view',tag,'--json','isDraft,isPrerelease,url'))
  assert not final['isDraft'] and final['isPrerelease'];print(final['url'])
 else:print(view['url']+' (draft)')
if __name__=='__main__':main()

"""Publish already-verified assets through a draft, then verify GitHub digests."""
import argparse,json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(ROOT/'launcher'))
import core
REPO=core.REPOSITORY

def gh(*args):return subprocess.check_output(['gh',*map(str,args),'--repo',REPO],cwd=ROOT,text=True)
def main():
 p=argparse.ArgumentParser();p.add_argument('--version',required=True);p.add_argument('--source-commit',required=True);p.add_argument('--notes-file',type=Path,required=True);p.add_argument('--publish',action='store_true');args=p.parse_args()
 core.version(args.version);directory=ROOT/'build/releases'/('v'+args.version)
 checks=json.loads((directory/'build-check.json').read_text(encoding='utf-8'))
 public=(ROOT/'assets/updates/release-public.pem').read_bytes()
 manifest=core.verified((directory/'release.json').read_bytes(),(directory/'release.sig').read_bytes(),public)
 assert manifest['version']==args.version and checks['version']==args.version
 # Refuse developer docs, local data and private keys in the tagged source tree.
 paths=subprocess.check_output(['git','ls-tree','-r','--name-only',args.source_commit],cwd=ROOT,text=True).splitlines()
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

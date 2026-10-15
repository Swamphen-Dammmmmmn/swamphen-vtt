"""Verify and publish one Android APK; never rebuilds or changes Windows assets."""
import argparse,json,re,subprocess,zipfile
from pathlib import Path
import publish_release as release
from release_upload_progress import upload
ROOT=Path(__file__).resolve().parent.parent

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--version',required=True)
    parser.add_argument('--source-commit',required=True)
    parser.add_argument('--apk',type=Path,required=True)
    parser.add_argument('--notes-file',type=Path,required=True)
    parser.add_argument('--publish',action='store_true')
    parser.add_argument('--check-only',action='store_true')
    args=parser.parse_args()
    if not re.fullmatch(r'\d+\.\d+\.\d+[a-z]?',args.version):raise SystemExit('Invalid release version.')
    apk=args.apk.resolve()
    if not apk.is_relative_to((ROOT/'build').resolve()) or apk.suffix!='.apk':raise SystemExit('APK must be inside build output.')
    with zipfile.ZipFile(apk) as z:
        assert z.testzip() is None
        libs=[n for n in z.namelist() if n.startswith('lib/') and n.endswith('.so')]
        assert libs and all(n.startswith('lib/arm64-v8a/') for n in libs)
    java=next((ROOT/'artifacts/android-toolchain/java').glob('*/bin/java.exe'))
    signer=ROOT/'artifacts/android-toolchain/sdk/build-tools/35.0.1/lib/apksigner.jar'
    result=subprocess.run([str(java),'-jar',str(signer),'verify','--print-certs',str(apk)],capture_output=True,text=True)
    assert result.returncode==0,result.stderr
    assert 'fc1d7b1535062c1a3caaa29b55a3f43f23f99450137748124a7a2e6bfa02c007' in result.stdout,'APK signing certificate changed.'
    aapt=ROOT/'artifacts/android-toolchain/sdk/build-tools/35.0.1/aapt2.exe'
    manifest=subprocess.check_output([str(aapt),'dump','xmltree',str(apk),'--file','AndroidManifest.xml'],text=True,encoding='utf-8')
    assert 'org.swamphen.svtt.test' in manifest and '="'+args.version+'"' in manifest,'APK package/version mismatch.'
    paths=subprocess.check_output(['git','-c','core.quotepath=false','ls-tree','-r','--name-only',args.source_commit],cwd=ROOT,text=True,encoding='utf-8').splitlines()
    forbidden=[n for n in paths if n.startswith(('docs/','artifacts/','build/','userdata/','cache/','logs/')) or n.endswith(('.keystore','.key','.jks','.p12','private.pem')) or (n.lower().endswith(('.md','.rst','.pdf','.docx')) and n!='README.md' and Path(n).name.upper()!='LICENSE.MD')]
    assert not forbidden,'Forbidden public source paths: '+repr(forbidden[:10])
    project=subprocess.check_output(['git','show',args.source_commit+':project.godot'],cwd=ROOT,text=True,encoding='utf-8')
    assert 'config/version="'+args.version+'"' in project,'Source version mismatch.'
    print('APK archive, signature, architecture, version and public source checks passed.',flush=True)
    if args.check_only:return
    release.release_env=release.publishing_environment()
    tag='v'+args.version
    probe=subprocess.run(['gh','release','view',tag,'--repo',release.REPO,'--json','isDraft'],env=release.release_env,capture_output=True,text=True,encoding='utf-8')
    if probe.returncode==0:
        if not json.loads(probe.stdout)['isDraft']:raise SystemExit('Release already public; replacement refused.')
        release.gh('release','edit',tag,'--draft=true','--prerelease','--title',tag+' · Android 修复测试版','--notes-file',args.notes_file)
    else:release.gh('release','create',tag,'--draft','--prerelease','--target',args.source_commit,'--title',tag+' · Android 修复测试版','--notes-file',args.notes_file)
    upload([apk],release.REPO,tag,release.release_env)
    view=json.loads(release.gh('release','view',tag,'--json','assets,isDraft,isPrerelease,url'))
    assert view['isDraft'] and view['isPrerelease'] and len(view['assets'])==1,'Expected exactly one APK attachment.'
    asset=view['assets'][0]
    assert asset['name']==apk.name and asset['size']==apk.stat().st_size and asset['digest']=='sha256:'+release.core.sha(apk)
    if args.publish:
        release.gh('release','edit',tag,'--draft=false','--prerelease')
        final=json.loads(release.gh('release','view',tag,'--json','isDraft,isPrerelease,url'))
        assert not final['isDraft'] and final['isPrerelease']
        (apk.parent/'published-check.json').write_text(json.dumps({'version':args.version,'source_commit':args.source_commit,'url':final['url'],'asset':asset},ensure_ascii=False,indent=2),encoding='utf-8')
        print(final['url'],flush=True)
    else:print(view['url']+' (draft)',flush=True)

if __name__=='__main__':main()

"""Local release pipeline: build, sign and verify; never uploads signing keys."""
import argparse,hashlib,json,re,shutil,subprocess,sys,time,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(ROOT/'launcher'))
import core

def run(*args):
    subprocess.run([str(a) for a in args],cwd=ROOT,check=True)

def export(preset,path,log,debug=False):
    log.parent.mkdir(parents=True,exist_ok=True)
    log.write_text('',encoding='utf-8')
    args=['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File',str(ROOT/'tools/start_godot.ps1'),'-ExportPreset',preset,'-ExportPath',str(path),'-LogFile',str(log)]
    if debug:args.append('-ExportDebug')
    run(*args)
    wait_export(path,log)

def wait_export(path,log):
    deadline=time.monotonic()+900
    notice=0
    while time.monotonic()<deadline:
        text=log.read_text(encoding='utf-8',errors='replace') if log.exists() else ''
        if 'Project export for preset' in text and 'failed' in text:raise RuntimeError('Export failed: '+str(log))
        if ('[ DONE ] export' in text or (path.suffix == '.exe' and '[ DONE ] savepack' in text)) and path.exists():
            errors=[line for line in text.splitlines() if 'ERROR:' in line and 'No project icon specified' not in line]
            if errors:raise RuntimeError('Export errors: '+str(log)+'\n'+'\n'.join(errors))
            return
        if time.monotonic()-notice>15:print('Waiting for export: '+path.name,flush=True);notice=time.monotonic()
        time.sleep(1)
    raise RuntimeError('Export timeout: '+str(log))

def verify(directory,version):
    public=(ROOT/'assets/updates/release-public.pem').read_bytes()
    record=core.verified((directory/'release.json').read_bytes(),(directory/'release.sig').read_bytes(),public)
    assert record['version']==version and record['channel']=='testing'
    portable=directory/f'svtt-{version}-windows-portable.zip'
    assert core.sha(portable)==record['package_sha256'] and portable.stat().st_size==record['package_size']
    with zipfile.ZipFile(portable) as z:
        assert z.testzip() is None
        assert not any('/userdata/' in n or '/artifacts/' in n or '/docs/' in n or 'private.pem' in n or 'AGENTS.md' in n for n in z.namelist())
        payload,_,_,mapping=core.archive_layout(z,public)
        assert payload['version']==version and payload['files']==record['files']
        for name,canonical in mapping.items():
            entry=payload['files'][canonical];data=z.read(name)
            assert len(data)==entry['size'] and hashlib.sha256(data).hexdigest()==entry['sha256']
    return record

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--version',required=True);ap.add_argument('--android-apk',type=Path);ap.add_argument('--notes',required=True);ap.add_argument('--resume',action='store_true');ap.add_argument('--output',type=Path);args=ap.parse_args()
    parts=core.version(args.version)
    output=(args.output or ROOT/'build/releases'/('v'+args.version)).resolve()
    if not output.is_relative_to((ROOT/'build').resolve()):raise SystemExit('Output must be inside build directory.')
    if output.exists() and not args.resume:raise SystemExit('Output already exists; inspect it before using --resume.')
    if (output/'build-check.json').exists():
        verify(output,args.version);print('Existing release verified: '+str(output));return
    if not (ROOT/'artifacts/release-signing/private.pem').exists():raise SystemExit('Local release signing key missing.')
    output.mkdir(parents=True,exist_ok=True)
    project=ROOT/'project.godot';project.write_text(re.sub(r'config/version="[^"]+"','config/version="'+args.version+'"',project.read_text(encoding='utf-8')),encoding='utf-8')
    # Android test builds have an increasing code; reused APKs retain their original bytes and version.
    presets=ROOT/'export_presets.cfg';text=presets.read_text(encoding='utf-8')
    code=int(re.search(r'version/code=(\d+)',text)[1])
    if f'version/name="{args.version}"' not in text:
        raise SystemExit('Commit matching Android version/name and an increasing version/code before building.')
    work=output.parent/(output.name+'-work');program=work/'program';boot=work/'boot';program.mkdir(parents=True,exist_ok=True);boot.mkdir(exist_ok=True)
    if args.resume and (program/core.ENTRY).exists():
        wait_export(program/core.ENTRY,ROOT/'logs'/('release-'+args.version+'-windows.log'))
    else:
        export('Windows',program/core.ENTRY,ROOT/'logs'/('release-'+args.version+'-windows.log'))
    run(sys.executable,'-m','PyInstaller','--noconfirm','--clean','--windowed','--onedir','--name',core.BOOT.removesuffix('.exe'),'--distpath',boot,'--workpath',ROOT/'artifacts'/('launcher-build-'+args.version),'--specpath',ROOT/'artifacts/launcher-spec','--paths',ROOT/'launcher','--add-data',str(ROOT/'assets/updates/release-public.pem')+';.',ROOT/'launcher/main.py')
    actual_boot=boot/core.BOOT.removesuffix('.exe')
    for target in [program,actual_boot]:run(sys.executable,ROOT/'tools/collect_release_licenses.py','--boot',target)
    run(sys.executable,ROOT/'tools/package_portable.py','--program',program,'--boot',actual_boot,'--version',args.version,'--output',output,'--base-url','https://github.com/'+core.REPOSITORY+'/releases/download/v'+args.version+'/','--channel','testing','--notes',args.notes)
    if args.android_apk:
        apk=args.android_apk.resolve()
        if not apk.is_relative_to((ROOT/'build').resolve()):raise SystemExit('Reused APK must be inside build output.')
    else:
        apk=work/('svtt-'+args.version+'-android-arm64-test.apk')
        (ROOT/'logs/android-export.log').write_text('',encoding='utf-8')
        run('powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File',ROOT/'tools/export_android.ps1','-OutputPath',apk)
        wait_export(apk,ROOT/'logs/android-export.log')
    shutil.copy2(apk,output/apk.name)
    with zipfile.ZipFile(output/apk.name) as z:
        assert z.testzip() is None
        libs=[n for n in z.namelist() if n.startswith('lib/')]
        assert libs and all(n.startswith('lib/arm64-v8a/') for n in libs)
        assert 'terrain_3d' not in z.read('assets/.godot/extension_list.cfg').decode()
    java=next((ROOT/'artifacts/android-toolchain/java').glob('*/bin/java.exe'))
    signer=ROOT/'artifacts/android-toolchain/sdk/build-tools/35.0.1/lib/apksigner.jar'
    run(java,'-jar',signer,'verify','--verbose',output/apk.name)
    record=verify(output,args.version)
    files=[output/f'svtt-{args.version}-windows-portable.zip',output/'release.json',output/'release.sig',output/apk.name]
    checks={p.name:{'size':p.stat().st_size,'sha256':core.sha(p)} for p in files}
    (output/'SHA256SUMS.txt').write_text(''.join(v['sha256']+'  '+k+'\n' for k,v in checks.items()),encoding='ascii')
    (output/'build-check.json').write_text(json.dumps({'version':args.version,'channel':record['channel'],'assets':checks},indent=2),encoding='utf-8')
    print('Release packages verified: '+str(output),flush=True)

if __name__=='__main__':main()

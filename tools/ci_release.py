"""GitHub-hosted Windows build entry. No Explorer or personal server dependency."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'launcher'))
import core

LOCK = json.loads((ROOT / 'tools/ci-toolchain.json').read_text())
KEYS = ROOT / 'artifacts/ci-secrets'
OUT = ROOT / 'build/ci'


def run(*args, **kwargs):
    return subprocess.run(list(map(str, args)), cwd=ROOT, check=True, **kwargs)


def capture(*args):
    return subprocess.check_output(list(map(str, args)), cwd=ROOT, text=True, encoding='utf-8')


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def check_draft(existing, commit):
    require(existing['isDraft'], 'Existing release is public; replacement refused.')
    require(existing['targetCommitish'] == commit, 'Draft belongs to a different source commit.')


def validate(version, platform, code):
    try:
        core.version(version)
    except core.UpdateError as error:
        raise RuntimeError(str(error)) from error
    require(platform in ('all', 'windows', 'android'), 'Unknown platform.')
    require(0 <= code <= 2100000000, 'Invalid Android version code.')


def public_source(commit):
    paths = capture('git', '-c', 'core.quotepath=false', 'ls-tree', '-r', '--name-only', commit).splitlines()
    forbidden = [n for n in paths if n.startswith(('docs/', '.agents/', 'artifacts/', 'build/', 'userdata/', 'cache/', 'logs/'))
                 or n.endswith(('.keystore', '.key', '.jks', '.p12', 'private.pem'))
                 or (n.lower().endswith(('.md', '.rst', '.pdf', '.docx')) and n != 'README.md' and Path(n).name.upper() != 'LICENSE.MD')]
    require(not forbidden, 'Source contains local-only files: ' + repr(forbidden[:10]))


def checked_download(url, destination, digest):
    if destination.exists() and core.sha(destination) == digest:
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(url, headers={'User-Agent': 'Swamphen-VTT-CI'})
    temporary = destination.with_suffix(destination.suffix + '.download')
    with urllib.request.urlopen(request, timeout=120) as response, temporary.open('wb') as output:
        shutil.copyfileobj(response, output)
    require(core.sha(temporary) == digest, 'Toolchain SHA256 mismatch: ' + destination.name)
    temporary.replace(destination)


def toolchain(platform):
    # The existing installer pins the official editor ZIP hash, including console binary.
    import install_godot
    require(install_godot.VERSION == LOCK['godot'], 'Godot installer/lock version mismatch.')
    engine = install_godot.INSTALL / f'Godot_v{LOCK["godot"]}-stable_win64_console.exe'
    # Re-extract from the hash-checked archive even on a cache hit; never trust cached EXEs alone.
    archive = ROOT / 'artifacts/ci-toolchain/editor.zip'
    checked_download(install_godot.BASE + f'Godot_v{LOCK["godot"]}-stable_win64.exe.zip', archive,
                     '731980f9608d61333e5baf54a2ef17210acc7a538446c0cb9969f002aca1e953')
    install_godot.INSTALL.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as z:
        for name in (f'Godot_v{LOCK["godot"]}-stable_win64.exe', engine.name):
            require(name in z.namelist(), 'Missing Godot executable: ' + name)
            (install_godot.INSTALL / name).write_bytes(z.read(name))
    wanted = ['windows_release_x86_64.exe'] if platform == 'windows' else ['android_debug.apk'] if platform == 'android' else list(LOCK['templates'])
    missing = [n for n in wanted if not (ROOT / 'artifacts/export-templates' / n).exists()
               or core.sha(ROOT / 'artifacts/export-templates' / n) != LOCK['templates'][n]]
    if missing:
        with zipfile.ZipFile(install_godot.RemoteZip(install_godot.BASE + f'Godot_v{LOCK["godot"]}-stable_export_templates.tpz')) as z:
            for name in missing:
                data = z.read(next(n for n in z.namelist() if n.endswith('/' + name)))
                require(hashlib.sha256(data).hexdigest() == LOCK['templates'][name], 'Template hash mismatch: ' + name)
                dest = ROOT / 'artifacts/export-templates' / name
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_bytes(data)
    for name, digest in LOCK['licenses'].items():
        checked_download(f'https://raw.githubusercontent.com/godotengine/godot/{LOCK["godot"]}-stable/{name}',
                         ROOT / 'artifacts/godot-licenses' / name, digest)
    return engine


def secret(name, filename):
    raw = os.environ.pop(name, '')
    require(bool(raw), 'Missing protected secret: ' + name)
    KEYS.mkdir(parents=True, exist_ok=True)
    target = KEYS / filename
    target.write_bytes(base64.b64decode(raw, validate=True))
    return target


def export(engine, preset, destination, debug=False):
    destination.parent.mkdir(parents=True, exist_ok=True)
    log = ROOT / 'logs' / ('ci-' + destination.suffix[1:] + '-export.log')
    log.parent.mkdir(exist_ok=True)
    print('::group::Export ' + preset, flush=True)
    run(engine, '--headless', '--path', ROOT, '--log-file', log,
        '--export-debug' if debug else '--export-release', preset, destination)
    text = log.read_text(encoding='utf-8', errors='replace')
    errors = [n for n in text.splitlines() if 'ERROR:' in n and 'No project icon specified' not in n]
    require(destination.exists() and not errors, 'Godot export failed: ' + '\n'.join(errors))
    print('::endgroup::', flush=True)


def verify_apk(apk, version, code):
    with zipfile.ZipFile(apk) as z:
        require(z.testzip() is None, 'APK CRC failed.')
        libs = [n for n in z.namelist() if n.startswith('lib/') and n.endswith('.so')]
        require(bool(libs) and all(n.startswith('lib/arm64-v8a/') for n in libs), 'Unexpected APK architecture.')
        require(not any('terrain_3d/' in n for n in z.namelist()), 'Developer extension in APK.')
    sdk = Path(os.environ['ANDROID_HOME']) / 'build-tools' / LOCK['android_build_tools']
    result = capture(Path(os.environ['JAVA_HOME']) / 'bin/java.exe', '-jar', sdk / 'lib/apksigner.jar', 'verify', '--print-certs', apk)
    require(LOCK['android_certificate_sha256'] in result, 'Android signing certificate changed.')
    manifest = capture(sdk / 'aapt2.exe', 'dump', 'xmltree', apk, '--file', 'AndroidManifest.xml')
    require('="' + LOCK['package'] + '"' in manifest and '="' + version + '"' in manifest, 'APK package/version mismatch.')
    match = re.search(r'versionCode[^\n]*?=\s*(0x[0-9a-f]+|\d+)', manifest, re.I)
    require(match is not None and int(match[1], 0) == code, 'APK version code mismatch.')


def verify_windows(version, channel):
    public = (ROOT / 'assets/updates/release-public.pem').read_bytes()
    record = core.verified((OUT / 'release.json').read_bytes(), (OUT / 'release.sig').read_bytes(), public)
    require(record['version'] == version and record['channel'] == channel, 'Release manifest mismatch.')
    package = OUT / f'svtt-{version}-windows-portable.zip'
    require(core.sha(package) == record['package_sha256'] and package.stat().st_size == record['package_size'], 'ZIP hash mismatch.')
    with zipfile.ZipFile(package) as z:
        require(z.testzip() is None, 'ZIP CRC failed.')
        payload, _, _, mapping = core.archive_layout(z, public)
        require(payload['version'] == version and payload['files'] == record['files'], 'Payload mismatch.')
        for name, canonical in mapping.items():
            data = z.read(name)
            meta = payload['files'][canonical]
            require(len(data) == meta['size'] and hashlib.sha256(data).hexdigest() == meta['sha256'], 'Payload file mismatch: ' + name)


def build(args):
    require(os.environ.get('GITHUB_ACTIONS') == 'true', 'This entry is for GitHub Actions; use local export scripts on your computer.')
    validate(args.version, args.platform, args.android_code)
    commit = capture('git', 'rev-parse', 'HEAD').strip()
    public_source(commit)
    project = (ROOT / 'project.godot').read_text(encoding='utf-8')
    require(f'config/version="{args.version}"' in project, 'Commit the requested project version before building.')
    require(not OUT.exists(), 'CI output already exists; download the earlier artifact instead of rebuilding.')
    OUT.mkdir(parents=True)
    assets = []
    try:
        engine = toolchain(args.platform)
        if args.platform in ('all', 'windows'):
            from cryptography.hazmat.primitives import serialization
            key = secret('RELEASE_SIGNING_KEY_B64', 'release-private.pem')
            actual = serialization.load_pem_private_key(key.read_bytes(), password=None).public_key()
            expected = serialization.load_pem_public_key((ROOT / 'assets/updates/release-public.pem').read_bytes())
            require(actual.public_numbers() == expected.public_numbers(), 'Update signing key does not match application public key.')
            program = ROOT / 'build/ci-work/program'
            program.mkdir(parents=True)
            export(engine, 'Windows', program / core.ENTRY)
            run(sys.executable, '-m', 'PyInstaller', '--noconfirm', '--clean', '--windowed', '--onedir', '--name', core.BOOT.removesuffix('.exe'),
                '--distpath', ROOT / 'build/ci-work/boot', '--workpath', ROOT / 'build/ci-work/pyinstaller', '--specpath', ROOT / 'artifacts/ci-spec',
                '--paths', ROOT / 'launcher', '--add-data', str(ROOT / 'assets/updates/release-public.pem') + ';.', ROOT / 'launcher/main.py')
            boot = ROOT / 'build/ci-work/boot' / core.BOOT.removesuffix('.exe')
            for target in (program, boot):
                run(sys.executable, ROOT / 'tools/collect_release_licenses.py', '--boot', target)
            run(sys.executable, ROOT / 'tools/package_portable.py', '--program', program, '--boot', boot, '--version', args.version,
                '--private-key', key, '--output', OUT, '--channel', args.channel, '--notes', args.notes,
                '--base-url', f'https://github.com/{core.REPOSITORY}/releases/download/v{args.version}/')
            verify_windows(args.version, args.channel)
            assets += [OUT / f'svtt-{args.version}-windows-portable.zip', OUT / 'release.json', OUT / 'release.sig']
        if args.platform in ('all', 'android'):
            key = secret('ANDROID_KEYSTORE_B64', 'android.keystore')
            password = os.environ.pop('ANDROID_KEYSTORE_PASSWORD', '')
            alias = os.environ.pop('ANDROID_KEYSTORE_ALIAS', '')
            require(bool(password) and bool(alias), 'Android signing configuration missing.')
            settings = Path(os.environ['APPDATA']) / 'Godot' / 'editor_settings-4.7.tres'
            settings.parent.mkdir(parents=True, exist_ok=True)
            values = {'export/android/java_sdk_path': os.environ['JAVA_HOME'], 'export/android/android_sdk_path': os.environ['ANDROID_HOME'],
                      'export/android/debug_keystore': key.as_posix(), 'export/android/debug_keystore_user': alias,
                      'export/android/debug_keystore_pass': password}
            settings.write_text('[gd_resource type="EditorSettings" format=3]\n\n[resource]\n' + ''.join(k + '=' + json.dumps(v.replace('\\', '/'), ensure_ascii=False) + '\n' for k, v in values.items()), encoding='utf-8')
            presets = ROOT / 'export_presets.cfg'
            text = presets.read_text(encoding='utf-8')
            code = args.android_code or int(re.search(r'version/code=(\d+)', text)[1])
            text = re.sub(r'version/code=\d+', 'version/code=' + str(code), text)
            text = re.sub(r'version/name="[^"]+"', f'version/name="{args.version}"', text)
            presets.write_text(text, encoding='utf-8')
            apk = OUT / f'svtt-{args.version}-android-arm64-test.apk'
            export(engine, 'Android ARM64 Test', apk, debug=True)
            verify_apk(apk, args.version, code)
            assets.append(apk)
        checks = {p.name: {'size': p.stat().st_size, 'sha256': core.sha(p)} for p in assets}
        (OUT / 'SHA256SUMS.txt').write_text(''.join(v['sha256'] + '  ' + k + '\n' for k, v in checks.items()), encoding='ascii')
        checks['SHA256SUMS.txt'] = {'size': (OUT / 'SHA256SUMS.txt').stat().st_size, 'sha256': core.sha(OUT / 'SHA256SUMS.txt')}
        record = {'version': args.version, 'channel': args.channel, 'platform': args.platform, 'source_commit': commit,
                  'run_url': f'https://github.com/{core.REPOSITORY}/actions/runs/{os.environ["GITHUB_RUN_ID"]}', 'assets': checks}
        if args.platform in ('all', 'android'):
            record['android_code'] = code
        (OUT / 'build-check.json').write_text(json.dumps(record, indent=2), encoding='utf-8')
        print('Build verified: ' + json.dumps(record, ensure_ascii=False), flush=True)
    finally:
        cleanup()


def cleanup():
    shutil.rmtree(KEYS, ignore_errors=True)
    if os.environ.get('GITHUB_ACTIONS') == 'true':
        settings = Path(os.environ['APPDATA']) / 'Godot/editor_settings-4.7.tres'
        settings.unlink(missing_ok=True)


def publish(args):
    from release_upload_progress import upload
    record = json.loads((OUT / 'build-check.json').read_text())
    require(record['source_commit'] == capture('git', 'rev-parse', 'HEAD').strip(), 'Artifact/source commit mismatch.')
    require(record['version'] == args.version and record['channel'] == args.channel, 'Artifact request mismatch.')
    require(record['platform'] == args.platform, 'Artifact platform mismatch.')
    public_source(record['source_commit'])
    files = []
    for name, meta in record['assets'].items():
        require(Path(name).name == name, 'Invalid asset path.')
        p = OUT / name
        require(p.stat().st_size == meta['size'] and core.sha(p) == meta['sha256'], 'Artifact hash mismatch: ' + name)
        files.append(p)
    env = os.environ.copy()
    tag = 'v' + args.version
    def gh(*parts):
        return json.loads(capture('gh', *parts))
    tags = gh('api', f'repos/{core.REPOSITORY}/git/matching-refs/tags/{tag}')
    if any(item['ref'] == 'refs/tags/' + tag for item in tags):
        tagged = gh('api', f'repos/{core.REPOSITORY}/commits/{tag}')
        require(tagged['sha'] == record['source_commit'], 'Existing tag belongs to another source commit.')
    probe = subprocess.run(['gh', 'release', 'view', tag, '--repo', core.REPOSITORY, '--json', 'isDraft,targetCommitish'], capture_output=True, text=True)
    notes = ROOT / 'build/ci-notes.txt'
    notes.write_text(args.notes + '\n\nSource: ' + record['source_commit'] + '\nBuild: ' + record['run_url'], encoding='utf-8')
    if probe.returncode == 0:
        existing = json.loads(probe.stdout)
        check_draft(existing, record['source_commit'])
    else:
        # Distinguish a missing release from permissions/network errors.
        gh('repo', 'view', core.REPOSITORY, '--json', 'name')
        run('gh', 'release', 'create', tag, '--repo', core.REPOSITORY, '--draft', '--target', record['source_commit'], '--title', tag,
            '--notes-file', notes, '--prerelease=' + str(args.channel == 'testing').lower())
    run('gh', 'release', 'edit', tag, '--repo', core.REPOSITORY, '--notes-file', notes, '--prerelease=' + str(args.channel == 'testing').lower())
    upload(files, core.REPOSITORY, tag, env)
    remote = gh('release', 'view', tag, '--repo', core.REPOSITORY, '--json', 'assets,isDraft,url')
    require(remote['isDraft'], 'Release became public before verification.')
    actual = {a['name']: a for a in remote['assets']}
    require(set(actual) == set(record['assets']), 'Unexpected draft attachments; inspect draft before retrying.')
    for name, meta in record['assets'].items():
        require(actual[name]['size'] == meta['size'] and actual[name]['digest'] == 'sha256:' + meta['sha256'], 'Remote digest mismatch: ' + name)
    if args.mode == 'publish':
        run('gh', 'release', 'edit', tag, '--repo', core.REPOSITORY, '--draft=false')
    final = gh('release', 'view', tag, '--repo', core.REPOSITORY, '--json', 'isDraft,isPrerelease,url')
    require(final['isDraft'] == (args.mode != 'publish') and final['isPrerelease'] == (args.channel == 'testing'), 'Final release state mismatch.')
    print(final['url'], flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=['build', 'publish', 'clean', 'check'])
    parser.add_argument('--version', default='0.0.0')
    parser.add_argument('--platform', default='all')
    parser.add_argument('--android-code', type=int, default=0)
    parser.add_argument('--channel', choices=['testing', 'stable'], default='testing')
    parser.add_argument('--notes', default='')
    parser.add_argument('--mode', choices=['draft', 'publish'], default='draft')
    args = parser.parse_args()
    if args.command == 'clean': cleanup()
    elif args.command == 'check':
        public_source('HEAD')
        import py_compile
        for path in [*ROOT.glob('tools/*.py'), *ROOT.glob('launcher/*.py')]: py_compile.compile(str(path), doraise=True)
    elif args.command == 'build': build(args)
    else: publish(args)


if __name__ == '__main__':
    main()

"""Verify existing CI packages and start the packaged Windows application only."""
import argparse
import json
from pathlib import Path
import subprocess
import zipfile

import ci_release as ci


def verify(directory, version, channel, platform, source, skip_startup=False):
    directory = directory.resolve()
    record = json.loads((directory / 'build-check.json').read_text())
    ci.require(record['source_commit'] == source, 'Build source does not match the trusted workflow run.')
    ci.require((record['version'], record['channel'], record['platform']) == (version, channel, platform), 'Artifact request mismatch.')
    for name, meta in record['assets'].items():
        ci.require(Path(name).name == name, 'Invalid asset name.')
        file = directory / name
        ci.require(file.stat().st_size == meta['size'] and ci.core.sha(file) == meta['sha256'], 'Artifact hash mismatch: ' + name)
    result = {'source_commit': source, 'version': version, 'assets': record['assets'], 'windows_startup': 'not applicable'}
    if platform in ('all', 'windows'):
        ci.OUT = directory
        ci.verify_windows(version, channel)
        if skip_startup:
            result['windows_startup'] = 'skipped: explicit user request; not verified'
            (directory / 'verification.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
            print(json.dumps(result, ensure_ascii=False), flush=True)
            return
        package = directory / f'svtt-{version}-windows-portable.zip'
        preview = directory / 'startup-check'
        ci.require(not preview.exists(), 'Startup check directory already exists.')
        with zipfile.ZipFile(package) as archive:
            for entry in archive.infolist():
                ci.core.child(preview, entry.filename.rstrip('/'))
            archive.extractall(preview)
        executable = preview / '紫水鸡棋盘' / 'versions' / version / ci.core.ENTRY
        log = directory / 'windows-startup.log'
        process = subprocess.run([str(executable), '--headless', '--log-file', str(log), '--quit-after', '180', '--max-fps', '60', '--', '--page=home'], cwd=executable.parent, timeout=90)
        ci.require(process.returncode == 0 and log.exists(), 'Packaged Windows application failed to start/exit.')
        text = log.read_text(encoding='utf-8', errors='replace')
        ci.require('启动项目：' in text and 'ERROR:' not in text and 'SCRIPT ERROR' not in text, 'Packaged application startup error; see windows-startup.log.')
        result['windows_startup'] = 'passed: headless home startup only; no gameplay or visual validation'
    (directory / 'verification.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps(result, ensure_ascii=False), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--channel', choices=['testing', 'stable'], required=True)
    parser.add_argument('--platform', choices=['all', 'windows', 'android'], required=True)
    parser.add_argument('--source', required=True)
    parser.add_argument('--skip-startup', action='store_true')
    args = parser.parse_args()
    verify(args.directory, args.version, args.channel, args.platform, args.source, args.skip_startup)

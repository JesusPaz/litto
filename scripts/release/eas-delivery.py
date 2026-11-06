#!/usr/bin/env python3
"""Dispatch the tested source to EAS and retrieve only the expected Mac assets."""
import datetime
import json
import os
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile
import urllib.request
import tarfile
import importlib.util
from version import parse

_spec = importlib.util.spec_from_file_location('build_number', Path(__file__).with_name('build-number.py'))
_module = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_module)
build_number = _module.build_number


def expected_assets(tag):
    parse(tag)
    return {f'Litto-{tag}-macOS.dmg', f'Litto-{tag}-macOS.zip', 'SHA256SUMS'}


def extract_assets(archive, destination, tag):
    expected = expected_assets(tag)
    with tarfile.open(archive, 'r:gz') as bundle:
        files = {}
        for item in bundle.getmembers():
            if item.isdir():
                continue
            if not item.isfile():
                raise ValueError('Release artifacts must be regular files')
            name = Path(item.name).name
            if name not in expected or name in files:
                raise ValueError('Unexpected or duplicate release artifact')
            files[name] = item
        if set(files) != expected:
            raise ValueError('Incomplete Mac release artifacts')
        destination.mkdir(exist_ok=True)
        for name, item in files.items():
            (destination / name).write_bytes(bundle.extractfile(item).read())


def main():
    tag, platform = sys.argv[1:]
    parse(tag)
    if platform not in ('all', 'ios', 'mac'):
        raise ValueError('Expected all, ios or mac')
    if subprocess.check_output(['git', 'status', '--porcelain']).strip():
        raise ValueError('Delivery requires a clean source tree')
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
    number = build_number(datetime.datetime.now(datetime.timezone.utc))
    # Export only tracked files: never upload local .env, signing keys or build output.
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        source = root / 'source'
        source.mkdir()
        archive = root / 'source.tar'
        subprocess.run(['git', 'archive', '--format=tar', '-o', str(archive), commit], check=True)
        subprocess.run(['tar', '-xf', str(archive), '-C', str(source)], check=True)
        (source / '.litto-source-commit').write_text(commit + '\n')
        subprocess.run(['git', 'init', '-q', str(source)], check=True)
        subprocess.run(['git', 'add', '.'], cwd=source, check=True)
        subprocess.run(['git', '-c', 'user.name=Litto Delivery', '-c', 'user.email=delivery@localhost',
                        '-c', 'commit.gpgsign=false', 'commit', '-qm', f'Source {commit}'], cwd=source, check=True)
        command = ['eas', 'workflow:run', '.eas/workflows/apple.yml', '--non-interactive', '--wait', '--json',
                   '-F', f'tag={tag}', '-F', f'build={number}', '-F', f'commit={commit}', '-F', f'platform={platform}']
        result = subprocess.run(command, cwd=source, stdout=subprocess.PIPE, text=True)
        # Preserve the run ID on failures too, so operators can inspect before retrying an upload.
        run = json.loads(result.stdout)
        print(f'EAS run: {run["id"]}; Apple build: {number}', flush=True)
        result.check_returncode()
        detail = json.loads(subprocess.check_output(['eas', 'workflow:view', run['id'], '--json', '--non-interactive'], cwd=source))
        if platform != 'ios':
            job = next(job for job in detail['jobs'] if job['key'] == 'mac')
            artifacts = job.get('artifacts') or []
            if len(artifacts) != 1:
                raise ValueError('Expected exactly one Mac artifact bundle')
            url = artifacts[0]['downloadUrl']
            if not url.startswith('https://'):
                raise ValueError('Expected HTTPS artifact download')
            bundle = root / 'mac.tar.gz'
            request = urllib.request.Request(url, headers={'User-Agent': 'Litto-Release/1.0'})
            with urllib.request.urlopen(request, timeout=60) as response, bundle.open('wb') as output:
                shutil.copyfileobj(response, output)
            extract_assets(bundle, Path('dist'), tag)
            subprocess.run(['shasum', '-a', '256', '-c', 'SHA256SUMS'], cwd='dist', check=True)
        summary = os.environ.get('GITHUB_STEP_SUMMARY')
        if summary:
            with open(summary, 'a') as handle:
                handle.write(f'Apple build {number}, source `{commit}`, EAS run `{run["id"]}`.\n')


if __name__ == '__main__':
    main()

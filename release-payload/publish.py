"""Publish the locally verified, signed v0.2.0 payload using the job token."""
import hashlib
import json
import os
from pathlib import Path
import subprocess

repo = os.environ['GITHUB_REPOSITORY']
assert repo == 'chujianyun/wnip'
tag = 'v0.2.0'
commit = '7b3a1b639ccbf3e9226ebaa4fb2e2f45e9abeca4'
title = 'Wnip v0.2.0 · 截图加背景'
folder = Path(__file__).resolve().parent

def gh(*args, payload=None):
    command = ['gh', *args]
    if payload is not None:
        command += ['--input', '-']
    result = subprocess.run(command, input=json.dumps(payload) if payload is not None else None,
                            check=True, text=True, capture_output=True)
    return json.loads(result.stdout) if result.stdout.strip() else None

ref = gh('api', f'repos/{repo}/git/ref/tags/{tag}')['object']
if ref['type'] == 'tag':
    ref = gh('api', f'repos/{repo}/git/tags/{ref["sha"]}')['object']
assert ref['type'] == 'commit' and ref['sha'] == commit
expected = {}
for line in (folder/'Wnip-0.2.0-SHA256SUMS.txt').read_text().splitlines():
    digest, name = line.split()
    assert Path(name).name == name
    assert hashlib.sha256((folder/name).read_bytes()).hexdigest() == digest
    expected[name] = 'sha256:' + digest
checksum = folder/'Wnip-0.2.0-SHA256SUMS.txt'
expected[checksum.name] = 'sha256:' + hashlib.sha256(checksum.read_bytes()).hexdigest()
releases = gh('api', f'repos/{repo}/releases')
matching = [r for r in releases if r['tag_name'] == tag or (r['draft'] and r['name'] == title)]
assert len(matching) <= 1, 'Ambiguous existing release; refusing to overwrite'
body = (folder/'notes.md').read_text()
if matching:
    release = gh('api', '--method', 'PATCH', f'repos/{repo}/releases/{matching[0]["id"]}',
                 payload={'tag_name': tag, 'target_commitish': commit, 'name': title, 'body': body})
else:
    release = gh('api', '--method', 'POST', f'repos/{repo}/releases',
                 payload={'tag_name': tag, 'target_commitish': commit, 'name': title, 'body': body, 'draft': True})
subprocess.run(['gh', 'release', 'upload', tag, '--repo', repo,
                *[str(folder/name) for name in expected]], check=True)
release = gh('api', f'repos/{repo}/releases/{release["id"]}')
assets = {a['name']: a for a in release['assets']}
assert set(assets) == set(expected)
for name, digest in expected.items():
    assert assets[name]['state'] == 'uploaded'
    assert assets[name]['digest'] == digest
    assert assets[name]['size'] == (folder/name).stat().st_size
release = gh('api', '--method', 'PATCH', f'repos/{repo}/releases/{release["id"]}',
             payload={'draft': False, 'prerelease': False, 'make_latest': 'true'})
assert not release['draft'] and release['tag_name'] == tag
print(release['html_url'])
print('Published 3 assets with verified SHA-256 digests.')

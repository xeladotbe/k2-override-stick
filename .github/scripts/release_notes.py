"""Release notes for a tag (stdout): the annotated tag's message first (upgrade notes the commits can't tell), then the
Conventional Commits since the previous tag, grouped by type, then the usual upgrade steps.

Usage: release_notes.py <tag>   (a tag that doesn't exist yet previews HEAD under that name)
"""
import os
import re
import subprocess
import sys

GROUPS = [('feat', 'Features'), ('fix', 'Fixes'), ('perf', 'Improvements'), ('refactor', 'Changes'),
          ('docs', 'Documentation'), ('other', 'Other')]
SKIP = {'chore', 'ci', 'test', 'build', 'style'}
HEADER = re.compile(r'^(?P<type>[a-z]+)(?:\((?P<scope>[^)]*)\))?(?P<bang>!)?: (?P<desc>.+)$')


def git(*args):
    return subprocess.run(['git', *args], capture_output=True, text=True, encoding='utf-8').stdout


def main():
    tag = sys.argv[1]
    exists = git('rev-parse', '-q', '--verify', 'refs/tags/' + tag).strip() != ''
    end = tag if exists else 'HEAD'
    prev = git('describe', '--tags', '--abbrev=0', end + '^').strip()
    out = []

    if exists and git('cat-file', '-t', tag).strip() == 'tag':
        message = git('tag', '-l', '--format=%(contents)', tag).strip()
        if message:
            out += [message, '']

    groups = {key: [] for key, _ in GROUPS}
    log = git('log', '--no-merges', '--format=%h %s', (prev + '..' if prev else '') + end)
    for line in log.splitlines():
        sha, subject = line.split(' ', 1)
        m = HEADER.match(subject)
        kind = m.group('type') if m else 'other'
        if kind in SKIP:
            continue
        desc = m.group('desc') if m else subject
        scope = m.group('scope') if m else None
        breaking = '**Breaking:** ' if m and m.group('bang') else ''
        groups[kind if kind in groups else 'other'].append(
            '- %s%s (%s%s)' % (breaking, desc, ('`%s`, ' % scope) if scope else '', sha))

    out.append('## Changes since %s' % prev if prev else '## Changes')
    for key, title in GROUPS:
        if groups[key]:
            out += ['', '### ' + title] + groups[key]

    out += ['', '## Upgrading',
            '**With the stick:** download `k2-overrides.zip` below, copy the `k2-overrides` folder to the stick again '
            'and plug it in. Your `00_user_config.cfg` is not in the download and stays as it is.', '',
            '**Manual install:** upload all `.cfg` files from `k2-overrides.zip` (new files included, '
            '`k2_overrides.cfg` includes every one of them), then run `FIRMWARE_RESTART`.']

    repo = os.environ.get('GITHUB_REPOSITORY', 'xeladotbe/k2-override-stick')
    if prev:
        out += ['', 'Full diff: https://github.com/%s/compare/%s...%s' % (repo, prev, tag)]

    sys.stdout.reconfigure(encoding='utf-8')
    print('\n'.join(out))


if __name__ == '__main__':
    main()

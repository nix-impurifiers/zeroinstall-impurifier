#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Import an offline closure for an existing, verified per-user native cache."""
import json
import os
from pathlib import Path
import pwd
import re
import shutil
import subprocess
import sys
import tempfile


def main():
    if os.geteuid() != 0 or len(sys.argv) != 2:
        raise ValueError('use as root: prepare.py NATIVE_IMPLEMENTATION_DIRECTORY')
    implementation = Path(sys.argv[1]).resolve(strict=True)
    owner = implementation.stat().st_uid
    if owner == 0:
        raise ValueError('prepare requires a per-user Zero Install cache')
    username = pwd.getpwuid(owner).pw_name
    digest = subprocess.check_output(['0install', 'digest', '--algorithm=sha256new', str(implementation)], text=True).strip()
    if digest != implementation.name:
        raise ValueError('native implementation content does not match its cache digest')
    spec = json.loads((implementation / 'application.json').read_text())
    target = spec['installable']
    if not re.fullmatch(r'/nix/store/[0-9abcdfghijklmnpqrsvwxyz]{32}-[A-Za-z0-9+._?=-]+', target):
        raise ValueError('invalid Nix store target')
    if not spec['offline'] or not (implementation / 'cache/nix-cache-info').is_file():
        raise ValueError('implementation does not carry an offline Nix cache')
    if not (implementation / 'nix-root').is_symlink() or os.readlink(implementation / 'nix-root') != target:
        raise ValueError('native cache root does not identify the selected Nix application')
    nix_store = shutil.which('nix-store')
    if not nix_store:
        raise ValueError('a working host Nix provider is required')
    with tempfile.TemporaryDirectory(prefix='zeroinstall-prepare-') as temporary:
        subprocess.run([nix_store, '--realise', target, '--option', 'substituters', (implementation / 'cache').as_uri(), '--option', 'require-sigs', 'false', '--option', 'builders', '', '--add-root', temporary + '/root', '--indirect'], check=True)
        original_mode = implementation.stat().st_mode & 0o777
        implementation.chmod(original_mode | 0o200)
        try:
            subprocess.run(['runuser', '-u', username, '--', nix_store, '--realise', target, '--add-root', str(implementation / 'nix-root'), '--indirect'], check=True)
        finally:
            implementation.chmod(original_mode)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print('zeroinstall-impurifier prepare: ' + str(error), file=sys.stderr)
        sys.exit(1)

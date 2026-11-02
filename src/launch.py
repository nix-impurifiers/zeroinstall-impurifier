#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Realize a Nix application while leaving native Zero Install ownership intact."""
import fcntl
import json
import hashlib
import importlib.util
import os
from pathlib import Path
import subprocess
import shlex
import sys


def main():
    implementation = Path(__file__).resolve().parent
    spec = json.loads((implementation / 'application.json').read_text())
    state = Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state'))) / 'zeroinstall-impurifier' / implementation.name
    state.mkdir(parents=True, exist_ok=True)
    with (state / 'lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        location = state / 'implementation'
        if not location.is_symlink():
            location.symlink_to(implementation)
        command = ['nix-store', '--realise', spec['installable']]
        if spec['offline'] and not Path(spec['installable']).exists():
            command += ['--option', 'substituters', (implementation / 'cache').as_uri(), '--option', 'require-sigs', 'false', '--option', 'builders', '']
        try:
            subprocess.run(command, check=True)
        except subprocess.CalledProcessError:
            if spec['offline'] and os.geteuid() != 0:
                print('Offline import may need root preparation: sudo zeroinstall-impurifier prepare ' + shlex.quote(str(implementation)), file=sys.stderr)
            raise
        # The existing native-cache symlink has the same target before/after
        # registration. Its content digest therefore remains unchanged.
        original_mode = implementation.stat().st_mode & 0o777
        implementation.chmod(original_mode | 0o200)
        try:
            subprocess.run(['nix-store', '--realise', spec['installable'], '--add-root', str(implementation / 'nix-root'), '--indirect'], check=True)
        finally:
            implementation.chmod(original_mode)
    executable = spec['installable'] + '/bin/' + spec['program']
    environment = os.environ.copy()
    if spec.get('hardware'):
        module_spec = importlib.util.spec_from_file_location('impurifier_engine', implementation / 'engine.py')
        engine = importlib.util.module_from_spec(module_spec)
        module_spec.loader.exec_module(engine)
        manifest = engine.validate({'name': spec['name'], 'version': spec['version'], 'priority': 5, 'installable': spec['installable'], 'hardware': spec['hardware']}, 'zeroinstall-impurifier')
        # Capture and root a fresh immutable snapshot before starting the app.
        with (state / 'lock').open('w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            snapshot = engine.hardware_snapshots([manifest], state)[spec['name']]
            key = hashlib.sha256(snapshot.encode()).hexdigest()
            subprocess.run(['nix-store', '--realise', snapshot, '--add-root', str(state / ('library-' + key)), '--indirect'], check=True)
            environment['LD_LIBRARY_PATH'] = snapshot + (':' + environment['LD_LIBRARY_PATH'] if environment.get('LD_LIBRARY_PATH') else '')
            preload = [str(Path(snapshot) / name) for name in spec['hardware']['preload']]
            if preload:
                environment['LD_PRELOAD'] = ' '.join(preload) + (' ' + environment['LD_PRELOAD'] if environment.get('LD_PRELOAD') else '')
    os.execve(executable, [spec['program'], *sys.argv[1:]], environment)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print('zeroinstall-impurifier: ' + str(error), file=sys.stderr)
        sys.exit(1)

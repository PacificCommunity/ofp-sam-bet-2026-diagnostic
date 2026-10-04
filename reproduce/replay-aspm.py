#!/usr/bin/env python3
"""Replay preserved ASPM reports; require the complete original REP checksum."""
import argparse
import json
import math
from pathlib import Path
import platform
import re
import subprocess
import restore
from native_directory import NativeDirectory

POLICIES = {
    'constant': {'source_par_sha256': '813398732e0356c5b8715e264bc984b6373b75819c3a35c03c2c548e43ce57fe',
                 'input': 'aspm-input-final.par', 'output': 'aspm.par',
                 'rep_sha256': '2803c87af4232cf7a5f2797d51d9a4bf8d3b6d355373770820d756c381d9f0a7',
                 'rep_bytes': 2868428, 'objective': -394.782832716888, 'source_role': 'original terminal PAR'},
    'fitted': {'source_par_sha256': '0450a2f159e3d31aa10bb1f856179058a185faa8224f14c4ab8b1117e64dba94',
               'input': 'aspm-input-aspm.par', 'output': 'aspm-restart-1.par',
               'rep_sha256': '39ccb835cc6b88395049905b057d75d1e870a7727c27e39445a8645bebbad12c',
               'rep_bytes': 2847026, 'objective': -1069.12558223634,
               'source_role': 'original pre-restart PAR; original terminal PAR and restart input remain unavailable'}
}

def scalar(data, marker):
    lines = data.decode().splitlines()
    indexes = [i for i, line in enumerate(lines) if line.strip() == marker]
    if len(indexes) != 1 or indexes[0] + 1 >= len(lines):
        raise ValueError('Missing or duplicate PAR value: ' + marker)
    tokens = lines[indexes[0] + 1].split()
    if len(tokens) != 1:
        raise ValueError('Malformed PAR value: ' + marker)
    value = float(tokens[0])
    if not math.isfinite(value):
        raise ValueError('Nonfinite PAR value: ' + marker)
    return value

def replay(case, path):
    policy = POLICIES[case]
    with restore.frozen_bytes(restore.HERE / 'package.json') as data:
        recipe = json.loads(data)
    manifest, closure = restore.read_json(recipe['manifest']), restore.read_json(recipe['closure'])
    payload = restore.archive_files(recipe, manifest)
    name = 'aspm-' + case
    models = [row for row in closure['models'] if row['model'] == name]
    if len(models) != 1:
        raise ValueError('Missing original ASPM source closure')
    before = payload[name + '/aspm.par']
    if restore.digest(before) != policy['source_par_sha256']:
        raise ValueError('Original source PAR checksum differs')
    files = {}
    for row in models[0]['reused_git_files']:
        target = row.get('target_name', Path(row['path']).name)
        NativeDirectory.filename(target)
        if target in files:
            raise ValueError('Duplicate source target')
        files[target] = (restore.git_bytes(row), row['mode'])
    if not restore.NATIVE_INPUTS <= files.keys():
        raise ValueError('Original native input closure is incomplete')
    engine = recipe['engine']
    files['mfclo64'] = (restore.git_bytes(engine), engine['mode'])
    files['saved-aspm.par'] = (before, 0o600)
    controls = payload[name + '/aspm_control.txt']
    files['aspm_control.txt'] = (controls, 0o600)
    if controls.decode().splitlines().count('1 1 10000') != 1:
        raise ValueError('Original evaluation limit is ambiguous')
    quick = controls.decode().replace('1 1 10000', '1 1 1') + '1 246 1\n'
    restore.save_files(path, files, name + '-report-replay')
    with NativeDirectory(path) as output:
        def unchanged():
            for filename, (original, _) in files.items():
                if output.read_bytes(filename) != original:
                    raise ValueError('Source input changed: ' + filename)
        unchanged()
        output.write_new(policy['input'], before)
        with output.open_input('mfclo64') as (fd, executable):
            if restore.digest(executable) != engine['sha256']:
                raise ValueError('Native engine checksum differs')
            with output.open_new('mfcl-native.log') as log:
                result = subprocess.run([output.child_file(fd), 'bet.frq', policy['input'],
                                         policy['output'], '-file', '-'], input=quick.encode(),
                                        stdout=log, stderr=subprocess.STDOUT, timeout=600,
                                        **output.child_kwargs(fd))
        unchanged()
        if output.read_bytes(policy['input']) != before:
            raise ValueError('Replay input PAR changed')
        if result.returncode not in (0, 3):
            raise ValueError('Native replay failed: status ' + str(result.returncode))
        par = output.read_bytes(policy['output'])
        report = output.read_bytes('plot-' + policy['output'] + '.rep')
        count = scalar(par, '# The number of parameters')
        objective = scalar(par, '# Objective function value')
        values = re.findall(r'^\s*Total func\s+([^\s]+)\s*$', output.read_bytes('mfcl-native.log').decode(), re.MULTILINE)
        first = float(values[0]) if values else math.nan
        if (count != 1 or scalar(before, '# The number of parameters') != 1
                or not math.isfinite(first) or max(abs(objective-policy['objective']), abs(first-policy['objective'])) > 1e-6):
            raise ValueError('Original ASPM objective or active count differs')
        if len(report) != policy['rep_bytes'] or restore.digest(report) != policy['rep_sha256']:
            raise ValueError('Complete original ASPM REP checksum differs')
        unchanged()
        receipt = {'case': case, 'source_role': policy['source_role'], 'source_par_sha256': restore.digest(before),
                   'original_terminal_par_recovered': case == 'constant',
                   'original_complete_rep_sha256': policy['rep_sha256'], 'native_report_sha256': restore.digest(report),
                   'complete_rep_bytes_match': True, 'objective': objective, 'first_logged_objective': first,
                   'active_parameters': 1, 'native_status': result.returncode, 'function_evaluation_limit': 1,
                   'source_inputs_unchanged': True, 'mfcl_sha256': engine['sha256']}
        output.write_new('native-check.json', (json.dumps(receipt, indent=2)+'\n').encode())
        print(case + ': complete original ASPM REP reproduced', flush=True)
        return receipt

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('case', choices=POLICIES)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    if platform.system() != 'Linux' or platform.machine() not in ('x86_64', 'amd64'):
        parser.error('Native MFCL requires 64-bit x86 Linux')
    if args.output.exists() or args.output.is_symlink():
        parser.error('Choose a new output directory')
    output = args.output.resolve()
    if output == restore.REPO or restore.REPO in output.parents and restore.REPO/'outputs' not in output.parents:
        parser.error('Output inside the checkout must be beneath outputs/')
    replay(args.case, output)

if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, UnicodeError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        raise SystemExit(str(error))

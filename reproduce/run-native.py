#!/usr/bin/env python3
"""Evaluate preserved profile and constant ASPM cases in fresh directories."""
import argparse
import concurrent.futures
import contextlib
import hashlib
import json
import math
from pathlib import Path
import platform
import re
import subprocess
import sys
import restore
from native_directory import NativeDirectory, original_files

HERE = Path(__file__).resolve().parent


def sha(data):
    return hashlib.sha256(data).hexdigest()


def scalar(data, marker):
    lines = data.decode().splitlines()
    indexes = [i for i, line in enumerate(lines) if line.strip() == marker]
    if len(indexes) != 1:
        raise ValueError('Missing or duplicate PAR field: ' + marker)
    value = float(lines[indexes[0] + 1].strip())
    if not math.isfinite(value):
        raise ValueError('Nonfinite PAR field: ' + marker)
    return value


def native_command(policy, output):
    prefix = ['./mfclo64', 'bet.frq', 'input.par', 'evaluated.par']
    if policy['kind'] == 'profile':
        switches = policy['original_zero_penalty_switch']
        if (switches[:2] != ['-switch', '10'] or len(switches) != 32
                or switches[5:8] != ['1', '1', '1']):
            raise ValueError('Invalid original one-evaluation profile recipe')
        # Keep the original objective switches; request native biomass outputs.
        return prefix + ['-switch', '11'] + switches[2:] + ['1', '246', '1'], None
    if policy['kind'] == 'aspm':
        original = output.read_bytes('aspm_control.txt').decode()
        if original.splitlines().count('1 1 10000') != 1:
            raise ValueError('Original ASPM evaluation limit is ambiguous')
        controls = original.replace('1 1 10000', '1 1 1') + '1 246 1\n'
        return prefix + ['-file', '-'], controls.encode()
    return prefix + ['-file', '-'], b'1 1 1\n1 246 1\n'


def evaluate(case, output, policy, directory=None):
    if policy.get('original_last_par_available') is False:
        raise ValueError('Original terminal PAR missing for ' + case)
    if directory is None:
        subprocess.run([sys.executable, str(HERE / 'restore.py'), case, str(output)], check=True)
    with (contextlib.nullcontext(directory) if directory is not None else NativeDirectory(output)) as output:
        saved = json.loads(output.read_bytes('saved-inputs.json'))['files']

        def unchanged():
            for name, row in saved.items():
                data = output.read_bytes(name)
                if len(data) != row['bytes'] or sha(data) != row['sha256']:
                    raise ValueError('Saved input changed: ' + name)

        unchanged()
        before = output.read_bytes('final.par')
        output.write_new('input.par', before)
        command, controls = native_command(policy, output)
        with output.open_input('mfclo64') as (engine_fd, engine_bytes):
            if sha(engine_bytes) != saved['mfclo64']['sha256']:
                raise ValueError('Native executable changed before evaluation')
            command[0] = output.child_file(engine_fd)
            with output.open_new('mfcl-native.log') as log:
                result = subprocess.run(command, input=controls, stdout=log,
                                        stderr=subprocess.STDOUT, timeout=600,
                                        **output.child_kwargs(engine_fd))
        unchanged()
        if sha(output.read_bytes('input.par')) != sha(before):
            raise ValueError('Staged final PAR changed for ' + case)
        if result.returncode not in (0, 3):
            raise ValueError(f'Native evaluation failed for {case}: status {result.returncode}')
        par = output.read_bytes('evaluated.par')
        report = output.read_bytes('plot-evaluated.par.rep')
        if not par or not report:
            raise ValueError('Empty native output for ' + case)
        expected = (policy['original_profile_nll'] if policy['kind'] == 'profile'
                    else policy['original_objective'] if policy['kind'] == 'aspm'
                    else scalar(before, '# Objective function value'))
        count = scalar(par, '# The number of parameters')
        original_count = scalar(before, '# The number of parameters')
        if count != original_count or count <= 0 or count != int(count):
            raise ValueError('Active parameter count changed for ' + case)
        if policy['kind'] == 'aspm' and count != policy['original_active_parameters']:
            raise ValueError('ASPM active count differs from original result')
        objective = scalar(par, '# Objective function value')
        values = re.findall(r'^\s*Total func\s+([^\s]+)\s*$',
                            output.read_bytes('mfcl-native.log').decode(), re.MULTILINE)
        logged = float(values[0]) if values else math.nan
        if (not math.isfinite(expected) or not math.isfinite(logged)
                or max(abs(objective - expected), abs(logged - expected)) > 1e-6):
            raise ValueError(f'Original objective differs for {case}: expected={expected}; PAR={objective}; first_log={logged}')
        receipt = {'case': case, 'input_par_sha256': sha(before),
                   'native_input_sha256': {name: row['sha256'] for name, row in saved.items()},
                   'expected_objective': expected, 'native_objective': objective,
                   'first_logged_objective': logged, 'active_parameters': int(count),
                   'native_status': result.returncode, 'function_evaluation_limit': 1,
                   'native_command': command, 'controls': controls.decode().splitlines() if controls else None,
                   'report_sha256': sha(report),
                   'scope': 'Original final PAR and inputs unchanged; original reported objective verified; full REP byte identity and Hessian regeneration are not asserted'}
        output.write_new('native-check.json', (json.dumps(receipt, indent=2) + '\n').encode())
        print(case + ': original objective reproduced; preserved inputs unchanged', flush=True)
        return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('case', help='profile-SCALAR, aspm-constant, profiles, or available')
    parser.add_argument('output', type=Path, help='a new output directory')
    args = parser.parse_args()
    if platform.system() != 'Linux' or platform.machine() not in ('x86_64', 'amd64'):
        parser.error('Native MFCL requires 64-bit x86 Linux')
    with restore.frozen_bytes(HERE / 'package.json') as data:
        recipe = json.loads(data)
    policies = restore.read_json(recipe['validation'])
    if args.case == 'profiles':
        selected = {name: p for name, p in policies.items() if name.startswith('profile-')}
    elif args.case == 'available':
        selected = {name: p for name, p in policies.items() if p.get('original_last_par_available') is not False}
    elif args.case in policies:
        selected = {args.case: policies[args.case]}
    else:
        parser.error('Unknown case; see validation.json')
    if any(p.get('original_last_par_available') is False for p in selected.values()):
        parser.error('Fitted ASPM terminal PAR is missing; native rerun refused')
    if args.output.exists() or args.output.is_symlink():
        parser.error('Choose a new output directory')
    args.output = args.output.resolve()
    if (args.output == restore.REPO
            or restore.REPO in args.output.parents and restore.REPO / 'outputs' not in args.output.parents):
        parser.error('Output inside the checkout must be beneath outputs/')
    if args.case in ('profiles', 'available'):
        restore.save_files(args.output, {}, 'diagnostic-check-collection')
        with NativeDirectory(args.output) as collection:
            def check(case, policy):
                files = original_files(restore, case)
                with collection.create_child(case) as directory:
                    directory.stage_files(files, case)
                    return evaluate(case, directory.path, policy, directory)
            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                futures = [pool.submit(check, case, policy) for case, policy in selected.items()]
                receipts = [item.result() for item in futures]
            collection.write_new('native-checks.json', (json.dumps(receipts, indent=2) + '\n').encode())

    else:
        evaluate(args.case, args.output, selected[args.case])


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        raise SystemExit(str(error))

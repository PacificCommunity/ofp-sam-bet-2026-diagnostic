#!/usr/bin/env python3
"""Check BET Index CPUE directly against frozen FRQ/REP; run no model or R."""
import argparse
import csv
import hashlib
import io
import json
import math
import os
from pathlib import Path
import re
import stat
import sys
import tempfile

PINS = {
    "MFCL/bet.frq": "d0d84f0a498e6a62681f2a58ffc1ba53dab9e3d6af856b4ad1fd907196250004",
    "MFCL/plot-11.par.rep": "bdc4468ea540da966bed821c2179c0d0e8bcc82698d4ac4665bfa04685928e3f",
    "TAF/output/cpue.csv": "2e6ad2a82a8b7be11062dd31be5755163ab2a31006e9189476de1f36319a2ead",
}
RTOL = 1e-12
FISHERIES = range(29, 34)
MISSING = {(32, 1952, 1), (32, 1952, 2)}
REP_COUNTS = (292, 292, 137, 292, 268, 291, 292, 292, 154, 290, 153,
              265, 292, 164, 220, 208, 180, 220, 175, 177, 220, 220,
              100, 135, 213, 138, 201, 110, 292, 292, 292, 290, 292)
GRID = tuple((fishery, year, quarter) for fishery in FISHERIES
             for year in range(1952, 2025) for quarter in range(1, 5))
INPUT_KEYS = tuple(key for key in GRID if key not in MISSING)
INPUT_FIELDS = ("year", "season", "fishery", "area", "index")
OUTPUT_FIELDS = ("year", "season", "fishery", "area", "obs", "pred")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def finite(text, label):
    try:
        value = float(text)
    except (TypeError, ValueError) as error:
        raise ValueError(f"invalid number in {label}: {text!r}") from error
    require(math.isfinite(value), f"nonfinite number in {label}")
    return value


def integer(text, label):
    require(isinstance(text, str) and re.fullmatch(r"[0-9]+", text) is not None,
            f"invalid integer in {label}: {text!r}")
    return int(text)


def directory(path):
    require(stat.S_ISDIR(path.lstat().st_mode), f"not a regular directory: {path}")


def read_file(root, relative, limit):
    path = root
    for part in Path(relative).parts[:-1]:
        path /= part
        directory(path)
    path = root / relative
    info = path.lstat()
    require(stat.S_ISREG(info.st_mode), f"not a regular file: {path}")
    require(0 < info.st_size <= limit, f"invalid byte count: {relative}")
    content = path.read_bytes()
    require(len(content) == info.st_size, f"file changed while reading: {relative}")
    return content


def pinned(root, relative):
    content = read_file(root, relative, 4 * 1024 * 1024)
    require(hashlib.sha256(content).hexdigest() == PINS[relative],
            f"frozen source hash mismatch: {relative}")
    return content


def parse_frq(content):
    lines = content.decode("utf-8").splitlines()
    headers = [i for i, line in enumerate(lines) if line.strip().startswith("# age_nage")]
    require(len(headers) == 1, "FRQ age_nage header must occur once")
    marker = headers[0]
    require(marker >= 2 and marker + 2 < len(lines), "truncated FRQ header")
    dataset_fields = lines[marker - 1].split()
    require(len(dataset_fields) == 9 and dataset_fields[0] == "7449",
            "FRQ dataset count/header must declare 7449 realizations")
    require(lines[marker + 1].split() == ["0", "-1"], "unexpected FRQ age_nage values")
    records = []
    indices = {}
    observed_keys = []
    for line_number, line in enumerate(lines[marker + 2:], marker + 3):
        require(line.strip() and not line.lstrip().startswith("#"),
                f"unexpected FRQ record at line {line_number}")
        fields = line.split()
        require(len(fields) >= 8, f"truncated FRQ record at line {line_number}")
        values = [finite(value, f"FRQ line {line_number}") for value in fields]
        year, month, week, fishery = [integer(value, f"FRQ line {line_number}")
                                       for value in fields[:4]]
        require(1 <= fishery <= 33, f"invalid FRQ fishery at line {line_number}")
        records.append(fishery)
        if fishery not in FISHERIES:
            continue
        require(year in range(1952, 2025), f"invalid Index year at line {line_number}")
        require(month in (2, 5, 8, 11) and week == 1,
                f"invalid Index month/week at line {line_number}")
        catch, effort = values[4:6]
        require(catch == 1.0 and effort > 0.0,
                f"Index requires dummy catch=1 and positive effort at line {line_number}")
        key = (fishery, year, (month + 1) // 3)
        require(key not in indices, f"duplicate Index FRQ key: {key}")
        indices[key] = catch / effort
        require(math.isfinite(indices[key]) and indices[key] > 0, f"invalid raw quotient: {key}")
        observed_keys.append(key)
    require(len(records) == 7449, "FRQ must contain 7449 realizations")
    require(tuple(observed_keys) == INPUT_KEYS, "FRQ Index keys/count/order must match the 1458 frozen records")
    counts = tuple(records.count(fishery) for fishery in range(1, 34))
    require(counts == REP_COUNTS, "FRQ fishery realization counts changed")
    return indices


def decode_time(value, fishery):
    require(math.isfinite(value), "nonfinite REP time")
    year = math.floor(value)
    eighths = (value - year) * 8
    midpoint = round(eighths)
    require(year in range(1952, 2025) and midpoint in (1, 3, 5, 7)
            and abs(eighths - midpoint) <= 1e-9,
            f"invalid native quarter midpoint for fishery {fishery}: {value}")
    return fishery, year, (midpoint + 1) // 2


def parse_rep(content, index_keys):
    lines = content.decode("utf-8").splitlines()

    def section(label):
        locations = [i for i, line in enumerate(lines) if line.startswith("# " + label)]
        require(len(locations) == 1, f"REP section must occur once: {label}")
        start = locations[0] + 1
        require(start + 33 < len(lines) and lines[start + 33].startswith("#"),
                f"REP section must have exactly 33 fishery rows: {label}")
        rows = []
        for fishery, line in enumerate(lines[start:start + 33], 1):
            fields = line.split()
            require(len(fields) == REP_COUNTS[fishery - 1],
                    f"REP realization count mismatch: {label}, fishery {fishery}")
            rows.append([finite(value, f"REP {label}, fishery {fishery}") for value in fields])
        return rows

    times = section("Time of each realization")
    obs = section("Observed CPUE by fishery")
    pred = section("Predicted CPUE by fishery")
    expected = {}
    for fishery in range(1, 34):
        keys = [decode_time(value, fishery) for value in times[fishery - 1]]
        require(len(keys) == len(set(keys)) and keys == sorted(keys),
                f"duplicate or unordered REP time keys: fishery {fishery}")
        if fishery not in FISHERIES:
            continue
        for key, observed, predicted in zip(keys, obs[fishery - 1], pred[fishery - 1]):
            try:
                values = math.exp(observed), math.exp(predicted)
            except OverflowError as error:
                raise ValueError(f"native exp CPUE overflow: {key}") from error
            require(all(math.isfinite(value) and value > 0 for value in values),
                    f"invalid native exp CPUE: {key}")
            expected[key] = values
    require(tuple(expected) == INPUT_KEYS and set(expected) == set(index_keys),
            "native REP and FRQ Index key sets/count/order differ")
    return expected


def csv_rows(content, fields, expected_keys, label):
    reader = csv.DictReader(io.StringIO(content.decode("utf-8")), strict=True)
    require(tuple(reader.fieldnames or ()) == fields, f"wrong {label} CSV fields/order")
    rows = list(reader)
    require(len(rows) == len(expected_keys), f"wrong {label} CSV row count")
    keys = []
    for row_number, row in enumerate(rows, 2):
        require(set(row) == set(fields) and all(value is not None for value in row.values()),
                f"malformed {label} CSV row {row_number}")
        key = (integer(row["fishery"], label), integer(row["year"], label), integer(row["season"], label))
        require(key[0] in FISHERIES and key[1] in range(1952, 2025) and key[2] in range(1, 5),
                f"invalid {label} row key: {key}")
        require(integer(row["area"], label) == key[0] - 28, f"wrong {label} area: {key}")
        keys.append(key)
    require(len(set(keys)) == len(keys), f"duplicate {label} CSV key")
    require(tuple(keys) == expected_keys, f"wrong {label} CSV keys/order")
    return list(zip(keys, rows))


def close(value, expected, label):
    require(value > 0, f"nonpositive {label}")
    error = abs(value / expected - 1)
    require(error <= RTOL, f"wrong {label} scale/value (relative error {error:.6g})")
    return error


def verify(source_repo, regenerated_root):
    directory(source_repo)
    directory(regenerated_root)
    source_repo, regenerated_root = source_repo.resolve(), regenerated_root.resolve()
    require(source_repo != regenerated_root and source_repo not in regenerated_root.parents,
            "regenerated root must be a separate working copy outside source repository")
    frq = parse_frq(pinned(source_repo, "MFCL/bet.frq"))
    rep = parse_rep(pinned(source_repo, "MFCL/plot-11.par.rep"), frq)
    original_output = pinned(source_repo, "TAF/output/cpue.csv")
    data = read_file(regenerated_root, "TAF/data/cpue.csv", 1024 * 1024)
    output = read_file(regenerated_root, "TAF/output/cpue.csv", 1024 * 1024)
    input_errors = [close(finite(row["index"], "input CPUE"), frq[key], f"input CPUE {key}")
                    for key, row in csv_rows(data, INPUT_FIELDS, INPUT_KEYS, "input")]
    output_errors = []
    missing = []
    for key, row in csv_rows(output, OUTPUT_FIELDS, GRID, "output"):
        if key in MISSING:
            require(row["obs"] == row["pred"] == "NA", f"missing output pair must be exactly NA: {key}")
            missing.append(list(key))
        else:
            require(row["obs"] != "NA" and row["pred"] != "NA", f"unexpected output NA: {key}")
            output_errors.extend(close(finite(row[field], f"output {field}"), expected,
                                       f"output {field} {key}")
                                 for field, expected in zip(("obs", "pred"), rep[key]))
    require(set(map(tuple, missing)) == MISSING and len(missing) == 2, "wrong missing CPUE pairs")
    output_hash = hashlib.sha256(output).hexdigest()
    require(output_hash == hashlib.sha256(original_output).hexdigest(),
            "regenerated CPUE output bytes differ from original saved model output")
    report = {"schema_version": 1, "status": "passed", "relative_tolerance": RTOL,
              "input_scale": "relative CPUE on MFCL input scale: raw catch/effort, no hooks conversion",
              "output_scale": "relative CPUE on MFCL model scale: exp(native REP)",
              "input_rows": len(INPUT_KEYS), "output_rows": len(GRID),
              "index_fishery_counts": {str(f): REP_COUNTS[f - 1] for f in FISHERIES},
              "native_time_rows_checked": 33, "missing_output_pairs": sorted(missing),
              "maximum_input_relative_error": max(input_errors),
              "maximum_output_relative_error": max(output_errors),
              "frozen_source_sha256": PINS, "regenerated_output_sha256": output_hash,
              "checker_executes_model_or_R": False,
              "verification_method": "Python FRQ/REP arithmetic; checker does not execute R or MFCL"}
    target = regenerated_root / "cpue-check.json"
    if target.exists() or target.is_symlink():
        require(stat.S_ISREG(target.lstat().st_mode), "CPUE receipt destination must be a regular file")
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=regenerated_root,
                                         prefix=".cpue-check.", suffix=".tmp", delete=False) as stream:
            temporary = Path(stream.name)
            json.dump(report, stream, indent=2)
            stream.write("\n")
        os.replace(temporary, target)
        temporary = None
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    print("CPUE passed: 1458 raw input quotients, 1460 native-exp output rows, two NA pairs; output bytes unchanged.")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_repo", type=Path)
    parser.add_argument("regenerated_root", type=Path)
    args = parser.parse_args()
    try:
        verify(args.source_repo, args.regenerated_root)
    except (OSError, ValueError, UnicodeError, csv.Error) as error:
        print(f"CPUE check failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

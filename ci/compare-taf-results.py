#!/usr/bin/env python3
"""Compare regenerated TAF tables and native copies with the saved files."""
import argparse
import csv
import hashlib
import json
import math
from pathlib import Path


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rows(path):
    with path.open(newline="", encoding="utf-8") as stream:
        return list(csv.reader(stream))


def compare_table(saved, generated):
    left, right = rows(saved), rows(generated)
    require(left and right and left[0] == right[0], f"columns differ: {saved.name}")
    require(len(left) == len(right), f"row count differs: {saved.name}")
    cells, largest = 0, 0.0
    for index, (a, b) in enumerate(zip(left[1:], right[1:]), 2):
        require(len(a) == len(b) == len(left[0]), f"row shape differs: {saved.name}:{index}")
        for original, current in zip(a, b):
            if original == current:
                continue
            try:
                x, y = float(original), float(current)
            except ValueError:
                raise ValueError(f"text differs: {saved.name}:{index}")
            require(math.isfinite(x) and math.isfinite(y), f"nonfinite change: {saved.name}:{index}")
            difference = abs(x - y)
            require(difference <= 1e-10 * max(1.0, abs(x)),
                    f"numeric value differs: {saved.name}:{index}")
            largest = max(largest, difference)
            cells += 1
    return {"rows": len(left) - 1, "columns": len(left[0]),
            "equivalent_numeric_format_changes": cells, "largest_absolute_difference": largest}


def compare(root, work):
    tables = {}
    for stage in ("data", "output", "report"):
        expected = sorted((root / "TAF" / stage).glob("*.csv"))
        observed = sorted((work / "TAF" / stage).glob("*.csv"))
        require(expected and [p.name for p in expected] == [p.name for p in observed],
                f"table inventory differs: {stage}")
        for saved, generated in zip(expected, observed):
            tables[stage + "/" + saved.name] = compare_table(saved, generated)
    native = ("11.par", "catch.rep", "indepvar.rpt", "length.fit",
              "plot-11.par.rep", "test_plot_output")
    for name in native:
        require(digest(root / "MFCL" / name) == digest(work / "TAF" / "model" / name),
                f"saved native output differs: {name}")
    proof = {"status": "passed", "scope": "TAF saved-result regeneration",
             "table_comparisons": tables, "native_files_byte_identical": list(native),
             "model_refit": False, "plot_pixel_parity": "not asserted"}
    (work / "taf-check.json").write_text(json.dumps(proof, indent=2) + "\n")
    print(f"Verified {len(tables)} regenerated tables and {len(native)} exact native copies.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("work", type=Path)
    args = parser.parse_args()
    try:
        compare(args.root, args.work)
    except (OSError, ValueError) as error:
        raise SystemExit(str(error))

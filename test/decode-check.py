#!/usr/bin/env python3
"""Decode a clqr PBM (P4) image and assert it matches the expected text.

Used by CI as an end-to-end conformance guard: it proves clqr's output is not
merely well-formed but actually decodable by an independent reader (ZXing via
the zxing-cpp wheel).

Usage:  decode-check.py PBM-FILE EXPECTED-TEXT
Exit:   0 on a matching decode, 1 otherwise.
"""
import re
import sys

import numpy as np
import zxingcpp
from PIL import Image


def read_pbm_p4(path):
    with open(path, "rb") as fh:
        raw = fh.read()
    m = re.match(rb"P4\s+(\d+)\s+(\d+)\s", raw)
    if not m:
        raise ValueError(f"{path}: not a P4 PBM")
    w, h = int(m.group(1)), int(m.group(2))
    off = m.end()
    rowbytes = (w + 7) // 8
    data = raw[off:off + rowbytes * h]
    arr = np.zeros((h, w), dtype=np.uint8)
    for y in range(h):
        for x in range(w):
            bit = (data[y * rowbytes + (x // 8)] >> (7 - (x % 8))) & 1
            arr[y, x] = 0 if bit else 255  # 1 => black module
    return arr


def main(argv):
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    path, expected = argv[1], argv[2]
    arr = read_pbm_p4(path)
    results = zxingcpp.read_barcodes(Image.fromarray(arr, "L"))
    got = results[0].text if results else ""
    if got == expected:
        print(f"OK: decoded {got!r}")
        return 0
    print(f"FAIL: decoded {got!r}, expected {expected!r}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))

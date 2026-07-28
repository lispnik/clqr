#!/usr/bin/env python3
"""End-to-end conformance check for clqr.

Encodes a wide range of inputs with the built `clqr` binary and decodes each
symbol with an independent reader (ZXing, via the zxing-cpp wheel), asserting
the decoded content matches the input.  This is the guarantee the FiveAM suite
cannot give on its own: that clqr's output is not merely well-formed but actually
*scannable*, across every mode, error-correction level, Micro QR, and Structured
Append reassembly.

Requirements (pip):  zxing-cpp  pillow  numpy
Usage:               python3 test/conformance.py [path/to/clqr]
Exit status:         0 if every symbol decoded correctly, 1 otherwise.
"""
import os
import re
import subprocess
import sys
import tempfile

import numpy as np
import zxingcpp
from PIL import Image

BIN = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    os.path.dirname(__file__), os.pardir, "bin", "clqr")


def read_pbm_p4(path):
    with open(path, "rb") as fh:
        raw = fh.read()
    m = re.match(rb"P4\s+(\d+)\s+(\d+)\s", raw)
    if not m:
        raise ValueError(f"{path}: not a P4 PBM")
    w, h = int(m.group(1)), int(m.group(2))
    off, rowbytes = m.end(), (int(m.group(1)) + 7) // 8
    data = raw[off:off + rowbytes * h]
    arr = np.zeros((h, w), dtype=np.uint8)
    for y in range(h):
        for x in range(w):
            bit = (data[y * rowbytes + (x // 8)] >> (7 - (x % 8))) & 1
            arr[y, x] = 0 if bit else 255
    return arr


def clqr(content, out, *args):
    subprocess.run([BIN, *args, "-f", "pbm", "--pbm-format", "p4", "-s", "6",
                    "-o", out, "--", content], check=True, stderr=subprocess.DEVNULL)


def decode(path):
    results = zxingcpp.read_barcodes(Image.fromarray(read_pbm_p4(path), "L"))
    return results[0].text if results else None


PASS, FAIL = 0, []


def check(label, expected, got):
    global PASS
    if got == expected:
        PASS += 1
    else:
        FAIL.append((label, expected[:40], (got or "<none>")[:40]))


def main():
    tmp = tempfile.mkdtemp(prefix="clqr-conf-")
    out = os.path.join(tmp, "s.pbm")

    # Standard QR: representative content in each mode, at every EC level.
    contents = [
        "01234567", "HELLO WORLD 123", "https://github.com/lispnik/clqr",
        "Hello, world! Mixed 12345 content.", "日本語テスト", "café ☕ 日本",
        "0123456789" * 8, "ABCDEFGHIJ 0123456789 $%*+-./: MIXED",
    ]
    for ecl in ("l", "m", "q", "h"):
        for c in contents:
            clqr(c, out, "-e", ecl)
            check(f"qr/{ecl}/{c[:16]}", c, decode(out))

    # Micro QR: M1-M4 across the levels each supports.
    for ver, ecls in (("1", "l"), ("2", "lm"), ("3", "lm"), ("4", "lmq")):
        for ecl in ecls:
            c = "01234567" if ver != "1" else "12345"
            clqr(c, out, "--micro", "-V", ver, "-e", ecl)
            check(f"micro/M{ver}/{ecl}", c, decode(out))

    # Structured Append: split, decode each piece, reassemble.
    sa_text = ("The quick brown fox jumps over the lazy dog 0123456789 "
               "repeatedly, long enough to span several linked symbols.")
    for count in (2, 3, 4):
        base = os.path.join(tmp, "sa.pbm")
        subprocess.run([BIN, "--structured-append", str(count), "-f", "pbm",
                        "--pbm-format", "p4", "-s", "6", "-o", base, "--", sa_text],
                       check=True, stderr=subprocess.DEVNULL)
        pieces = [decode(os.path.join(tmp, f"sa-{i}.pbm")) or "" for i in range(1, count + 1)]
        check(f"structured-append/{count}", sa_text, "".join(pieces))

    total = PASS + len(FAIL)
    print(f"conformance: {PASS}/{total} symbols decoded correctly")
    for label, exp, got in FAIL:
        print(f"  FAIL {label}: expected {exp!r} got {got!r}")
    return 0 if not FAIL else 1


if __name__ == "__main__":
    sys.exit(main())

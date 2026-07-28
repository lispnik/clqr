# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2026-07-28

### Added
- `encode-structured-append` gained an `:eci` keyword.
- An end-to-end conformance check (`test/conformance.py`, `make conformance`)
  that encodes every mode / EC level / Micro QR / Structured Append and decodes
  each back with an independent reader; it runs in CI.

### Changed
- Much faster encoding of large inputs: the segmenter is now an O(n·modes²)
  forward dynamic program (was O(n²)) and penalty rule 3 uses a sliding-window
  integer, with hot-loop type declarations. Measured: a version-40 encode 387→12
  ms (~31×) and a 3000-digit encode 752→6 ms (~123×), with identical output.

### Fixed
- A multi-agent audit surfaced and fixed twelve edge-case defects:
  - byte runs in the auto ECI-26 regime are now always UTF-8 (a lone Latin-1
    run the segmenter isolated was mis-encoded as ISO-8859-1);
  - the segmentation cost model no longer over-counts Latin-1 characters in the
    non-ECI regime (they cost 8 bits each, not a UTF-8 byte count);
  - dual-mapped Kanji code points resolve to the canonical JIS X 0208 value;
  - `encode-segments` / `encode-structured-append` reject a bad `:mask`, and
    `encode-micro` rejects bad `:mode` / content, with typed conditions;
  - `encode-structured-append` honours `:eci`;
  - renderers reject negative quiet zones and non-positive module sizes, and the
    SVG renderer escapes colour strings;
  - the CLI honours `--eci` with `--structured-append`, rejects out-of-range
    `--structured-append`, and fixes indexed output paths containing a dotted
    directory.

## [0.2.0] - 2026-07-27

### Added
- **Optimal mixed-mode segmentation**: the input is split across Numeric,
  Alphanumeric, Byte and Kanji runs to minimise the encoded size (Japanese text
  auto-selects the compact Kanji mode). Kanji mode and a UTF-8 byte ECI are never
  mixed, so every symbol decodes unambiguously.
- **Automatic ECI 26 (UTF-8)** header when byte content is not Latin-1.
- **FNC1** headers (GS1 first position and AIM second position) via `:fnc1`.
- **Structured Append** multi-symbol sequences via `encode-structured-append`.
- **Micro QR** (M1–M4) via `encode-micro` and the `--micro` CLI flag.
- Typed, message-carrying error conditions (`invalid-error-correction`,
  `invalid-mask`, `shift-jis-unavailable`).
- SVG renderer `role="img"` and optional `:title` / `:description` for
  accessibility (CLI `--title`).
- `make coverage` (sb-cover), and `make man` / `make completions` (clingon).

### Changed
- The CLI reads standard input verbatim (newlines preserved), so piped content
  is encoded byte-for-byte.

### Fixed
- Reversed Reed-Solomon generator coefficient order and a zig-zag parity error
  at the timing column (found before release).

## [0.1.0] - 2026-07-27

### Added
- Pure Common Lisp QR code encoder for Model 2 symbols, following ISO/IEC 18004:
  versions 1–40, error correction levels L/M/Q/H, all eight data masks with
  penalty-based selection, and the Numeric, Alphanumeric, Byte (ISO-8859-1 /
  UTF-8) and Kanji (Shift-JIS) modes plus ECI.
- A model/display separation: the `clqr:qr-code` model object and the `clqr:encode`
  entry point are independent of the `clqr.render` renderers (Unicode/ASCII text,
  SVG and netpbm PBM).
- A `clqr` command line driver (built with clingon) that exposes the full API,
  produced as a native binary via `asdf:make` / `make`.
- A FiveAM test suite with ISO worked-example vectors and a golden symbol matrix.

[Unreleased]: https://github.com/lispnik/clqr/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/lispnik/clqr/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/lispnik/clqr/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/lispnik/clqr/releases/tag/v0.1.0

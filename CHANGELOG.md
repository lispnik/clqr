# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-07-27

### Added
- Pure Common Lisp QR code encoder for Model 2 symbols, following ISO/IEC 18004.
- Versions 1–40, error correction levels L/M/Q/H, all eight data masks with
  penalty-based selection, and the Numeric, Alphanumeric, Byte (ISO-8859-1 /
  UTF-8) and Kanji (Shift-JIS) modes plus ECI. Micro QR, FNC1 (GS1) and
  Structured Append are not supported.
- Optimal mixed-mode segmentation: the input is split across Numeric,
  Alphanumeric, Byte and Kanji runs to minimise the encoded size (Japanese text
  auto-selects Kanji mode). Kanji mode and a UTF-8 byte ECI are never mixed, so
  every symbol decodes unambiguously.
- Automatic ECI 26 (UTF-8) header when byte content is not Latin-1.
- A model/display separation: the `clqr:qr-code` model object and the `clqr:encode`
  entry point are independent of the `clqr.render` renderers (Unicode/ASCII text,
  SVG and netpbm PBM).
- A `clqr` command line driver (built with clingon) that exposes the full API,
  produced as a native binary via `asdf:make` / `make`.
- A FiveAM test suite with ISO worked-example vectors and a golden symbol matrix.

[Unreleased]: https://github.com/lispnik/clqr/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/lispnik/clqr/releases/tag/v0.1.0

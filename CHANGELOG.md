# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-07-27

### Added
- Pure Common Lisp, ISO/IEC 18004 conformant QR code encoder.
- Full support for versions 1–40, error correction levels L/M/Q/H, all eight
  data masks with penalty-based selection, and the Numeric, Alphanumeric, Byte
  and Kanji (Shift-JIS) modes plus ECI.
- A model/display separation: the `clqr:qr-code` model object and the `clqr:encode`
  entry point are independent of the `clqr.render` renderers (Unicode/ASCII text,
  SVG and netpbm PBM).
- A `clqr` command line driver (built with clingon) that exposes the full API,
  produced as a native binary via `asdf:make` / `make`.
- A FiveAM test suite with ISO worked-example vectors and a golden symbol matrix.

[Unreleased]: https://github.com/lispnik/clqr/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/lispnik/clqr/releases/tag/v0.1.0

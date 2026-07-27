# clqr

A pure Common Lisp **QR Code encoder** for Model 2 symbols, following
[ISO/IEC 18004](https://www.iso.org/standard/62021.html).

`clqr` has no external dependencies for its core: it computes the entire symbol —
Galois field arithmetic, Reed-Solomon error correction, block interleaving,
function-pattern placement, data masking and penalty scoring — in portable
Common Lisp. It cleanly separates the **model** (the abstract QR symbol) from the
**display** (renderers), and ships a command line driver that exposes the whole
API.

- Versions **1–40**, error correction levels **L / M / Q / H**.
- Modes **Numeric**, **Alphanumeric**, **Byte** (ISO-8859-1 / UTF-8) and
  **Kanji** (Shift-JIS), plus **ECI**.
- Automatic mode and minimal-version selection, or force any of them.
- Automatic **ECI 26 (UTF-8)** header when byte content isn't Latin-1, so the
  symbol is self-describing rather than relying on the reader to guess.
- All eight data masks with ISO penalty scoring (or force a mask).
- Renderers: **Unicode/ASCII** text, **SVG**, and **netpbm PBM** (P1 and P4).

### Scope

`clqr` targets standard (Model 2) QR symbols. It does **not** implement Micro QR,
the FNC1 (GS1) modes, or Structured Append (multi-symbol) sequences. Automatic
mode selection chooses a single best-fit mode for the whole input; mixed-mode
optimisation is available by constructing segments explicitly (see
`encode-segments` below).

```
  █▀▀▀▀▀█ ▄▄█ ▀ █▀▀▀▀▀█
  █ ███ █   █ █ █ ███ █
  █ ▀▀▀ █ ▀▄██▀ █ ▀▀▀ █
  ▀▀▀▀▀▀▀ ▀ ▀ ▀ ▀▀▀▀▀▀▀
  ▀▄█▄█ ▀ ▄▀ ▄▀   █  ▀▄
  ▄▄▄█▀█▀██▀ █▄▄▀▄▀█▄▄
   ▀  ▀▀▀▀▄▀▄▀  █▀▀ █ █
  █▀▀▀▀▀█  ▄▄ ▀ ▄█ █▀
  █ ███ █ ▀▀▄▄▀▄▀█▀▀▀█▀
  █ ▀▀▀ █ ▀▀▀█▄█▀▀ █ ▄█
  ▀▀▀▀▀▀▀ ▀▀ ▀ ▀▀▀    ▀
```

## Model and display

The two halves are deliberately independent:

- **Model** — `clqr:encode` returns a `clqr:qr-code`, a plain data object holding
  the version, error correction level, chosen mask, modes used, and the module
  bit-matrix. It knows nothing about output. Read it with `clqr:qr-version`,
  `clqr:qr-mask`, `clqr:qr-size`, `clqr:qr-module` and `clqr:map-modules`.
- **Display** — the `clqr.render` package turns any `qr-code` into an external
  representation and only uses the model's public readers. Add your own renderer
  without touching the encoder.

## Installation

`clqr` is distributed with [ocicl](https://github.com/ocicl/ocicl):

```sh
ocicl install clqr
```

Then load it with ASDF:

```lisp
(asdf:load-system "clqr")
```

The core system `clqr` has no dependencies. The command line system `clqr/cli`
additionally uses [clingon](https://github.com/dnaeon/clingon); the test system
`clqr/test` uses [FiveAM](https://github.com/lispci/fiveam).

## Library usage

```lisp
;; Encode; the model is separate from any rendering.
(let ((qr (clqr:encode "HELLO WORLD" :error-correction :q)))
  (clqr:qr-version qr)          ; => 1
  (clqr:qr-mask qr)             ; => an integer 0-7
  (clqr:qr-size qr)             ; => 21 (modules per side)
  (clqr:qr-module qr 0 0)       ; => T   (dark module at row 0, col 0)

  ;; Render the model however you like.
  (clqr.render:render-text qr)                         ; to *standard-output*
  (with-open-file (s "hello.svg" :direction :output :if-exists :supersede)
    (clqr.render:render-svg qr :stream s :module-size 10)))
```

### `clqr:encode`

```lisp
(clqr:encode content &key (error-correction :m) version mask mode eci)
```

| Argument            | Meaning                                                             |
|---------------------|--------------------------------------------------------------------|
| `content`           | a string, or a sequence of `(unsigned-byte 8)` for byte mode       |
| `:error-correction` | `:l` `:m` `:q` `:h` (default `:m`)                                  |
| `:version`          | force `1`–`40`, or `nil` for the smallest that fits                 |
| `:mask`             | force `0`–`7`, or `nil` to select the lowest-penalty mask          |
| `:mode`             | force `:numeric` `:alphanumeric` `:byte` `:kanji`, or `nil` (auto) |
| `:eci`              | an ECI assignment number to prefix, or `nil`                       |

For mixed-mode content, build segments explicitly and use `clqr:encode-segments`:

```lisp
(clqr:encode-segments
  (list (clqr:make-alphanumeric-segment "HELLO ")
        (clqr:make-byte-segment "world!"))
  :error-correction :h)
```

### Renderers

```lisp
(clqr.render:render-text qr &key (stream *standard-output*) (quiet-zone 4)
                                 (style :unicode) invert)
(clqr.render:render-svg  qr &key (stream *standard-output*) (quiet-zone 4)
                                 (module-size 8) (foreground "#000000")
                                 (background "#ffffff"))
(clqr.render:render-pbm  qr &key (stream *standard-output*) (quiet-zone 4)
                                 (module-size 1) (format :p4))
```

`render-pbm` with `:format :p4` writes raw bytes and needs a binary stream;
`:p1` and the other renderers write to a character stream.

## Command line

Build the binary (dumped with `asdf:make` / `program-op`):

```sh
make            # produces bin/clqr
```

```sh
# Print to the terminal
clqr "HELLO WORLD"

# SVG at error correction level H
clqr -e h -f svg -o hello.svg "https://github.com/lispnik/clqr"

# Force numeric mode and version 4
clqr -M numeric -V 4 123456789

# Read content from standard input, write a PBM image
printf 'hi' | clqr -f pbm -o hi.pbm -
```

Run `clqr --help` for the full option list. Every option maps onto an `encode`
or renderer argument, so the CLI covers the complete API surface. A one-line
summary (version, EC level, mask, size) is written to standard error so standard
output stays clean for piping.

> Terminal note: the default text style draws dark modules as filled blocks,
> which scans correctly on a light background. On a dark-background terminal add
> `--invert`.

## Development

```sh
make deps     # ocicl install (restore clingon + fiveam)
make test     # run the FiveAM suite
make          # build bin/clqr
make clean    # remove bin/ and this tree's fasl cache
```

The test suite checks against the ISO/IEC 18004 Annex worked example (numeric
`01234567`, version 1-M), the format and version information tables, and a golden
full-symbol matrix cross-checked with an independent decoder.

## License

MIT © Matthew Kennedy. See [LICENSE](LICENSE).

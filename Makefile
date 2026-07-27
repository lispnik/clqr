# Makefile for clqr --- a pure Common Lisp QR code encoder.
#
#   make          build the bin/clqr command line binary
#   make test     run the FiveAM test suite
#   make deps     restore dependencies with ocicl
#   make clean    remove build artifacts and the fasl cache
#   make help     show this help

LISP       ?= sbcl
SBCL_FLAGS := --non-interactive --no-userinit --no-sysinit
# NOTE: (require :asdf) must be its own --eval so the ASDF package exists before
# the reader sees any asdf:/uiop: symbols in the following forms.
REQUIRE    := --eval '(require :asdf)'
REGISTRY   := --eval '(asdf:initialize-source-registry (list :source-registry (list :tree (uiop:getcwd)) :inherit-configuration))'
BIN        := bin/clqr

.PHONY: all build test deps clean help

all: build

## build: dump the bin/clqr executable via asdf:make (program-op)
build: $(BIN)

$(BIN): clqr.asd $(wildcard src/*.lisp render/*.lisp cli/*.lisp) ocicl.csv
	$(LISP) $(SBCL_FLAGS) $(REQUIRE) $(REGISTRY) \
		--eval '(asdf:make :clqr/cli)' \
		--eval '(uiop:quit 0)'

## deps: restore pinned dependencies into ./ocicl using ocicl
deps: ocicl.csv
	ocicl install

## test: load and run the test suite (non-zero exit on failure)
test:
	$(LISP) $(SBCL_FLAGS) $(REQUIRE) $(REGISTRY) \
		--eval '(asdf:test-system :clqr)' \
		--eval '(uiop:quit 0)'

## clean: remove the binary and this project tree's fasl cache
clean:
	rm -rf bin
	rm -rf "$${HOME}/.cache/common-lisp/"*"$$(pwd | tr / -)"* 2>/dev/null || true

## help: list the available targets
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## //'

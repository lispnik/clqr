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

.PHONY: all build test coverage conformance man completions deps clean help

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

## coverage: run the suite under sb-cover and write coverage/ HTML report
coverage:
	$(LISP) $(SBCL_FLAGS) $(REQUIRE) $(REGISTRY) --load test/coverage.lisp

## conformance: encode + decode round-trip (needs pip: zxing-cpp pillow numpy)
conformance: $(BIN)
	python3 test/conformance.py $(BIN)

## man: generate the clqr.1 man page (via clingon)
man:
	$(LISP) $(SBCL_FLAGS) $(REQUIRE) $(REGISTRY) \
		--eval '(asdf:load-system :clqr/cli)' \
		--eval '(with-open-file (s "clqr.1" :direction :output :if-exists :supersede) (clingon:print-documentation :mandoc (clqr.cli:command) s))' \
		--eval '(uiop:quit 0)'

## completions: generate bash and zsh shell completions into completions/
completions:
	$(LISP) $(SBCL_FLAGS) $(REQUIRE) $(REGISTRY) \
		--eval '(asdf:load-system :clqr/cli)' \
		--eval '(ensure-directories-exist "completions/")' \
		--eval '(with-open-file (s "completions/clqr.bash" :direction :output :if-exists :supersede) (clingon:print-documentation :bash-completions (clqr.cli:command) s))' \
		--eval '(with-open-file (s "completions/_clqr" :direction :output :if-exists :supersede) (clingon:print-documentation :zsh-completions (clqr.cli:command) s))' \
		--eval '(uiop:quit 0)'

## clean: remove build artifacts and this project tree's fasl cache
clean:
	rm -rf bin coverage completions clqr.1
	rm -rf "$${HOME}/.cache/common-lisp/"*"$$(pwd | tr / -)"* 2>/dev/null || true

## help: list the available targets
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## //'

;;;; clqr.asd --- System definitions for clqr.

(defsystem "clqr"
  :description "Pure Common Lisp, ISO/IEC 18004 conformant QR code encoder."
  :version "0.1.0"
  :author "Matthew Kennedy"
  :license "MIT"
  :homepage "https://github.com/lispnik/clqr"
  :source-control (:git "https://github.com/lispnik/clqr.git")
  :bug-tracker "https://github.com/lispnik/clqr/issues"
  :serial t
  :components ((:module "src"
                :serial t
                :components ((:file "package")
                             (:file "galois")
                             (:file "tables")
                             (:file "bitstream")
                             (:file "kanji")
                             (:file "segment")
                             (:file "reed-solomon")
                             (:file "matrix")
                             (:file "qr")))
               (:module "render"
                :serial t
                :components ((:file "render")
                             (:file "text")
                             (:file "svg")
                             (:file "pbm"))))
  :in-order-to ((test-op (test-op "clqr/test"))))

(defsystem "clqr/cli"
  :description "Command line driver for clqr."
  :version "0.1.0"
  :author "Matthew Kennedy"
  :license "MIT"
  :depends-on ("clqr" "clingon")
  :serial t
  :components ((:module "cli"
                :serial t
                :components ((:file "package")
                             (:file "cli"))))
  :build-operation "program-op"
  :build-pathname "bin/clqr"
  :entry-point "clqr.cli:main")

(defsystem "clqr/test"
  :description "Test suite for clqr."
  :version "0.1.0"
  :author "Matthew Kennedy"
  :license "MIT"
  :depends-on ("clqr" "fiveam")
  :serial t
  :components ((:module "test"
                :serial t
                :components ((:file "package")
                             (:file "suite")
                             (:file "galois-tests")
                             (:file "segment-tests")
                             (:file "encode-tests")
                             (:file "render-tests"))))
  :perform (test-op (op c)
             (uiop:symbol-call :clqr.test :run-tests)))

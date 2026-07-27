;;;; suite.lisp --- Master test suite and runner.

(in-package #:clqr.test)

(def-suite clqr-suite
  :description "All clqr tests.")

(defun run-tests (&key (exit t))
  "Run the clqr test suite.  When EXIT is true (the default, used by
asdf:test-system) the image exits with status 0 on success or 1 on failure,
which is what CI relies on.  Call with :exit nil from a REPL."
  (let ((ok (run! 'clqr-suite)))
    (if exit
        (uiop:quit (if ok 0 1))
        ok)))

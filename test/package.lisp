;;;; package.lisp --- Test package for clqr.

(defpackage #:clqr.test
  (:use #:common-lisp #:fiveam)
  (:documentation "FiveAM test suite for clqr.")
  (:export #:run-tests #:clqr-suite))

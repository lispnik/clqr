;;;; package.lisp --- Package for the clqr command line driver.

(defpackage #:clqr.cli
  (:use #:common-lisp)
  (:documentation "Command line driver for clqr, built on clingon.")
  (:export #:main #:command))

;;;; package.lisp --- Package definitions for clqr.
;;;;
;;;; The library is split into three packages that mirror the model/display
;;;; separation:
;;;;
;;;;   CLQR         - the model: the QR-CODE object, the encoding pipeline and
;;;;                  the public ENCODE entry point.  Pure Common Lisp, no
;;;;                  external dependencies.
;;;;   CLQR.RENDER  - the display: renderers that turn a QR-CODE model into text,
;;;;                  SVG or netpbm output.  Depends only on the CLQR model API.
;;;;   CLQR.CLI     - the command line driver.  Defined in cli/ and depends on
;;;;                  clingon (only the CLI pulls in an external dependency).

(defpackage #:clqr
  (:use #:common-lisp)
  (:documentation
   "Pure Common Lisp, ISO/IEC 18004 conformant QR code encoder (model).")
  (:export
   ;; High level entry points
   #:encode
   #:encode-micro
   ;; The model object and its readers
   #:qr-code
   #:qr-code-p
   #:qr-version
   #:qr-error-correction
   #:qr-mask
   #:qr-mode
   #:qr-size
   #:qr-modules
   #:qr-module
   #:qr-micro-p
   #:map-modules
   ;; Structured Append (multi-symbol sequences)
   #:encode-structured-append
   ;; Segments (advanced / explicit construction)
   #:segment
   #:make-numeric-segment
   #:make-alphanumeric-segment
   #:make-byte-segment
   #:make-kanji-segment
   #:make-eci-segment
   #:make-fnc1-first-segment
   #:make-fnc1-second-segment
   #:make-structured-append-segment
   #:encode-segments
   ;; Conditions
   #:clqr-error
   #:data-too-long
   #:invalid-mode
   #:invalid-version
   #:invalid-error-correction
   #:invalid-mask
   #:shift-jis-unavailable
   ;; Introspection helpers
   #:error-correction-levels
   #:*modes*))

(defpackage #:clqr.render
  (:use #:common-lisp #:clqr)
  (:documentation "Renderers that display a CLQR:QR-CODE model.")
  (:export
   #:render
   #:render-text
   #:render-svg
   #:render-pbm))

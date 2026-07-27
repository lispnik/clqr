;;;; qr.lisp --- The QR-CODE model object and the ENCODE entry point.
;;;;
;;;; This is the public model surface.  A QR-CODE is a plain data object that
;;;; describes a finished symbol: its version, error correction level, chosen
;;;; mask, the modes used, and the module bit-matrix.  It knows nothing about
;;;; how it is displayed; renderers (see the CLQR.RENDER package) consume this
;;;; object through the readers defined here.

(in-package #:clqr)

(defstruct (qr-code (:constructor %make-qr-code) (:copier nil))
  "A finished QR symbol (the model).
VERSION           the symbol version, 1-40.
ERROR-CORRECTION  the error correction level, one of :l :m :q :h.
MASK              the applied data mask pattern, 0-7.
MODE              a list of the encoding modes used.
SIZE              the number of modules per side.
MODULES           a (simple-array bit (size size)); 1 = dark, 0 = light."
  (version 1 :type (integer 1 40) :read-only t)
  (error-correction :m :read-only t)
  (mask 0 :type (integer 0 7) :read-only t)
  (mode nil :read-only t)
  (size 21 :type (integer 21 177) :read-only t)
  (modules nil :type (simple-array bit (* *)) :read-only t))

(declaim (inline qr-module))
(defun qr-module (qr row col)
  "Return T if the module at (ROW, COL) of QR is dark, NIL if light."
  (= 1 (aref (qr-code-modules qr) row col)))

;; Convenience readers under the exported names.
(setf (fdefinition 'qr-version) #'qr-code-version
      (fdefinition 'qr-error-correction) #'qr-code-error-correction
      (fdefinition 'qr-mask) #'qr-code-mask
      (fdefinition 'qr-mode) #'qr-code-mode
      (fdefinition 'qr-size) #'qr-code-size
      (fdefinition 'qr-modules) #'qr-code-modules)

(defun map-modules (qr function)
  "Call FUNCTION with (ROW COL DARK-P) for every module of QR, row by row.
This iterates the bare symbol with no quiet zone."
  (let ((size (qr-code-size qr))
        (modules (qr-code-modules qr)))
    (dotimes (r size qr)
      (dotimes (c size)
        (funcall function r c (= 1 (aref modules r c)))))))

;;; ---------------------------------------------------------------------------
;;; Encoding
;;; ---------------------------------------------------------------------------

(defun content-to-segment (content mode)
  "Build a single segment encoding CONTENT in the forced MODE."
  (ecase mode
    (:numeric (make-numeric-segment content))
    (:alphanumeric (make-alphanumeric-segment content))
    (:byte (make-byte-segment content))
    (:kanji (make-kanji-segment content))))

(defun encode (content &key (error-correction :m) version mask mode eci)
  "Encode CONTENT into a QR-CODE (the model).

CONTENT           a string, or a sequence of (unsigned-byte 8) for byte mode.
:error-correction one of :l :m :q :h (default :m).
:version          force a version 1-40, or NIL to pick the smallest that fits.
:mask             force a mask pattern 0-7, or NIL to pick the best by penalty.
:mode             force an encoding mode (:numeric :alphanumeric :byte :kanji),
                  or NIL to select automatically.
:eci              an ECI assignment number to prefix, or NIL for none.

Signals CLQR:DATA-TOO-LONG if the content does not fit, CLQR:INVALID-VERSION or
CLQR:INVALID-MODE for bad arguments."
  (unless (member error-correction +ecl-order+)
    (error 'clqr-error))
  (when (and mask (not (typep mask '(integer 0 7))))
    (error 'clqr-error))
  (let* ((base-segments (if mode
                            (list (content-to-segment content mode))
                            (auto-segments content)))
         (segments (if eci
                       (cons (make-eci-segment eci) base-segments)
                       base-segments))
         (ver (choose-version segments error-correction version))
         (data (segments-to-data-codewords segments ver error-correction))
         (final (make-final-message data ver error-correction)))
    (multiple-value-bind (modules chosen-mask)
        (build-matrix final ver error-correction mask)
      (%make-qr-code
       :version ver
       :error-correction error-correction
       :mask chosen-mask
       :mode (remove-duplicates (mapcar #'segment-mode base-segments))
       :size (module-count ver)
       :modules modules))))

(defun encode-segments (segments &key (error-correction :m) version mask)
  "Encode an explicit list of SEGMENTS (see MAKE-*-SEGMENT) into a QR-CODE.
This is the low-level entry point for mixed-mode content."
  (let* ((ver (choose-version segments error-correction version))
         (data (segments-to-data-codewords segments ver error-correction))
         (final (make-final-message data ver error-correction)))
    (multiple-value-bind (modules chosen-mask)
        (build-matrix final ver error-correction mask)
      (%make-qr-code
       :version ver :error-correction error-correction :mask chosen-mask
       :mode (remove-duplicates
              (remove :eci (mapcar #'segment-mode segments)))
       :size (module-count ver) :modules modules))))

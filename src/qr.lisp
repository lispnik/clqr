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

(defun utf8-content-p (content)
  "True when CONTENT is a string that needs UTF-8, i.e. contains a character
outside the single-byte ISO-8859-1 range (so STRING-TO-BYTES will emit UTF-8)."
  (and (stringp content)
       (find-if (lambda (c) (>= (char-code c) 256)) content)
       t))

(defun content-segments (content mode eci)
  "Build the segment list for CONTENT under the (possibly NIL) forced MODE and
explicit ECI.  When the content is encoded as UTF-8 byte data and no ECI was
requested, an ECI 26 (UTF-8) header is prefixed so the byte segment is
self-describing instead of relying on the reader to guess ISO-8859-1 vs UTF-8."
  (let* ((base (if mode
                   (list (content-to-segment content mode))
                   (auto-segments content)))
         (effective-eci (or eci
                            (when (and (utf8-content-p content)
                                       (member mode '(nil :byte)))
                              26))))
    (if effective-eci
        (cons (make-eci-segment effective-eci) base)
        base)))

(defun encode (content &key (error-correction :m) version mask mode eci)
  "Encode CONTENT into a QR-CODE (the model).

CONTENT           a string, or a sequence of (unsigned-byte 8) for byte mode.
:error-correction one of :l :m :q :h (default :m).
:version          force a version 1-40, or NIL to pick the smallest that fits.
:mask             force a mask pattern 0-7, or NIL to pick the best by penalty.
:mode             force an encoding mode (:numeric :alphanumeric :byte :kanji),
                  or NIL to select automatically.
:eci              an ECI assignment number to prefix, or NIL for none.  When
                  NIL and the content is encoded as UTF-8 byte data, ECI 26
                  (UTF-8) is prefixed automatically.

Signals CLQR:DATA-TOO-LONG if the content does not fit, and
CLQR:INVALID-VERSION / CLQR:INVALID-ERROR-CORRECTION / CLQR:INVALID-MASK /
CLQR:INVALID-MODE for bad arguments."
  (unless (member error-correction +ecl-order+)
    (error 'invalid-error-correction :datum error-correction))
  (when (and mask (not (typep mask '(integer 0 7))))
    (error 'invalid-mask :datum mask))
  ;; The whole encoding pipeline lives in ENCODE-SEGMENTS; it already drops the
  ;; :eci mode from the recorded mode list.
  (encode-segments (content-segments content mode eci)
                   :error-correction error-correction
                   :version version :mask mask))

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

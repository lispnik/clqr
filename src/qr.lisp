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
  (size 21 :type (integer 11 177) :read-only t)
  (modules nil :type (simple-array bit (* *)) :read-only t)
  ;; True for Micro QR (M1-M4) symbols; NIL for standard QR.
  (micro nil :read-only t))

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
      (fdefinition 'qr-modules) #'qr-code-modules
      (fdefinition 'qr-micro-p) #'qr-code-micro)

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

(defun eci-prefix (eci-number)
  (when eci-number (list (make-eci-segment eci-number))))

(defun plan-encoding (content mode eci error-correction forced-version &optional leading)
  "Choose the segments and version for CONTENT.  Returns (values SEGMENTS
VERSION).  LEADING is a list of fixed header segments (e.g. Structured Append or
FNC1) prefixed before everything and counted against capacity.  With no forced
MODE and a string CONTENT the segmentation is optimal (minimal-bit mixed mode,
including Kanji); otherwise a single forced-mode or byte segment is used.

An ECI 26 (UTF-8) header is prefixed automatically only when the content is
actually encoded as UTF-8 *byte* data (never for Kanji-mode runs, which are
self-describing), unless an explicit ECI was given."
  (let ((leading-bits (reduce #'+ leading :initial-value 0
                                          :key (lambda (s) (segment-bits s 1)))))
    (cond
      (mode
       ;; Forced single mode: only byte mode can carry UTF-8 that needs an ECI.
       (let* ((eci-number (or eci (when (and (eq mode :byte) (utf8-content-p content)) 26)))
              (segments (append leading (eci-prefix eci-number)
                                (list (content-to-segment content mode))))
              (version (choose-version segments error-correction forced-version)))
         (values segments version)))
      ((stringp content)
       ;; Optimal segmentation.  Two mutually exclusive regimes keep the symbol
       ;; unambiguous for readers:
       ;;   * If a UTF-8 byte ECI is in play (an explicit ECI, or content with a
       ;;     non-Kanji character above Latin-1), encode all non-ASCII as UTF-8
       ;;     bytes under that ECI and do NOT use Kanji mode -- mixing Kanji runs
       ;;     with an ECI confuses decoders.
       ;;   * Otherwise use Kanji mode freely (self-describing, no ECI) and keep
       ;;     byte runs Latin-1 only, so no undeclared UTF-8 is ever emitted.
       (let* ((utf8-required (some (lambda (c) (and (>= (char-code c) 256)
                                                    (not (shift-jis-value c))))
                                   content))
              (eci-number (cond (eci eci) (utf8-required 26) (t nil)))
              (modes (if eci-number
                         '(:numeric :alphanumeric :byte)
                         '(:numeric :alphanumeric :byte :kanji)))
              (latin1-byte-only (null eci-number))
              (prefix (eci-prefix eci-number))
              (prefix-bits (+ leading-bits (if prefix (segment-bits (first prefix) 1) 0))))
         (multiple-value-bind (runs version)
             (optimal-runs-and-version content error-correction prefix-bits
                                       forced-version modes latin1-byte-only)
           ;; Under ECI 26 every byte run must be UTF-8, even an all-Latin-1 run
           ;; the DP happened to isolate.
           (values (append leading prefix
                           (runs-to-segments content runs (eql eci-number 26)))
                   version))))
      (t                                ; a raw byte sequence -> single byte segment
       (let* ((segments (append leading (eci-prefix eci)
                                (list (make-byte-segment content))))
              (version (choose-version segments error-correction forced-version)))
         (values segments version))))))

(defun %build-symbol (segments version error-correction mask)
  "Encode SEGMENTS at VERSION into a finished QR-CODE."
  (when (and mask (not (typep mask '(integer 0 7))))
    (error 'invalid-mask :datum mask))
  (let* ((data (segments-to-data-codewords segments version error-correction))
         (final (make-final-message data version error-correction)))
    (multiple-value-bind (modules chosen-mask)
        (build-matrix final version error-correction mask)
      (%make-qr-code
       :version version :error-correction error-correction :mask chosen-mask
       :mode (remove-duplicates
              (set-difference (mapcar #'segment-mode segments) +header-modes+))
       :size (module-count version) :modules modules))))

(defun fnc1-leading (fnc1)
  "Translate the :FNC1 argument into a list of leading header segments.
NIL          -> none
:GS1         -> FNC1 in the first position (GS1)
(:aim N)     -> FNC1 in the second position with application indicator N (0-255)"
  (cond ((null fnc1) nil)
        ((eq fnc1 :gs1) (list (make-fnc1-first-segment)))
        ((and (consp fnc1) (eq (first fnc1) :aim))
         (list (make-fnc1-second-segment (second fnc1))))
        (t (error 'invalid-mode :datum (list :fnc1 fnc1)))))

(defun encode (content &key (error-correction :m) version mask mode eci fnc1)
  "Encode CONTENT into a QR-CODE (the model).

CONTENT           a string, or a sequence of (unsigned-byte 8) for byte mode.
:error-correction one of :l :m :q :h (default :m).
:version          force a version 1-40, or NIL to pick the smallest that fits.
:mask             force a mask pattern 0-7, or NIL to pick the best by penalty.
:mode             force an encoding mode (:numeric :alphanumeric :byte :kanji),
                  or NIL to select the optimal mixed-mode segmentation.
:eci              an ECI assignment number to prefix, or NIL for none.  When
                  NIL and the content is encoded as UTF-8 byte data, ECI 26
                  (UTF-8) is prefixed automatically.
:fnc1             :GS1 for an FNC1 first-position (GS1) header, (:aim N) for an
                  FNC1 second-position header with application indicator N, or
                  NIL for none.

With automatic mode selection the content is segmented to minimise the encoded
size, mixing Numeric, Alphanumeric, Byte and Kanji runs as beneficial.

Signals CLQR:DATA-TOO-LONG if the content does not fit, and
CLQR:INVALID-VERSION / CLQR:INVALID-ERROR-CORRECTION / CLQR:INVALID-MASK /
CLQR:INVALID-MODE for bad arguments."
  (unless (member error-correction +ecl-order+)
    (error 'invalid-error-correction :datum error-correction))
  (when (and mask (not (typep mask '(integer 0 7))))
    (error 'invalid-mask :datum mask))
  (multiple-value-bind (segments version)
      (plan-encoding content mode eci error-correction version (fnc1-leading fnc1))
    (%build-symbol segments version error-correction mask)))

(defun encode-segments (segments &key (error-correction :m) version mask)
  "Encode an explicit list of SEGMENTS (see MAKE-*-SEGMENT) into a QR-CODE.
This is the low-level entry point for hand-built mixed-mode content."
  (%build-symbol segments (choose-version segments error-correction version)
                 error-correction mask))

;;; ---------------------------------------------------------------------------
;;; Structured Append (multi-symbol sequences)
;;; ---------------------------------------------------------------------------

(defun structured-append-parity (content)
  "The 8-bit parity of CONTENT: the XOR of its byte values (ISO 8.4).  A string
is taken in its byte representation (ISO-8859-1 or UTF-8)."
  (let ((bytes (if (stringp content) (string-to-bytes content) content)))
    (reduce #'logxor bytes :initial-value 0)))

(defun split-string-evenly (content parts)
  "Split the string CONTENT into PARTS roughly-equal contiguous substrings."
  (let ((n (length content)))
    (loop with start = 0
          for i below parts
          for len = (+ (floor n parts) (if (< i (mod n parts)) 1 0))
          collect (subseq content start (+ start len))
          do (incf start len))))

(defun encode-structured-append (content &key (error-correction :m) (count 2)
                                            version mask mode eci fnc1)
  "Encode CONTENT as a Structured Append sequence of COUNT symbols (2-16),
returning a list of COUNT QR-CODE objects.  All symbols carry the same sequence
parity so a reader can reassemble them.  CONTENT must be a string; it is split
into COUNT roughly-equal pieces, each segmented independently.  The other
keywords (including :eci) behave as in ENCODE and apply to every symbol."
  (check-type count (integer 2 16))
  (unless (stringp content)
    (error 'invalid-mode :datum "structured append requires string content"))
  (let ((parity (structured-append-parity content))
        (pieces (split-string-evenly content count)))
    (loop for piece in pieces
          for index from 0
          collect (let ((leading (cons (make-structured-append-segment index count parity)
                                       (fnc1-leading fnc1))))
                    (multiple-value-bind (segments symbol-version)
                        (plan-encoding piece mode eci error-correction version leading)
                      (%build-symbol segments symbol-version error-correction mask))))))

;;;; segment.lisp --- Data segments and their bit encoding (ISO 8.4).
;;;;
;;;; A SEGMENT captures a run of data encoded in one mode.  Segments know how
;;;; many bits they occupy at a given version and how to emit those bits.  This
;;;; file also implements automatic single-mode selection and minimal version
;;;; selection for a given error correction level.

(in-package #:clqr)

(defstruct (segment (:constructor %make-segment))
  "A run of data in one encoding mode.
MODE     one of :numeric :alphanumeric :byte :kanji :eci.
DATA     interpretation depends on MODE:
           :numeric / :alphanumeric  -> a string of characters
           :byte                     -> a vector of (unsigned-byte 8)
           :kanji                    -> a vector of (unsigned-byte 16) Shift-JIS values
           :eci                      -> an (unsigned-byte 24) assignment number
COUNT    the character count placed in the character count indicator."
  (mode nil :type symbol)
  (data nil)
  (count 0 :type (integer 0)))

;;; ---------------------------------------------------------------------------
;;; String -> byte helpers
;;; ---------------------------------------------------------------------------

(defun string-to-utf8 (string)
  "Encode STRING as a vector of UTF-8 (unsigned-byte 8)."
  (let ((out (make-array (length string)
                         :element-type '(unsigned-byte 8)
                         :adjustable t :fill-pointer 0)))
    (loop for ch across string
          for cp = (char-code ch)
          do (cond
               ((< cp #x80)
                (vector-push-extend cp out))
               ((< cp #x800)
                (vector-push-extend (logior #xC0 (ldb (byte 5 6) cp)) out)
                (vector-push-extend (logior #x80 (ldb (byte 6 0) cp)) out))
               ((< cp #x10000)
                (vector-push-extend (logior #xE0 (ldb (byte 4 12) cp)) out)
                (vector-push-extend (logior #x80 (ldb (byte 6 6) cp)) out)
                (vector-push-extend (logior #x80 (ldb (byte 6 0) cp)) out))
               (t
                (vector-push-extend (logior #xF0 (ldb (byte 3 18) cp)) out)
                (vector-push-extend (logior #x80 (ldb (byte 6 12) cp)) out)
                (vector-push-extend (logior #x80 (ldb (byte 6 6) cp)) out)
                (vector-push-extend (logior #x80 (ldb (byte 6 0) cp)) out))))
    (coerce out '(simple-array (unsigned-byte 8) (*)))))

(defun string-to-bytes (string)
  "Convert STRING to bytes for byte-mode encoding.  Uses ISO-8859-1 (one byte
per character) when every character fits in a single byte, otherwise UTF-8."
  (if (every (lambda (ch) (< (char-code ch) 256)) string)
      (map '(simple-array (unsigned-byte 8) (*)) #'char-code string)
      (string-to-utf8 string)))

;;; ---------------------------------------------------------------------------
;;; Segment constructors
;;; ---------------------------------------------------------------------------

(defun make-numeric-segment (string)
  "Create a numeric-mode segment from STRING, which must contain only the
digits 0-9."
  (unless (every (lambda (c) (char<= #\0 c #\9)) string)
    (error 'invalid-mode :datum "numeric segment requires digits 0-9 only"))
  (%make-segment :mode :numeric :data (coerce string 'string) :count (length string)))

(defun make-alphanumeric-segment (string)
  "Create an alphanumeric-mode segment from STRING, whose characters must all
belong to the QR alphanumeric set."
  (unless (every #'alphanumeric-value string)
    (error 'invalid-mode :datum "alphanumeric segment contains unsupported characters"))
  (%make-segment :mode :alphanumeric :data (coerce string 'string) :count (length string)))

(defun make-byte-segment (data)
  "Create a byte-mode segment.  DATA may be a string (encoded to bytes) or a
sequence of (unsigned-byte 8)."
  (let ((bytes (if (stringp data)
                   (string-to-bytes data)
                   (coerce data '(simple-array (unsigned-byte 8) (*))))))
    (%make-segment :mode :byte :data bytes :count (length bytes))))

(defun make-kanji-segment (data)
  "Create a Kanji-mode segment.  DATA may be a string (converted to Shift-JIS)
or a sequence of (unsigned-byte 16) Shift-JIS double-byte values."
  (let ((values (if (stringp data)
                    (string-to-shift-jis data)
                    (coerce data '(simple-array (unsigned-byte 16) (*))))))
    (%make-segment :mode :kanji :data values :count (length values))))

(defun make-eci-segment (assignment-number)
  "Create an ECI header segment for ASSIGNMENT-NUMBER (0-999999)."
  (check-type assignment-number (integer 0 999999))
  (%make-segment :mode :eci :data assignment-number :count 0))

;;; ---------------------------------------------------------------------------
;;; Bit length
;;; ---------------------------------------------------------------------------

(defun segment-data-bits (segment)
  "Number of bits in the data portion of SEGMENT (excluding mode indicator and
character count indicator)."
  (let ((n (segment-count segment)))
    (ecase (segment-mode segment)
      (:numeric (+ (* 10 (floor n 3))
                   (case (mod n 3) (0 0) (1 4) (2 7))))
      (:alphanumeric (+ (* 11 (floor n 2)) (* 6 (mod n 2))))
      (:byte (* 8 n))
      (:kanji (* 13 n))
      (:eci (let ((v (segment-data segment)))
              (cond ((< v #x80) 8) ((< v #x4000) 16) (t 24)))))))

(defun segment-bits (segment version)
  "Total number of bits SEGMENT occupies at VERSION, including the mode
indicator and (except for ECI) the character count indicator."
  (+ 4                                  ; mode indicator
     (if (eq (segment-mode segment) :eci)
         0
         (char-count-bits (segment-mode segment) version))
     (segment-data-bits segment)))

(defun segments-bits (segments version)
  (reduce #'+ segments :key (lambda (s) (segment-bits s version))))

;;; ---------------------------------------------------------------------------
;;; Bit emission
;;; ---------------------------------------------------------------------------

(defun write-eci-designator (stream value)
  (cond ((< value #x80) (write-bits stream value 8))
        ((< value #x4000) (write-bits stream (logior #x8000 value) 16))
        (t (write-bits stream (logior #xC00000 value) 24))))

(defun write-segment (stream segment version)
  "Emit SEGMENT (mode indicator, character count and data) into STREAM."
  (let ((mode (segment-mode segment)))
    (write-bits stream (mode-indicator mode) 4)
    (unless (eq mode :eci)
      (write-bits stream (segment-count segment) (char-count-bits mode version)))
    (ecase mode
      (:numeric
       (let ((s (segment-data segment)))
         (loop for i from 0 below (length s) by 3
               for chunk = (subseq s i (min (+ i 3) (length s)))
               do (write-bits stream (parse-integer chunk)
                              (case (length chunk) (3 10) (2 7) (1 4))))))
      (:alphanumeric
       (let ((s (segment-data segment)))
         (loop for i from 0 below (length s) by 2
               do (if (= (1+ i) (length s))
                      (write-bits stream (alphanumeric-value (char s i)) 6)
                      (write-bits stream
                                  (+ (* 45 (alphanumeric-value (char s i)))
                                     (alphanumeric-value (char s (1+ i))))
                                  11)))))
      (:byte
       (loop for b across (segment-data segment) do (write-bits stream b 8)))
      (:kanji
       (loop for v across (segment-data segment)
             for adjusted = (cond ((<= #x8140 v #x9FFC) (- v #x8140))
                                  ((<= #xE040 v #xEBBF) (- v #xC140))
                                  (t (error 'invalid-mode
                                            :datum "value outside Shift-JIS Kanji range")))
             do (write-bits stream
                            (+ (* (ldb (byte 8 8) adjusted) #xC0)
                               (ldb (byte 8 0) adjusted))
                            13)))
      (:eci (write-eci-designator stream (segment-data segment))))
    stream))

;;; ---------------------------------------------------------------------------
;;; Automatic segmentation and version selection
;;; ---------------------------------------------------------------------------

(defun auto-segments (content)
  "Build a list of segments for CONTENT (a string or a byte sequence) by
choosing the most compact single mode that can represent all of it."
  (if (stringp content)
      (list (cond
              ((and (plusp (length content))
                    (every (lambda (c) (char<= #\0 c #\9)) content))
               (make-numeric-segment content))
              ((and (plusp (length content))
                    (every #'alphanumeric-value content))
               (make-alphanumeric-segment content))
              (t (make-byte-segment content))))
      (list (make-byte-segment content))))

(defun choose-version (segments ecl &optional forced-version)
  "Return the version to use for SEGMENTS at error correction level ECL.  If
FORCED-VERSION is supplied it is validated for capacity; otherwise the smallest
fitting version (1-40) is returned."
  (flet ((fits (version)
           (<= (segments-bits segments version) (data-capacity-bits version ecl))))
    (cond
      (forced-version
       (unless (and (integerp forced-version) (<= 1 forced-version 40))
         (error 'invalid-version :datum forced-version))
       (unless (fits forced-version)
         (error 'data-too-long
                :content-bits (segments-bits segments forced-version)
                :version forced-version :error-correction ecl))
       forced-version)
      (t (or (loop for v from 1 to 40 when (fits v) return v)
             (error 'data-too-long
                    :content-bits (segments-bits segments 40)
                    :version nil :error-correction ecl))))))

(defun segments-to-data-codewords (segments version ecl)
  "Encode SEGMENTS into the padded data codeword vector for VERSION and ECL."
  (let ((stream (make-bit-stream)))
    (dolist (s segments) (write-segment stream s version))
    (pad-to-capacity stream (total-data-codewords version ecl))
    (bit-stream-to-codewords stream)))

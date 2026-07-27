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
  (unless (and (typep string 'sequence)
               (every (lambda (c) (and (characterp c) (char<= #\0 c #\9))) string))
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

(defun make-fnc1-first-segment ()
  "Create an FNC1 header in the first position (GS1 application, ISO 8.4.1)."
  (%make-segment :mode :fnc1-first :data nil :count 0))

(defun make-fnc1-second-segment (application-indicator)
  "Create an FNC1 header in the second position with the given 8-bit
APPLICATION-INDICATOR codeword (AIM industry applications, ISO 8.4.1)."
  (check-type application-indicator (integer 0 255))
  (%make-segment :mode :fnc1-second :data application-indicator :count 0))

(defun make-structured-append-segment (index total parity)
  "Create a Structured Append header (ISO 8.4): this is symbol INDEX (0-based)
of TOTAL symbols (1-16), with the 8-bit sequence PARITY common to the set."
  (check-type index (integer 0 15))
  (check-type total (integer 1 16))
  (check-type parity (integer 0 255))
  (assert (< index total) (index total)
          "Structured Append index ~D must be less than total ~D." index total)
  (%make-segment :mode :structured-append :data (list index total parity) :count 0))

;;; ---------------------------------------------------------------------------
;;; Bit length
;;; ---------------------------------------------------------------------------

(defun eci-designator-bits (value)
  "Width in bits of the ECI designator encoding VALUE (ISO 8.4.1.1)."
  (cond ((< value #x80) 8) ((< value #x4000) 16) (t 24)))

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
      (:eci (eci-designator-bits (segment-data segment)))
      (:fnc1-first 0)                   ; mode indicator only
      (:fnc1-second 8)                  ; + application indicator codeword
      (:structured-append 16))))        ; + sequence indicator + parity codewords

(defun segment-bits (segment version)
  "Total number of bits SEGMENT occupies at VERSION, including the mode
indicator and (for data modes) the character count indicator."
  (+ 4                                  ; mode indicator
     (if (member (segment-mode segment) +header-modes+)
         0
         (char-count-bits (segment-mode segment) version))
     (segment-data-bits segment)))

(defun segments-bits (segments version)
  (reduce #'+ segments :key (lambda (s) (segment-bits s version))))

;;; ---------------------------------------------------------------------------
;;; Bit emission
;;; ---------------------------------------------------------------------------

(defun write-eci-designator (stream value)
  (ecase (eci-designator-bits value)
    (8 (write-bits stream value 8))
    (16 (write-bits stream (logior #x8000 value) 16))
    (24 (write-bits stream (logior #xC00000 value) 24))))

(defun write-segment (stream segment version)
  "Emit SEGMENT (mode indicator, character count and data) into STREAM."
  (let ((mode (segment-mode segment)))
    (write-bits stream (mode-indicator mode) 4)
    (unless (member mode +header-modes+)
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
      (:eci (write-eci-designator stream (segment-data segment)))
      (:fnc1-first)                     ; mode indicator only, nothing further
      (:fnc1-second (write-bits stream (segment-data segment) 8))
      (:structured-append
       (destructuring-bind (index total parity) (segment-data segment)
         ;; Symbol sequence indicator: position (0-based) then (total - 1).
         (write-bits stream (logior (ash index 4) (1- total)) 8)
         (write-bits stream parity 8))))
    stream))

;;; ---------------------------------------------------------------------------
;;; Optimal mixed-mode segmentation and version selection
;;; ---------------------------------------------------------------------------
;;;
;;; The optimal segmentation of a string is the partition into runs (each in one
;;; mode) that minimises the total encoded bit count.  Since the character-count
;;; indicator width depends only on the version group (1-9, 10-26, 27-40), the
;;; dynamic program below is run once per group; version selection then picks the
;;; smallest version whose capacity holds the group's optimal bit count.

(defun utf8-char-length (char)
  "Number of UTF-8 bytes needed to encode CHAR."
  (let ((cp (char-code char)))
    (cond ((< cp #x80) 1) ((< cp #x800) 2) ((< cp #x10000) 3) (t 4))))

(defun char-supports-mode-p (char mode &optional latin1-byte-only)
  "True if CHAR can be encoded in MODE.  When LATIN1-BYTE-ONLY is true, byte mode
only accepts single-byte (ISO-8859-1) characters, so that multi-byte UTF-8 is
never emitted in a byte run without an accompanying ECI."
  (ecase mode
    (:numeric (char<= #\0 char #\9))
    (:alphanumeric (and (alphanumeric-value char) t))
    (:byte (or (not latin1-byte-only) (< (char-code char) 256)))
    (:kanji (and (shift-jis-value char) t))))

(defun mode-data-bits (mode length)
  "Data bits for a run of LENGTH characters in MODE (byte mode is handled with
UTF-8 byte counts elsewhere, so it is not accepted here)."
  (ecase mode
    (:numeric (+ (* 10 (floor length 3)) (case (mod length 3) (0 0) (1 4) (2 7))))
    (:alphanumeric (+ (* 11 (floor length 2)) (* 6 (mod length 2))))
    (:kanji (* 13 length))))

(defun optimal-runs (content version modes latin1-byte-only)
  "Return (values TOTAL-BITS RUNS) for the minimal-bit segmentation of the
string CONTENT at VERSION, choosing among MODES (byte mode restricted to
Latin-1 when LATIN1-BYTE-ONLY).  RUNS is a list of (MODE START END)."
  (let* ((n (length content))
         (dp (make-array (1+ n) :initial-element nil))    ; dp[i] = min bits or NIL
         (back (make-array (1+ n) :initial-element nil))  ; back[i] = (start . mode)
         (byte-prefix (make-array (1+ n) :initial-element 0)))
    (when (zerop n)
      (return-from optimal-runs
        (values (+ 4 (char-count-bits :byte version)) (list (list :byte 0 0)))))
    (setf (aref dp 0) 0)
    (dotimes (k n)
      (setf (aref byte-prefix (1+ k))
            (+ (aref byte-prefix k) (utf8-char-length (char content k)))))
    (dotimes (j n)
      (when (aref dp j)
        (dolist (mode modes)
          (loop for i from (1+ j) to n
                while (char-supports-mode-p (char content (1- i)) mode latin1-byte-only)
                do (let* ((data-bits (if (eq mode :byte)
                                         (* 8 (- (aref byte-prefix i) (aref byte-prefix j)))
                                         (mode-data-bits mode (- i j))))
                          (cost (+ (aref dp j) 4 (char-count-bits mode version) data-bits)))
                     (when (or (null (aref dp i)) (< cost (aref dp i)))
                       (setf (aref dp i) cost
                             (aref back i) (cons j mode))))))))
    (let ((runs '()) (i n))
      (loop while (> i 0)
            for entry = (aref back i)
            do (push (list (cdr entry) (car entry) i) runs)
               (setf i (car entry)))
      (values (aref dp n) runs))))

(defun run-to-segment (content mode start end)
  "Build the segment for the run CONTENT[START:END] in MODE."
  (let ((s (subseq content start end)))
    (ecase mode
      (:numeric (make-numeric-segment s))
      (:alphanumeric (make-alphanumeric-segment s))
      (:byte (make-byte-segment s))
      (:kanji (make-kanji-segment s)))))

(defun runs-to-segments (content runs)
  (mapcar (lambda (run) (apply #'run-to-segment content run)) runs))

(defun version-group (version)
  (cond ((<= version 9) 0) ((<= version 26) 1) (t 2)))

(defun optimal-runs-and-version (content ecl prefix-bits forced-version modes latin1-byte-only)
  "Choose the optimal segmentation of the string CONTENT (over MODES, byte mode
Latin-1-only when LATIN1-BYTE-ONLY) and the version that holds it, allowing
PREFIX-BITS for any fixed prefix segment.  Returns (values RUNS VERSION)."
  (labels ((fits (bits version) (<= (+ bits prefix-bits) (data-capacity-bits version ecl)))
           (runs-for (v) (multiple-value-list
                          (optimal-runs content v modes latin1-byte-only))))
    (if forced-version
        (multiple-value-bind (bits runs) (optimal-runs content forced-version modes latin1-byte-only)
          (unless (and (integerp forced-version) (<= 1 forced-version 40))
            (error 'invalid-version :datum forced-version))
          (unless (fits bits forced-version)
            (error 'data-too-long :content-bits (+ bits prefix-bits)
                                  :version forced-version :error-correction ecl))
          (values runs forced-version))
        (let ((cache (make-array 3 :initial-element nil)))
          (flet ((group (g)
                   (or (aref cache g)
                       (setf (aref cache g) (runs-for (svref #(1 10 27) g))))))
            (loop for v from 1 to 40
                  for (bits runs) = (group (version-group v))
                  when (fits bits v)
                    do (return (values runs v))
                  finally (destructuring-bind (bits runs) (group 2)
                            (declare (ignore runs))
                            (error 'data-too-long :content-bits (+ bits prefix-bits)
                                                  :version nil :error-correction ecl))))))))

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

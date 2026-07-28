;;;; micro.lisp --- Micro QR Code (M1-M4) encoder.
;;;;
;;;; Micro QR (ISO/IEC 18004 clause dedicated to Micro QR) is a compact symbol
;;;; family with a single finder pattern, timing patterns along the top row and
;;;; left column, a 15-bit format information string with its own BCH mask, only
;;;; four data masks, and version-dependent mode indicators and character-count
;;;; widths.  Versions are M1 (11x11), M2 (13x13), M3 (15x15) and M4 (17x17),
;;;; represented here as the integers 1-4.
;;;;
;;;; The finished symbol is returned as an ordinary CLQR:QR-CODE with its MICRO
;;;; slot set, so the renderers work unchanged.

(in-package #:clqr)

(declaim (inline micro-module-count))
(defun micro-module-count (version)
  "Modules per side for Micro QR VERSION (1-4)."
  (+ 9 (* 2 version)))

;;; Symbol number (3 bits) used in the format information (ISO Table 13).
(defun micro-symbol-number (version ecl)
  (ecase version
    (1 0)
    (2 (ecase ecl (:l 1) (:m 2)))
    (3 (ecase ecl (:l 3) (:m 4)))
    (4 (ecase ecl (:l 5) (:m 6) (:q 7)))))

(defun micro-error-levels (version)
  "The error correction levels available for Micro QR VERSION."
  (ecase version (1 '(:l)) (2 '(:l :m)) (3 '(:l :m)) (4 '(:l :m :q))))

;;; Data-bit capacity and codeword structure (ISO Micro QR tables).  Each row is
;;; (VERSION ECL DATA-BITS DATA-CODEWORDS EC-CODEWORDS).  M1 and M3 have a final
;;; data codeword of only 4 bits, so DATA-BITS is not a multiple of 8 there.
(defparameter +micro-spec+
  '((1 :l 20  3  2)
    (2 :l 40  5  5)
    (2 :m 32  4  6)
    (3 :l 84 11  6)
    (3 :m 68  9  8)
    (4 :l 128 16  8)
    (4 :m 112 14 10)
    (4 :q 80 10 14)))

(defun micro-spec (version ecl)
  (or (find-if (lambda (row) (and (= (first row) version) (eq (second row) ecl)))
               +micro-spec+)
      (error 'invalid-error-correction :datum ecl)))

(defun micro-data-bits (version ecl) (third (micro-spec version ecl)))
(defun micro-ec-count (version ecl) (fifth (micro-spec version ecl)))

;;; Mode indicators and character-count widths (ISO Micro QR Tables 2-3).
(defun micro-mode-bits (version) (ecase version (1 0) (2 1) (3 2) (4 3)))

(defun micro-mode-value (mode)
  (ecase mode (:numeric 0) (:alphanumeric 1) (:byte 2) (:kanji 3)))

(defun micro-mode-allowed-p (mode version)
  (ecase mode
    (:numeric t)
    (:alphanumeric (>= version 2))
    (:byte (>= version 3))
    (:kanji (>= version 3))))

(defun micro-char-count-bits (mode version)
  (ecase mode
    (:numeric (ecase version (1 3) (2 4) (3 5) (4 6)))
    (:alphanumeric (ecase version (2 3) (3 4) (4 5)))
    (:byte (ecase version (3 4) (4 5)))
    (:kanji (ecase version (3 3) (4 4)))))

(defun micro-terminator-bits (version) (ecase version (1 3) (2 5) (3 7) (4 9)))

;;; Format information: BCH(15,5) over generator 0x537, XORed with 0x4445.
(defparameter +micro-format-mask+ #x4445)

(defun micro-format-information (symbol-number mask)
  (let* ((data (logior (ash symbol-number 2) mask))
         (bch (%bch-remainder data #b10100110111 11)))
    (logxor (logior (ash data 10) bch) +micro-format-mask+)))

;;; ---------------------------------------------------------------------------
;;; Data encoding
;;; ---------------------------------------------------------------------------

(defun micro-content-segment (content mode)
  (ecase mode
    (:numeric (make-numeric-segment content))
    (:alphanumeric (make-alphanumeric-segment content))
    (:byte (make-byte-segment content))
    (:kanji (make-kanji-segment content))))

(defun micro-pad (stream data-bits version)
  "Append the terminator and padding so STREAM holds exactly DATA-BITS bits.
M1 and M3 fill all remaining bits with 0; M2 and M4 byte-align then add the
alternating pad codewords 0xEC/0x11 (ISO Micro QR padding rules)."
  (let ((terminator (min (micro-terminator-bits version)
                         (- data-bits (bit-stream-length stream)))))
    (dotimes (i terminator) (write-bit stream 0)))
  (cond
    ((member version '(1 3))
     (loop while (< (bit-stream-length stream) data-bits) do (write-bit stream 0)))
    (t
     (loop while (plusp (mod (bit-stream-length stream) 8)) do (write-bit stream 0))
     (loop for i from 0
           while (< (bit-stream-length stream) data-bits)
           do (write-bits stream (aref +pad-bytes+ (mod i 2)) 8)))))

(defun micro-data-codewords (stream)
  "Split the bit STREAM into codewords for Reed-Solomon.  A final partial (4-bit)
codeword for M1/M3 is high-aligned within its byte (the 4 data bits occupy the
high nibble, low nibble 0), matching the ISO/segno convention."
  (let* ((bits (bit-stream-bits stream))
         (len (fill-pointer bits))
         (n (ceiling len 8))
         (cw (make-array n :element-type '(unsigned-byte 8))))
    (dotimes (i n cw)
      (let ((byte 0) (width (min 8 (- len (* i 8)))))
        (dotimes (b width)
          (setf byte (logior (ash byte 1) (aref bits (+ (* i 8) b)))))
        ;; High-align a short final codeword (e.g. 4 bits -> high nibble).
        (setf (aref cw i) (ash byte (- 8 width)))))))

(defun micro-encode (content mode version ecl)
  "Encode CONTENT into the final placement bit sequence for Micro QR VERSION/ECL.
Returns a bit vector of DATA-BITS + 8*EC-COUNT bits."
  (let* ((segment (micro-content-segment content mode))
         (data-bits (micro-data-bits version ecl))
         (stream (make-bit-stream)))
    (when (plusp (micro-mode-bits version))
      (write-bits stream (micro-mode-value mode) (micro-mode-bits version)))
    (write-bits stream (segment-count segment) (micro-char-count-bits mode version))
    (write-segment-payload stream segment)
    (when (> (bit-stream-length stream) data-bits)
      (error 'data-too-long :content-bits (bit-stream-length stream)
                            :version version :error-correction ecl))
    (micro-pad stream data-bits version)
    ;; Reed-Solomon over the data codewords (final 4-bit codeword as a 0-15 byte).
    (let* ((data-cw (micro-data-codewords stream))
           (ec (rs-encode data-cw (micro-ec-count version ecl)))
           (out (make-array (+ data-bits (* 8 (length ec)))
                            :element-type 'bit :fill-pointer 0)))
      ;; Data bits verbatim, then EC codewords 8 bits each, MSB first.
      (loop for b across (bit-stream-bits stream) do (vector-push b out))
      (loop for c across ec
            do (loop for i from 7 downto 0 do (vector-push (ldb (byte 1 i) c) out)))
      out)))

;;; ---------------------------------------------------------------------------
;;; Matrix
;;; ---------------------------------------------------------------------------

(defun micro-draw-timing (modules func size)
  "Timing patterns along the top row and left column (from the finder to edge)."
  (loop for i from 8 below size
        for bit = (if (evenp i) 1 0)
        do (setf (mref modules 0 i) bit (mref func 0 i) 1)
           (setf (mref modules i 0) bit (mref func i 0) 1)))

(defun micro-format-positions (size)
  "The 15 format-information positions, indexed by bit 0..14: down column 8
(rows 1-8) then left along row 8 (cols 7-1)."
  (declare (ignore size))
  (let ((p (make-array 15)))
    (dotimes (i 15 p)
      (setf (aref p i)
            (if (<= i 7)
                (cons (1+ i) 8)              ; (1,8)..(8,8)
                (cons 8 (- 15 i)))))))        ; (8,7)..(8,1)

(defun micro-reserve-format (modules func size)
  (declare (ignore modules))
  (loop for cell across (micro-format-positions size)
        do (setf (mref func (car cell) (cdr cell)) 1)))

(defun micro-draw-format-bits (modules size symbol-number mask)
  ;; Micro QR places the format bits least-significant-bit first (position i
  ;; holds bit i), unlike standard QR which is most-significant-bit first.
  (let ((bits (micro-format-information symbol-number mask)))
    (loop for cell across (micro-format-positions size)
          for i from 0
          do (setf (mref modules (car cell) (cdr cell))
                   (ldb (byte 1 i) bits)))))

(defun micro-place-function-patterns (modules func size)
  (draw-finder modules func size 0 0)   ; finder + separator (right/bottom)
  (micro-draw-timing modules func size)
  (micro-reserve-format modules func size))

(defun micro-draw-data (modules func size bits inc)
  "Place BITS with the zig-zag scan; leftover modules stay light.  INC is 0 for
M2/M4 and 2 for M1/M3, which flips the scan direction so it starts at the
upper-right corner (ISO 7.7.3 / the M1,M3 special case)."
  (let ((idx 0) (n (length bits)))
    (let ((right (1- size)))
      (loop while (>= right 1) do
        (dotimes (vert size)
          (dotimes (j 2)
            (let* ((col (- right j))
                   (upward (zerop (logand (+ right inc) 2)))
                   (row (if upward (- size 1 vert) vert)))
              (when (zerop (mref func row col))
                (setf (mref modules row col) (if (< idx n) (aref bits idx) 0))
                (incf idx)))))
        (decf right 2)))))

;;; Micro QR data masks (2 bits): patterns 0-3 (= QR masks 1,4,6,7).
(defun micro-mask-predicate (mask)
  (ecase mask
    (0 (lambda (r c) (declare (ignore c)) (zerop (mod r 2))))
    (1 (lambda (r c) (zerop (mod (+ (floor r 2) (floor c 3)) 2))))
    (2 (lambda (r c) (zerop (mod (+ (mod (* r c) 2) (mod (* r c) 3)) 2))))
    (3 (lambda (r c) (zerop (mod (+ (mod (+ r c) 2) (mod (* r c) 3)) 2))))))

(defun micro-apply-mask (modules func size mask)
  (let ((pred (micro-mask-predicate mask)))
    (dotimes (r size)
      (dotimes (c size)
        (when (and (zerop (mref func r c)) (funcall pred r c))
          (setf (mref modules r c) (- 1 (mref modules r c))))))))

(defun micro-mask-score (modules size)
  "Micro QR mask evaluation (ISO 8.8.3): count dark modules on the right column
and bottom row (excluding the top-left finder edges); larger is better."
  (let ((sum1 0) (sum2 0))
    (loop for i from 1 below size
          do (incf sum1 (mref modules i (1- size)))     ; rightmost column
             (incf sum2 (mref modules (1- size) i)))    ; bottom row
    (if (<= sum1 sum2) (+ (* sum1 16) sum2) (+ (* sum2 16) sum1))))

(defun micro-build-matrix (bits version ecl forced-mask)
  "Build the finished Micro QR module matrix.  Returns (values MODULES MASK)."
  (let* ((size (micro-module-count version))
         (symbol-number (micro-symbol-number version ecl))
         (modules (make-bit-matrix size))
         (func (make-bit-matrix size))
         (inc (if (member version '(1 3)) 2 0)))
    (micro-place-function-patterns modules func size)
    (micro-draw-data modules func size bits inc)
    (let ((best-mask nil) (best-score nil))
      (dolist (mask (if forced-mask (list forced-mask) '(0 1 2 3)))
        (micro-apply-mask modules func size mask)
        (micro-draw-format-bits modules size symbol-number mask)
        (let ((s (micro-mask-score modules size)))
          (when (or (null best-score) (> s best-score))
            (setf best-mask mask best-score s)))
        (micro-apply-mask modules func size mask))   ; undo (self-inverse)
      (micro-apply-mask modules func size best-mask)
      (micro-draw-format-bits modules size symbol-number best-mask)
      (values modules best-mask))))

;;; ---------------------------------------------------------------------------
;;; Entry point
;;; ---------------------------------------------------------------------------

(defun micro-auto-mode (content)
  "Choose the most compact Micro QR mode for CONTENT (a string)."
  (cond ((every (lambda (c) (char<= #\0 c #\9)) content) :numeric)
        ((every #'alphanumeric-value content) :alphanumeric)
        (t :byte)))

(defun micro-choose-version (content mode ecl forced-version)
  "Return the smallest Micro QR version (or FORCED-VERSION) that holds CONTENT in
MODE at ECL, considering mode/version availability."
  (flet ((fits (v)
           (and (micro-mode-allowed-p mode v)
                (member ecl (micro-error-levels v))
                (let ((stream (make-bit-stream)))
                  (when (plusp (micro-mode-bits v))
                    (write-bits stream (micro-mode-value mode) (micro-mode-bits v)))
                  (write-bits stream (segment-count (micro-content-segment content mode))
                              (micro-char-count-bits mode v))
                  (write-segment-payload stream (micro-content-segment content mode))
                  (<= (bit-stream-length stream) (micro-data-bits v ecl))))))
    (cond (forced-version
           (unless (fits forced-version)
             (error 'data-too-long :version forced-version :error-correction ecl
                                   :content-bits nil))
           forced-version)
          (t (or (loop for v from 1 to 4 when (fits v) return v)
                 (error 'data-too-long :version nil :error-correction ecl
                                       :content-bits nil))))))

(defun encode-micro (content &key (error-correction :l) version mask mode)
  "Encode CONTENT into a Micro QR symbol (M1-M4), returned as a CLQR:QR-CODE with
its MICRO slot set.

CONTENT           a string, or a sequence of (unsigned-byte 8) for byte mode.
:error-correction :l :m or :q (Micro QR has no :h); note M1 supports only :l.
:version          force 1-4 (M1-M4), or NIL for the smallest that fits.
:mask             force a mask 0-3, or NIL to auto-select.
:mode             force :numeric :alphanumeric :byte or :kanji, or NIL (auto)."
  (when (and version (not (typep version '(integer 1 4))))
    (error 'invalid-version :datum version))
  (when (and mask (not (typep mask '(integer 0 3))))
    (error 'invalid-mask :datum mask))
  (unless (member error-correction '(:l :m :q))    ; Micro QR has no :h
    (error 'invalid-error-correction :datum error-correction))
  (when (and mode (not (member mode '(:numeric :alphanumeric :byte :kanji))))
    (error 'invalid-mode :datum mode))
  (unless (or (stringp content) (typep content 'sequence))
    (error 'invalid-mode :datum (list :content content)))
  (let ((mode (or mode (if (stringp content) (micro-auto-mode content) :byte))))
    ;; For a forced version, report mode / EC incompatibility precisely.
    (when version
      (unless (member error-correction (micro-error-levels version))
        (error 'invalid-error-correction :datum error-correction))
      (unless (micro-mode-allowed-p mode version)
        (error 'invalid-mode :datum (list mode version))))
    (let* ((version (micro-choose-version content mode error-correction version))
           (bits (micro-encode content mode version error-correction)))
      (multiple-value-bind (modules chosen-mask)
          (micro-build-matrix bits version error-correction mask)
        (%make-qr-code
         :version version :error-correction error-correction :mask chosen-mask
         :mode (list mode) :size (micro-module-count version)
         :modules modules :micro t)))))

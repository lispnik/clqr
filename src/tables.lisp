;;;; tables.lisp --- Static ISO/IEC 18004 conformance tables and helpers.
;;;;
;;;; This file gathers the fixed data tables the encoder needs: mode indicators,
;;;; character-count-indicator widths, the alphanumeric character set, the error
;;;; correction block structure (ISO Table 9), alignment pattern positions
;;;; (Table E.1), remainder bit counts (Table 1), and generators for the format
;;;; and version information strings (sections 7.9 and 7.10).  Values that are
;;;; cheap and safe to derive (format/version BCH strings) are computed rather
;;;; than transcribed, to avoid copying errors.

(in-package #:clqr)

;;; ---------------------------------------------------------------------------
;;; Conditions
;;; ---------------------------------------------------------------------------

(define-condition clqr-error (error) ()
  (:documentation "Base class for all errors signalled by clqr."))

(define-condition data-too-long (clqr-error)
  ((content-bits :initarg :content-bits :initform nil
                 :reader data-too-long-content-bits)
   (version :initarg :version :initform nil :reader data-too-long-version)
   (error-correction :initarg :error-correction :initform nil
                     :reader data-too-long-error-correction))
  (:report (lambda (c s)
             (format s "Data (~D bits) does not fit ~@[in version ~D ~]at error correction level ~A."
                     (data-too-long-content-bits c)
                     (data-too-long-version c)
                     (data-too-long-error-correction c))))
  (:documentation "Signalled when the content cannot fit the requested version/EC level."))

(define-condition invalid-mode (clqr-error)
  ((datum :initarg :datum :reader invalid-mode-datum))
  (:report (lambda (c s)
             (format s "Invalid or unsupported mode: ~S." (invalid-mode-datum c)))))

(define-condition invalid-version (clqr-error)
  ((datum :initarg :datum :reader invalid-version-datum))
  (:report (lambda (c s)
             (format s "Invalid version: ~S (must be an integer 1-40)."
                     (invalid-version-datum c)))))

;;; ---------------------------------------------------------------------------
;;; Modes and error correction levels
;;; ---------------------------------------------------------------------------

(defparameter *modes* '(:numeric :alphanumeric :byte :kanji :eci)
  "The encoding modes supported by clqr.")

(defparameter +mode-indicators+
  '((:eci          . #b0111)
    (:numeric      . #b0001)
    (:alphanumeric . #b0010)
    (:byte         . #b0100)
    (:kanji        . #b1000))
  "4-bit mode indicators (ISO Table 2).")

(defun mode-indicator (mode)
  (or (cdr (assoc mode +mode-indicators+))
      (error 'invalid-mode :datum mode)))

(defparameter +ecl-order+ '(:l :m :q :h)
  "Error correction levels from lowest to highest recovery capacity.")

(defun error-correction-levels ()
  "Return the list of supported error correction levels."
  (copy-list +ecl-order+))

(defun ecl-index (ecl)
  "Index of ECL within the L,M,Q,H block table."
  (or (position ecl +ecl-order+)
      (error 'clqr-error)))

(defparameter +ecl-format-bits+
  '((:l . #b01) (:m . #b00) (:q . #b11) (:h . #b10))
  "2-bit error correction level indicators used in the format information (Table 12).")

;;; ---------------------------------------------------------------------------
;;; Geometry
;;; ---------------------------------------------------------------------------

(declaim (inline module-count))
(defun module-count (version)
  "Number of modules per side for VERSION (ISO 6.2)."
  (declare (type (integer 1 40) version))
  (+ 17 (* 4 version)))

;;; The remainder bits (ISO Table 1) that pad the symbol after the final
;;; codeword are always zero, so DRAW-DATA simply leaves those trailing modules
;;; light rather than tracking an explicit count.

;;; Alignment pattern centre coordinates, indexed by version (ISO Table E.1).
;;; Version 1 has no alignment patterns.
(defparameter +alignment-positions+
  #(()                                      ; 1
    (6 18) (6 22) (6 26) (6 30) (6 34)      ; 2-6
    (6 22 38) (6 24 42) (6 26 46) (6 28 50) (6 30 54) (6 32 58) (6 34 62) ; 7-13
    (6 26 46 66) (6 26 48 70) (6 26 50 74) (6 30 54 78) (6 30 56 82)
    (6 30 58 86) (6 34 62 90)               ; 14-20
    (6 28 50 72 94) (6 26 50 74 98) (6 30 54 78 102) (6 28 54 80 106)
    (6 32 58 84 110) (6 30 58 86 114) (6 34 62 90 118) ; 21-27
    (6 26 50 74 98 122) (6 30 54 78 102 126) (6 26 52 78 104 130)
    (6 30 56 82 108 134) (6 34 60 86 112 138) (6 30 58 86 114 142)
    (6 34 62 90 118 146)                    ; 28-34
    (6 30 54 78 102 126 150) (6 24 50 76 102 128 154) (6 28 54 80 106 132 158)
    (6 32 58 84 110 136 162) (6 26 54 82 110 138 166) (6 30 58 86 114 142 170)) ; 35-40
  "Alignment pattern centre coordinates per version.")

(defun alignment-positions (version)
  (aref +alignment-positions+ (1- version)))

;;; ---------------------------------------------------------------------------
;;; Character count indicator widths (ISO Table 3)
;;; ---------------------------------------------------------------------------

(defun char-count-bits (mode version)
  "Number of bits in the character count indicator for MODE at VERSION."
  (let ((group (cond ((<= version 9) 0)
                     ((<= version 26) 1)
                     (t 2))))
    (ecase mode
      (:numeric      (svref #(10 12 14) group))
      (:alphanumeric (svref #(9 11 13) group))
      (:byte         (svref #(8 16 16) group))
      (:kanji        (svref #(8 10 12) group)))))

;;; ---------------------------------------------------------------------------
;;; Alphanumeric character set (ISO Table 5)
;;; ---------------------------------------------------------------------------

(defparameter +alphanumeric-chars+
  "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:"
  "The 45 alphanumeric mode characters; index is the mode value.")

(defun alphanumeric-value (char)
  "The alphanumeric mode value for CHAR, or NIL if CHAR is not encodable."
  (position char +alphanumeric-chars+))

;;; ---------------------------------------------------------------------------
;;; Error correction block structure (ISO Table 9)
;;; ---------------------------------------------------------------------------
;;;
;;; One row per version (1-40).  Each row has four entries in L,M,Q,H order.
;;; Each entry is (EC-CODEWORDS-PER-BLOCK
;;;                GROUP1-BLOCKS GROUP1-DATA-CODEWORDS
;;;                GROUP2-BLOCKS GROUP2-DATA-CODEWORDS).

(defparameter +ec-blocks+
  #(;; v1
    (( 7 1 19 0 0) (10 1 16 0 0) (13 1 13 0 0) (17 1  9 0 0))
    ;; v2
    ((10 1 34 0 0) (16 1 28 0 0) (22 1 22 0 0) (28 1 16 0 0))
    ;; v3
    ((15 1 55 0 0) (26 1 44 0 0) (18 2 17 0 0) (22 2 13 0 0))
    ;; v4
    ((20 1 80 0 0) (18 2 32 0 0) (26 2 24 0 0) (16 4  9 0 0))
    ;; v5
    ((26 1 108 0 0) (24 2 43 0 0) (18 2 15 2 16) (22 2 11 2 12))
    ;; v6
    ((18 2 68 0 0) (16 4 27 0 0) (24 4 19 0 0) (28 4 15 0 0))
    ;; v7
    ((20 2 78 0 0) (18 4 31 0 0) (18 2 14 4 15) (26 4 13 1 14))
    ;; v8
    ((24 2 97 0 0) (22 2 38 2 39) (22 4 18 2 19) (26 4 14 2 15))
    ;; v9
    ((30 2 116 0 0) (22 3 36 2 37) (20 4 16 4 17) (24 4 12 4 13))
    ;; v10
    ((18 2 68 2 69) (26 4 43 1 44) (24 6 19 2 20) (28 6 15 2 16))
    ;; v11
    ((20 4 81 0 0) (30 1 50 4 51) (28 4 22 4 23) (24 3 12 8 13))
    ;; v12
    ((24 2 92 2 93) (22 6 36 2 37) (26 4 20 6 21) (28 7 14 4 15))
    ;; v13
    ((26 4 107 0 0) (22 8 37 1 38) (24 8 20 4 21) (22 12 11 4 12))
    ;; v14
    ((30 3 115 1 116) (24 4 40 5 41) (20 11 16 5 17) (24 11 12 5 13))
    ;; v15
    ((22 5 87 1 88) (24 5 41 5 42) (30 5 24 7 25) (24 11 12 7 13))
    ;; v16
    ((24 5 98 1 99) (28 7 45 3 46) (24 15 19 2 20) (30 3 15 13 16))
    ;; v17
    ((28 1 107 5 108) (28 10 46 1 47) (28 1 22 15 23) (28 2 14 17 15))
    ;; v18
    ((30 5 120 1 121) (26 9 43 4 44) (28 17 22 1 23) (28 2 14 19 15))
    ;; v19
    ((28 3 113 4 114) (26 3 44 11 45) (26 17 21 4 22) (26 9 13 16 14))
    ;; v20
    ((28 3 107 5 108) (26 3 41 13 42) (30 15 24 5 25) (28 15 15 10 16))
    ;; v21
    ((28 4 116 4 117) (26 17 42 0 0) (28 17 22 6 23) (30 19 16 6 17))
    ;; v22
    ((28 2 111 7 112) (28 17 46 0 0) (30 7 24 16 25) (24 34 13 0 0))
    ;; v23
    ((30 4 121 5 122) (28 4 47 14 48) (30 11 24 14 25) (30 16 15 14 16))
    ;; v24
    ((30 6 117 4 118) (28 6 45 14 46) (30 11 24 16 25) (30 30 16 2 17))
    ;; v25
    ((26 8 106 4 107) (28 8 47 13 48) (30 7 24 22 25) (30 22 15 13 16))
    ;; v26
    ((28 10 114 2 115) (28 19 46 4 47) (28 28 22 6 23) (30 33 16 4 17))
    ;; v27
    ((30 8 122 4 123) (28 22 45 3 46) (30 8 23 26 24) (30 12 15 28 16))
    ;; v28
    ((30 3 117 10 118) (28 3 45 23 46) (30 4 24 31 25) (30 11 15 31 16))
    ;; v29
    ((30 7 116 7 117) (28 21 45 7 46) (30 1 23 37 24) (30 19 15 26 16))
    ;; v30
    ((30 5 115 10 116) (28 19 47 10 48) (30 15 24 25 25) (30 23 15 25 16))
    ;; v31
    ((30 13 115 3 116) (28 2 46 29 47) (30 42 24 1 25) (30 23 15 28 16))
    ;; v32
    ((30 17 115 0 0) (28 10 46 23 47) (30 10 24 35 25) (30 19 15 35 16))
    ;; v33
    ((30 17 115 1 116) (28 14 46 21 47) (30 29 24 19 25) (30 11 15 46 16))
    ;; v34
    ((30 13 115 6 116) (28 14 46 23 47) (30 44 24 7 25) (30 59 16 1 17))
    ;; v35
    ((30 12 121 7 122) (28 12 47 26 48) (30 39 24 14 25) (30 22 15 41 16))
    ;; v36
    ((30 6 121 14 122) (28 6 47 34 48) (30 46 24 10 25) (30 2 15 64 16))
    ;; v37
    ((30 17 122 4 123) (28 29 46 14 47) (30 49 24 10 25) (30 24 15 46 16))
    ;; v38
    ((30 4 122 18 123) (28 13 46 32 47) (30 48 24 14 25) (30 42 15 32 16))
    ;; v39
    ((30 20 117 4 118) (28 40 47 7 48) (30 43 24 22 25) (30 10 15 67 16))
    ;; v40
    ((30 19 118 6 119) (28 18 47 31 48) (30 34 24 34 25) (30 20 15 61 16)))
  "Error correction block structure, one row per version, L/M/Q/H per row.")

(defun ec-block-spec (version ecl)
  "Return (values EC-PER-BLOCK G1-BLOCKS G1-DATA G2-BLOCKS G2-DATA) for
VERSION and error correction level ECL."
  (unless (and (integerp version) (<= 1 version 40))
    (error 'invalid-version :datum version))
  (let ((spec (nth (ecl-index ecl) (aref +ec-blocks+ (1- version)))))
    (values-list spec)))

(defun total-data-codewords (version ecl)
  "Total number of data codewords (excluding EC) for VERSION at ECL."
  (multiple-value-bind (ec g1b g1d g2b g2d) (ec-block-spec version ecl)
    (declare (ignore ec))
    (+ (* g1b g1d) (* g2b g2d))))

(defun data-capacity-bits (version ecl)
  "Number of data bits available for VERSION at ECL."
  (* 8 (total-data-codewords version ecl)))

;;; ---------------------------------------------------------------------------
;;; Format and version information (ISO 7.9, 7.10)
;;; ---------------------------------------------------------------------------

(defun %bch-remainder (data generator gen-length)
  "Polynomial remainder of DATA*x^(gen-length-1) divided by GENERATOR over
GF(2).  GEN-LENGTH is the bit length of GENERATOR."
  (let ((rem (ash data (1- gen-length))))
    (loop while (>= (integer-length rem) gen-length)
          do (setf rem (logxor rem
                               (ash generator (- (integer-length rem) gen-length)))))
    rem))

(defparameter +format-mask+ #b101010000010010
  "The mask XORed into every format information string (ISO 7.9.1).")

(defun format-information (ecl mask)
  "Return the 15-bit format information string for error correction level ECL
and data mask pattern MASK (0-7)."
  (let* ((ecl-bits (cdr (assoc ecl +ecl-format-bits+)))
         (data (logior (ash ecl-bits 3) mask))     ; 5 data bits
         (bch (%bch-remainder data #b10100110111 11))) ; generator 0x537
    (logxor (logior (ash data 10) bch) +format-mask+)))

(defun version-information (version)
  "Return the 18-bit version information string for VERSION (>= 7), or NIL for
versions that carry no version information (1-6)."
  (when (>= version 7)
    (let ((bch (%bch-remainder version #b1111100100101 13))) ; generator 0x1F25
      (logior (ash version 12) bch))))

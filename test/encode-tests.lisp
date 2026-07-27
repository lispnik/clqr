;;;; encode-tests.lisp --- Format/version info, geometry and full-symbol tests.

(in-package #:clqr.test)

(in-suite clqr-suite)

(test format-information-values
  "Format information strings (ISO Table C.1)."
  (is (= #x77C4 (clqr::format-information :l 0)))
  (is (= #x5412 (clqr::format-information :m 0)))
  ;; All 32 combinations are distinct.
  (let ((values '()))
    (dolist (ecl '(:l :m :q :h))
      (dotimes (mask 8)
        (push (clqr::format-information ecl mask) values)))
    (is (= 32 (length (remove-duplicates values))))))

(test version-information-values
  "Version information strings (ISO Table D.1)."
  (is (null (clqr::version-information 1)))
  (is (null (clqr::version-information 6)))
  (is (= #x07C94 (clqr::version-information 7)))
  ;; All 34 version strings (7..40) are distinct.
  (let ((values (loop for v from 7 to 40 collect (clqr::version-information v))))
    (is (= 34 (length (remove-duplicates values))))))

(test geometry
  (is (= 21 (clqr::module-count 1)))
  (is (= 25 (clqr::module-count 2)))
  (is (= 177 (clqr::module-count 40))))

(test ec-block-totals
  "A few well-known total codeword counts."
  (is (= 26 (+ (clqr::total-data-codewords 1 :l) 7)))    ; v1-L: 19 data + 7 EC
  (is (= 19 (clqr::total-data-codewords 1 :l)))
  (is (= 16 (clqr::total-data-codewords 1 :m)))
  (is (= 9  (clqr::total-data-codewords 1 :h))))

(test encode-basic-properties
  (let ((qr (clqr:encode "01234567" :error-correction :m)))
    (is (clqr:qr-code-p qr))
    (is (= 1 (clqr:qr-version qr)))
    (is (= 21 (clqr:qr-size qr)))
    (is (eq :m (clqr:qr-error-correction qr)))
    (is (typep (clqr:qr-mask qr) '(integer 0 7)))))

(test automatic-mode-selection
  (is (equal '(:numeric) (clqr:qr-mode (clqr:encode "12345"))))
  (is (equal '(:alphanumeric) (clqr:qr-mode (clqr:encode "HELLO WORLD"))))
  (is (equal '(:byte) (clqr:qr-mode (clqr:encode "Hello, world!")))))

(test kanji-auto-detected
  "All-Kanji content auto-selects the compact Kanji mode instead of byte."
  (is (equal '(:kanji) (clqr:qr-mode (clqr:encode "日本語")))))

(test optimal-mixed-mode-segmentation
  "A digit run inside otherwise-byte content becomes its own numeric segment."
  (let ((modes (clqr:qr-mode (clqr:encode "Contact: 0123456789012345"))))
    (is (member :numeric modes))
    (is (member :byte modes))))

(test optimal-never-worse-than-single-mode
  "Optimal segmentation never needs a larger version than forcing byte mode."
  (dolist (s '("ABC123" "HELLO 12345 WORLD" "mixed Text 999 and MORE" "日本語ABC123"))
    (is (<= (clqr:qr-version (clqr:encode s))
            (clqr:qr-version (clqr:encode s :mode :byte))))))

(test kanji-eci-regime
  "Kanji mode and a UTF-8 byte ECI are never mixed: a non-Kanji character above
Latin-1 forces UTF-8 bytes under ECI (no Kanji); Kanji + ASCII stays Kanji."
  (flet ((modes-of (content)
           (mapcar #'clqr::segment-mode
                   (values (clqr::plan-encoding content nil nil :m nil)))))
    (let ((m (modes-of "本€")))          ; € is not JIS X 0208
      (is (eq :eci (first m)))
      (is (member :byte m))
      (is (not (member :kanji m))))
    (let ((m (modes-of "本A")))
      (is (not (member :eci m)))
      (is (member :kanji m)))))

(test version-grows-with-content
  (let ((small (clqr:encode "1" :error-correction :l))
        (large (clqr:encode (make-string 200 :initial-element #\A)
                            :error-correction :h)))
    (is (< (clqr:qr-version small) (clqr:qr-version large)))))

(test data-too-long-signals
  (signals clqr:data-too-long
    (clqr:encode (make-string 100 :initial-element #\a)
                 :error-correction :h :version 1)))

(test invalid-argument-conditions
  "Bad arguments signal specific, message-carrying conditions."
  (signals clqr:invalid-error-correction (clqr:encode "x" :error-correction :bogus))
  (signals clqr:invalid-mask (clqr:encode "x" :mask 9))
  (signals clqr:invalid-mask (clqr:encode "x" :mask :nope))
  (signals clqr:invalid-version (clqr:encode "x" :version 99))
  ;; The reports are real strings, not unbound-slot crashes.
  (handler-case (clqr:encode "x" :error-correction :bogus)
    (clqr:invalid-error-correction (e) (is (stringp (princ-to-string e))))))

(test auto-eci-for-utf8-byte-content
  "UTF-8 byte content gets an automatic ECI 26 header; Latin-1 and explicit
cases behave as expected."
  (flet ((segs (content &key mode eci)
           (values (clqr::plan-encoding content mode eci :m nil))))
    ;; Latin-1 (é = U+00E9 fits one byte): no ECI.
    (is (notany (lambda (s) (eq (clqr::segment-mode s) :eci)) (segs "café")))
    ;; UTF-8 (€ = U+20AC): ECI 26 prefixed.
    (let ((s (segs "€uro")))
      (is (eq :eci (clqr::segment-mode (first s))))
      (is (= 26 (clqr::segment-data (first s)))))
    ;; An explicit ECI wins and is not duplicated.
    (let ((s (segs "€uro" :eci 9)))
      (is (= 9 (clqr::segment-data (first s))))
      (is (= 1 (count :eci s :key #'clqr::segment-mode))))
    ;; Forced Kanji on CJK does not add a UTF-8 ECI.
    (is (notany (lambda (s) (eq (clqr::segment-mode s) :eci))
                (segs "日本" :mode :kanji)))))

(test data-too-long-report-is-clean
  "The DATA-TOO-LONG report never hits an unbound slot (its slots default to
NIL), so printing the condition works."
  (handler-case
      (progn (clqr:encode (make-string 100 :initial-element #\a)
                          :error-correction :h :version 1)
             (fail "expected data-too-long"))
    (clqr:data-too-long (e)
      (is (stringp (princ-to-string e))))))

;;; A golden full-symbol matrix for numeric "01234567" at version 1-M with a
;;; forced mask 0.  This exact matrix was cross-checked against an independent
;;; reference encoder and decoded by ZXing.
(defparameter +golden-01234567+
  '("111111100011101111111"
    "100000101110001000001"
    "101110100110001011101"
    "101110100101101011101"
    "101110101101101011101"
    "100000100001001000001"
    "111111101010101111111"
    "000000000000000000000"
    "101010100010100010010"
    "110100001011010100010"
    "000110111011011101110"
    "110011010101110110010"
    "001001110111011100001"
    "000000001010001000010"
    "111111100000100010001"
    "100000100010001001011"
    "101110101110101011101"
    "101110100101010101110"
    "101110101101011100101"
    "100000100001110111000"
    "111111101001011100101"))

;;; A version 5-Q golden.  v5-Q splits the data into two block groups of
;;; unequal length (2 x 15 + 2 x 16 codewords), so this exercises the
;;; column-wise data/EC interleaving with ragged blocks, plus the version 5
;;; alignment pattern.  Content is 40 digits; forced mask 0.
(defparameter +golden-v5q+
  '("1111111011000010000111001010001111111"
    "1000001011100010001111111100001000001"
    "1011101010000100000011001001001011101"
    "1011101011101100010010111100101011101"
    "1011101011100011010110101000101011101"
    "1000001000100011100111011100001000001"
    "1111111010101010101010101010101111111"
    "0000000010011010100101110110000000000"
    "0110101100011010110110101011101011111"
    "0000000010001100111010111011100100110"
    "0000001100010110001101011111111110010"
    "0011110010101011010100001010100100111"
    "0001111111011101110110010011101110110"
    "0000010110001100111010001101110100001"
    "0000001110001110001001000011101111001"
    "0111110010101111010010000110100101111"
    "0101111011000111110000001011001011001"
    "0010110101011001001010011011000011010"
    "1111011111100110100010111100010001101"
    "0010000100000011111101001001011010011"
    "1011001011110011111101011000010111100"
    "0110010100011001010010111001010101000"
    "1110011111100111111011011101010101101"
    "0011000100000011111100001001111101000"
    "1011101001011010100110010000010011101"
    "0101010110001101011011010101010011000"
    "1011111101001010111000100000001001101"
    "0100000101001101000111110111001011000"
    "1011101111010011101100101110111111101"
    "0000000010101011011111100010100010001"
    "1111111011001100111110111100101011011"
    "1000001001000001000011100001100011001"
    "1011101011010111001010110000111110000"
    "1011101001111110111110110100010101010"
    "1011101010101111111111000010111100101"
    "1000001011100101000010010111001111000"
    "1111111001100001101110000011000100101"))

;;; A version 7-H golden.  Version 7 is the first version carrying version
;;; information (18-bit strings in two corners) and has a 3x3 alignment grid;
;;; v7-H also spreads data over five EC blocks in two groups (4 x 13 + 1 x 14),
;;; so this covers version info, alignment placement and multi-block
;;; interleaving at once.  Content is 50 digits; forced mask 0.
(defparameter +golden-v7h+
  '("111111101010100100110111000011110000101111111"
    "100000100001001101010010001000110001001000001"
    "101110100011110100000011101000111001001011101"
    "101110101011010011110001100000010101101011101"
    "101110100001110100011111101100111011101011101"
    "100000100100010000111000111010010000001000001"
    "111111101010101010101010101010101010101111111"
    "000000000101100101111000101010110111000000000"
    "001011101011100001101111110000010000110001001"
    "010010011001011101101100000000111110101111010"
    "000010110110010111110010110000110110001101110"
    "111010000001000001100010111111000110100001011"
    "111011111001001001001101110001101111111011110"
    "010000001110001110101010100101000111010000000"
    "110010101110010000001111010101101001101011001"
    "001101000010110100010110110110110011010101100"
    "000001111000110111001111110110010000001101001"
    "011001010101101010011111000100111011110111101"
    "101000101001000011010111100000110011110101011"
    "010100010100101101000001000101011101110000010"
    "000111111000111010111111100111100111111111000"
    "111010001101010100001000111001011101100010110"
    "111110101011010011111010100001100110101010000"
    "010010001001010001101000100011010010100010110"
    "100111111000010000101111101101010001111110110"
    "001110011100100000100101010010011011100001010"
    "110101110110111111111100011000110010101111110"
    "010111011001100100010000000111100111100101011"
    "100001111110001101001101110010101101110111110"
    "001110010000100110111010101000100110111100100"
    "000111111111101000100010111110001011010100001"
    "110011011100110000110000100101110011010100100"
    "111110111001001000001001001100010110001110101"
    "011011011011000000010011010111011101000100010"
    "000010110101111100010001001110010010101111010"
    "011110011111010110010011111101110101100101011"
    "100110100101110111111111101101001111111110010"
    "000000001011001100011000100110010101100011011"
    "111111100110000100001010110111101111101010010"
    "100000101000100010001000100011101010100011000"
    "101110101100111110011111100010101001111111010"
    "101110100100010000000000111000100010010101010"
    "101110101110110000100101110101111011110101101"
    "100000100111010000111001110010000100010111000"
    "111111100010001101100100011000001110111101101"))

(defun check-golden (golden content ecl version)
  "Assert that encoding CONTENT at ECL/VERSION with forced mask 0 reproduces the
GOLDEN matrix (a list of \"01\" strings)."
  (let* ((qr (clqr:encode content :error-correction ecl :version version :mask 0))
         (size (clqr:qr-size qr)))
    (is (= (length golden) size))
    (is (= version (clqr:qr-version qr)))
    (is (= 0 (clqr:qr-mask qr)))
    (loop for row from 0 below size
          for line = (nth row golden)
          do (loop for col from 0 below size
                   do (is (eq (char= (char line col) #\1)
                              (clqr:qr-module qr row col))
                          "module (~D,~D) mismatch" row col)))))

(test golden-symbol-matrix
  "The full module matrix for the ISO example matches a verified golden."
  (check-golden +golden-01234567+ "01234567" :m 1))

(test golden-v5q-ragged-blocks
  "Version 5-Q (two block groups of unequal size) matches a verified golden."
  (check-golden +golden-v5q+
                "1234567890123456789012345678901234567890" :q 5))

(test golden-v7h-version-info-and-blocks
  "Version 7-H (version information, 3x3 alignment grid, five EC blocks) matches
a verified golden."
  (check-golden +golden-v7h+
                "12345678901234567890123456789012345678901234567890" :h 7))

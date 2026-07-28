;;;; micro-tests.lisp --- Micro QR (M1-M4) tests.

(in-package #:clqr.test)

(in-suite clqr-suite)

;;; Golden Micro QR matrices, each cross-checked against the segno reference
;;; encoder and decoded by ZXing.

(defparameter +golden-m1+
  '("11111110101" "10000010100" "10111010011" "10111010101" "10111010010"
    "10000010010" "11111110000" "00000000111" "11000100011" "01101011100"
    "10110000010"))

(defparameter +golden-m3l+
  '("111111101010101" "100000100001010" "101110100110110" "101110100000001"
    "101110101111111" "100000101000101" "111111101111010" "000000001110001"
    "111101100011101" "001101110010101" "101000011000000" "010111010001100"
    "111011000101111" "010101000101011" "111111010011101"))

(defparameter +golden-m4q+
  '("11111110101010101" "10000010001110011" "10111010111110000" "10111010000101001"
    "10111010110111100" "10000010110110001" "11111110111100010" "00000000011001100"
    "10111011100000010" "00110101110101010" "10010100000100111" "01011010001011101"
    "10010000010101111" "01100010001001100" "11101011011110101" "01001100001000110"
    "11001010001011100"))

(defun check-micro-golden (golden content ecl version mask mode)
  (let* ((qr (clqr:encode-micro content :error-correction ecl :version version
                                        :mask mask :mode mode))
         (size (clqr:qr-size qr)))
    (is (clqr:qr-micro-p qr))
    (is (= (length golden) size))
    (is (= version (clqr:qr-version qr)))
    (loop for row from 0 below size
          for line = (nth row golden)
          do (loop for col from 0 below size
                   do (is (eq (char= (char line col) #\1) (clqr:qr-module qr row col))
                          "module (~D,~D) mismatch" row col)))))

(test micro-golden-m1
  "M1 (11x11, 4-bit final codeword) matches a verified golden."
  (check-micro-golden +golden-m1+ "1234" :l 1 0 :numeric))

(test micro-golden-m3l
  "M3-L (15x15, alphanumeric, 4-bit final codeword) matches a verified golden."
  (check-micro-golden +golden-m3l+ "ABCDEF123456" :l 3 0 :alphanumeric))

(test micro-golden-m4q
  "M4-Q (17x17, highest Micro EC level) matches a verified golden."
  (check-micro-golden +golden-m4q+ "999999" :q 4 3 :numeric))

(test micro-basic-properties
  (let ((qr (clqr:encode-micro "01234567")))
    (is (clqr:qr-micro-p qr))
    (is (typep (clqr:qr-version qr) '(integer 1 4)))
    (is (= (clqr:qr-size qr) (+ 9 (* 2 (clqr:qr-version qr)))))
    (is (typep (clqr:qr-mask qr) '(integer 0 3)))))

(test micro-sizes
  (is (= 11 (clqr::micro-module-count 1)))
  (is (= 13 (clqr::micro-module-count 2)))
  (is (= 15 (clqr::micro-module-count 3)))
  (is (= 17 (clqr::micro-module-count 4))))

(test micro-version-selection
  ;; Small numeric fits M1; longer text needs a larger version.
  (is (= 1 (clqr:qr-version (clqr:encode-micro "123" :mode :numeric))))
  (is (<= (clqr:qr-version (clqr:encode-micro "1" :mode :numeric))
          (clqr:qr-version (clqr:encode-micro "HELLO WORLD" :mode :alphanumeric)))))

(test micro-mode-and-ec-restrictions
  ;; M1 supports only numeric and only error level :l.
  (signals clqr:clqr-error (clqr:encode-micro "AB" :version 1 :mode :alphanumeric))
  (signals clqr:invalid-error-correction (clqr:encode-micro "12" :version 1 :error-correction :m))
  ;; Byte mode needs at least M3.
  (signals clqr:clqr-error (clqr:encode-micro "hi" :version 2 :mode :byte))
  ;; Micro QR has no :h level.
  (signals clqr:clqr-error (clqr:encode-micro "1" :version 4 :error-correction :h)))

(test micro-forced-and-auto-modes
  "Forced Byte/Kanji modes and automatic mode selection for Micro QR."
  (is (equal '(:byte) (clqr:qr-mode (clqr:encode-micro "Hi" :version 3 :mode :byte))))
  (is (equal '(:kanji) (clqr:qr-mode (clqr:encode-micro "日本" :version 4 :mode :kanji))))
  (is (equal '(:numeric) (clqr:qr-mode (clqr:encode-micro "123"))))
  (is (equal '(:alphanumeric) (clqr:qr-mode (clqr:encode-micro "ABC"))))
  (is (equal '(:byte) (clqr:qr-mode (clqr:encode-micro "hello!")))))

(test micro-invalid-arguments
  (signals clqr:invalid-version (clqr:encode-micro "1" :version 5))
  (signals clqr:invalid-mask (clqr:encode-micro "1" :mask 5))
  (signals clqr:invalid-error-correction (clqr:encode-micro "1" :error-correction :h))
  (signals clqr:data-too-long
    (clqr:encode-micro (make-string 100 :initial-element #\1) :mode :numeric))
  ;; audit findings: mode / content type get typed clqr conditions, not raw errors.
  (signals clqr:invalid-mode (clqr:encode-micro "123" :mode :foo))
  (signals clqr:clqr-error (clqr:encode-micro 12345)))

(test micro-format-information-matches-table
  "A couple of Micro format-info values (ISO Table C.2 / segno FORMAT_INFO_MICRO)."
  (is (= 17477 (clqr::micro-format-information 0 0)))   ; #x4445
  (is (= 21934 (clqr::micro-format-information 1 0)))
  (is (=  5941 (clqr::micro-format-information 5 0))))

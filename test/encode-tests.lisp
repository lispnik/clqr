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

(test version-grows-with-content
  (let ((small (clqr:encode "1" :error-correction :l))
        (large (clqr:encode (make-string 200 :initial-element #\A)
                            :error-correction :h)))
    (is (< (clqr:qr-version small) (clqr:qr-version large)))))

(test data-too-long-signals
  (signals clqr:data-too-long
    (clqr:encode (make-string 100 :initial-element #\a)
                 :error-correction :h :version 1)))

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

(test golden-symbol-matrix
  "The full module matrix for the ISO example matches a verified golden."
  (let* ((qr (clqr:encode "01234567" :error-correction :m :mask 0))
         (size (clqr:qr-size qr)))
    (is (= 21 size))
    (is (= 0 (clqr:qr-mask qr)))
    (loop for row from 0 below size
          for golden = (nth row +golden-01234567+)
          do (loop for col from 0 below size
                   do (is (eq (char= (char golden col) #\1)
                              (clqr:qr-module qr row col))
                          "module (~D,~D) mismatch" row col)))))

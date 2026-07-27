;;;; galois-tests.lisp --- GF(256) and Reed-Solomon tests.

(in-package #:clqr.test)

(in-suite clqr-suite)

(test gf-log-antilog-roundtrip
  "The log and antilog tables are inverses over 1..255."
  (loop for x from 1 to 255
        do (is (= x (aref clqr::+gf-exp+ (aref clqr::+gf-log+ x)))
               "gf-exp(gf-log(~D)) should be ~D" x x)))

(test gf-mul-identities
  "Multiplication by 0 and 1 behaves as expected."
  (is (= 0 (clqr::gf-mul 0 123)))
  (is (= 0 (clqr::gf-mul 45 0)))
  (is (= 123 (clqr::gf-mul 1 123)))
  (is (= 45 (clqr::gf-mul 45 1)))
  ;; alpha * alpha = alpha^2 = 4 (primitive element 2)
  (is (= 4 (clqr::gf-mul 2 2))))

(test rs-generator-is-monic
  "Generator polynomials are monic with degree+1 coefficients."
  (dolist (deg '(7 10 13 22 30))
    (let ((g (clqr::rs-generator-polynomial deg)))
      (is (= (1+ deg) (length g)))
      (is (= 1 (aref g 0)) "generator of degree ~D should be monic" deg))))

(test rs-encode-iso-annex-example
  "Reed-Solomon EC codewords for the ISO/IEC 18004 Annex I worked example
(numeric \"01234567\", version 1-M)."
  (let* ((data #(16 32 12 86 97 128 236 17 236 17 236 17 236 17 236 17))
         (ec (clqr::rs-encode data 10)))
    (is (equalp #(165 36 212 193 237 54 199 135 44 85) ec))))

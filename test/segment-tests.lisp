;;;; segment-tests.lisp --- Segment encoding and table tests.

(in-package #:clqr.test)

(in-suite clqr-suite)

(test alphanumeric-values
  (is (= 0 (clqr::alphanumeric-value #\0)))
  (is (= 10 (clqr::alphanumeric-value #\A)))
  (is (= 44 (clqr::alphanumeric-value #\:)))
  (is (= 36 (clqr::alphanumeric-value #\Space)))
  (is (null (clqr::alphanumeric-value #\a))))

(test char-count-indicator-widths
  "ISO Table 3 character count indicator widths."
  (is (= 10 (clqr::char-count-bits :numeric 1)))
  (is (= 12 (clqr::char-count-bits :numeric 10)))
  (is (= 14 (clqr::char-count-bits :numeric 27)))
  (is (= 9  (clqr::char-count-bits :alphanumeric 9)))
  (is (= 11 (clqr::char-count-bits :alphanumeric 26)))
  (is (= 8  (clqr::char-count-bits :byte 9)))
  (is (= 16 (clqr::char-count-bits :byte 10)))
  (is (= 8  (clqr::char-count-bits :kanji 9)))
  (is (= 12 (clqr::char-count-bits :kanji 40))))

(test segment-data-bit-lengths
  (is (= 17 (clqr::segment-data-bits (clqr:make-numeric-segment "12345"))))
  (is (= 10 (clqr::segment-data-bits (clqr:make-numeric-segment "123"))))
  (is (= 4  (clqr::segment-data-bits (clqr:make-numeric-segment "1"))))
  (is (= 11 (clqr::segment-data-bits (clqr:make-alphanumeric-segment "AB"))))
  (is (= 6  (clqr::segment-data-bits (clqr:make-alphanumeric-segment "A"))))
  (is (= 24 (clqr::segment-data-bits (clqr:make-byte-segment "abc")))))

(test segment-validation
  (signals clqr:invalid-mode (clqr:make-numeric-segment "12A"))
  (signals clqr:invalid-mode (clqr:make-alphanumeric-segment "ab")))

(test forced-numeric-on-bytes-signals-invalid-mode
  "Forcing :numeric on a byte sequence signals CLQR:INVALID-MODE, not a raw
type-error."
  (signals clqr:invalid-mode (clqr:make-numeric-segment #(48 49 50)))
  (signals clqr:invalid-mode (clqr:encode #(48 49 50) :mode :numeric)))

(test kanji-error-paths
  "A character outside JIS X 0208 signals INVALID-MODE, and an unavailable
mapping table signals SHIFT-JIS-UNAVAILABLE."
  ;; 🎉 (U+1F389) is not in JIS X 0208.
  (signals clqr:invalid-mode (clqr:make-kanji-segment "🎉"))
  ;; With an empty mapping table, string conversion cannot proceed.
  (let ((clqr::*unicode->shift-jis* (make-hash-table)))
    (signals clqr:shift-jis-unavailable (clqr::string-to-shift-jis "日"))))

(test string-to-bytes-encoding
  ;; ISO-8859-1 (one byte per character) while every character fits in a byte,
  ;; including Latin-1 characters such as é (U+00E9 = 233) ...
  (is (equalp #(65 66 67) (clqr::string-to-bytes "ABC")))
  (is (equalp #(233) (clqr::string-to-bytes "é")))
  ;; ... UTF-8 once any character needs more than one byte (€ = U+20AC).
  (is (equalp #(226 130 172) (clqr::string-to-bytes "€"))))

(test iso-annex-data-codewords
  "Data codewords for numeric \"01234567\" at version 1-M (ISO Annex I)."
  (let ((data (clqr::segments-to-data-codewords
               (list (clqr:make-numeric-segment "01234567")) 1 :m)))
    (is (equalp #(16 32 12 86 97 128 236 17 236 17 236 17 236 17 236 17)
                data))))

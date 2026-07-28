;;;; render-tests.lisp --- Renderer tests.

(in-package #:clqr.test)

(in-suite clqr-suite)

(defun render-to-string (fn qr &rest args)
  (with-output-to-string (s)
    (apply fn qr :stream s args)))

(test map-modules-visits-every-module
  (let* ((qr (clqr:encode "test"))
         (size (clqr:qr-size qr))
         (count 0))
    (clqr:map-modules qr (lambda (r c d) (declare (ignore r c d)) (incf count)))
    (is (= (* size size) count))))

(test render-text-line-count
  "Unicode text output packs two module rows per line, plus quiet zone."
  (let* ((qr (clqr:encode "01234567"))
         (qz 4)
         (dim (+ (clqr:qr-size qr) (* 2 qz)))
         (out (render-to-string #'clqr.render:render-text qr :quiet-zone qz))
         (lines (count #\Newline out)))
    (is (= (ceiling dim 2) lines))))

(test render-text-invert-no-phantom-row
  "Under :invert the out-of-grid phantom row stays light, so the final line is
made of upper-half blocks, never full blocks."
  (let* ((qr (clqr:encode "01234567"))
         (qz 4)
         (dim (+ (clqr:qr-size qr) (* 2 qz)))
         (out (render-to-string #'clqr.render:render-text qr
                                :quiet-zone qz :invert t))
         (lines (remove "" (uiop:split-string out :separator '(#\Newline))
                        :test #'string=)))
    (is (= (ceiling dim 2) (count #\Newline out)))
    (is (not (find #\FULL_BLOCK (car (last lines))))
        "final line must not contain a phantom full block")))

(test render-text-ascii-style
  "The :ascii style uses two characters per module and one text line per module
row (no half-block packing)."
  (let* ((qr (clqr:encode "01234567"))
         (qz 2)
         (dim (+ (clqr:qr-size qr) (* 2 qz)))
         (out (render-to-string #'clqr.render:render-text qr
                                :quiet-zone qz :style :ascii)))
    (is (= dim (count #\Newline out)))
    (is (search "##" out))
    (is (not (find #\FULL_BLOCK out)))))

(test render-svg-structure
  (let ((out (render-to-string #'clqr.render:render-svg (clqr:encode "svg test"))))
    (is (search "<svg" out))
    (is (search "<path" out))
    (is (search "</svg>" out))))

(test render-pbm-p1-header-and-size
  (let* ((qr (clqr:encode "01234567"))
         (qz 4) (ms 3)
         (px (* (+ (clqr:qr-size qr) (* 2 qz)) ms))
         (out (render-to-string #'clqr.render:render-pbm qr
                                :quiet-zone qz :module-size ms :format :p1)))
    (is (eql 0 (search "P1" out)))
    (is (search (format nil "~D ~D" px px) out))))

(test render-pbm-p4-binary-header
  "P4 output writes a valid raw binary PBM header and payload."
  (uiop:with-temporary-file (:stream s :pathname path :direction :output
                             :element-type '(unsigned-byte 8) :keep nil)
    (let ((qr (clqr:encode "01234567")))
      (clqr.render:render-pbm qr :stream s :quiet-zone 1 :module-size 1 :format :p4))
    (finish-output s)
    (with-open-file (in path :element-type '(unsigned-byte 8))
      (is (= (char-code #\P) (read-byte in)))
      (is (= (char-code #\4) (read-byte in)))
      ;; Header followed by at least one payload byte.
      (is (> (file-length in) 6)))))

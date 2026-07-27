;;;; text.lisp --- Terminal / text rendering of a QR code.

(in-package #:clqr.render)

(defun render-text (qr &key (stream *standard-output*) (quiet-zone 4)
                         (style :unicode) (invert nil))
  "Render QR as text to STREAM.

:quiet-zone  width of the light border in modules (default 4).
:style       :unicode (default) packs two module rows per line using half-block
             characters; :ascii uses two characters per module ('##' / '  ').
:invert      swap dark and light (useful for light-background terminals).

Returns QR."
  (let* ((size (qr-size qr))
         (dim (+ size (* 2 quiet-zone))))
    (flet ((dark (row col)
             ;; Positions outside the grid (the phantom row that pairs with the
             ;; final module row when DIM is odd) are always light, even under
             ;; INVERT, so the bottom border matches the top.
             (and (< row dim)
                  (let ((d (grid-dark-p qr quiet-zone row col)))
                    (if invert (not d) d)))))
      (ecase style
        (:ascii
         (dotimes (row dim)
           (dotimes (col dim)
             (write-string (if (dark row col) "##" "  ") stream))
           (terpri stream)))
        (:unicode
         (loop for row from 0 below dim by 2 do
           (dotimes (col dim)
             (let ((top (dark row col))
                   (bottom (dark (1+ row) col)))
               (write-char (cond ((and top bottom) #\FULL_BLOCK)
                                 (top #\UPPER_HALF_BLOCK)
                                 (bottom #\LOWER_HALF_BLOCK)
                                 (t #\Space))
                           stream)))
           (terpri stream))))))
  qr)

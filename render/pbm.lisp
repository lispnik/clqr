;;;; pbm.lisp --- Netpbm (PBM) rendering of a QR code.
;;;;
;;;; PBM images use 1 for black (a dark module) and 0 for white.  The plain P1
;;;; format is written to a character stream; the raw P4 format is written to a
;;;; binary stream (element-type (unsigned-byte 8)).

(in-package #:clqr.render)

(defun %pixel-dark (qr quiet-zone module-size x y)
  "Dark predicate for output pixel (X,Y) given MODULE-SIZE scaling."
  (grid-dark-p qr quiet-zone (floor y module-size) (floor x module-size)))

(defun render-pbm-p1 (qr stream quiet-zone module-size)
  (let* ((dim (+ (qr-size qr) (* 2 quiet-zone)))
         (px (* dim module-size)))
    (format stream "P1~%# clqr~%~D ~D~%" px px)
    (dotimes (y px)
      (dotimes (x px)
        (write-char (if (%pixel-dark qr quiet-zone module-size x y) #\1 #\0) stream)
        (write-char #\Space stream))
      (terpri stream)))
  qr)

(defun render-pbm-p4 (qr stream quiet-zone module-size)
  (let* ((dim (+ (qr-size qr) (* 2 quiet-zone)))
         (px (* dim module-size)))
    ;; Header, written as raw bytes so a single binary stream suffices.
    (loop for ch across (format nil "P4~%~D ~D~%" px px)
          do (write-byte (char-code ch) stream))
    (dotimes (y px)
      (let ((byte 0) (nbits 0))
        (dotimes (x px)
          (setf byte (logior (ash byte 1)
                             (if (%pixel-dark qr quiet-zone module-size x y) 1 0)))
          (incf nbits)
          (when (= nbits 8)
            (write-byte byte stream)
            (setf byte 0 nbits 0)))
        ;; Pad the final partial byte of the row.
        (when (plusp nbits)
          (write-byte (ash byte (- 8 nbits)) stream)))))
  qr)

(defun render-pbm (qr &key (stream *standard-output*) (quiet-zone 4)
                        (module-size 1) (format :p4))
  "Render QR as a netpbm PBM image to STREAM.

:quiet-zone   width of the light border in modules (default 4).
:module-size  side length of one module in pixels (default 1).
:format       :p4 (raw binary, needs a binary STREAM; the default) or
              :p1 (plain ASCII, needs a character STREAM).

Returns QR."
  (ecase format
    (:p1 (render-pbm-p1 qr stream quiet-zone module-size))
    (:p4 (render-pbm-p4 qr stream quiet-zone module-size))))

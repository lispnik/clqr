;;;; pbm.lisp --- Netpbm (PBM) rendering of a QR code.
;;;;
;;;; PBM images use 1 for black (a dark module) and 0 for white.  The plain P1
;;;; format is written to a character stream; the raw P4 format is written to a
;;;; binary stream (element-type (unsigned-byte 8)).

(in-package #:clqr.render)

(defun grid-bits (qr quiet-zone)
  "Sample the quiet-zone-padded grid once into a (simple-array bit (dim dim));
1 = dark.  This avoids repeating the module lookup for every scaled pixel."
  (let* ((dim (+ (qr-size qr) (* 2 quiet-zone)))
         (grid (make-array (list dim dim) :element-type 'bit)))
    (dotimes (r dim grid)
      (dotimes (c dim)
        (setf (aref grid r c) (if (grid-dark-p qr quiet-zone r c) 1 0))))))

(defun render-pbm-p1 (qr stream quiet-zone module-size)
  (let* ((grid (grid-bits qr quiet-zone))
         (dim (array-dimension grid 0))
         (px (* dim module-size)))
    (format stream "P1~%# clqr~%~D ~D~%" px px)
    (dotimes (my dim)
      (dotimes (rep module-size)
        (dotimes (mx dim)
          (let ((ch (if (= 1 (aref grid my mx)) #\1 #\0)))
            (dotimes (cx module-size)
              (declare (ignore cx))
              (write-char ch stream)
              (write-char #\Space stream))))
        (terpri stream))))
  qr)

(defun render-pbm-p4 (qr stream quiet-zone module-size)
  (let* ((grid (grid-bits qr quiet-zone))
         (dim (array-dimension grid 0))
         (px (* dim module-size)))
    ;; Header, written as raw bytes so a single binary stream suffices.
    (loop for ch across (format nil "P4~%~D ~D~%" px px)
          do (write-byte (char-code ch) stream))
    (dotimes (my dim)
      (dotimes (rep module-size)
        (declare (ignore rep))
        (let ((byte 0) (nbits 0))
          (dotimes (mx dim)
            (let ((bit (aref grid my mx)))
              (dotimes (cx module-size)
                (declare (ignore cx))
                (setf byte (logior (ash byte 1) bit))
                (incf nbits)
                (when (= nbits 8)
                  (write-byte byte stream)
                  (setf byte 0 nbits 0)))))
          ;; Pad the final partial byte of the row.
          (when (plusp nbits)
            (write-byte (ash byte (- 8 nbits)) stream))))))
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

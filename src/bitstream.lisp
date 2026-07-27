;;;; bitstream.lisp --- A growable MSB-first bit buffer.
;;;;
;;;; The encoder accumulates the data bit stream (mode indicators, character
;;;; counts and encoded data) into a BIT-STREAM before it is padded to the
;;;; version's capacity and split into codewords.

(in-package #:clqr)

(defstruct (bit-stream (:constructor %make-bit-stream))
  "A growable most-significant-bit-first buffer of bits."
  (bits (make-array 256 :element-type 'bit :adjustable t :fill-pointer 0)
        :type (array bit (*))))

(defun make-bit-stream ()
  (%make-bit-stream))

(declaim (inline bit-stream-length))
(defun bit-stream-length (stream)
  "Number of bits currently in STREAM."
  (fill-pointer (bit-stream-bits stream)))

(defun write-bits (stream value width)
  "Append the low WIDTH bits of the non-negative integer VALUE to STREAM,
most significant bit first."
  (declare (type (integer 0) value)
           (type (integer 0) width))
  (let ((bits (bit-stream-bits stream)))
    (loop for i from (1- width) downto 0
          do (vector-push-extend (ldb (byte 1 i) value) bits)))
  stream)

(defun write-bit (stream bit)
  (vector-push-extend bit (bit-stream-bits stream))
  stream)

(defun bit-stream-to-codewords (stream)
  "Return the contents of STREAM as a vector of (unsigned-byte 8) codewords.
STREAM must already be a whole number of bytes long."
  (let* ((bits (bit-stream-bits stream))
         (len (fill-pointer bits)))
    (assert (zerop (mod len 8)) ()
            "Bit stream length ~D is not a multiple of 8." len)
    (let ((bytes (make-array (floor len 8) :element-type '(unsigned-byte 8))))
      (dotimes (i (length bytes) bytes)
        (let ((byte 0))
          (dotimes (b 8)
            (setf byte (logior (ash byte 1) (aref bits (+ (* i 8) b)))))
          (setf (aref bytes i) byte))))))

(defparameter +pad-bytes+ #(#xEC #x11)
  "The two alternating pad bytes appended to fill a symbol (ISO 8.4.9).")

(defun pad-to-capacity (stream data-codewords)
  "Add the terminator, byte-align, and append alternating pad bytes so that
STREAM holds exactly DATA-CODEWORDS codewords.  STREAM must not already exceed
the capacity."
  (let ((capacity-bits (* 8 data-codewords)))
    (assert (<= (bit-stream-length stream) capacity-bits) ()
            'data-too-long :content-bits (bit-stream-length stream))
    ;; Terminator: up to four 0 bits, but never past capacity.
    (let ((terminator (min 4 (- capacity-bits (bit-stream-length stream)))))
      (dotimes (i terminator) (write-bit stream 0)))
    ;; Pad with 0 bits to the next byte boundary.
    (loop until (zerop (mod (bit-stream-length stream) 8))
          do (write-bit stream 0))
    ;; Append alternating pad bytes until full.
    (loop for i from 0
          while (< (bit-stream-length stream) capacity-bits)
          do (write-bits stream (aref +pad-bytes+ (mod i 2)) 8))
    stream))

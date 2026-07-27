;;;; reed-solomon.lisp --- Block splitting, EC generation and interleaving.
;;;;
;;;; ISO/IEC 18004 8.5-8.6: the data codewords are divided into blocks, each
;;;; block gets its own Reed-Solomon error correction codewords, and the data
;;;; and error correction codewords are then interleaved to form the final
;;;; message sequence that is placed in the symbol.

(in-package #:clqr)

(defun split-into-blocks (data-codewords version ecl)
  "Divide DATA-CODEWORDS into the data blocks required for VERSION at ECL.
Returns a list of (unsigned-byte 8) vectors."
  (multiple-value-bind (ec g1b g1d g2b g2d) (ec-block-spec version ecl)
    (declare (ignore ec))
    (let ((blocks '())
          (i 0))
      (flet ((take (count size)
               (dotimes (b count)
                 (push (subseq data-codewords i (+ i size)) blocks)
                 (incf i size))))
        (take g1b g1d)
        (take g2b g2d))
      (nreverse blocks))))

(defun make-final-message (data-codewords version ecl)
  "Compute error correction codewords for each block of DATA-CODEWORDS and
interleave data and EC codewords into the final message sequence for VERSION
at ECL.  Returns a vector of (unsigned-byte 8)."
  (multiple-value-bind (ec-per-block) (ec-block-spec version ecl)
    (let* ((data-blocks (split-into-blocks data-codewords version ecl))
           (ec-blocks (mapcar (lambda (blk) (rs-encode blk ec-per-block))
                              data-blocks))
           (max-data (reduce #'max data-blocks :key #'length))
           (result (make-array 0 :element-type '(unsigned-byte 8)
                                 :adjustable t :fill-pointer 0)))
      ;; Interleave data codewords column by column.
      (dotimes (c max-data)
        (dolist (blk data-blocks)
          (when (< c (length blk))
            (vector-push-extend (aref blk c) result))))
      ;; Interleave EC codewords column by column (every block has the same
      ;; number of EC codewords).
      (dotimes (c ec-per-block)
        (dolist (blk ec-blocks)
          (vector-push-extend (aref blk c) result)))
      (coerce result '(simple-array (unsigned-byte 8) (*))))))

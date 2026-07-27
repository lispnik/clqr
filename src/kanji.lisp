;;;; kanji.lisp --- Unicode <-> Shift-JIS conversion for QR Kanji mode.
;;;;
;;;; QR Kanji mode (ISO/IEC 18004 8.4.5) encodes characters that exist in the
;;;; JIS X 0208 set, addressed by their Shift-JIS double-byte value.  This file
;;;; loads a bundled mapping (data/jis0208.txt, generated once from a trusted
;;;; codec) into a hash table at load time, so the table is baked into any
;;;; dumped executable image.  Callers that already hold Shift-JIS values can
;;;; bypass conversion entirely via MAKE-KANJI-SEGMENT with a numeric vector.

(in-package #:clqr)

(defparameter *unicode->shift-jis* (make-hash-table :size 8192)
  "Maps a Unicode code point to its Shift-JIS double-byte value.")

(defun %jis-data-file ()
  "Locate the bundled Shift-JIS mapping file."
  (ignore-errors
   (let ((system (asdf:find-system "clqr" nil)))
     (when system
       (asdf:system-relative-pathname system "data/jis0208.txt")))))

(defun load-shift-jis-table (&optional (pathname (%jis-data-file)))
  "Populate *UNICODE->SHIFT-JIS* from the mapping file at PATHNAME.  Returns the
number of entries loaded, or NIL if the file could not be read."
  (when (and pathname (probe-file pathname))
    (clrhash *unicode->shift-jis*)
    (with-open-file (in pathname :direction :input :external-format :utf-8)
      (loop for line = (read-line in nil nil)
            while line
            unless (or (zerop (length line)) (char= (char line 0) #\#))
              do (let* ((space (position #\Space line))
                        (sjis (parse-integer line :end space :radix 16))
                        (cp (parse-integer line :start (1+ space) :radix 16)))
                   (setf (gethash cp *unicode->shift-jis*) sjis))))
    (hash-table-count *unicode->shift-jis*)))

;;; Populate the table when this file loads.  For a dumped image this runs at
;;; build time and the populated table is saved into the image.
(load-shift-jis-table)

(defun shift-jis-value (char)
  "Return the Shift-JIS double-byte value for CHAR, or NIL if it is not in the
JIS X 0208 set."
  (gethash (char-code char) *unicode->shift-jis*))

(defun string-to-shift-jis (string)
  "Convert STRING to a vector of Shift-JIS double-byte values.  Signals an
error if any character is not representable in JIS X 0208 (or if the mapping
table is unavailable)."
  (when (zerop (hash-table-count *unicode->shift-jis*))
    (error 'clqr-error))
  (map '(simple-array (unsigned-byte 16) (*))
       (lambda (ch)
         (or (shift-jis-value ch)
             (error 'invalid-mode
                    :datum (format nil "character ~S is not encodable in Kanji mode" ch))))
       string))

(defun kanji-encodable-p (string)
  "True if every character of STRING can be encoded in Kanji mode."
  (and (plusp (length string))
       (every #'shift-jis-value string)))

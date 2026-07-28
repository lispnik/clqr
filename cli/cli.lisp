;;;; cli.lisp --- The `clqr` command line driver.
;;;;
;;;; Exposes the full ENCODE + render API surface as a single command.  The
;;;; content to encode is given as a positional argument (or read from standard
;;;; input when it is "-" or omitted); options mirror the keyword arguments of
;;;; CLQR:ENCODE and the renderers in CLQR.RENDER.

(in-package #:clqr.cli)

(defparameter +version+ "0.2.0")

;;; ---------------------------------------------------------------------------
;;; Option parsing helpers
;;; ---------------------------------------------------------------------------

(defun parse-auto-integer (value what lo hi)
  "Parse VALUE (a string) as \"auto\" -> NIL or an integer in [LO,HI]."
  (cond ((or (null value) (string-equal value "auto")) nil)
        (t (let ((n (ignore-errors (parse-integer value :junk-allowed nil))))
             (unless (and n (<= lo n hi))
               (error "Invalid ~A: ~S (expected \"auto\" or ~D-~D)." what value lo hi))
             n))))

(defun read-stream-content (stream)
  "Read all remaining characters of STREAM into a string, verbatim -- newlines
(including a trailing one) are preserved exactly, so piped content is encoded
byte-for-byte."
  (let ((out (make-string-output-stream)))
    (loop for ch = (read-char stream nil :eof)
          until (eq ch :eof)
          do (write-char ch out))
    (get-output-stream-string out)))

;;; ---------------------------------------------------------------------------
;;; Options
;;; ---------------------------------------------------------------------------

(defun options ()
  (list
   (clingon:make-option
    :enum :description "error correction level"
    :short-name #\e :long-name "error-correction" :initial-value "m"
    :items '(("l" . :l) ("m" . :m) ("q" . :q) ("h" . :h))
    :key :error-correction)
   (clingon:make-option
    :string :description "symbol version: \"auto\" or 1-40"
    :short-name #\V :long-name "qr-version" :initial-value "auto"
    :key :qr-version)
   (clingon:make-option
    :string :description "data mask: \"auto\" or 0-7"
    :short-name #\m :long-name "mask" :initial-value "auto"
    :key :mask)
   (clingon:make-option
    :enum :description "encoding mode"
    :short-name #\M :long-name "mode" :initial-value "auto"
    :items '(("auto" . :auto) ("numeric" . :numeric) ("alphanumeric" . :alphanumeric)
             ("byte" . :byte) ("kanji" . :kanji))
    :key :mode)
   (clingon:make-option
    :integer :description "prefix an ECI assignment number"
    :long-name "eci" :key :eci)
   (clingon:make-option
    :string :description "FNC1 header: \"gs1\" or \"aim:N\""
    :long-name "fnc1" :key :fnc1)
   (clingon:make-option
    :integer :description "emit a Structured Append sequence of N symbols (2-16)"
    :long-name "structured-append" :key :structured-append)
   (clingon:make-option
    :flag :description "encode a Micro QR symbol (M1-M4)"
    :long-name "micro" :key :micro)
   (clingon:make-option
    :enum :description "output format"
    :short-name #\f :long-name "format" :initial-value "text"
    :items '(("text" . :text) ("svg" . :svg) ("pbm" . :pbm))
    :key :format)
   (clingon:make-option
    :string :description "output file (default: standard output)"
    :short-name #\o :long-name "output" :key :output)
   (clingon:make-option
    :integer :description "quiet zone width in modules"
    :short-name #\b :long-name "quiet-zone" :initial-value 4 :key :quiet-zone)
   (clingon:make-option
    :integer :description "module size in pixels/units (svg, pbm)"
    :short-name #\s :long-name "module-size" :key :module-size)
   (clingon:make-option
    :string :description "svg foreground colour"
    :long-name "fg" :initial-value "#000000" :key :fg)
   (clingon:make-option
    :string :description "svg background colour (or \"none\")"
    :long-name "bg" :initial-value "#ffffff" :key :bg)
   (clingon:make-option
    :string :description "svg accessible title (<title> element)"
    :long-name "title" :key :title)
   (clingon:make-option
    :flag :description "text: use ASCII instead of Unicode blocks"
    :long-name "ascii" :key :ascii)
   (clingon:make-option
    :flag :description "text: swap dark/light (for light-background terminals)"
    :long-name "invert" :key :invert)
   (clingon:make-option
    :enum :description "pbm sub-format"
    :long-name "pbm-format" :initial-value "p4"
    :items '(("p4" . :p4) ("p1" . :p1)) :key :pbm-format)))

;;; ---------------------------------------------------------------------------
;;; Output stream handling
;;; ---------------------------------------------------------------------------

(defun binary-output-p (format pbm-format)
  "True when the chosen output is raw bytes (PBM P4)."
  (and (eq format :pbm) (eq pbm-format :p4)))

(defmacro with-output-stream ((var output binary) &body body)
  "Bind VAR to an output stream for OUTPUT (a filename or NIL for stdout),
character or binary per BINARY."
  (let ((out (gensym)) (bin (gensym)))
    `(let ((,out ,output) (,bin ,binary))
       (flet ((body (,var) ,@body))
         (if ,out
             (with-open-file (s ,out :direction :output :if-exists :supersede
                                     :if-does-not-exist :create
                                     :element-type (if ,bin '(unsigned-byte 8) 'character))
               (body s))
             (if ,bin
                 (let ((s (stdout-binary-stream)))
                   (body s)
                   (finish-output s))
                 (body *standard-output*)))))))

(defun stdout-binary-stream ()
  "A binary stream writing to standard output (SBCL)."
  #+sbcl (sb-sys:make-fd-stream 1 :output t :element-type '(unsigned-byte 8)
                                  :buffering :full)
  #-sbcl (error "Binary output to standard output requires a file (-o)."))

;;; ---------------------------------------------------------------------------
;;; Handler
;;; ---------------------------------------------------------------------------

(defun parse-fnc1 (value)
  "Parse the --fnc1 option: \"gs1\" or \"aim:N\" (or NIL)."
  (cond ((or (null value) (string= value "")) nil)
        ((string-equal value "gs1") :gs1)
        ((and (>= (length value) 4) (string-equal (subseq value 0 4) "aim:"))
         (list :aim (parse-integer value :start 4)))
        (t (error "Invalid --fnc1: ~S (expected \"gs1\" or \"aim:N\")." value))))

(defun indexed-path (path index)
  "Insert -INDEX before PATH's extension (foo.svg -> foo-3.svg).  A dot inside a
parent directory (foo.d/qr) is not treated as an extension."
  (let* ((slash (position #\/ path :from-end t))
         (dot (position #\. path :from-end t :start (if slash (1+ slash) 0))))
    (if dot
        (format nil "~A-~D~A" (subseq path 0 dot) index (subseq path dot))
        (format nil "~A-~D" path index))))

(defun render-symbol (cmd qr stream)
  "Render QR to STREAM in the requested format using CMD's options."
  (let ((quiet-zone (clingon:getopt cmd :quiet-zone))
        (module-size (clingon:getopt cmd :module-size))
        (bg (clingon:getopt cmd :bg)))
    (ecase (clingon:getopt cmd :format)
      (:text (clqr.render:render-text
              qr :stream stream :quiet-zone quiet-zone
              :style (if (clingon:getopt cmd :ascii) :ascii :unicode)
              :invert (clingon:getopt cmd :invert)))
      (:svg (clqr.render:render-svg
             qr :stream stream :quiet-zone quiet-zone
             :module-size (or module-size 8)
             :foreground (clingon:getopt cmd :fg)
             :background (if (string-equal bg "none") nil bg)
             :title (clingon:getopt cmd :title)))
      (:pbm (clqr.render:render-pbm
             qr :stream stream :quiet-zone quiet-zone
             :module-size (or module-size 8)
             :format (clingon:getopt cmd :pbm-format))))))

(defun summarise (qr &optional index count)
  (format *error-output* "clqr: ~Aversion ~:[~;M~]~D, EC ~A, mask ~D, ~D modules~%"
          (if index (format nil "[~D/~D] " index count) "")
          (clqr:qr-micro-p qr) (clqr:qr-version qr) (clqr:qr-error-correction qr)
          (clqr:qr-mask qr) (clqr:qr-size qr)))

(defun run-encode (cmd)
  (let* ((args (clingon:command-arguments cmd))
         (content-arg (first args))
         (content (if (or (null content-arg) (string= content-arg "-"))
                      (read-stream-content *standard-input*)
                      content-arg))
         (ecl (clingon:getopt cmd :error-correction))
         (micro (clingon:getopt cmd :micro))
         (version (parse-auto-integer (clingon:getopt cmd :qr-version) "version"
                                      1 (if micro 4 40)))
         (mask (parse-auto-integer (clingon:getopt cmd :mask) "mask" 0 (if micro 3 7)))
         (mode-opt (clingon:getopt cmd :mode))
         (mode (unless (eq mode-opt :auto) mode-opt))
         (eci (clingon:getopt cmd :eci))
         (fnc1 (parse-fnc1 (clingon:getopt cmd :fnc1)))
         (format (clingon:getopt cmd :format))
         (output (clingon:getopt cmd :output))
         (binary (binary-output-p format (clingon:getopt cmd :pbm-format)))
         (sa (clingon:getopt cmd :structured-append)))
    (when (and sa (not (<= 2 sa 16)))
      (error "--structured-append must be between 2 and 16."))
    (when (and micro (or eci fnc1 sa))
      (error "Micro QR does not support ECI, FNC1 or Structured Append."))
    (cond
      (micro
       (let ((qr (clqr:encode-micro content :error-correction ecl :version version
                                            :mask mask :mode mode)))
         (with-output-stream (stream output binary)
           (render-symbol cmd qr stream))
         (summarise qr)))
      ((and sa (>= sa 2))
       ;; Structured Append: one symbol per piece.
       (when (and (null output) binary)
         (error "Structured Append with a binary PBM needs --output."))
       (let ((qrs (clqr:encode-structured-append
                   content :error-correction ecl :count sa :version version
                           :mask mask :mode mode :eci eci :fnc1 fnc1)))
         (loop for qr in qrs
               for i from 1
               do (let ((path (and output (indexed-path output i))))
                    (with-output-stream (stream path binary)
                      (when (and (null output) (not binary) (> i 1))
                        (terpri stream))
                      (render-symbol cmd qr stream))
                    (summarise qr i sa)))))
      (t
       (let ((qr (clqr:encode content :error-correction ecl :version version
                                      :mask mask :mode mode :eci eci :fnc1 fnc1)))
         (with-output-stream (stream output binary)
           (render-symbol cmd qr stream))
         (summarise qr))))))

(defun handler (cmd)
  "Top-level command handler with friendly error reporting."
  (handler-case (run-encode cmd)
    (clqr:clqr-error (e)
      (format *error-output* "clqr: ~A~%" e)
      (clingon:exit 1))
    (error (e)
      (format *error-output* "clqr: ~A~%" e)
      (clingon:exit 1))))

;;; ---------------------------------------------------------------------------
;;; Command and entry point
;;; ---------------------------------------------------------------------------

(defun command ()
  (clingon:make-command
   :name "clqr"
   :version +version+
   :description "Encode content into a QR code (ISO/IEC 18004)."
   :usage "[options] [CONTENT|-]"
   :authors '("Matthew Kennedy <burnsidemk@gmail.com>")
   :options (options)
   :handler #'handler
   :examples '(("Print a QR code to the terminal:"
                . "clqr \"HELLO WORLD\"")
               ("Write an SVG file at error correction level H:"
                . "clqr -e h -f svg -o hello.svg \"https://example.com\"")
               ("Encode numbers, forcing numeric mode and version 4:"
                . "clqr -M numeric -V 4 123456789")
               ("Read content from standard input as a PBM image:"
                . "echo -n hi | clqr -f pbm -o hi.pbm -")
               ("Encode a GS1 code with an FNC1 header:"
                . "clqr --fnc1 gs1 0112345678901231")
               ("Split a long message into 3 Structured Append SVGs:"
                . "clqr --structured-append 3 -f svg -o msg.svg \"…long text…\"")
               ("Encode a Micro QR symbol:"
                . "clqr --micro -f svg -o m.svg 01234567"))))

(defun main ()
  (clingon:run (command)))

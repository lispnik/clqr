;;;; cli.lisp --- The `clqr` command line driver.
;;;;
;;;; Exposes the full ENCODE + render API surface as a single command.  The
;;;; content to encode is given as a positional argument (or read from standard
;;;; input when it is "-" or omitted); options mirror the keyword arguments of
;;;; CLQR:ENCODE and the renderers in CLQR.RENDER.

(in-package #:clqr.cli)

(defparameter +version+ "0.1.0")

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
  "Read all remaining characters of STREAM into a string."
  (with-output-to-string (out)
    (loop for line = (read-line stream nil :eof)
          for first = t then nil
          until (eq line :eof)
          do (unless first (terpri out))
             (write-string line out))))

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

(defun run-encode (cmd)
  (let* ((args (clingon:command-arguments cmd))
         (content-arg (first args))
         (content (if (or (null content-arg) (string= content-arg "-"))
                      (read-stream-content *standard-input*)
                      content-arg))
         (ecl (clingon:getopt cmd :error-correction))
         (version (parse-auto-integer (clingon:getopt cmd :qr-version) "version" 1 40))
         (mask (parse-auto-integer (clingon:getopt cmd :mask) "mask" 0 7))
         (mode-opt (clingon:getopt cmd :mode))
         (mode (unless (eq mode-opt :auto) mode-opt))
         (eci (clingon:getopt cmd :eci))
         (format (clingon:getopt cmd :format))
         (output (clingon:getopt cmd :output))
         (quiet-zone (clingon:getopt cmd :quiet-zone))
         (module-size (clingon:getopt cmd :module-size))
         (pbm-format (clingon:getopt cmd :pbm-format))
         (bg (clingon:getopt cmd :bg)))
    (let ((qr (clqr:encode content :error-correction ecl :version version
                                   :mask mask :mode mode :eci eci)))
      (with-output-stream (stream output (binary-output-p format pbm-format))
        (ecase format
          (:text (clqr.render:render-text
                  qr :stream stream :quiet-zone quiet-zone
                  :style (if (clingon:getopt cmd :ascii) :ascii :unicode)
                  :invert (clingon:getopt cmd :invert)))
          (:svg (clqr.render:render-svg
                 qr :stream stream :quiet-zone quiet-zone
                 :module-size (or module-size 8)
                 :foreground (clingon:getopt cmd :fg)
                 :background (if (string-equal bg "none") nil bg)))
          (:pbm (clqr.render:render-pbm
                 qr :stream stream :quiet-zone quiet-zone
                 :module-size (or module-size 8) :format pbm-format))))
      ;; A short summary to stderr keeps stdout clean for piping.
      (format *error-output* "clqr: version ~D, EC ~A, mask ~D, ~D modules~%"
              (clqr:qr-version qr) (clqr:qr-error-correction qr)
              (clqr:qr-mask qr) (clqr:qr-size qr)))))

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
                . "echo -n hi | clqr -f pbm -o hi.pbm -"))))

(defun main ()
  (clingon:run (command)))

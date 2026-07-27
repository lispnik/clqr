;;;; coverage.lisp --- Generate an sb-cover HTML coverage report.
;;;;
;;;; Run via `make coverage`.  Instruments the clqr sources, runs the FiveAM
;;;; suite (without exiting), and writes an HTML report to coverage/.

(require :asdf)
(require :sb-cover)

;; Compile clqr with coverage instrumentation, forcing a fresh compile.
(declaim (optimize sb-cover:store-coverage-data))
(asdf:load-system :clqr :force t)
(asdf:load-system :clqr/test)

;; Run the suite in-process (do not exit, so we can still emit the report).
(let ((ok (uiop:symbol-call :clqr.test :run-tests :exit nil)))
  (ensure-directories-exist
   (merge-pathnames "coverage/" (uiop:getcwd)))
  (funcall (uiop:find-symbol* :report :sb-cover)
           (merge-pathnames "coverage/" (uiop:getcwd)))
  ;; Stop instrumenting further compiles in this image.
  (proclaim '(optimize (sb-cover:store-coverage-data 0)))
  (format t "~&Coverage report written to coverage/cover-index.html~%")
  (uiop:quit (if ok 0 1)))

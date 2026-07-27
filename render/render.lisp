;;;; render.lisp --- Rendering protocol and shared helpers (the display side).
;;;;
;;;; Renderers turn a CLQR:QR-CODE model into some external representation.  They
;;;; only use the model's public readers, keeping display concerns separate from
;;;; the encoding model.  Common concerns (the quiet zone) live here.

(in-package #:clqr.render)

(defun grid-dark-p (qr quiet-zone row col)
  "Dark predicate for a module in the quiet-zone-padded grid.  ROW and COL are
in padded coordinates (0 .. size+2*quiet-zone-1); quiet-zone modules are light."
  (let* ((size (qr-size qr))
         (r (- row quiet-zone))
         (c (- col quiet-zone)))
    (and (<= 0 r (1- size)) (<= 0 c (1- size))
         (qr-module qr r c))))

(defun map-grid (qr quiet-zone function)
  "Call FUNCTION with (ROW COL DARK-P) over the quiet-zone-padded grid."
  (let ((dim (+ (qr-size qr) (* 2 quiet-zone))))
    (dotimes (row dim)
      (dotimes (col dim)
        (funcall function row col (grid-dark-p qr quiet-zone row col))))))

(defun render (qr format &rest args)
  "Render QR in FORMAT (:text, :svg or :pbm), passing ARGS to the specific
renderer.  Returns whatever that renderer returns."
  (ecase format
    (:text (apply #'render-text qr args))
    (:svg (apply #'render-svg qr args))
    (:pbm (apply #'render-pbm qr args))))

;;;; svg.lisp --- SVG rendering of a QR code.

(in-package #:clqr.render)

(defun render-svg (qr &key (stream *standard-output*) (quiet-zone 4)
                        (module-size 8) (foreground "#000000")
                        (background "#ffffff"))
  "Render QR as a self-contained SVG document to STREAM.

:quiet-zone   width of the light border in modules (default 4).
:module-size  side length of one module in SVG user units (default 8).
:foreground   dark module colour (default black).
:background   background colour (default white); NIL for a transparent
              background (no background rectangle).

Returns QR."
  (let* ((dim (+ (qr-size qr) (* 2 quiet-zone)))
         (px (* dim module-size)))
    (format stream "<?xml version=\"1.0\" encoding=\"UTF-8\"?>~%")
    (format stream "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"~D\" height=\"~D\" ~
viewBox=\"0 0 ~D ~D\" shape-rendering=\"crispEdges\">~%"
            px px dim dim)
    (when background
      (format stream "<rect width=\"~D\" height=\"~D\" fill=\"~A\"/>~%"
              dim dim background))
    ;; Emit all dark modules as one path for a compact document.
    (write-string "<path fill=\"" stream)
    (write-string foreground stream)
    (write-string "\" d=\"" stream)
    (map-grid qr quiet-zone
              (lambda (row col dark)
                (when dark
                  (format stream "M~D ~Dh1v1h-1z" col row))))
    (format stream "\"/>~%</svg>~%"))
  qr)

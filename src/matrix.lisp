;;;; matrix.lisp --- Module matrix construction (ISO 8.7-8.9).
;;;;
;;;; Builds the module bit-matrix: the function patterns (finders, separators,
;;;; timing, alignment, dark module), the reserved format/version areas, the
;;;; zig-zag placement of the final message bits, and data masking with penalty
;;;; scoring to pick the best mask.
;;;;
;;;; MODULES is a (simple-array bit (size size)); 1 = dark, 0 = light.  A
;;;; parallel FUNCTION array marks modules that belong to function patterns and
;;;; must not be masked or overwritten by data.

(in-package #:clqr)

(defmacro mref (a r c) `(aref ,a ,r ,c))

(defun make-bit-matrix (size)
  (make-array (list size size) :element-type 'bit :initial-element 0))

;;; ---------------------------------------------------------------------------
;;; Function patterns
;;; ---------------------------------------------------------------------------

(defun finder-module-p (dr dc)
  "Dark predicate for a 7x7 finder pattern at relative offset (DR,DC)."
  (or (member dr '(0 6)) (member dc '(0 6))
      (and (<= 2 dr 4) (<= 2 dc 4))))

(defun draw-finder (modules func size r0 c0)
  "Draw a finder pattern whose top-left corner is (R0,C0) together with its
separator (a one-module light border on the sides facing the data)."
  (loop for dr from -1 to 7 do
    (loop for dc from -1 to 7 do
      (let ((r (+ r0 dr)) (c (+ c0 dc)))
        (when (and (<= 0 r (1- size)) (<= 0 c (1- size)))
          (setf (mref func r c) 1)
          (setf (mref modules r c)
                (if (and (<= 0 dr 6) (<= 0 dc 6) (finder-module-p dr dc)) 1 0)))))))

(defun draw-timing (modules func size)
  "Draw the horizontal and vertical timing patterns on row 6 and column 6."
  (loop for i from 8 to (- size 9)
        for bit = (if (evenp i) 1 0)
        do (unless (plusp (mref func 6 i))
             (setf (mref modules 6 i) bit (mref func 6 i) 1))
           (unless (plusp (mref func i 6))
             (setf (mref modules i 6) bit (mref func i 6) 1))))

(defun overlaps-finder-p (r c size)
  "True if the 5x5 alignment pattern centred at (R,C) would overlap a finder
pattern (including separator)."
  (flet ((box-hit (r0 c0)
           (and (<= r0 (+ r 2)) (<= (- r 2) (+ r0 7))
                (<= c0 (+ c 2)) (<= (- c 2) (+ c0 7)))))
    (or (box-hit 0 0)
        (box-hit 0 (- size 8))
        (box-hit (- size 8) 0))))

(defun draw-alignment (modules func size version)
  "Draw all alignment patterns for VERSION, skipping those overlapping finders."
  (let ((positions (alignment-positions version)))
    (dolist (r positions)
      (dolist (c positions)
        (unless (overlaps-finder-p r c size)
          (loop for dr from -2 to 2 do
            (loop for dc from -2 to 2 do
              (let ((rr (+ r dr)) (cc (+ c dc)))
                (setf (mref func rr cc) 1)
                (setf (mref modules rr cc)
                      (if (or (= (max (abs dr) (abs dc)) 2)
                              (and (zerop dr) (zerop dc)))
                          1 0))))))))))

;;; ---------------------------------------------------------------------------
;;; Format and version information placement
;;; ---------------------------------------------------------------------------

(defun format-positions (size)
  "Return two vectors of (row . col) positions, one per format-info copy, each
indexed by format bit 0..14."
  (let ((p1 (make-array 15)) (p2 (make-array 15)))
    (dotimes (i 15)
      (setf (aref p1 i)
            (cond ((<= i 5) (cons 8 i))
                  ((= i 6) (cons 8 7))
                  ((= i 7) (cons 8 8))
                  ((= i 8) (cons 7 8))
                  (t (cons (- 14 i) 8))))
      (setf (aref p2 i)
            (cond ((<= i 6) (cons (- size 1 i) 8))
                  ((= i 7) (cons 8 (- size 8)))
                  (t (cons 8 (+ (- size 15) i))))))
    (values p1 p2)))

(defun reserve-format (modules func size)
  "Reserve the format-information modules (as function) and set the dark module."
  (multiple-value-bind (p1 p2) (format-positions size)
    (flet ((reserve (pos)
             (loop for cell across pos
                   do (setf (mref func (car cell) (cdr cell)) 1))))
      (reserve p1)
      (reserve p2)))
  ;; The dark module, always dark (ISO 8.9).
  (setf (mref modules (- size 8) 8) 1
        (mref func (- size 8) 8) 1))

(defun draw-format-bits (modules size ecl mask)
  "Write both copies of the format information for ECL and MASK into MODULES."
  (let ((bits (format-information ecl mask)))
    (multiple-value-bind (p1 p2) (format-positions size)
      (dotimes (i 15)
        ;; Position I holds bit (14 - I): the most significant bit is placed
        ;; first (at (8,0) and the top of the vertical strip).
        (let ((b (ldb (byte 1 (- 14 i)) bits))
              (a (aref p1 i)) (d (aref p2 i)))
          (setf (mref modules (car a) (cdr a)) b)
          (setf (mref modules (car d) (cdr d)) b))))))

(defun draw-version-info (modules func size version)
  "Write both copies of the version information for VERSION (>= 7)."
  (let ((bits (version-information version)))
    (when bits
      (dotimes (i 18)
        (let ((b (ldb (byte 1 i) bits))
              (row (+ (- size 11) (mod i 3)))
              (col (floor i 3)))
          ;; Bottom-left block.
          (setf (mref modules row col) b (mref func row col) 1)
          ;; Top-right block (transposed).
          (setf (mref modules col row) b (mref func col row) 1))))))

;;; ---------------------------------------------------------------------------
;;; Data placement
;;; ---------------------------------------------------------------------------

(defun draw-data (modules func size codewords)
  "Place the final-message CODEWORDS into MODULES using the ISO zig-zag scan,
skipping function modules.  Leftover modules stay light (remainder bits)."
  (let ((bit-index 0)
        (total-bits (* 8 (length codewords))))
    (flet ((next-bit ()
             (if (< bit-index total-bits)
                 (prog1 (ldb (byte 1 (- 7 (mod bit-index 8)))
                             (aref codewords (floor bit-index 8)))
                   (incf bit-index))
                 0)))
      ;; Scan column pairs from the right.  When the right column reaches the
      ;; vertical timing column (6) it is shifted to 5, which also flips the
      ;; parity of the remaining columns so every data column is covered.
      (let ((right (1- size)))
        (loop while (>= right 1) do
          (when (= right 6) (setf right 5))
          (dotimes (vert size)
            (dotimes (j 2)
              (let* ((col (- right j))
                     (upward (zerop (logand (+ right 1) 2)))
                     (row (if upward (- size 1 vert) vert)))
                (when (zerop (mref func row col))
                  (setf (mref modules row col) (next-bit))))))
          (decf right 2))))))

;;; ---------------------------------------------------------------------------
;;; Masking
;;; ---------------------------------------------------------------------------

(defun mask-predicate (mask)
  "Return the boolean masking condition for MASK pattern (0-7)."
  (ecase mask
    (0 (lambda (r c) (zerop (mod (+ r c) 2))))
    (1 (lambda (r c) (declare (ignore c)) (zerop (mod r 2))))
    (2 (lambda (r c) (declare (ignore r)) (zerop (mod c 3))))
    (3 (lambda (r c) (zerop (mod (+ r c) 3))))
    (4 (lambda (r c) (zerop (mod (+ (floor r 2) (floor c 3)) 2))))
    (5 (lambda (r c) (zerop (+ (mod (* r c) 2) (mod (* r c) 3)))))
    (6 (lambda (r c) (zerop (mod (+ (mod (* r c) 2) (mod (* r c) 3)) 2))))
    (7 (lambda (r c) (zerop (mod (+ (mod (+ r c) 2) (mod (* r c) 3)) 2))))))

(defun apply-mask (modules func size mask)
  "Flip every non-function module of MODULES where MASK's condition holds."
  (let ((pred (mask-predicate mask)))
    (dotimes (r size)
      (dotimes (c size)
        (when (and (zerop (mref func r c)) (funcall pred r c))
          (setf (mref modules r c) (- 1 (mref modules r c))))))))

;;; ---------------------------------------------------------------------------
;;; Penalty scoring (ISO 8.8.2)
;;; ---------------------------------------------------------------------------

(defparameter +penalty-n1+ 3)
(defparameter +penalty-n2+ 3)
(defparameter +penalty-n3+ 40)
(defparameter +penalty-n4+ 10)

(defun penalty-line-runs (modules size row-major)
  "Rule 1 penalty for rows (ROW-MAJOR true) or columns (false)."
  (let ((total 0))
    (dotimes (a size)
      (let ((run 1) (prev nil))
        (dotimes (b size)
          (let ((v (if row-major (mref modules a b) (mref modules b a))))
            (cond ((eql v prev) (incf run)
                   (cond ((= run 5) (incf total +penalty-n1+))
                         ((> run 5) (incf total))))
                  (t (setf run 1 prev v)))))))
    total))

(defparameter +finder-pattern-a+ #*10111010000)
(defparameter +finder-pattern-b+ #*00001011101)

(defun penalty-finder-lines (modules size row-major)
  "Rule 3 penalty: occurrences of the 1:1:3:1:1 pattern with a 4-module light
margin, scanned along rows or columns."
  (let ((total 0))
    (dotimes (a size)
      (loop for start from 0 to (- size 11)
            do (let ((match-a t) (match-b t))
                 (dotimes (k 11)
                   (let ((v (if row-major (mref modules a (+ start k))
                                (mref modules (+ start k) a))))
                     (unless (= v (aref +finder-pattern-a+ k)) (setf match-a nil))
                     (unless (= v (aref +finder-pattern-b+ k)) (setf match-b nil))))
                 (when match-a (incf total +penalty-n3+))
                 (when match-b (incf total +penalty-n3+)))))
    total))

(defun penalty-score (modules size)
  "Total masking penalty for MODULES (ISO 8.8.2, four rules)."
  (let ((total 0) (dark 0))
    ;; Rule 1: runs in rows and columns.
    (incf total (penalty-line-runs modules size t))
    (incf total (penalty-line-runs modules size nil))
    ;; Rule 2: 2x2 blocks of one colour.
    (dotimes (r (1- size))
      (dotimes (c (1- size))
        (let ((v (mref modules r c)))
          (when (and (= v (mref modules r (1+ c)))
                     (= v (mref modules (1+ r) c))
                     (= v (mref modules (1+ r) (1+ c))))
            (incf total +penalty-n2+)))))
    ;; Rule 3: finder-like patterns.
    (incf total (penalty-finder-lines modules size t))
    (incf total (penalty-finder-lines modules size nil))
    ;; Rule 4: dark-module balance.
    (dotimes (r size)
      (dotimes (c size)
        (incf dark (mref modules r c))))
    (let ((percent (/ (* dark 100) (* size size))))
      (incf total (* +penalty-n4+ (floor (abs (- percent 50)) 5))))
    total))

;;; ---------------------------------------------------------------------------
;;; Assembly
;;; ---------------------------------------------------------------------------

(defun place-function-patterns (modules func size version)
  (draw-finder modules func size 0 0)
  (draw-finder modules func size 0 (- size 7))
  (draw-finder modules func size (- size 7) 0)
  (draw-alignment modules func size version)
  (draw-timing modules func size)
  (reserve-format modules func size)
  (draw-version-info modules func size version))

(defun build-matrix (codewords version ecl forced-mask)
  "Build the finished module matrix.  Returns (values MODULES MASK)."
  (let* ((size (module-count version))
         (base (make-bit-matrix size))
         (func (make-bit-matrix size)))
    (place-function-patterns base func size version)
    (draw-data base func size codewords)
    (let ((best nil) (best-mask nil) (best-penalty nil))
      (dolist (mask (if forced-mask (list forced-mask) '(0 1 2 3 4 5 6 7)))
        (let ((trial (make-bit-matrix size)))
          (dotimes (r size) (dotimes (c size) (setf (mref trial r c) (mref base r c))))
          (apply-mask trial func size mask)
          (draw-format-bits trial size ecl mask)
          (let ((p (penalty-score trial size)))
            (when (or (null best-penalty) (< p best-penalty))
              (setf best trial best-mask mask best-penalty p)))))
      (values best best-mask))))

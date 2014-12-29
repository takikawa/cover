#lang racket
(provide generate-html-coverage generate-coveralls-coverage)
(require syntax/modread
         syntax/parse
         unstable/sequence
         json
         syntax-color/racket-lexer
         (only-in xml write-xexpr))
(module+ test (require rackunit "main.rkt"))


;;;;; main

;;; Coverage [PathString] -> Void
(define (generate-html-coverage coverage [dir "coverage"])
  (make-directory* dir)
  (for ([(k v) coverage])
    (define relative-file-name
      (string-replace k (path->string (build-path (current-directory))) ""))
    (define coverage-path (path->string (build-path (current-directory) dir)))
    (define coverage-file-relative
      (string-replace (string-replace relative-file-name ".rkt" "") "/" "-"))
    (define output-file (string-append coverage-path "/" coverage-file-relative ".html"))
    (with-output-to-file output-file
      (λ () (write-xexpr (make-html-file (hash-ref coverage k) relative-file-name)))
      #:exists 'replace)))

;;;;; a Coverage is the output of (get-test-coverage)
;;;;; a FileCoverage is the values of the hashmap from (get-test-coverage)

;;;;; percentage
;; A Percentage is a [HashMap Type Real∈[0,1]]
;; a Type is one of: (update this as needed)
;; 'expr

;;  TODO this needs not count submodules and test directories

;; Coverage -> Percentage
(define (get-percentages/top coverage)
  (hash
   'expr (file-percentages->top expr-percentage coverage)))

(define (file-percentages->top get-% coverage)
  (define per-file
    (for/list ([(f v) coverage])
      (call-with-values (thunk (get-% f v)) list)))
  (define total (for/sum ([v per-file]) (second v)))
  (for/sum ([v per-file])
    (* (first v) (/ (second v) total))))

;; PathString FileCoverage -> Percentage
(define (get-percentages/file path coverage)
  (hash
   'expr (first (call-with-values (thunk (expr-percentage path coverage)) list))))

;;; percentage generators. each one has the type:
;; FileCoverage -> Real∈[0,1] Natural
;; there the Real is the percentage covered
;; and the Natural is the number of things of that type in the file

(define (expr-percentage path coverage)
  (define (is-covered? e)
    ;; we don't need to look at the span because the coverage is expression based
    (define p (syntax-position e))
    (covered? p coverage path))

  (define e
    (with-module-reading-parameterization
        (thunk (with-input-from-file path read-syntax))))
  (define (ret e)
    (values (e->n e) (a->n e)))
  (define (a->n e)
    (case (is-covered? e)
      [(yes no) 1]
      [else 0]))
  (define (e->n e)
    (if (eq? (is-covered? e) 'yes) 1 0))
  (define-values (covered count)
    (let recur ([e e])
      (syntax-parse e
        [(v ...)
         (for/fold ([covered (e->n e)] [count (a->n e)])
                   ([e (in-syntax e)])
           (define-values (cov cnt) (recur e))
           (values (+ covered cov)
                   (+ count cnt)))]
        [e:expr (ret #'e)]
        [_ (values 0 0)])))
  (values (/ covered count) count))

(module+ test
  (test-begin
   (define f (path->string (build-path (current-directory) "tests/basic/prog.rkt")))
   (test-files! f)
   (define-values (result _) (expr-percentage f (hash-ref (get-test-coverage) f)))
   (check-equal? result 1)
   (clear-coverage!)))

;;;;; html
;; FileCoverage PathString -> Xexpr
(define (make-html-file coverage path)
  (define %age (get-percentages/file path coverage))
  `(html ()
    (body ()
          ,@(for/list ([(type %) %age])
              `(p () ,(~a type ': " " (~r (* 100 %) #:precision 2) "%") (br ())))
          ,@(file->html coverage path))))

(module+ test
  (test-begin
   (define f
     (path->string (build-path (current-directory) "tests/basic/prog.rkt")))
   (test-files! f)
   (check-equal? (make-html-file (hash-ref (get-test-coverage) f) f)
                 `(html ()
                   (body ()
                         (p () "expr: 100%" (br ()))
                         ,@(file->html (hash-ref (get-test-coverage) f) f))))
   (clear-coverage!)))

(define (file->html cover path)
  (define file (file->string path))
  (let loop ([loc 1] [start 1] [left (string-length file)] [mode (covered? 1 cover path)])
    (define (get-xml)
      (mode-xml mode (encode-string (substring file (sub1 start) (sub1 loc)))))
    (case left
      [(0) (list (get-xml))]
      [else
       (define m (covered? loc cover path))
       (define (loop* start) (loop (add1 loc) start (sub1 left) m))
       (if (eq? m mode)
           (loop* start)
           (cons (get-xml)
                 (loop* loc)))])))

(define (get-mode loc c)
  (define-values (mode _)
    (for/fold ([mode 'none] [last-start 0])
              ([pair c])
      (match pair
        [(list m (srcloc _ _ _ start range))
         (if (and (<= start loc (+ start range))
                  (or (eq? mode 'none)
                      (> start last-start)))
             (values m start)
             (values mode last-start))])))
  mode)

(define (encode-string c)
  (foldr (λ (el rst) (cons el (cons '(br ()) rst)))
         '()
         (string-split c "\n")))

(define (mode-xml mode body)
  (define color
    (case mode
      [(yes) "green"]
      [(no) "red"]
      [(missing) "black"]))
  `(div ((style ,(string-append "color:" color))) ,@body))

(module+ test
  (define (test f out)
    (define file (path->string (build-path (current-directory) f)))
    (test-files! file)
    (check-equal? (file->html (hash-ref (get-test-coverage) file)
                              file)
                  out)
    (clear-coverage!))
  (test "tests/basic/prog.rkt"
        `((div ((style "color:green"))
          ,@(encode-string (file->string "tests/basic/prog.rkt"))))))


;; Coveralls

;; Coverage [Hasheq String String] [path-string] -> Void
(define (generate-coveralls-coverage coverage meta [dir "coverage"])
  (make-directory* dir)
  (define coverage-path (path->string (build-path (current-directory) dir)))
  (with-output-to-file (string-append coverage-path "/coverage.json")
    (λ () (write-json (generate-coveralls-json coverage meta)))
    #:exists 'replace))

;; Coverage [Hasheq String String] -> JSexpr
;; Generates a string that represents a valid coveralls json_file object
(define (generate-coveralls-json coverage meta)
  (define src-files
    (for/list ([file (hash-keys coverage)])
      (define src (file->string file))
      (define c (line-coverage coverage file))
      (hasheq 'src src 'coverage c)))
  (hash-set meta 'source_files src-files))

;; CoverallsCoverage = Nat | json-null

;; Coverage PathString -> [Listof CoverallsCoverage]
;; Get the line coverage for the file to generate a coverage report
(define (line-coverage coverage file)
  (define split-src (string-split (file->string file) "\n"))
  (define file-coverage (hash-ref coverage file))
  (define (process-coverage value rst-of-line)
    (case (covered? value file-coverage file)
      ['yes (if (equal? 'no rst-of-line) rst-of-line 'yes)]
      ['no 'no]
      [else rst-of-line]))
  (define (process-coverage-value value)
    (case value
      ['yes 1]
      ['no 0]
      [else (json-null)]))

  (define-values (line-cover _)
    (for/fold ([coverage '()] [count 1]) ([line split-src])
      (cond [(zero? (string-length line)) (values (cons (json-null) coverage) (add1 count))]
            [else (define nw-count (+ count (string-length line)))
                  (define all-covered (foldr process-coverage 'missing (range count nw-count)))
                  (values (cons (process-coverage-value all-covered) coverage) nw-count)])))
  (reverse line-cover))

(module+ test
  (let ()
    (define file (path->string (build-path (current-directory) "tests/basic/not-run.rkt")))
    (test-files! file)
    (check-equal? (line-coverage (get-test-coverage) file) '(1 0))
    (clear-coverage!)))

;;;;; utils

;;; a Cover is (U 'yes 'no 'missing)

;; [Hashof PathString [Hashof Natural Cover]]
(define file-location-coverage-cache (make-hash))

;; Natural FileCoverage PathString -> Cover
(define (covered? loc c path)
  (define file-cache
    (let ([v (hash-ref file-location-coverage-cache path #f)])
      (if v v (coverage-cache-file! path c))))
  (hash-ref file-cache loc))


;; Path FileCoverage -> [Hashof Natural Cover]
(define (coverage-cache-file! f c)
  (with-input-from-file f
    (thunk
     (define lexer
       ((read-language) 'color-lexer racket-lexer))
     (define irrelevant? (make-irrelevant? lexer f))
     (define file-length (string-length (file->string f)))
     (define cache
       (for/hash ([i (range 1 (add1 file-length))])
         (values i
                 (cond [(irrelevant? i) 'missing]
                       [else (raw-covered? i c)]))))
     (hash-set! file-location-coverage-cache
                f
                cache)
     cache)))

;; TODO should we only ignore test (and main) submodules?
(define (make-irrelevant? lexer f)
  (define s (mutable-set))
  (let loop ()
    (define-values (_v type _m start end) (lexer (current-input-port)))
    (case type
      [(eof) (void)]
      [(comment sexp-comment no-color)
       (for ([i (in-range start end)])
         (set-add! s i))
       (loop)]
      [else (loop)]))
  (define stx
    (with-input-from-file f
      (thunk (with-module-reading-parameterization read-syntax))))
  (let loop ([stx stx] [first? #t])
    (define (loop* stx) (loop stx #f))
    (syntax-parse stx
      #:datum-literals (module module* module+)
      [((~or module module* module+) e ...)
       #:when (not first?)
       (define pos (syntax-position stx))
       (when pos
         (for ([i (in-range pos (+ pos (syntax-span stx)))])
           (set-add! s i)))]
      [(e ...) (for-each loop* (syntax->list #'(e ...)))]
      [_else (void)]))
  (lambda (i) (set-member? s i)))

(define (in-syntax-object? i stx)
  (define p (syntax-position stx))
  (define r (syntax-span stx))
  (<= p i (+ p r)))

(define (raw-covered? loc c)
  (define-values (mode _)
    (for/fold ([mode 'none] [last-start 0])
              ([pair c])
      (match pair
        [(list m (srcloc _ _ _ start range))
         (if (and (<= start loc (+ start range))
                  (or (eq? mode 'none)
                      (> start last-start)))
             (values m start)
             (values mode last-start))])))
  (case mode
    [(#t) 'yes]
    [(#f) 'no]
    [else 'missing]))

(module+ test
  (test-begin
   (define f (path->string (build-path (current-directory) "tests/prog.rkt")))
   (test-files! f)
   (define coverage (hash-ref (get-test-coverage) f))
   (check-equal? (covered? 17 coverage f) 'missing)
   (check-equal? (covered? 35 coverage f) 'yes)
   (clear-coverage!)))
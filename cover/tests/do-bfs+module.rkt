#lang racket
(require cover rackunit racket/runtime-path)
(define-runtime-path-list fs
  (list "module.rkt"
        "bfs.rkt"
        "bfs+module.rkt"))
(test-case
 "begin-for-syntax with nexted modules should be okay"
 (parameterize ([current-cover-environment (make-cover-environment)])
   (for-each
    (lambda (f)
      (check-not-exn
       (lambda () (test-files! f))
       (path->string f)))
    fs)))
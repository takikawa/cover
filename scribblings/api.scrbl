#lang scribble/doc
@(require "base.rkt")

@title[#:tag "api"]{Racket API}

@defmodule[cover #:use-sources (cover)]

In addition to a raco tool Cover provides racket bindings for running
tests and collecting coverage information. The following are the basic
functions of test coverage.

@defproc[(test-files! (files path-string?) ...) any/c]{

Clears all coverage information, then tests all given @racket[files]
and stores the coverage information. Returns false if tests
failed. Test coverage information is still collected when test fail.}

@defproc[(clear-coverage!) any]{Clears all coverage information.}

@defproc[(get-coverage-information) coverage/c]{Gets coverage information.}
@defproc[(covered? (loc exact-positive-integer?) (coverage file-coverage/c)
                   (path path-string?))
         (or/c 'yes 'no 'missing)
         ]{
Given some location in a file, the
coverage information for that file, and the path to that file,
@racket[covered?] returns if that position how that position is
covered. There are three possible results:
@itemize[@item{@racket['missing] --- The location is not in the
coverage information, is a comment, or is in a submodule}
@item{@racket['yes] --- The location is not @racket['missing] and is
covered} @item{@racket['no] --- The location is not @racket['missing]
and is not covered}]
                                   }

@deftogether[(@defproc[(generate-coveralls-coverage (c coverage/c) (p path-string? "coverage")) any]
              @defproc[(generate-html-coverage (c coverage/c) (p path-string? "coverage")) any])]{
Generates coverage information in the coveralls and html
formats. Equivalent to the specifications of the @Flag{c} argument to
@exec{raco cover}.}

@deftogether[(@defthing[coverage/c
                         contract?
                         #:value (hash/c (and/c path-string? absolute-path?)
                                         file-coverage/c)]
                @defthing[file-coverage/c contract? #:value (listof (list/c boolean? srcloc?))])]{
Coverage infomation is a hash map mapping absolute
file paths to a list detailing the coverage of that file. The coverage
information is a list of lists, mapping a boolean to a range of
characters within the file. True means @racket[srcloc] structure
represents an expression that was run, and False means the structure
represents an expression that was not run. Not that not all
expressions may be represented directly in this coverage
information. For example, type annotations in @racket[typed/racket]
removed during macro expansion and are thus neither run or not run.
Not that the @racket[srcloc]s are one indexed, meaning a @racket[1]
represents the first character in the file.}
;;; sbcl --non-interactive --load build.lisp   ->  ./tubedrop, one executable
(push :hunchentoot-no-ssl *features*)           ; curl does the TLS; hunchentoot serves plain HTTP
(require :asdf)
(push (uiop:getcwd) asdf:*central-registry*)
(dolist (d (uiop:subdirectories (merge-pathnames "deps/" (uiop:getcwd)))) (push d asdf:*central-registry*))
(ql:quickload :tubedrop :silent t)
(sb-ext:save-lisp-and-die "tubedrop" :executable t
  :toplevel (lambda ()
              (setf sb-impl::*default-external-format* :utf-8)
              (handler-case (tubedrop:main (rest sb-ext:*posix-argv*))
                (sb-sys:interactive-interrupt () (uiop:quit 130))
                (error (e) (format *error-output* "tubedrop: ~a~%" e) (uiop:quit 1)))
              (uiop:quit 0)))

;;; sbcl --non-interactive --load tests/self-check.lisp   (repo root, dropin in deps/dropin; no network)
(push :hunchentoot-no-ssl *features*)
(require :asdf)
(push (uiop:getcwd) asdf:*central-registry*)
(push (merge-pathnames "deps/dropin/" (uiop:getcwd)) asdf:*central-registry*)
(ql:quickload :tubedrop :silent t)
(in-package :tubedrop)

(defvar *fails* 0)
(defmacro check (name form)
  `(if ,form (format t "ok   ~a~%" ,name) (progn (incf *fails*) (format t "FAIL ~a~%" ,name))))

(check "safe-name drops folders" (string= (safe-name "C:\\x\\..\\a [1].mp3") "a [1].mp3"))
(check "safe-name drops leading dots" (string= (safe-name "../../.bashrc") "bashrc"))
(check "safe-name never empty" (string= (safe-name "...") "upload"))
(check "query-param decodes"
       (string= (query-param "http://localhost:8080/oauth/callback?state=ab&code=4%2F0Ab_x&scope=s" "code") "4/0Ab_x"))
(check "query-param missing is nil" (null (query-param "http://localhost/x?state=1" "code")))
(check "header takes the last match, any case"
       (string= (header (format nil "HTTP/1.1 100~a~%Location: a~a~%location: b~a~%" #\Return #\Return #\Return) "location") "b"))
(let ((r (next-quota-reset)) (now (get-universal-time)))
  (check "quota reset is within a day" (< now r (+ now 86401)))
  (check "quota reset is at 08:00 UTC" (multiple-value-bind (s m h) (decode-universal-time r 0) (and (= s m 0) (= h 8)))))
(check "quota errors are recognised" (quota-error-p "{\"reason\": \"quotaExceeded\"}"))
(let ((job (dropin::%make-job :name "x" :dir "/tmp" :data '(:file "Book [2] (1).m4a"))))
  (check "title drops the extension" (string= (title-of job) "Book [2] (1)")))

(format t "~:[all checks passed~;~:*~d check~:p FAILED~]~%" (and (plusp *fails*) *fails*))
(uiop:quit (if (plusp *fails*) 1 0))

(in-package :tubedrop)
;;; The web page: drop files on it to queue them, watch the jobs, connect the YouTube account.

(defparameter +index+ #.(uiop:read-file-string (merge-pathnames "../www/index.html" (or *compile-file-truename* *load-truename*))))

(defvar *queue* nil)
(defvar *redirect* nil "OAuth redirect URI; Google allows http://localhost:PORT/... for a Desktop app client.")
(defvar *password* nil "With TUBEDROP_PASSWORD set, the page asks for it (any user name).")
(defvar *states* '() "OAuth state values handed out, to match the callback.")

(defun json-out (object)
  (setf (hunchentoot:content-type*) "application/json")
  (jzon:stringify object))

(defun job-json (j)
  (alexandria:plist-hash-table
   (list "name" (getf j :name) "state" (getf j :state) "stage" (or (getf j :stage) 'null)
         "error" (or (getf j :error) 'null) "url" (or (getf j :url) 'null)
         "dropped" (or (getf j :dropped) 'null) "finished" (or (getf j :finished) 'null))
   :test #'equal))

(defun status-json ()
  (json-out (alexandria:plist-hash-table
             (list "connected" (connected-p)
                   "client" (and (probe-file (config-path "client_secret.json")) t)
                   "privacy" *privacy*
                   "jobs" (coerce (mapcar #'job-json (queue-status *queue*)) 'vector))
             :test #'equal)))

(defun safe-name (name)
  "The browser's file name with any folder part and leading dots cut off, so it stays inside the inbox."
  (let* ((base (subseq name (1+ (or (position-if (lambda (c) (member c '(#\/ #\\))) name :from-end t) -1))))
         (base (string-left-trim "." base)))
    (if (string= base "") "upload" base)))

(defun receive-uploads ()
  "Every \"file\" part of a multipart POST goes into the inbox under its own name."
  (let ((names (loop for (key . value) in (hunchentoot:post-parameters*)
                     when (and (string= key "file") (consp value))
                       collect (destructuring-bind (path name &rest _) value
                                 (declare (ignore _))
                                 (drop-file *queue* (native path) (safe-name name))))))
    (json-out (coerce names 'vector))))

(defun new-state ()
  (let ((s (format nil "~36r" (random (expt 2 64) (make-random-state t)))))
    (push s *states*)
    (setf *states* (subseq *states* 0 (min 20 (length *states*))))
    s))

(defun finish-oauth (code state)
  (unless (member state *states* :test #'equal) (error "unknown sign-in attempt: start again with Connect"))
  (exchange-code code *redirect*)
  (log-line "connected to YouTube")
  (hunchentoot:redirect "/"))

(defun query-param (url name)
  "Value of NAME in the query of URL, decoded."
  (let* ((q (subseq url (1+ (or (position #\? url) (1- (length url))))))
         (pair (find-if (lambda (p) (uiop:string-prefix-p (uiop:strcat name "=") p))
                        (uiop:split-string q :separator "&"))))
    (and pair (hunchentoot:url-decode (subseq pair (1+ (length name))) :utf-8))))

(defclass site (hunchentoot:acceptor) ())

(defmethod hunchentoot:acceptor-dispatch-request ((site site) request)
  (when *password*
    (multiple-value-bind (user pass) (hunchentoot:authorization)
      (declare (ignore user))
      (unless (equal pass *password*)
        (return-from hunchentoot:acceptor-dispatch-request (hunchentoot:require-authorization "tubedrop")))))
  (let ((path (hunchentoot:script-name request))
        (post (eq (hunchentoot:request-method request) :post)))
    (handler-case
        (cond ((string= path "/") (setf (hunchentoot:content-type*) "text/html; charset=utf-8") +index+)
              ((string= path "/api/status") (status-json))
              ((and post (string= path "/api/upload")) (receive-uploads))
              ((and post (string= path "/api/retry"))
               (retry *queue* (hunchentoot:post-parameter "name")) (json-out t))
              ((string= path "/oauth/start") (hunchentoot:redirect (consent-url *redirect* (new-state))))
              ((string= path "/oauth/callback")
               (finish-oauth (hunchentoot:get-parameter "code") (hunchentoot:get-parameter "state")))
              ((and post (string= path "/oauth/paste"))
               (let ((url (hunchentoot:post-parameter "url")))
                 (finish-oauth (query-param url "code") (query-param url "state"))))
              (t (setf (hunchentoot:return-code*) 404) "not found"))
      (error (e)
        (setf (hunchentoot:return-code*) 500 (hunchentoot:content-type*) "text/plain; charset=utf-8")
        (princ-to-string e)))))

(defun start-web (queue port)
  (setf *queue* queue
        hunchentoot:*tmp-directory* (uiop:ensure-directory-pathname (queue-path queue ".tmp"))
        hunchentoot:*show-lisp-errors-p* nil)
  (ensure-directories-exist hunchentoot:*tmp-directory*)
  (hunchentoot:start (make-instance 'site :port port :access-log-destination nil))
  (log-line "web page on port ~d (sign-in redirect ~a)" port *redirect*))

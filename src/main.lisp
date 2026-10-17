(in-package :tubedrop)

(setf *valued-options* (append *valued-options* '("--config" "--port" "--privacy" "--redirect")))

(defun env-or (option env default) (or (option option) (uiop:getenv env) default))

(defun configure ()
  (setf *config* (env-or "--config" "TUBEDROP_CONFIG" "/config")
        *privacy* (env-or "--privacy" "TUBEDROP_PRIVACY" "private")
        *delete-source* (or (flag "--delete-source") (equal (uiop:getenv "TUBEDROP_DELETE_SOURCE") "1"))
        *password* (uiop:getenv "TUBEDROP_PASSWORD"))
  (unless (member *privacy* '("private" "unlisted" "public") :test #'string=)
    (error "--privacy must be private, unlisted or public, not ~s" *privacy*)))

(defcommand web (q words) "" "the web page and the daemon together (the container's command)"
  (let ((port (parse-integer (env-or "--port" "TUBEDROP_PORT" "8080"))))
    (setf *redirect* (env-or "--redirect" "TUBEDROP_REDIRECT" (format nil "http://localhost:~d/oauth/callback" port)))
    (start-web q port)
    (serve q :jobs (int-option "--jobs" 1) :every (int-option "--every" 600))))

(defcommand auth (q words) "" "sign in to YouTube from a terminal: open the URL, paste back the address you land on"
  (let ((redirect "http://localhost:1/oauth/callback"))
    (format t "Open this URL, allow access, then paste the address the browser lands on (it fails to load: fine):~%~a~%> "
            (consent-url redirect "cli"))
    (finish-output)
    (exchange-code (query-param (read-line) "code") redirect)
    (format t "connected; token in ~a/token.json~%" *config*)))

(defun main (args)
  (let ((*args* args))  ; configure reads the options before dropin:main binds them for the command
    (configure))
  (dropin:main args :program "tubedrop"))

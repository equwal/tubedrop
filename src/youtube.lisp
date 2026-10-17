(in-package :tubedrop)
;;; YouTube Data API v3 through curl: OAuth for an installed app, and the resumable upload.
;;; The config folder holds client_secret.json (the self-hoster's OAuth client) and token.json.

(defvar *config* "/config" "Folder with client_secret.json and token.json.")
(defvar *privacy* "private")
(defparameter +scope+ "https://www.googleapis.com/auth/youtube.upload")

(defvar *access* nil "(token . expiry universal time) of the current access token.")
(defvar *access-lock* (bt:make-lock "access token"))

(defun config-path (name) (uiop:parse-native-namestring (uiop:strcat *config* "/" name)))

(defun read-json (path)
  (and (probe-file path) (jzon:parse (uiop:read-file-string path))))

(defun write-secret (path string)
  "Write STRING to PATH readable by its owner only."
  (with-open-file (s path :direction :output :if-exists :supersede) (write-string string s))
  (run (list "chmod" "600" path)))

(defun client ()
  "The \"installed\" (Desktop app) or \"web\" block of client_secret.json."
  (let ((j (read-json (config-path "client_secret.json"))))
    (unless j (error "no ~a/client_secret.json: create an OAuth client (Desktop app) in Google Cloud" *config*))
    (or (gethash "installed" j) (gethash "web" j))))

(defun client-field (name) (gethash name (client)))

(defun connected-p () (and (read-json (config-path "token.json")) t))

(defun query-string (pairs)
  (format nil "~{~a=~a~^&~}"
          (loop for (k v) on pairs by #'cddr collect k collect (hunchentoot:url-encode v :utf-8))))

(defun consent-url (redirect state)
  (uiop:strcat "https://accounts.google.com/o/oauth2/v2/auth?"
               (query-string (list "client_id" (client-field "client_id") "redirect_uri" redirect
                                   "response_type" "code" "scope" +scope+ "access_type" "offline"
                                   "prompt" "consent" "state" state))))

(defun curl (&rest args)
  "Run curl with ARGS; return the response body, the HTTP status, and the response headers."
  (uiop:with-temporary-file (:pathname body)
    (uiop:with-temporary-file (:pathname head)
      (let ((code (or (parse-integer (run (append (list "curl" "-sS" "-o" body "-D" head "-w" "%{http_code}") args)
                                          :ignore-error t)
                                     :junk-allowed t)
                      0)))
        (when (zerop code) (hold 300 "network error talking to Google"))
        (values (uiop:read-file-string body) code (uiop:read-file-string head))))))

(defun token-request (&rest pairs)
  (multiple-value-bind (body code)
      (curl "-X" "POST" "https://oauth2.googleapis.com/token"
            "-H" "Content-Type: application/x-www-form-urlencoded"
            "--data" (query-string (append (list "client_id" (client-field "client_id")
                                                 "client_secret" (client-field "client_secret"))
                                           pairs)))
    (values (ignore-errors (jzon:parse body)) code body)))

(defun exchange-code (code redirect)
  "Trade the consent CODE for a refresh token and keep it in token.json."
  (multiple-value-bind (j status body) (token-request "code" code "redirect_uri" redirect
                                                      "grant_type" "authorization_code")
    (unless (and j (= status 200) (gethash "refresh_token" j))
      (error "Google refused the code (~a): ~a" status body))
    (write-secret (config-path "token.json")
                  (jzon:stringify (alexandria:plist-hash-table
                                   (list "refresh_token" (gethash "refresh_token" j)) :test #'equal)))
    (setf *access* nil)
    t))

(defun hold (seconds reason) (retry-later (+ (get-universal-time) seconds) reason))

(defun access-token ()
  "A valid access token, refreshed from token.json when it is old. Parks the job while nobody is signed in."
  (bt:with-lock-held (*access-lock*)
    (unless (and *access* (< (get-universal-time) (- (cdr *access*) 60)))
      (let ((tok (read-json (config-path "token.json"))))
        (unless tok (hold 300 "not connected to YouTube: open the web page and click Connect"))
        (multiple-value-bind (j status body)
            (token-request "refresh_token" (gethash "refresh_token" tok) "grant_type" "refresh_token")
          (cond ((and j (= status 200))
                 (setf *access* (cons (gethash "access_token" j)
                                      (+ (get-universal-time) (gethash "expires_in" j)))))
                ((search "invalid_grant" body)
                 ;; A Testing-mode OAuth app's refresh token dies after 7 days: sign in again.
                 (delete-file (config-path "token.json"))
                 (hold 300 "YouTube sign-in expired: open the web page and click Connect"))
                (t (hold 600 (format nil "token refresh failed (~a)" status)))))))
    (car *access*)))

(defun next-quota-reset ()
  "Universal time of the next 08:00 UTC. The quota resets at midnight Pacific, which is 07:00 or 08:00 UTC."
  (multiple-value-bind (s m h) (decode-universal-time (get-universal-time) 0)
    (let ((today-8 (- (get-universal-time) (+ s (* 60 m) (* 3600 h)) (- (* 8 3600)))))
      (if (> today-8 (get-universal-time)) today-8 (+ today-8 86400)))))

(defun header (headers name)
  "Value of the last header NAME in a curl -D dump (redirects can repeat it)."
  (let (value)
    (dolist (line (uiop:split-string headers :separator '(#\Newline)) value)
      (let ((colon (position #\: line)))
        (when (and colon (string-equal name (subseq line 0 colon)))
          (setf value (string-trim '(#\Space #\Return) (subseq line (1+ colon)))))))))

(defun quota-error-p (body)
  (or (search "quotaExceeded" body) (search "uploadLimitExceeded" body)
      (search "rateLimitExceeded" body)))

(defun upload (file title)
  "Upload FILE as a video named TITLE with *privacy*; return its video id."
  (let* ((size (with-open-file (s file :element-type '(unsigned-byte 8)) (file-length s)))
         (meta (jzon:stringify
                (alexandria:plist-hash-table
                 (list "snippet" (alexandria:plist-hash-table
                                  (list "title" (subseq title 0 (min 100 (length title))) "categoryId" "22")
                                  :test #'equal)
                       "status" (alexandria:plist-hash-table
                                 (list "privacyStatus" *privacy* "selfDeclaredMadeForKids" nil)
                                 :test #'equal))
                 :test #'equal)))
         (auth (uiop:strcat "Authorization: Bearer " (access-token))))
    (multiple-value-bind (body code headers)
        (curl "-X" "POST"
              "https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status"
              "-H" auth "-H" "Content-Type: application/json; charset=UTF-8"
              "-H" (format nil "X-Upload-Content-Length: ~d" size)
              "--data-binary" meta)
      (cond ((= code 200))
            ((quota-error-p body) (retry-later (next-quota-reset) "YouTube upload quota used up for today"))
            ((= code 401) (setf *access* nil) (hold 60 "access token rejected"))
            (t (error "upload session refused (~a): ~a" code body)))
      ;; ponytail: a broken PUT restarts the whole file; resume from the session's offset if uplinks are flaky
      (multiple-value-bind (body code)
          (curl "-X" "PUT" "--upload-file" (native file) "-H" auth (header headers "location"))
        (cond ((member code '(200 201)) (gethash "id" (jzon:parse body)))
              ((quota-error-p body) (retry-later (next-quota-reset) "YouTube upload quota used up for today"))
              (t (error "upload failed (~a): ~a" code body)))))))

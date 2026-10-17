(in-package :tubedrop)
;;; What happens to a dropped file: make it a video, upload it, tidy up.

(defvar *delete-source* nil "Delete the dropped file once its video is on YouTube.")

(defun ffprobe-lines (file &rest args)
  (uiop:split-string (string-trim '(#\Newline) (run (append (list "ffprobe" "-v" "error") args (list file))))
                     :separator '(#\Newline)))

(defun real-video-p (file)
  "True when FILE has a video stream that is not just embedded cover art."
  (member "0" (ffprobe-lines file "-select_streams" "v" "-show_entries" "stream_disposition=attached_pic"
                             "-of" "csv=p=0")
          :test #'string=))

(defun cover-art-p (file)
  (ffprobe-lines file "-select_streams" "v" "-show_entries" "stream=index" "-of" "csv=p=0"))

(defun title-of (job)
  "The dropped file's name without its extension."
  (let* ((f (job-get job :file)) (dot (position #\. f :from-end t)))
    (if (and dot (plusp dot)) (subseq f 0 dot) f)))

(defstage video (job)
  "audio becomes a 1 fps still-frame video (embedded cover art, else black); the audio is copied untouched"
  (let ((src (job-source job)))
    (if (real-video-p src)
        (job-put job :video (job-get job :file))
        (let ((cover (job-path job "cover.png"))
              (out (job-path job "video.mkv")))
          (if (cover-art-p src)
              (run (list "ffmpeg" "-v" "error" "-y" "-i" src "-map" "0:v:0" "-frames:v" "1" "-vf"
                         "scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2"
                         cover))
              (run (list "ffmpeg" "-v" "error" "-y" "-f" "lavfi" "-i" "color=black:s=1280x720"
                         "-frames:v" "1" cover)))
          (run (list "ffmpeg" "-v" "error" "-y" "-loop" "1" "-framerate" "1" "-i" cover "-i" src
                     "-map" "0:v" "-map" "1:a" "-c:v" "libx264" "-tune" "stillimage" "-pix_fmt" "yuv420p"
                     "-c:a" "copy" "-shortest" out))
          (delete-file cover)
          (job-put job :video "video.mkv")))))

(defstage upload (job)
  "the video goes to YouTube (private by default); its id lands in the job record"
  (let ((id (upload (job-path job (job-get job :video)) (title-of job))))
    (job-put job :video-id id :url (uiop:strcat "https://youtu.be/" id))
    (log-line "~a: uploaded https://youtu.be/~a" (job-name job) id)))

(defstage tidy (job)
  "delete the made video; with --delete-source, the dropped file too"
  (let ((made (job-path job "video.mkv")))
    (when (probe-file made) (delete-file made)))
  (when *delete-source*
    (let ((src (job-source job))) (when (probe-file src) (delete-file src)))))

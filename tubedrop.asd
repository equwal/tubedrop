(asdf:defsystem "tubedrop"
  :description "Drop audio files in a folder or a web page; each one goes to YouTube as a private video."
  :license "CCAI-1.0"
  :depends-on ("dropin" "alexandria" "hunchentoot" "com.inuoe.jzon")
  :serial t
  :components ((:module "src"
                :components ((:file "package")
                             (:file "youtube")
                             (:file "stages")
                             (:file "web")
                             (:file "main")))))

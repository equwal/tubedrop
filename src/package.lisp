(defpackage :tubedrop
  (:use :cl :dropin)
  (:shadow #:main)                        ; tubedrop:main sets up, then calls dropin:main
  (:local-nicknames (:jzon :com.inuoe.jzon))
  (:export #:main))

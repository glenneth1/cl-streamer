(asdf:defsystem #:cl-streamer
  :description "Common Lisp audio streaming server for Asteroid Radio"
  :author "Glenn Thompson <glenn@asteroid.radio>"
  :license "AGPL-3.0"
  :version "0.1.0"
  :serial t
  :depends-on (#:alexandria
               #:bordeaux-threads
               #:iolib
               #:flexi-streams
               #:split-sequence
               #:log4cl)
  :components ((:file "package")
               (:file "conditions")
               (:file "buffer")
               (:file "icy-protocol")
               (:file "stream-server")
               (:file "cl-streamer")
               (:file "protocol")))

(asdf:defsystem #:cl-streamer/harmony
  :description "Harmony audio backend for cl-streamer"
  :depends-on (#:cl-streamer
               #:harmony
               #:cl-mixed
               #:cl-mixed-mpg123
               #:cl-mixed-flac
               #:taglib)
  :components ((:file "harmony-backend")))

(asdf:defsystem #:cl-streamer/encoder
  :description "Audio encoding for cl-streamer (LAME MP3)"
  :depends-on (#:cl-streamer
               #:cffi)
  :components ((:file "lame-ffi")
               (:file "encoder")))

(asdf:defsystem #:cl-streamer/aac-encoder
  :description "AAC encoding for cl-streamer (FDK-AAC)"
  :depends-on (#:cl-streamer
               #:cffi)
  :components ((:file "fdkaac-ffi")
               (:file "aac-encoder")))

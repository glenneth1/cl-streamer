;;; End-to-end streaming test with playlist (MP3 + AAC)
;;; Usage: sbcl --load test-stream.lisp
;;;
;;; Then open in VLC or browser:
;;;   http://localhost:8000/stream.mp3  (MP3 128kbps)
;;;   http://localhost:8000/stream.aac  (AAC 128kbps)
;;; ICY metadata will show track names as they change.

(push #p"/home/glenn/SourceCode/harmony/" asdf:*central-registry*)
(push #p"/home/glenn/SourceCode/asteroid/cl-streamer/" asdf:*central-registry*)

(ql:quickload '(:cl-streamer :cl-streamer/encoder :cl-streamer/aac-encoder :cl-streamer/harmony))

(format t "~%=== CL-Streamer Playlist Test (MP3 + AAC) ===~%")
(format t "LAME version: ~A~%" (cl-streamer::lame-version))

;; 1. Create and start stream server
(format t "~%[1] Starting stream server on port 8000...~%")
(cl-streamer:start :port 8000)

;; 2. Add mount points
(format t "[2] Adding mount points...~%")
(cl-streamer:add-mount cl-streamer:*server* "/stream.mp3"
                       :content-type "audio/mpeg"
                       :bitrate 128
                       :name "Asteroid Radio MP3")
(cl-streamer:add-mount cl-streamer:*server* "/stream.aac"
                       :content-type "audio/aac"
                       :bitrate 128
                       :name "Asteroid Radio AAC")

;; 3. Create encoders
(format t "[3] Creating encoders...~%")
(defvar *mp3-encoder* (cl-streamer:make-mp3-encoder :sample-rate 44100
                                                     :channels 2
                                                     :bitrate 128))
(defvar *aac-encoder* (cl-streamer:make-aac-encoder :sample-rate 44100
                                                     :channels 2
                                                     :bitrate 128000))

;; 4. Create and start audio pipeline with both outputs
(format t "[4] Starting audio pipeline with Harmony (MP3 + AAC)...~%")
(defvar *pipeline* (cl-streamer/harmony:make-audio-pipeline
                    :encoder *mp3-encoder*
                    :stream-server cl-streamer:*server*
                    :mount-path "/stream.mp3"
                    :sample-rate 44100
                    :channels 2))

;; Add AAC as second output
(cl-streamer/harmony:add-pipeline-output *pipeline* *aac-encoder* "/stream.aac")

(cl-streamer/harmony:start-pipeline *pipeline*)

;; 5. Build a playlist from the music library
(format t "[5] Building playlist from music library...~%")
(defvar *music-dir* #p"/home/glenn/SourceCode/asteroid/music/library/")

(defvar *playlist*
  (let ((files nil))
    (dolist (dir (directory (merge-pathnames "*/" *music-dir*)))
      (dolist (flac (directory (merge-pathnames "**/*.flac" dir)))
        (push (list :file (namestring flac)) files)))
    ;; Shuffle and take first 10 tracks
    (subseq (alexandria:shuffle (copy-list files))
            0 (min 10 (length files)))))

(format t "Queued ~A tracks:~%" (length *playlist*))
(dolist (entry *playlist*)
  (format t "  ~A~%" (getf entry :file)))

;; 6. Start playlist playback
(format t "~%[6] Starting playlist...~%")
(cl-streamer/harmony:play-list *pipeline* *playlist*
                               :crossfade-duration 3.0
                               :fade-in 2.0
                               :fade-out 2.0)

(format t "~%=== Stream is live! ===~%")
(format t "MP3: http://localhost:8000/stream.mp3~%")
(format t "AAC: http://localhost:8000/stream.aac~%")
(format t "~%Press Enter to stop...~%")

(read-line)

;; Cleanup
(format t "Stopping...~%")
(cl-streamer/harmony:stop-pipeline *pipeline*)
(cl-streamer:close-encoder *mp3-encoder*)
(cl-streamer:close-aac-encoder *aac-encoder*)
(cl-streamer:stop)
(format t "Done.~%")

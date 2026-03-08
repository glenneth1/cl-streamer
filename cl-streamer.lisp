(in-package #:cl-streamer)

(defun write-audio-data (server mount-path data &key (start 0) (end (length data)))
  "Write audio data to a mount point's buffer.
   SERVER is the stream-server instance.
   This is called by the audio pipeline to feed encoded audio."
  (let ((mount (gethash mount-path (server-mounts server))))
    (when mount
      (buffer-write (mount-buffer mount) data :start start :end end))))

(defun set-now-playing (server mount-path title &optional url)
  "Update the now-playing metadata for a mount point.
   SERVER is the stream-server instance."
  (update-metadata server mount-path :title title :url url))

(defun get-listener-count (server &optional mount-path)
  "Get the current listener count.
   SERVER is the stream-server instance."
  (listener-count server mount-path))

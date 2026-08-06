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

(defun get-metadata-changed-at (server mount-path)
  "Return the epoch milliseconds when the metadata was last updated for MOUNT-PATH.
The client uses this plus its known buffer lag to schedule UI updates."
  (let ((mount (gethash mount-path (server-mounts server))))
    (when mount
      (bt:with-lock-held ((mount-metadata-lock mount))
        (let ((timeline (mount-metadata-timeline mount)))
          (when timeline
            ;; Timeline entries: (buffer-pos . (unix-time . metadata))
            ;; Use the wall-clock unix timestamp directly.
            ;; get-universal-time returns seconds since 1900-01-01;
            ;; subtract 2208988800 to convert to Unix epoch (1970-01-01),
            ;; then multiply by 1000 for milliseconds.
            (let ((unix-time (cadar timeline)))
              (when unix-time
                (* 1000 (- unix-time 2208988800))))))))))

(defun get-listener-count (server &optional mount-path)
  "Get the current listener count.
   SERVER is the stream-server instance."
  (listener-count server mount-path))

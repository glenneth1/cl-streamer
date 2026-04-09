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

(defparameter *browser-buffer-seconds* 10
  "Estimated seconds of delay between server-side track change and listener
hearing it. Includes ring buffer burst, encode latency, and browser decode
buffer. Measured empirically: 5s gave ~23s early, 23s gave ~14s late.
Settling on 10s as best estimate. The now-playing API delays reporting
the new title by this amount.")

(defun get-listener-now-playing (server mount-path)
  "Return the title that a typical listener is currently hearing.
Uses a time-based delay: after a metadata update, the API continues
returning the previous title for *browser-buffer-seconds* to account
for the browser's internal audio buffer."
  (let ((mount (gethash mount-path (server-mounts server))))
    (when mount
      (bt:with-lock-held ((mount-metadata-lock mount))
        (let* ((timeline (mount-metadata-timeline mount))
               (now (get-internal-real-time))
               (delay-ticks (* *browser-buffer-seconds*
                               internal-time-units-per-second)))
          ;; Timeline is newest-first. Find the most recent entry that is
          ;; old enough for the listener to have heard it.
          (dolist (entry timeline)
            (let ((timestamp (car entry))
                  (meta (cdr entry)))
              (when (>= (- now timestamp) delay-ticks)
                (return-from get-listener-now-playing
                  (icy-metadata-title meta)))))
          ;; No entry old enough — return the oldest entry if any
          (when timeline
            (icy-metadata-title (cdar (last timeline)))))))))

(defun get-listener-count (server &optional mount-path)
  "Get the current listener count.
   SERVER is the stream-server instance."
  (listener-count server mount-path))

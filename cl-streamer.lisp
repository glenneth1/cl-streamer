(in-package #:cl-streamer)

(defvar *server* nil
  "The global stream server instance.")

(defun ensure-server (&key (port *default-port*))
  "Ensure a server instance exists, creating one if needed."
  (unless *server*
    (setf *server* (make-stream-server :port port)))
  *server*)

(defun start (&key (port *default-port*))
  "Start the streaming server with default configuration."
  (let ((server (ensure-server :port port)))
    (start-server server)))

(defun stop ()
  "Stop the streaming server."
  (when *server*
    (stop-server *server*)))

(defun write-audio-data (mount-path data &key (start 0) (end (length data)))
  "Write audio data to a mount point's buffer.
   This is called by the audio pipeline to feed encoded audio."
  (let* ((server (ensure-server))
         (mount (gethash mount-path (server-mounts server))))
    (when mount
      (buffer-write (mount-buffer mount) data :start start :end end))))

(defun set-now-playing (mount-path title &optional url)
  "Update the now-playing metadata for a mount point."
  (let ((server (ensure-server)))
    (update-metadata server mount-path :title title :url url)))

(defun get-listener-count (&optional mount-path)
  "Get the current listener count."
  (let ((server (ensure-server)))
    (listener-count server mount-path)))

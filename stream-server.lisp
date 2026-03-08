(in-package #:cl-streamer)

(defparameter *default-port* 8000
  "Default port for the streaming server.")

(defparameter *client-write-timeout* 30
  "Seconds before a stale client write is abandoned.")

(defclass stream-server ()
  ((port :initarg :port :accessor server-port :initform *default-port*)
   (socket :initform nil :accessor server-socket)
   (running :initform nil :accessor server-running-p)
   (mounts :initform (make-hash-table :test 'equal) :accessor server-mounts)
   (clients :initform nil :accessor server-clients)
   (clients-lock :initform (bt:make-lock "clients-lock") :reader server-clients-lock)
   (accept-thread :initform nil :accessor server-accept-thread)))

(defclass mount-point ()
  ((path :initarg :path :accessor mount-path)
   (content-type :initarg :content-type :accessor mount-content-type
                 :initform "audio/mpeg")
   (bitrate :initarg :bitrate :accessor mount-bitrate :initform 128)
   (name :initarg :name :accessor mount-name :initform "CL-Streamer")
   (genre :initarg :genre :accessor mount-genre :initform "Various")
   (buffer :initarg :buffer :accessor mount-buffer)
   (metadata :initform (make-icy-metadata) :accessor mount-metadata)
   (metadata-lock :initform (bt:make-lock "metadata-lock") :reader mount-metadata-lock)))

(defclass client-connection ()
  ((socket :initarg :socket :accessor client-socket)
   (stream :initarg :stream :accessor client-stream)
   (mount :initarg :mount :accessor client-mount)
   (wants-metadata :initarg :wants-metadata :accessor client-wants-metadata-p)
   (bytes-since-meta :initform 0 :accessor client-bytes-since-meta)
   (read-pos :initform 0 :accessor client-read-pos
             :documentation "Client's absolute position in the broadcast buffer")
   (thread :initform nil :accessor client-thread)
   (active :initform t :accessor client-active-p)))

(defun make-stream-server (&key (port *default-port*))
  "Create a new stream server instance."
  (make-instance 'stream-server :port port))

(defun add-mount (server path &key (content-type "audio/mpeg")
                                   (bitrate 128)
                                   (name "CL-Streamer")
                                   (genre "Various")
                                   (buffer-size (* 1024 1024)))
  "Add a mount point to the server."
  (let ((mount (make-instance 'mount-point
                              :path path
                              :content-type content-type
                              :bitrate bitrate
                              :name name
                              :genre genre
                              :buffer (make-ring-buffer buffer-size))))
    (setf (gethash path (server-mounts server)) mount)
    mount))

(defun remove-mount (server path)
  "Remove a mount point from the server."
  (remhash path (server-mounts server)))

(defun update-metadata (server path &key title url)
  "Update the metadata for a mount point."
  (let ((mount (gethash path (server-mounts server))))
    (when mount
      (bt:with-lock-held ((mount-metadata-lock mount))
        (let ((meta (mount-metadata mount)))
          (when title (setf (icy-metadata-title meta) title))
          (when url (setf (icy-metadata-url meta) url)))))))

(defun listener-count (server &optional path)
  "Return the number of connected listeners.
   If PATH is specified, count only listeners on that mount."
  (bt:with-lock-held ((server-clients-lock server))
    (if path
        (count-if (lambda (c) (and (client-active-p c)
                                   (string= path (mount-path (client-mount c)))))
                  (server-clients server))
        (count-if #'client-active-p (server-clients server)))))

(defun configure-client-socket (socket)
  "Set socket options on an accepted client connection.
   Enables SO_KEEPALIVE for stale connection detection and
   TCP_NODELAY for low-latency streaming."
  (setf (iolib:socket-option socket :keep-alive) t)
  (setf (iolib:socket-option socket :tcp-nodelay) t)
  ;; SO_SNDTIMEO for write timeout — detect stale clients
  (setf (iolib:socket-option socket :send-timeout) *client-write-timeout*))

(defun start-server (server)
  "Start the streaming server."
  (when (server-running-p server)
    (error 'streamer-error :message "Server already running"))
  (setf (server-socket server)
        (iolib:make-socket :connect :passive
                           :address-family :internet
                           :type :stream
                           :local-host "0.0.0.0"
                           :local-port (server-port server)
                           :reuse-address t
                           :backlog 128))
  (setf (server-running-p server) t)
  (setf (server-accept-thread server)
        (bt:make-thread (lambda () (accept-loop server))
                        :name "cl-streamer-accept"))
  (log:info "CL-Streamer started on port ~A" (server-port server))
  server)

(defun stop-server (server)
  "Stop the streaming server."
  (setf (server-running-p server) nil)
  (bt:with-lock-held ((server-clients-lock server))
    (dolist (client (server-clients server))
      (setf (client-active-p client) nil)
      (ignore-errors (close (client-socket client)))))
  (ignore-errors (close (server-socket server)))
  (log:info "CL-Streamer stopped")
  server)

(defun accept-loop (server)
  "Main accept loop for incoming connections."
  (loop while (server-running-p server)
        do (handler-case
               (let ((client-socket (iolib:accept-connection (server-socket server))))
                 (handler-case
                     (configure-client-socket client-socket)
                   (error (e)
                     (log:debug "Socket option error: ~A" e)))
                 (bt:make-thread (lambda () (handle-client server client-socket))
                                 :name "cl-streamer-client"))
             (iolib:socket-connection-aborted-error ()
               ;; Client disconnected before we accepted — skip
               nil)
             (error (e)
               (unless (server-running-p server)
                 (return))
               (log:warn "Accept error: ~A" e)))))

(defun handle-client (server client-socket)
  "Handle a single client connection.
   The iolib socket is a dual-channel gray stream supporting both
   binary and character I/O."
  (let ((stream (flexi-streams:make-flexi-stream
                 client-socket
                 :external-format :latin-1)))
    (handler-case
        (let* ((request-line (read-line stream))
               (headers (read-http-headers stream))
               (method (first (split-sequence:split-sequence #\Space request-line))))
          ;; Handle CORS preflight
          (when (string-equal method "OPTIONS")
            (send-cors-preflight stream)
            (ignore-errors (close client-socket))
            (return-from handle-client))
          (multiple-value-bind (path wants-meta)
              (parse-icy-request request-line headers)
            (let ((mount (gethash path (server-mounts server))))
              (if mount
                  (serve-stream server client-socket stream mount wants-meta)
                  (progn
                    (log:debug "404 for path: ~A" path)
                    (send-404 stream path))))))
      (error (e)
        (log:debug "Client error: ~A" e)
        (ignore-errors (close client-socket))))))

(defun read-http-headers (stream)
  "Read HTTP headers from STREAM. Returns alist of (name . value)."
  (loop for line = (read-line stream nil nil)
        while (and line (> (length line) 1))
        for colon-pos = (position #\: line)
        when colon-pos
          collect (cons (string-trim '(#\Space #\Return) (subseq line 0 colon-pos))
                        (string-trim '(#\Space #\Return) (subseq line (1+ colon-pos))))))

(defun serve-stream (server client-socket stream mount wants-meta)
  "Serve audio stream to a client."
  (let ((client (make-instance 'client-connection
                               :socket client-socket
                               :stream stream
                               :mount mount
                               :wants-metadata wants-meta)))
    (bt:with-lock-held ((server-clients-lock server))
      (push client (server-clients server)))
    (log:info "Client connected to ~A (metadata: ~A)"
              (mount-path mount) wants-meta)
    (write-icy-response-headers stream
                                :content-type (mount-content-type mount)
                                :metaint (when wants-meta *default-metaint*)
                                :name (mount-name mount)
                                :genre (mount-genre mount)
                                :bitrate (mount-bitrate mount))
    (unwind-protect
         (stream-to-client client)
      (setf (client-active-p client) nil)
      (ignore-errors (close client-socket))
      (bt:with-lock-held ((server-clients-lock server))
        (setf (server-clients server)
              (remove client (server-clients server))))
      (log:info "Client disconnected from ~A" (mount-path mount)))))

(defun stream-to-client (client)
  "Stream audio data to a client from the broadcast buffer.
   Starts with a burst of recent data for fast playback start."
  (let* ((mount (client-mount client))
         (buffer (mount-buffer mount))
         (stream (client-stream client))
         (chunk-size 4096)
         (chunk (make-array chunk-size :element-type '(unsigned-byte 8))))
    ;; For MP3, burst recent data for fast playback start.
    ;; For AAC, start from current position — AAC requires ADTS frame alignment
    ;; and burst data from mid-stream causes browser decode errors.
    (setf (client-read-pos client)
          (if (string= (mount-content-type mount) "audio/aac")
              (buffer-current-pos buffer)
              (buffer-burst-start buffer)))
    (loop while (client-active-p client)
          do (multiple-value-bind (bytes-read new-pos)
                 (buffer-read-from buffer (client-read-pos client) chunk)
               (if (zerop bytes-read)
                   ;; No data yet — wait for producer
                   (buffer-wait-for-data buffer (client-read-pos client))
                   (progn
                     (setf (client-read-pos client) new-pos)
                     (handler-case
                         (progn
                           (if (client-wants-metadata-p client)
                               (write-with-metadata client chunk bytes-read)
                               (write-sequence chunk stream :end bytes-read))
                           (force-output stream))
                       (iolib:socket-connection-reset-error ()
                         (setf (client-active-p client) nil)
                         (return))
                       (isys:ewouldblock ()
                         ;; Write timeout — stale client
                         (log:warn "Write timeout on ~A, disconnecting stale client"
                                   (mount-path mount))
                         (setf (client-active-p client) nil)
                         (return))
                       (error (e)
                         (log:warn "Client stream error on ~A: ~A" 
                                   (mount-path mount) e)
                         (setf (client-active-p client) nil)
                         (return)))))))))

(defun write-with-metadata (client data length)
  "Write audio data with ICY metadata injection."
  (let* ((stream (client-stream client))
         (mount (client-mount client))
         (metaint *default-metaint*)
         (pos 0))
    (loop while (< pos length)
          do (let ((bytes-until-meta (- metaint (client-bytes-since-meta client)))
                   (bytes-remaining (- length pos)))
               (if (<= bytes-until-meta bytes-remaining)
                   (progn
                     (write-sequence data stream :start pos :end (+ pos bytes-until-meta))
                     (incf pos bytes-until-meta)
                     (setf (client-bytes-since-meta client) 0)
                     (let ((meta-bytes (bt:with-lock-held ((mount-metadata-lock mount))
                                         (encode-icy-metadata (mount-metadata mount)))))
                       (write-sequence meta-bytes stream)))
                   (progn
                     (write-sequence data stream :start pos :end length)
                     (incf (client-bytes-since-meta client) bytes-remaining)
                     (setf pos length)))))))

(defun send-cors-preflight (stream)
  "Send a CORS preflight response for OPTIONS requests."
  (format stream "HTTP/1.1 204 No Content~C~C" #\Return #\Linefeed)
  (format stream "Access-Control-Allow-Origin: *~C~C" #\Return #\Linefeed)
  (format stream "Access-Control-Allow-Methods: GET, OPTIONS~C~C" #\Return #\Linefeed)
  (format stream "Access-Control-Allow-Headers: Origin, Accept, Content-Type, Icy-MetaData, Range~C~C" #\Return #\Linefeed)
  (format stream "Access-Control-Max-Age: 86400~C~C" #\Return #\Linefeed)
  (format stream "~C~C" #\Return #\Linefeed)
  (force-output stream))

(defun send-404 (stream path)
  "Send a 404 response for unknown mount points."
  (format stream "HTTP/1.1 404 Not Found~C~C" #\Return #\Linefeed)
  (format stream "Content-Type: text/plain~C~C" #\Return #\Linefeed)
  (format stream "~C~C" #\Return #\Linefeed)
  (format stream "Mount point not found: ~A~%" path)
  (force-output stream))

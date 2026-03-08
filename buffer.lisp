(in-package #:cl-streamer)

;;; ---- Broadcast Ring Buffer ----
;;; Single-producer, multi-consumer circular buffer.
;;; The writer advances write-pos; each client has its own read cursor.
;;; Old data is overwritten when the buffer wraps — slow clients lose data
;;; rather than blocking the producer (appropriate for live streaming).

(defclass broadcast-buffer ()
  ((data :initarg :data :accessor buffer-data)
   (size :initarg :size :reader buffer-size)
   (write-pos :initform 0 :accessor buffer-write-pos)
   (lock :initform (bt:make-lock "broadcast-buffer-lock") :reader buffer-lock)
   (not-empty :initform (bt:make-condition-variable :name "buffer-not-empty")
              :reader buffer-not-empty)
   (burst-size :initarg :burst-size :reader buffer-burst-size
               :initform (* 64 1024)
               :documentation "Bytes of recent data to send on new client connect")))

(defun make-ring-buffer (size)
  "Create a broadcast ring buffer with SIZE bytes capacity."
  (make-instance 'broadcast-buffer
                 :data (make-array size :element-type '(unsigned-byte 8))
                 :size size))

(defun buffer-write (buffer data &key (start 0) (end (length data)))
  "Write bytes into the broadcast buffer. Never blocks; overwrites old data."
  (let ((len (- end start)))
    (when (> len 0)
      (bt:with-lock-held ((buffer-lock buffer))
        (let ((write-pos (buffer-write-pos buffer))
              (size (buffer-size buffer))
              (buf-data (buffer-data buffer)))
          (loop for i from start below end
                for j = (mod write-pos size) then (mod (1+ j) size)
                do (setf (aref buf-data j) (aref data i))
                finally (setf (buffer-write-pos buffer) (+ write-pos len))))
        (bt:condition-notify (buffer-not-empty buffer))))
    len))

(defun buffer-read-from (buffer read-pos output &key (start 0) (end (length output)))
  "Read bytes from BUFFER starting at READ-POS into OUTPUT.
   Returns (values bytes-read new-read-pos).
   READ-POS is the client's absolute position in the stream."
  (let ((requested (- end start)))
    (bt:with-lock-held ((buffer-lock buffer))
      (let* ((write-pos (buffer-write-pos buffer))
             (size (buffer-size buffer))
             (buf-data (buffer-data buffer))
             ;; Clamp read-pos: if client is too far behind, skip ahead
             (oldest-available (max 0 (- write-pos size)))
             (effective-read (max read-pos oldest-available))
             (available (- write-pos effective-read))
             (to-read (min requested available)))
        (if (> to-read 0)
            (progn
              (loop for i from start below (+ start to-read)
                    for j = (mod effective-read size) then (mod (1+ j) size)
                    do (setf (aref output i) (aref buf-data j)))
              (values to-read (+ effective-read to-read)))
            (values 0 effective-read))))))

(defun buffer-wait-for-data (buffer read-pos)
  "Block until new data is available past READ-POS."
  (bt:with-lock-held ((buffer-lock buffer))
    (loop while (<= (buffer-write-pos buffer) read-pos)
          do (bt:condition-wait (buffer-not-empty buffer) (buffer-lock buffer)))))

(defun buffer-current-pos (buffer)
  "Return the current write position (for new client burst start)."
  (bt:with-lock-held ((buffer-lock buffer))
    (buffer-write-pos buffer)))

(defun buffer-burst-start (buffer)
  "Return a read position that gives BURST-SIZE bytes of recent data.
   This lets new clients start playing immediately."
  (bt:with-lock-held ((buffer-lock buffer))
    (let* ((write-pos (buffer-write-pos buffer))
           (size (buffer-size buffer))
           (oldest (max 0 (- write-pos size)))
           (burst-start (max oldest (- write-pos (buffer-burst-size buffer)))))
      burst-start)))

(defun buffer-clear (buffer)
  "Clear the buffer."
  (bt:with-lock-held ((buffer-lock buffer))
    (setf (buffer-write-pos buffer) 0)))

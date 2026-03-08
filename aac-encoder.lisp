(in-package #:cl-streamer)

(defclass aac-encoder ()
  ((handle :initform nil :accessor encoder-handle)
   (sample-rate :initarg :sample-rate :accessor aac-encoder-sample-rate :initform 44100)
   (channels :initarg :channels :accessor aac-encoder-channels :initform 2)
   (bitrate :initarg :bitrate :accessor aac-encoder-bitrate :initform 128000)
   (aot :initarg :aot :accessor aac-encoder-aot :initform :aot-aac-lc)
   (out-buffer :initform nil :accessor aac-encoder-out-buffer)
   (out-buffer-size :initform (* 1024 8) :accessor aac-encoder-out-buffer-size)
   (frame-length :initform 1024 :accessor aac-encoder-frame-length)
   (pcm-accum :initform nil :accessor aac-encoder-pcm-accum
              :documentation "Accumulation buffer for PCM samples (signed-byte 16), frame-length * channels elements.")
   (pcm-accum-pos :initform 0 :accessor aac-encoder-pcm-accum-pos
                  :documentation "Number of samples currently accumulated.")))

(defun make-aac-encoder (&key (sample-rate 44100) (channels 2) (bitrate 128000))
  "Create an AAC encoder with the specified parameters.
   BITRATE is in bits per second (e.g., 128000 for 128kbps)."
  (let ((encoder (make-instance 'aac-encoder
                                :sample-rate sample-rate
                                :channels channels
                                :bitrate bitrate)))
    (initialize-aac-encoder encoder)
    encoder))

(defun initialize-aac-encoder (encoder)
  "Initialize the FDK-AAC encoder with current settings.
   Uses C shim to avoid SBCL signal handler conflicts with FDK-AAC."
  (cffi:with-foreign-objects ((handle-ptr :pointer)
                              (frame-length-ptr :int)
                              (max-out-bytes-ptr :int))
    (let ((result (fdkaac-open-and-init handle-ptr
                                        (aac-encoder-sample-rate encoder)
                                        (aac-encoder-channels encoder)
                                        (aac-encoder-bitrate encoder)
                                        2   ; AOT: AAC-LC
                                        2   ; TRANSMUX: ADTS
                                        1   ; AFTERBURNER: on
                                        frame-length-ptr
                                        max-out-bytes-ptr)))
      (unless (zerop result)
        (error 'encoding-error :format :aac
                               :message (format nil "fdkaac_open_and_init failed: ~A" result)))
      (setf (encoder-handle encoder) (cffi:mem-ref handle-ptr :pointer))
      (setf (aac-encoder-frame-length encoder) (cffi:mem-ref frame-length-ptr :int))
      (setf (aac-encoder-out-buffer-size encoder) (cffi:mem-ref max-out-bytes-ptr :int))))
  (setf (aac-encoder-out-buffer encoder)
        (cffi:foreign-alloc :unsigned-char :count (aac-encoder-out-buffer-size encoder)))
  ;; Initialize PCM accumulation buffer (frame-length * channels samples)
  (let ((accum-size (* (aac-encoder-frame-length encoder)
                       (aac-encoder-channels encoder))))
    (setf (aac-encoder-pcm-accum encoder)
          (make-array accum-size :element-type '(signed-byte 16) :initial-element 0))
    (setf (aac-encoder-pcm-accum-pos encoder) 0))
  (log:info "AAC encoder initialized: ~Akbps, ~AHz, ~A channels, frame-length=~A"
            (floor (aac-encoder-bitrate encoder) 1000)
            (aac-encoder-sample-rate encoder)
            (aac-encoder-channels encoder)
            (aac-encoder-frame-length encoder))
  encoder)

(defun close-aac-encoder (encoder)
  "Close the AAC encoder and free resources."
  (when (encoder-handle encoder)
    (cffi:with-foreign-object (handle-ptr :pointer)
      (setf (cffi:mem-ref handle-ptr :pointer) (encoder-handle encoder))
      (fdkaac-close handle-ptr))
    (setf (encoder-handle encoder) nil))
  (when (aac-encoder-out-buffer encoder)
    (cffi:foreign-free (aac-encoder-out-buffer encoder))
    (setf (aac-encoder-out-buffer encoder) nil)))

(defun encode-one-aac-frame (encoder)
  "Encode a single frame from the accumulation buffer.
   Returns a byte vector of AAC data, or an empty vector."
  (let* ((handle (encoder-handle encoder))
         (channels (aac-encoder-channels encoder))
         (frame-length (aac-encoder-frame-length encoder))
         (accum (aac-encoder-pcm-accum encoder))
         (out-buf (aac-encoder-out-buffer encoder))
         (out-buf-size (aac-encoder-out-buffer-size encoder))
         (total-samples (* frame-length channels))
         (pcm-bytes (* total-samples 2)))
    (cffi:with-pointer-to-vector-data (pcm-ptr accum)
      (cffi:with-foreign-object (bytes-written-ptr :int)
        (let ((result (fdkaac-encode handle pcm-ptr pcm-bytes total-samples
                                     out-buf out-buf-size bytes-written-ptr)))
          (unless (zerop result)
            (error 'encoding-error :format :aac
                                   :message (format nil "aacEncEncode failed: ~A" result)))
          (let ((bytes-written (cffi:mem-ref bytes-written-ptr :int)))
            (if (> bytes-written 0)
                (let ((result-vec (make-array bytes-written :element-type '(unsigned-byte 8))))
                  (loop for i below bytes-written
                        do (setf (aref result-vec i) (cffi:mem-aref out-buf :unsigned-char i)))
                  result-vec)
                (make-array 0 :element-type '(unsigned-byte 8)))))))))

(defun encode-aac-pcm (encoder pcm-samples num-samples)
  "Encode PCM samples (16-bit signed interleaved) to AAC.
   Accumulates samples and encodes in exact frame-length chunks.
   Returns a byte vector of AAC data (ADTS frames).
   Uses C shim to avoid SBCL signal handler conflicts."
  (let* ((channels (aac-encoder-channels encoder))
         (frame-samples (* (aac-encoder-frame-length encoder) channels))
         (accum (aac-encoder-pcm-accum encoder))
         (input-total (* num-samples channels))
         (input-pos 0)
         (output-chunks nil))
    ;; Copy input samples into accumulation buffer, encoding whenever full
    (loop while (< input-pos input-total)
          for space-left = (- frame-samples (aac-encoder-pcm-accum-pos encoder))
          for copy-count = (min space-left (- input-total input-pos))
          do (replace accum pcm-samples
                     :start1 (aac-encoder-pcm-accum-pos encoder)
                     :end1 (+ (aac-encoder-pcm-accum-pos encoder) copy-count)
                     :start2 input-pos
                     :end2 (+ input-pos copy-count))
             (incf (aac-encoder-pcm-accum-pos encoder) copy-count)
             (incf input-pos copy-count)
             ;; When accumulation buffer is full, encode one frame
             (when (= (aac-encoder-pcm-accum-pos encoder) frame-samples)
               (let ((encoded (encode-one-aac-frame encoder)))
                 (when (> (length encoded) 0)
                   (push encoded output-chunks)))
               (setf (aac-encoder-pcm-accum-pos encoder) 0)))
    ;; Concatenate all encoded chunks into one result vector
    (if (null output-chunks)
        (make-array 0 :element-type '(unsigned-byte 8))
        (let* ((total-bytes (reduce #'+ output-chunks :key #'length))
               (result (make-array total-bytes :element-type '(unsigned-byte 8)))
               (pos 0))
          (dolist (chunk (nreverse output-chunks))
            (replace result chunk :start1 pos)
            (incf pos (length chunk)))
          result))))

;;; ---- Protocol Methods ----

(defmethod encoder-encode ((encoder aac-encoder) pcm-buffer num-samples)
  (encode-aac-pcm encoder pcm-buffer num-samples))

(defmethod encoder-close ((encoder aac-encoder))
  (close-aac-encoder encoder))

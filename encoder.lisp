(in-package #:cl-streamer)

(defclass mp3-encoder ()
  ((lame :initform nil :accessor encoder-lame)
   (sample-rate :initarg :sample-rate :accessor encoder-sample-rate :initform 44100)
   (channels :initarg :channels :accessor encoder-channels :initform 2)
   (bitrate :initarg :bitrate :accessor encoder-bitrate :initform 128)
   (quality :initarg :quality :accessor encoder-quality :initform 5)
   (mp3-buffer :initform nil :accessor encoder-mp3-buffer)
   (mp3-buffer-size :initform (* 1024 8) :accessor encoder-mp3-buffer-size)))

(defun make-mp3-encoder (&key (sample-rate 44100) (channels 2) (bitrate 128) (quality 5))
  "Create an MP3 encoder with the specified parameters.
   QUALITY: 0=best/slowest, 9=worst/fastest. 5 is good default."
  (let ((encoder (make-instance 'mp3-encoder
                                :sample-rate sample-rate
                                :channels channels
                                :bitrate bitrate
                                :quality quality)))
    (initialize-encoder encoder)
    encoder))

(defun initialize-encoder (encoder)
  "Initialize the LAME encoder with current settings."
  (let ((lame (lame-init)))
    (when (cffi:null-pointer-p lame)
      (error 'encoding-error :format :mp3 :message "Failed to initialize LAME"))
    (setf (encoder-lame encoder) lame)
    (lame-set-in-samplerate lame (encoder-sample-rate encoder))
    (lame-set-out-samplerate lame (encoder-sample-rate encoder))
    (lame-set-num-channels lame (encoder-channels encoder))
    (lame-set-mode lame (if (= (encoder-channels encoder) 1) :mono :joint-stereo))
    (lame-set-brate lame (encoder-bitrate encoder))
    (lame-set-quality lame (encoder-quality encoder))
    (lame-set-vbr lame :vbr-off)
    (let ((result (lame-init-params lame)))
      (when (< result 0)
        (lame-close lame)
        (error 'encoding-error :format :mp3
                               :message (format nil "LAME init-params failed: ~A" result))))
    (setf (encoder-mp3-buffer encoder)
          (cffi:foreign-alloc :unsigned-char :count (encoder-mp3-buffer-size encoder)))
    (log:info "MP3 encoder initialized: ~Akbps, ~AHz, ~A channels"
              (encoder-bitrate encoder)
              (encoder-sample-rate encoder)
              (encoder-channels encoder))
    encoder))

(defun close-encoder (encoder)
  "Close the encoder and free resources."
  (when (encoder-lame encoder)
    (lame-close (encoder-lame encoder))
    (setf (encoder-lame encoder) nil))
  (when (encoder-mp3-buffer encoder)
    (cffi:foreign-free (encoder-mp3-buffer encoder))
    (setf (encoder-mp3-buffer encoder) nil)))

(defun encode-pcm-interleaved (encoder pcm-samples num-samples)
  "Encode interleaved PCM samples (16-bit signed) to MP3.
   PCM-SAMPLES should be a (simple-array (signed-byte 16) (*)).
   Returns a byte vector of MP3 data."
  (let* ((lame (encoder-lame encoder))
         (mp3-buf (encoder-mp3-buffer encoder))
         (mp3-buf-size (encoder-mp3-buffer-size encoder)))
    (cffi:with-pointer-to-vector-data (pcm-ptr pcm-samples)
      (let ((bytes-written (lame-encode-buffer-interleaved
                            lame pcm-ptr num-samples mp3-buf mp3-buf-size)))
        (cond
          ((< bytes-written 0)
           (error 'encoding-error :format :mp3
                                  :message (format nil "Encode failed: ~A" bytes-written)))
          ((= bytes-written 0)
           (make-array 0 :element-type '(unsigned-byte 8)))
          (t
           (let ((result (make-array bytes-written :element-type '(unsigned-byte 8))))
             (loop for i below bytes-written
                   do (setf (aref result i) (cffi:mem-aref mp3-buf :unsigned-char i)))
             result)))))))

(defun encode-flush (encoder)
  "Flush any remaining MP3 data from the encoder.
   Call this when done encoding to get final frames."
  (let* ((lame (encoder-lame encoder))
         (mp3-buf (encoder-mp3-buffer encoder))
         (mp3-buf-size (encoder-mp3-buffer-size encoder)))
    (let ((bytes-written (lame-encode-flush lame mp3-buf mp3-buf-size)))
      (if (> bytes-written 0)
          (let ((result (make-array bytes-written :element-type '(unsigned-byte 8))))
            (loop for i below bytes-written
                  do (setf (aref result i) (cffi:mem-aref mp3-buf :unsigned-char i)))
            result)
          (make-array 0 :element-type '(unsigned-byte 8))))))

(defun lame-version ()
  "Return the LAME library version string."
  (get-lame-version))

;;; ---- Protocol Methods ----

(defmethod encoder-encode ((encoder mp3-encoder) pcm-buffer num-samples)
  (encode-pcm-interleaved encoder pcm-buffer num-samples))

(defmethod encoder-flush ((encoder mp3-encoder))
  (encode-flush encoder))

(defmethod encoder-close ((encoder mp3-encoder))
  (close-encoder encoder))

;;;; protocol.lisp - Protocol definitions for cl-streamer
;;;; Defines the generic function protocol that decouples application code
;;;; from specific backend implementations (Harmony, encoders, server).
;;;;
;;;; Applications program against these generics; backends provide methods.

(in-package #:cl-streamer)

;;; ============================================================
;;; Stream Server Protocol
;;; ============================================================
;;; The stream server handles HTTP connections, mount points,
;;; ICY metadata injection, and client lifecycle.

(defgeneric server-start (server)
  (:documentation "Start the stream server, begin accepting connections."))

(defgeneric server-stop (server)
  (:documentation "Stop the stream server, disconnect all clients."))

(defgeneric server-running-p (server)
  (:documentation "Return T if the server is currently running."))

(defgeneric server-add-mount (server path &key content-type bitrate name genre buffer-size)
  (:documentation "Add a mount point to the server. Returns the mount-point object."))

(defgeneric server-remove-mount (server path)
  (:documentation "Remove a mount point from the server."))

(defgeneric server-update-metadata (server path &key title url)
  (:documentation "Update ICY metadata for a mount point."))

(defgeneric server-listener-count (server &optional path)
  (:documentation "Return the number of connected listeners.
   If PATH is given, count only listeners on that mount."))

(defgeneric server-write-audio (server mount-path data &key start end)
  (:documentation "Write encoded audio data to a mount point's broadcast buffer."))

;;; ============================================================
;;; Audio Pipeline Protocol
;;; ============================================================
;;; The pipeline connects an audio source (e.g. Harmony) to
;;; encoders and the stream server. It manages playback,
;;; queueing, crossfading, and metadata propagation.

(defgeneric pipeline-start (pipeline)
  (:documentation "Start the audio pipeline."))

(defgeneric pipeline-stop (pipeline)
  (:documentation "Stop the audio pipeline."))

(defgeneric pipeline-running-p (pipeline)
  (:documentation "Return T if the pipeline is currently running."))

(defgeneric pipeline-play-file (pipeline file-path &key title)
  (:documentation "Play a single audio file through the pipeline.
   Returns (values voice display-title track-info)."))

(defgeneric pipeline-play-list (pipeline file-list &key crossfade-duration
                                                        fade-in fade-out
                                                        loop-queue)
  (:documentation "Play a list of files sequentially with crossfading.
   Each entry can be a string (path) or plist (:file path :title title).
   Runs in a background thread."))

(defgeneric pipeline-skip (pipeline)
  (:documentation "Skip the currently playing track."))

(defgeneric pipeline-queue-files (pipeline file-entries &key position)
  (:documentation "Add file entries to the playback queue.
   POSITION is :end (append, default) or :next (prepend)."))

(defgeneric pipeline-get-queue (pipeline)
  (:documentation "Return a copy of the current playback queue."))

(defgeneric pipeline-clear-queue (pipeline)
  (:documentation "Clear the playback queue."))

(defgeneric pipeline-current-track (pipeline)
  (:documentation "Return the current track info plist, or NIL.
   Plist keys: :file :display-title :artist :title :album"))

(defgeneric pipeline-listener-count (pipeline &optional mount)
  (:documentation "Return the listener count (delegates to the server)."))

(defgeneric pipeline-update-metadata (pipeline title)
  (:documentation "Update ICY metadata on all mount points."))

;;; ============================================================
;;; Pipeline Hook Protocol
;;; ============================================================
;;; Hooks replace direct slot access for callbacks.
;;; Events: :track-change, :playlist-change

(defgeneric pipeline-add-hook (pipeline event function)
  (:documentation "Register FUNCTION to be called when EVENT occurs.
   Events:
     :track-change    — (lambda (pipeline track-info))
     :playlist-change — (lambda (pipeline playlist-path))"))

(defgeneric pipeline-remove-hook (pipeline event function)
  (:documentation "Remove FUNCTION from the hook list for EVENT."))

(defgeneric pipeline-fire-hook (pipeline event &rest args)
  (:documentation "Fire all hooks registered for EVENT with ARGS.
   Called internally by the pipeline implementation."))

;;; ============================================================
;;; Encoder Protocol
;;; ============================================================
;;; Encoders convert PCM audio data into a streaming format
;;; (MP3, AAC, Opus, etc).

(defgeneric encoder-encode (encoder pcm-buffer num-samples)
  (:documentation "Encode PCM samples. Returns encoded byte vector.
   PCM-BUFFER is a (signed-byte 16) array of interleaved stereo samples.
   NUM-SAMPLES is the number of sample frames (not individual samples)."))

(defgeneric encoder-flush (encoder)
  (:documentation "Flush any remaining data from the encoder. Returns byte vector."))

(defgeneric encoder-close (encoder)
  (:documentation "Release encoder resources."))

;;; ============================================================
;;; Default method implementations
;;; ============================================================

;;; Server protocol — default methods on the existing stream-server class
;;; These delegate to the existing functions so nothing breaks.

(defmethod server-start ((server stream-server))
  (start-server server))

(defmethod server-stop ((server stream-server))
  (stop-server server))

(defmethod server-running-p ((server stream-server))
  (slot-value server 'running))

(defmethod server-add-mount ((server stream-server) path
                             &key (content-type "audio/mpeg")
                                  (bitrate 128)
                                  (name "CL-Streamer")
                                  (genre "Various")
                                  (buffer-size (* 1024 1024)))
  (add-mount server path
             :content-type content-type
             :bitrate bitrate
             :name name
             :genre genre
             :buffer-size buffer-size))

(defmethod server-remove-mount ((server stream-server) path)
  (remove-mount server path))

(defmethod server-update-metadata ((server stream-server) path &key title url)
  (update-metadata server path :title title :url url))

(defmethod server-listener-count ((server stream-server) &optional path)
  (listener-count server path))

(defmethod server-write-audio ((server stream-server) mount-path data
                               &key (start 0) (end (length data)))
  (let ((mount (gethash mount-path (server-mounts server))))
    (when mount
      (buffer-write (mount-buffer mount) data :start start :end end))))

;;; Encoder protocol methods are defined in encoder.lisp and aac-encoder.lisp
;;; alongside their respective class definitions (separate ASDF subsystems).

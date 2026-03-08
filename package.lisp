(defpackage #:cl-streamer
  (:use #:cl #:alexandria)
  (:export
   ;; Conditions
   #:streamer-error
   #:connection-error
   #:encoding-error
   
   ;; Buffer
   #:broadcast-buffer
   #:make-ring-buffer
   #:buffer-write
   #:buffer-read-from
   #:buffer-wait-for-data
   #:buffer-current-pos
   #:buffer-burst-start
   #:buffer-clear
   
   ;; ICY Protocol
   #:icy-metadata
   #:make-icy-metadata
   #:icy-metadata-title
   #:icy-metadata-url
   #:encode-icy-metadata
   #:icy-metaint
   
   ;; Stream Server
   #:stream-server
   #:make-stream-server
   #:start-server
   #:stop-server
   #:server-running-p
   #:add-mount
   #:remove-mount
   #:update-metadata
   #:listener-count
   
   ;; Main API
   #:*server*
   #:*default-port*
   #:*default-metaint*
   #:start
   #:stop
   #:write-audio-data
   #:set-now-playing
   #:get-listener-count
   
   ;; Encoder
   #:make-mp3-encoder
   #:close-encoder
   #:encode-pcm-interleaved
   #:encode-flush
   #:lame-version
   
   ;; AAC Encoder
   #:make-aac-encoder
   #:close-aac-encoder
   #:encode-aac-pcm
   
   ;; Protocol — Server
   #:server-start
   #:server-stop
   #:server-running-p
   #:server-add-mount
   #:server-remove-mount
   #:server-update-metadata
   #:server-listener-count
   #:server-write-audio
   
   ;; Protocol — Pipeline
   #:pipeline-start
   #:pipeline-stop
   #:pipeline-running-p
   #:pipeline-play-file
   #:pipeline-play-list
   #:pipeline-skip
   #:pipeline-queue-files
   #:pipeline-get-queue
   #:pipeline-clear-queue
   #:pipeline-current-track
   #:pipeline-listener-count
   #:pipeline-update-metadata
   
   ;; Protocol — Pipeline Hooks
   #:pipeline-add-hook
   #:pipeline-remove-hook
   #:pipeline-fire-hook
   
   ;; Protocol — Encoder
   #:encoder-encode
   #:encoder-flush
   #:encoder-close))

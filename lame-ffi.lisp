(in-package #:cl-streamer)

(cffi:define-foreign-library liblame
  (:unix (:or "libmp3lame.so.0" "libmp3lame.so"))
  (:darwin "libmp3lame.dylib")
  (:windows "libmp3lame.dll")
  (t (:default "libmp3lame")))

(cffi:use-foreign-library liblame)

(cffi:defctype lame-global-flags :pointer)

(cffi:defcenum lame-vbr-mode
  (:vbr-off 0)
  (:vbr-mt 1)
  (:vbr-rh 2)
  (:vbr-abr 3)
  (:vbr-mtrh 4)
  (:vbr-default 4))

(cffi:defcenum lame-mode
  (:stereo 0)
  (:joint-stereo 1)
  (:dual-channel 2)
  (:mono 3))

(cffi:defcfun ("lame_init" lame-init) lame-global-flags)

(cffi:defcfun ("lame_close" lame-close) :int
  (gfp lame-global-flags))

(cffi:defcfun ("lame_set_in_samplerate" lame-set-in-samplerate) :int
  (gfp lame-global-flags)
  (rate :int))

(cffi:defcfun ("lame_set_out_samplerate" lame-set-out-samplerate) :int
  (gfp lame-global-flags)
  (rate :int))

(cffi:defcfun ("lame_set_num_channels" lame-set-num-channels) :int
  (gfp lame-global-flags)
  (channels :int))

(cffi:defcfun ("lame_set_mode" lame-set-mode) :int
  (gfp lame-global-flags)
  (mode lame-mode))

(cffi:defcfun ("lame_set_quality" lame-set-quality) :int
  (gfp lame-global-flags)
  (quality :int))

(cffi:defcfun ("lame_set_brate" lame-set-brate) :int
  (gfp lame-global-flags)
  (brate :int))

(cffi:defcfun ("lame_set_VBR" lame-set-vbr) :int
  (gfp lame-global-flags)
  (vbr-mode lame-vbr-mode))

(cffi:defcfun ("lame_set_VBR_quality" lame-set-vbr-quality) :int
  (gfp lame-global-flags)
  (quality :float))

(cffi:defcfun ("lame_init_params" lame-init-params) :int
  (gfp lame-global-flags))

(cffi:defcfun ("lame_encode_buffer_interleaved" lame-encode-buffer-interleaved) :int
  (gfp lame-global-flags)
  (pcm :pointer)
  (num-samples :int)
  (mp3buf :pointer)
  (mp3buf-size :int))

(cffi:defcfun ("lame_encode_buffer" lame-encode-buffer) :int
  (gfp lame-global-flags)
  (buffer-l :pointer)
  (buffer-r :pointer)
  (num-samples :int)
  (mp3buf :pointer)
  (mp3buf-size :int))

(cffi:defcfun ("lame_encode_flush" lame-encode-flush) :int
  (gfp lame-global-flags)
  (mp3buf :pointer)
  (mp3buf-size :int))

(cffi:defcfun ("lame_get_lametag_frame" lame-get-lametag-frame) :size
  (gfp lame-global-flags)
  (buffer :pointer)
  (size :size))

(cffi:defcfun ("get_lame_version" get-lame-version) :string)

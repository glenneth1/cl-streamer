(in-package #:cl-streamer)

(cffi:define-foreign-library libfdkaac
  (:unix (:or "libfdk-aac.so.2" "libfdk-aac.so"))
  (:darwin "libfdk-aac.dylib")
  (:windows "libfdk-aac.dll")
  (t (:default "libfdk-aac")))

(cffi:use-foreign-library libfdkaac)

;; Shim library for safe NULL-pointer init call (SBCL/CFFI crashes on NULL args to aacEncEncode)
(eval-when (:compile-toplevel :load-toplevel :execute)
  (let ((shim-path (merge-pathnames "libfdkaac-shim.so"
                                     (asdf:system-source-directory :cl-streamer/aac-encoder))))
    (cffi:load-foreign-library shim-path)))

(cffi:defctype aac-encoder-handle :pointer)

(cffi:defcenum aac-encoder-param
  (:aacenc-aot #x0100)
  (:aacenc-bitrate #x0101)
  (:aacenc-bitratemode #x0102)
  (:aacenc-samplerate #x0103)
  (:aacenc-sbr-mode #x0104)
  (:aacenc-granule-length #x0105)
  (:aacenc-channelmode #x0106)
  (:aacenc-channelorder #x0107)
  (:aacenc-sbr-ratio #x0108)
  (:aacenc-afterburner #x0200)
  (:aacenc-bandwidth #x0203)
  (:aacenc-transmux #x0300)
  (:aacenc-header-period #x0301)
  (:aacenc-signaling-mode #x0302)
  (:aacenc-tpsubframes #x0303)
  (:aacenc-protection #x0306)
  (:aacenc-ancillary-bitrate #x0500)
  (:aacenc-metadata-mode #x0600))

(cffi:defcenum aac-encoder-error
  (:aacenc-ok #x0000)
  (:aacenc-invalid-handle #x0020)
  (:aacenc-memory-error #x0021)
  (:aacenc-unsupported-parameter #x0022)
  (:aacenc-invalid-config #x0023)
  (:aacenc-init-error #x0040)
  (:aacenc-init-aac-error #x0041)
  (:aacenc-init-sbr-error #x0042)
  (:aacenc-init-tp-error #x0043)
  (:aacenc-init-meta-error #x0044)
  (:aacenc-encode-error #x0060)
  (:aacenc-encode-eof #x0080))

(cffi:defcenum aac-channel-mode
  (:mode-invalid -1)
  (:mode-unknown 0)
  (:mode-1 1)
  (:mode-2 2)
  (:mode-1-2 3)
  (:mode-1-2-1 4)
  (:mode-1-2-2 5)
  (:mode-1-2-2-1 6)
  (:mode-1-2-2-2-1 7))

(cffi:defcenum aac-transmux
  (:tt-unknown -1)
  (:tt-raw 0)
  (:tt-adif 1)
  (:tt-adts 2)
  (:tt-latm-mcp1 6)
  (:tt-latm-mcp0 7)
  (:tt-loas 10))

(cffi:defcenum aac-aot
  (:aot-none -1)
  (:aot-null 0)
  (:aot-aac-main 1)
  (:aot-aac-lc 2)
  (:aot-aac-ssr 3)
  (:aot-aac-ltp 4)
  (:aot-sbr 5)
  (:aot-aac-scal 6)
  (:aot-er-aac-lc 17)
  (:aot-er-aac-ld 23)
  (:aot-er-aac-eld 39)
  (:aot-ps 29)
  (:aot-mp2-aac-lc 129)
  (:aot-mp2-sbr 132))

(cffi:defcstruct aacenc-buf-desc
  (num-bufs :int)
  (bufs :pointer)
  (buf-ids :pointer)
  (buf-sizes :pointer)
  (buf-el-sizes :pointer))

(cffi:defcstruct aacenc-in-args
  (num-in-samples :int)
  (num-ancillary-bytes :int))

(cffi:defcstruct aacenc-out-args
  (num-out-bytes :int)
  (num-in-samples :int)
  (num-ancillary-bytes :int))

(cffi:defcstruct aacenc-info-struct
  (max-out-buf-bytes :uint)
  (max-ancillary-bytes :uint)
  (in-buf-fill-level :uint)
  (input-channels :uint)
  (frame-length :uint)
  (encoder-delay :uint)
  (conf-buf :pointer)
  (conf-size :uint))

(cffi:defcfun ("aacEncOpen" aac-enc-open) :int
  (ph-aac-encoder :pointer)
  (enc-modules :uint)
  (max-channels :uint))

(cffi:defcfun ("aacEncClose" aac-enc-close) :int
  (ph-aac-encoder :pointer))

(cffi:defcfun ("aacEncEncode" aac-enc-encode) :int
  (h-aac-encoder aac-encoder-handle)
  (in-buf-desc :pointer)
  (out-buf-desc :pointer)
  (in-args :pointer)
  (out-args :pointer))

(cffi:defcfun ("aacEncInfo" aac-enc-info) :int
  (h-aac-encoder aac-encoder-handle)
  (p-info :pointer))

(cffi:defcfun ("aacEncoder_SetParam" aac-encoder-set-param) :int
  (h-aac-encoder aac-encoder-handle)
  (param aac-encoder-param)
  (value :uint))

(cffi:defcfun ("aacEncoder_GetParam" aac-encoder-get-param) :uint
  (h-aac-encoder aac-encoder-handle)
  (param aac-encoder-param))

;; Shim: all FDK-AAC calls go through C to avoid SBCL signal handler conflicts
(cffi:defcfun ("fdkaac_open_and_init" fdkaac-open-and-init) :int
  (out-handle :pointer)
  (sample-rate :int)
  (channels :int)
  (bitrate :int)
  (aot :int)
  (transmux :int)
  (afterburner :int)
  (out-frame-length :pointer)
  (out-max-out-bytes :pointer))

(cffi:defcfun ("fdkaac_encode" fdkaac-encode) :int
  (handle :pointer)
  (pcm-buf :pointer)
  (pcm-bytes :int)
  (num-samples :int)
  (out-buf :pointer)
  (out-buf-size :int)
  (out-bytes-written :pointer))

(cffi:defcfun ("fdkaac_close" fdkaac-close) :void
  (ph :pointer))

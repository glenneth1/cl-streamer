(in-package #:cl-streamer)

(defparameter *default-metaint* 16000
  "Default ICY metadata interval in bytes.")

(defclass icy-metadata ()
  ((title :initarg :title :accessor icy-metadata-title :initform nil)
   (url :initarg :url :accessor icy-metadata-url :initform nil)))

(defun make-icy-metadata (&key title url)
  "Create an ICY metadata object."
  (make-instance 'icy-metadata :title title :url url))

(defun encode-icy-metadata (metadata)
  "Encode metadata into ICY protocol format.
   Returns a byte vector with length prefix."
  (let* ((stream-title (or (icy-metadata-title metadata) ""))
         (stream-url (or (icy-metadata-url metadata) ""))
         (meta-string (format nil "StreamTitle='~A';StreamUrl='~A';"
                              stream-title stream-url))
         (meta-bytes (flexi-streams:string-to-octets meta-string :external-format :utf-8))
         (meta-len (length meta-bytes))
         (padded-len (* 16 (ceiling meta-len 16)))
         (length-byte (floor padded-len 16))
         (result (make-array (1+ padded-len) :element-type '(unsigned-byte 8)
                                              :initial-element 0)))
    (setf (aref result 0) length-byte)
    (replace result meta-bytes :start1 1)
    result))

(defun parse-icy-request (request-line headers)
  "Parse an ICY/HTTP request. Returns (values mount-point wants-metadata-p).
   HEADERS is an alist of (name . value) pairs."
  (let* ((parts (split-sequence:split-sequence #\Space request-line))
         (path (second parts))
         (icy-metadata-header (cdr (assoc "icy-metadata" headers :test #'string-equal))))
    (values path
            (and icy-metadata-header
                 (string= icy-metadata-header "1")))))

(defun write-icy-response-headers (stream &key content-type metaint
                                               (name "CL-Streamer")
                                               (genre "Various")
                                               (bitrate 128))
  "Write ICY/HTTP response headers to STREAM."
  (format stream "HTTP/1.1 200 OK~C~C" #\Return #\Linefeed)
  (format stream "Content-Type: ~A~C~C" content-type #\Return #\Linefeed)
  (format stream "icy-name: ~A~C~C" name #\Return #\Linefeed)
  (format stream "icy-genre: ~A~C~C" genre #\Return #\Linefeed)
  (format stream "icy-br: ~A~C~C" bitrate #\Return #\Linefeed)
  (when metaint
    (format stream "icy-metaint: ~A~C~C" metaint #\Return #\Linefeed))
  (format stream "Access-Control-Allow-Origin: *~C~C" #\Return #\Linefeed)
  (format stream "Access-Control-Allow-Headers: Origin, Accept, Content-Type, Icy-MetaData~C~C" #\Return #\Linefeed)
  (format stream "Cache-Control: no-cache, no-store~C~C" #\Return #\Linefeed)
  (format stream "Connection: close~C~C" #\Return #\Linefeed)
  (format stream "~C~C" #\Return #\Linefeed)
  (force-output stream))

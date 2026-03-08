(in-package #:cl-streamer)

(define-condition streamer-error (error)
  ((message :initarg :message :reader streamer-error-message))
  (:report (lambda (c stream)
             (format stream "Streamer error: ~A" (streamer-error-message c)))))

(define-condition connection-error (streamer-error)
  ((client :initarg :client :reader connection-error-client))
  (:report (lambda (c stream)
             (format stream "Connection error for ~A: ~A"
                     (connection-error-client c)
                     (streamer-error-message c)))))

(define-condition encoding-error (streamer-error)
  ((format :initarg :format :reader encoding-error-format))
  (:report (lambda (c stream)
             (format stream "Encoding error (~A): ~A"
                     (encoding-error-format c)
                     (streamer-error-message c)))))

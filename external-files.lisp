;;;; external-files.lisp
;;;;
;;;; Serves files that live outside the OKF bundle proper but inside
;;;; *WORKSPACE-ROOT* -- everything under /workspace/, since that's the
;;;; whole container and this server only ever runs inside one. A
;;;; markdown link to such a file (an image, a source listing, a README
;;;; belonging to a sibling project) is rewritten by REWRITE-TARGET
;;;; (okf-web-server.lisp) into a /file/... route; this file defines
;;;; what that route actually does.
;;;;
;;;; Displayable kinds: ".md" as rendered HTML, common image extensions
;;;; served raw, and known source extensions syntax-highlighted via
;;;; COLORIZE (already in this project's Quicklisp cache -- covers
;;;; Common Lisp/C/C++/Java/Python/Haskell/Scheme/Clojure/Elisp, no
;;;; more than that; anything else recognized as plain text falls back
;;;; to an unhighlighted <pre> view rather than being refused outright).
;;;; Anything not recognized as one of these -- in particular anything
;;;; that looks binary -- is never served at all.

(in-package #:okf-web-server)

;;; ---------------------------------------------------------------------
;;; Path resolution and boundary enforcement
;;;
;;; This route handler NEVER trusts that the href it's reached through
;;; was honestly constructed by REWRITE-TARGET -- a URL can be typed
;;; directly into a browser -- so it re-validates from scratch: rejects
;;; "."/".."/empty segments at the URL level (VALID-SEGMENTS-P), then
;;; independently resolves symlinks (TRUENAME) and re-checks the result
;;; still falls under *WORKSPACE-ROOT* before ever reading the file.
;;; ---------------------------------------------------------------------

(defun segments->workspace-pathname (segments)
  (let ((last-seg (car (last segments))))
    (merge-pathnames
     (make-pathname :directory (list* :relative (butlast segments))
                     :name (pathname-name last-seg) :type (pathname-type last-seg))
     *workspace-root*)))

(defun resolve-workspace-file (segments)
  "SEGMENTS -> the real TRUENAME it names under *WORKSPACE-ROOT*, or NIL
   if invalid, missing, a directory, or (after resolving symlinks)
   outside *WORKSPACE-ROOT* after all."
  (when (and segments (valid-segments-p segments))
    (let ((truename (ignore-errors (truename (segments->workspace-pathname segments)))))
      (when (and truename
                 (within-root-p truename *workspace-root*)
                 (not (uiop:directory-pathname-p truename)))
        truename))))

;;; ---------------------------------------------------------------------
;;; What kind of thing is this file?
;;; ---------------------------------------------------------------------

(defparameter *displayable-image-extensions* '("png" "jpg" "jpeg" "gif" "svg" "webp"))

(defparameter *colorize-type-by-extension*
  '(("lisp" . :common-lisp) ("asd" . :common-lisp) ("cl" . :common-lisp)
    ("c" . :c) ("h" . :c) ("cpp" . :c++) ("cc" . :c++) ("hpp" . :c++) ("hh" . :c++)
    ("java" . :java) ("py" . :python) ("hs" . :haskell)
    ("scm" . :scheme) ("clj" . :clojure) ("el" . :elisp))
  "Extension -> COLORIZE coloring-type. Deliberately narrow: COLORIZE
   itself only knows these languages (see colorize's own
   coloring-types.lisp) -- notably no shell/YAML/JSON/Makefile support.
   Those extensions still display, just as plain unhighlighted text via
   LOOKS-LIKE-TEXT-P below, rather than being treated as undisplayable.")

(defun looks-like-text-p (pathname &optional (sniff-length 8192))
  "A cheap, standard binary-detection heuristic: T unless a NUL byte
   turns up in the first SNIFF-LENGTH octets."
  (with-open-file (s pathname :element-type '(unsigned-byte 8))
    (let ((buf (make-array (min sniff-length (file-length s)) :element-type '(unsigned-byte 8))))
      (read-sequence buf s)
      (notany #'zerop buf))))

(defun file-kind (truename)
  (let ((type (string-downcase (or (pathname-type truename) ""))))
    (cond
      ((string= type "md") :markdown)
      ((member type *displayable-image-extensions* :test #'string=) :image)
      ((assoc type *colorize-type-by-extension* :test #'string=) :code)
      ((looks-like-text-p truename) :text)
      (t :unsupported))))

;;; ---------------------------------------------------------------------
;;; Rendering each kind
;;; ---------------------------------------------------------------------

(defun external-file-notice (truename)
  (spinneret:with-html-string
    (:p :class "external-file-notice"
      (format nil "~a -- lives outside the OKF bundle, shown read-only." (namestring truename)))))

(defun render-external-page (title body-html)
  (render-page title nil body-html))

(defun serve-external-markdown (truename)
  ;; *CODE-BLOCKS* must be bound T around the parse call for GitHub-style
  ;; ``` fenced blocks to render as <pre><code> instead of one giant inline
  ;; span -- see RENDER-MARKDOWN's own comment (okf-web-server.lisp) for the
  ;; full story. This call site parses independently (external files aren't
  ;; bundle pages, so RENDER-MARKDOWN's link-rewriting doesn't apply) and was
  ;; missed when that fix first landed.
  (let ((text (uiop:read-file-string truename))
        (3bmd-code-blocks:*code-blocks* t))
    (render-external-page (file-namestring truename)
                          (concatenate 'string
                                       (external-file-notice truename)
                                       (with-output-to-string (s)
                                         (3bmd:parse-string-and-print-to-stream (linkify-bare-urls text) s))))))

(defun serve-external-code (truename coloring-type)
  ;; COLORIZE:HTML-COLORIZATION's default encoder (ENCODE-FOR-PRE) relies
  ;; on a <pre> element's whitespace-preserving rendering for line breaks
  ;; and indentation -- it never emits <br>/&nbsp; itself, matching
  ;; COLORIZE's own reference usage in COLORIZE-FILE-TO-STREAM, which
  ;; wraps this exact call in <pre>...</pre> the same way.
  (let ((text (uiop:read-file-string truename)))
    (render-external-page (file-namestring truename)
                          (concatenate 'string
                                       (external-file-notice truename)
                                       (spinneret:with-html-string (:style (:raw colorize:*coloring-css*)))
                                       (spinneret:with-html-string
                                         (:pre (:raw (colorize:html-colorization coloring-type text))))))))

(defun serve-external-text (truename)
  (let ((text (uiop:read-file-string truename)))
    (render-external-page (file-namestring truename)
                          (concatenate 'string
                                       (external-file-notice truename)
                                       (spinneret:with-html-string (:pre (:code text)))))))

(defun serve-external-unsupported (segments)
  (setf (hunchentoot:return-code*) hunchentoot:+http-not-found+)
  (render-external-page "Not displayable"
                        (spinneret:with-html-string
                          (:h1 "Not displayable")
                          (:p :class "missing"
                            (format nil "/~{~a~^/~} is not a file type this server can safely display."
                                    segments)))))

;;; ---------------------------------------------------------------------
;;; Route
;;; ---------------------------------------------------------------------

(easy-routes:defroute external-file-route ("/file/*path" :method :get) ()
  ;; No @html decorator: the :IMAGE branch needs HANDLE-STATIC-FILE's
  ;; own content-type, which a blanket "text/html" decorator (applied
  ;; unconditionally after the handler body runs) would clobber.
  (let* ((segments (remove "" path :test #'string=))
         (truename (resolve-workspace-file segments)))
    (if (null truename)
        (progn (setf (hunchentoot:content-type*) "text/html")
               (render-not-found segments))
        (case (file-kind truename)
          (:image (hunchentoot:handle-static-file truename))
          (:markdown (setf (hunchentoot:content-type*) "text/html") (serve-external-markdown truename))
          (:code (setf (hunchentoot:content-type*) "text/html")
           (serve-external-code truename (cdr (assoc (string-downcase (pathname-type truename))
                                                       *colorize-type-by-extension* :test #'string=))))
          (:text (setf (hunchentoot:content-type*) "text/html") (serve-external-text truename))
          (t (setf (hunchentoot:content-type*) "text/html") (serve-external-unsupported segments))))))

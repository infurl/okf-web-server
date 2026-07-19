;;;; audit.lisp
;;;;
;;;; A Lisp-native OKF bundle audit: reuses okf-web-server.lisp's own
;;;; frontmatter/link/code-shielding helpers rather than re-parsing YAML
;;;; and Markdown in shell (as automation/validate.sh does), and -- per
;;;; specification/core-spec.md section 4's own "broken links are
;;;; tolerated, not malformed" wording -- separates hard spec violations
;;;; ("errors") from spec-tolerated-but-worth-flagging issues
;;;; ("warnings"), which validate.sh does not. Exposed at the /audit
;;;; route (see the bottom of this file), not auto-run on every request
;;;; to "/" -- walking the whole tree and parsing every frontmatter block
;;;; is real per-request cost not worth paying on the busiest route.
;;;;
;;;; validate.sh is intentionally left alone (still useful standalone,
;;;; no SBCL dependency, fine for CI/pre-commit); this is a richer,
;;;; web-facing companion, not a replacement.

(in-package #:okf-web-server)

;;; ---------------------------------------------------------------------
;;; Bundle tree walking
;;;
;;; Deliberately walks the real OS directory tree directly (like
;;; validate.sh's own `find`), not just the bundle-recognized subset
;;; LIST-MD-CHILDREN/COLLECT-TAGGED-PAGES walk -- the whole point of the
;;; missing-index.md check below is to catch directories a bundle-aware
;;; renderer would otherwise silently skip.
;;; ---------------------------------------------------------------------

(defparameter *ignored-directory-names* '(".git" ".svn" ".hg")
  "Never bundle content, even if something inside happens to end in .md.")

(defun ignored-directory-p (dir)
  (member (car (last (pathname-directory dir))) *ignored-directory-names* :test #'string-equal))

(defun all-directories (root)
  "ROOT plus every subdirectory beneath it, recursively, excluding
   *IGNORED-DIRECTORY-NAMES*."
  (cons root (mapcan #'all-directories (remove-if #'ignored-directory-p (uiop:subdirectories root)))))

(defun all-markdown-files (root)
  "Every .md file anywhere under ROOT, recursively, excluding
   *IGNORED-DIRECTORY-NAMES*."
  (append (remove-if-not (lambda (f) (equal (pathname-type f) "md")) (uiop:directory-files root))
          (mapcan #'all-markdown-files (remove-if #'ignored-directory-p (uiop:subdirectories root)))))

(defun directory-has-md-content-p (dir)
  "T if DIR contains a .md file, directly or in any non-ignored
   subdirectory, however deep."
  (or (some (lambda (f) (equal (pathname-type f) "md")) (uiop:directory-files dir))
      (some #'directory-has-md-content-p (remove-if #'ignored-directory-p (uiop:subdirectories dir)))))

;; RELATIVE-SEGMENTS lives in okf-web-server.lisp now -- shared with
;; REWRITE-TARGET/TARGET-TRUENAME, which need the same relative-path
;; computation for the external-file link support (external-files.lisp).

(defun file-identity-segments (file)
  "FILE's OKF identity segments -- its relative path from *OKF-ROOT*
   with any \".md\" suffix removed, and a trailing \"index\" collapsed
   into its directory's own segments, matching section 4's identity
   rule and RENDER-SIDEBAR-TREE/FIND-PAGE's existing conventions."
  (let ((dir-segments (relative-segments file))
        (name (pathname-name file)))
    (if (string-equal name "index") dir-segments (append dir-segments (list name)))))

;;; ---------------------------------------------------------------------
;;; Link-target resolution
;;;
;;; Reuses TARGET-TRUENAME (okf-web-server.lisp) -- the same resolver
;;; REWRITE-TARGET now uses to serve non-".md" targets and targets that
;;; escape *OKF-ROOT* via external-files.lisp's /file/... route -- so a
;;; link the renderer can actually turn into a working route is never
;;; flagged here as broken, and vice versa.
;;; ---------------------------------------------------------------------

(defparameter *md-link-target-scanner*
  ;; Matches "](target)", "](target#frag)", "](target?q)" for ANY
  ;; target, not just ".md" -- the same broadening *MD-HREF-SCANNER* got
  ;; in okf-web-server.lisp, and for the same reason: images/code/other
  ;; files outside the bundle are now real, checkable link targets too.
  ;; Excludes "#"/"?" from the main group (mirroring *MD-HREF-SCANNER*)
  ;; so a pure same-page fragment link, "](#section)", is never captured
  ;; as if it were a file target.
  (cl-ppcre:create-scanner "\\]\\(([^()\\s#?]+)(?:[#?][^)]*)?\\)"))

(defun scan-markdown-links (body)
  "Every non-external link target in BODY, ignoring occurrences inside
   fenced/inline code -- shielded via the same PLACEHOLDER-OUT machinery
   LINKIFY-BARE-URLS already uses, discarded rather than restored since
   we only want them absent from the scan."
  (let* ((shielded (nth-value 0 (placeholder-out body *fenced-code-scanner* "F")))
         (shielded (nth-value 0 (placeholder-out shielded *inline-code-scanner* "I")))
         (targets nil))
    (cl-ppcre:do-register-groups (target) (*md-link-target-scanner* shielded)
      (push target targets))
    (nreverse targets)))

(defun link-target-exists-p (target current-dir-segments)
  (or (external-link-p target)
      (and (plusp (length target))
           (let ((truename (target-truename target current-dir-segments)))
             (and truename (within-root-p truename *workspace-root*))))))

;;; ---------------------------------------------------------------------
;;; Timestamp sanity
;;;
;;; A malformed/implausible `timestamp` is a real, recurring mistake --
;;; not just a formatting nit -- so beyond checking ISO 8601 UTC shape,
;;; it's also bounds-checked against [OKF spec's own publication date,
;;; now]: nothing in this bundle could have been "last verified" against
;;; a spec that didn't exist yet, and nothing should be dated in the
;;; future. Specifically requested after the user noted less capable
;;; coding agents have gotten timestamps' year wrong before.
;;; ---------------------------------------------------------------------

(defparameter *okf-spec-publication-date*
  (encode-universal-time 0 0 0 12 6 2026 0)
  "2026-06-12, UTC -- the one and only commit that has ever touched the
   real external spec (github.com/GoogleCloudPlatform/knowledge-catalog
   /blob/main/okf/SPEC.md), i.e. its original publication. See
   specification/core-spec.md section 0.")

(defparameter *iso8601-utc-scanner*
  (cl-ppcre:create-scanner "^(\\d{4})-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2}):(\\d{2})Z$"))

(defun parse-iso8601-utc (raw)
  "The universal-time RAW (e.g. \"2026-07-14T22:00:00Z\") denotes, or
   NIL if RAW isn't exactly that shape, or isn't a real calendar date."
  (multiple-value-bind (whole regs) (cl-ppcre:scan-to-strings *iso8601-utc-scanner* raw)
    (when whole
      (destructuring-bind (year month day hour minute second) (coerce regs 'list)
        (handler-case
            (encode-universal-time (parse-integer second) (parse-integer minute) (parse-integer hour)
                                    (parse-integer day) (parse-integer month) (parse-integer year) 0)
          (error () nil))))))

;;; ---------------------------------------------------------------------
;;; The audit itself
;;; ---------------------------------------------------------------------

(defstruct finding
  severity   ; :error or :warning
  segments   ; the page's identity segments this concerns, or NIL if bundle-wide
  message)   ; human-readable string, no trailing period

(defun looks-like-pascal-or-snake-case-p (value)
  (every (lambda (c) (or (alphanumericp c) (char= c #\_))) value))

(defun audit-bundle ()
  "Runs every structural/consistency check against *OKF-ROOT*, returning
   a list of FINDING structs. See this file's header for the checks'
   provenance and the errors-vs-warnings split's rationale."
  (let (findings)
    (flet ((err (segments format-string &rest args)
             (push (make-finding :severity :error :segments segments
                                  :message (apply #'format nil format-string args))
                   findings))
           (warn* (segments format-string &rest args)
             (push (make-finding :severity :warning :segments segments
                                  :message (apply #'format nil format-string args))
                   findings)))

      ;; Every directory with markdown content anywhere beneath it needs
      ;; its own index.md, or a bundle-aware renderer treats it (and
      ;; everything under it) as outside the bundle entirely.
      (dolist (dir (all-directories *okf-root*))
        (unless (or (probe-file (merge-pathnames (make-pathname :name "index" :type "md") dir))
                    (not (directory-has-md-content-p dir)))
          (err (relative-segments dir)
               "directory contains markdown content but has no index.md of its own")))

      ;; Per-file checks.
      (dolist (file (all-markdown-files *okf-root*))
        (let* ((segments (file-identity-segments file))
               (dir-segments (relative-segments file))
               (index-p (string-equal (pathname-name file) "index"))
               (root-p (and index-p (null dir-segments)))
               (text (uiop:read-file-string file))
               (has-frontmatter (and (plusp (length text))
                                     (let ((first-line (first (cl-ppcre:split "\\n" text))))
                                       (string= (string-right-trim '(#\Return) first-line) "---")))))
          (multiple-value-bind (body fields) (parse-frontmatter text)

            (cond
              ((and index-p (not root-p) has-frontmatter)
               (err segments "non-root index.md carries a YAML frontmatter block (only the bundle-root index.md may, and only okf_version)"))

              ((and index-p root-p has-frontmatter)
               (let ((extra (remove "okf_version" fields :key #'car :test #'string-equal)))
                 (when extra
                   (warn* segments "root index.md frontmatter defines fields other than okf_version: ~{~a~^, ~}"
                          (mapcar #'car extra)))))

              ((not index-p)
               (if (not has-frontmatter)
                   (err segments "missing YAML frontmatter block")
                   (let ((type (field-value fields "type")))
                     (if (null type)
                         (err segments "missing mandatory type field")
                         (unless (looks-like-pascal-or-snake-case-p type)
                           (warn* segments "type value ~s doesn't look like PascalCase or snake_case" type)))
                     (let ((ts (field-value fields "timestamp")))
                       (when ts
                         (let ((ut (parse-iso8601-utc ts)))
                           (cond
                             ((null ut)
                              (warn* segments "timestamp ~s is not valid ISO 8601 UTC (expected YYYY-MM-DDTHH:MM:SSZ)" ts))
                             ((> ut (get-universal-time))
                              (warn* segments "timestamp ~s is in the future" ts))
                             ((< ut *okf-spec-publication-date*)
                              (warn* segments "timestamp ~s predates the OKF spec's own publication (2026-06-12) -- check the year" ts))))))
                     (let ((tags (field-value fields "tags")))
                       (when (and tags (plusp (length tags)) (char= (char tags 0) #\[)
                                  (not (char= (char tags (1- (length tags))) #\])))
                         (warn* segments "tags value ~s looks malformed (unbalanced brackets)" tags)))
                     (unless (or (field-value fields "description") (field-value fields "tags"))
                       (warn* segments "has neither description nor tags -- consider adding for discoverability"))))))

            ;; Link check applies to every file's body, index or concept.
            (dolist (target (scan-markdown-links body))
              (unless (link-target-exists-p target dir-segments)
                (warn* segments "broken link to ~a" target))))))

      (nreverse findings))))

;;; ---------------------------------------------------------------------
;;; /audit route
;;; ---------------------------------------------------------------------

(defun render-finding (f)
  "Emits one <li> into the active Spinneret HTML stream -- must be
   called from within a WITH-HTML/WITH-HTML-STRING body, same
   convention as RENDER-SIDEBAR-TREE."
  (spinneret:with-html
    (:li (if (finding-segments f)
             (:a :href (segments->route (finding-segments f)) (format nil "~{~a~^/~}" (finding-segments f)))
             (:span "(bundle)"))
         ": " (finding-message f))))

(easy-routes:defroute audit-route ("/audit" :method :get :decorators (@html)) ()
  ;; Route-matching precedence over the "/*path" catch-all comes from
  ;; specificity, not file/definition order -- see TAG-INDEX-ROUTE's own
  ;; comment on this in okf-web-server.lisp.
  (let* ((findings (audit-bundle))
         (errors (remove :warning findings :key #'finding-severity))
         (warnings (remove :error findings :key #'finding-severity)))
    (render-page "Bundle Audit" nil
                 (spinneret:with-html-string
                   (:h1 "OKF Bundle Audit")
                   (:p (format nil "~d error~:p, ~d warning~:p." (length errors) (length warnings)))
                   (if (null findings)
                       (:p :class "audit-clean" "No issues found -- bundle is clean.")
                       (progn
                         (when errors
                           (:h2 "Errors")
                           (:ul :class "audit-list audit-errors"
                             (dolist (f errors) (render-finding f))))
                         (when warnings
                           (:h2 "Warnings")
                           (:ul :class "audit-list audit-warnings"
                             (dolist (f warnings) (render-finding f))))))))))

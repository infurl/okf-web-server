;;;; okf-web-server.lisp
;;;;
;;;; A small Hunchentoot server that renders the OKF markdown bundle as
;;;; browsable HTML: every concept file and index.md gets its own page,
;;;; internal .md links are rewritten to point at those pages, and a
;;;; persistent, recursively-generated hierarchical index sits on the
;;;; left of every page.
;;;;
;;;; Every non-obvious API call here (LASS's real entry point, 3bmd's
;;;; real function name, cl-ppcre's REGEX-REPLACE-ALL callback signature,
;;;; easy-routes' wildcard-segment binding, and the pathname-merging
;;;; approach) was verified directly against a live SBCL image before
;;;; being written here -- see okf/lessons-learned/notebook.md for why
;;;; that matters in this codebase specifically.

(defpackage #:okf-web-server
  (:use #:cl #:easy-routes)
  (:export #:start-server
           #:stop-server))

(in-package #:okf-web-server)

;;; ---------------------------------------------------------------------
;;; Configuration
;;; ---------------------------------------------------------------------

(defparameter *okf-root* (uiop:ensure-directory-pathname #P"/workspace/okf/")
  "Root directory of the OKF bundle this server renders. Always a proper
   directory pathname -- see SEGMENTS->PATHNAME for why that matters.")

(defparameter *server-port* 8090
  "8090-8099 is the published port range this container always reserves
   for always-on services; this one is pinned to 8090. Kept as the real
   default (not just a runtime override) so reloading this file no
   longer silently reverts a live instance back to 8082.")

(defvar *acceptor* nil
  "The running HUNCHENTOOT acceptor, or NIL if the server is stopped.")

;;; ---------------------------------------------------------------------
;;; Segment helpers
;;;
;;; Request paths and markdown link targets are manipulated as plain
;;; lists of path-segment strings, not raw namestrings. The one place we
;;; touch CL pathnames (SEGMENTS->PATHNAME) merges a properly-constructed
;;; relative pathname (explicit :DIRECTORY list, explicit :NAME/:TYPE)
;;; against *OKF-ROOT*, which is itself guaranteed to be a directory
;;; pathname -- the unsafe pattern is coercing a bare *string* without a
;;; trailing slash, which is never done here.
;;; ---------------------------------------------------------------------

(defun split-segments (path-string)
  "Split a slash-delimited PATH-STRING into a list of non-empty segments."
  (remove "" (cl-ppcre:split "/" path-string) :test #'string=))

(defun resolve-segments (base-segments target-segments)
  "Resolve TARGET-SEGMENTS (may contain \".\" / \"..\") against
   BASE-SEGMENTS, both lists of strings, returning a flat list of
   segments with no \".\"/\"..\" left in it."
  (let ((stack (reverse base-segments)))
    (dolist (seg target-segments)
      (cond
        ((string= seg "."))
        ((string= seg "..") (when stack (pop stack)))
        ((string= seg ""))
        (t (push seg stack))))
    (nreverse stack)))

(defun valid-segments-p (segments)
  "T if SEGMENTS contains no empty/\".\"/\"..\" components. Used to
   reject any request path that could otherwise escape *OKF-ROOT*."
  (every (lambda (s) (and (plusp (length s))
                          (not (string= s "."))
                          (not (string= s ".."))))
         segments))

(defun segments->pathname (segments &key name type)
  "Build an absolute pathname under *OKF-ROOT* naming the directory
   SEGMENTS, optionally with a file NAME/TYPE."
  (merge-pathnames
   (make-pathname :directory (list* :relative segments) :name name :type type)
   *okf-root*))

(defun segments->route (segments &key directory)
  "Build the URL path for SEGMENTS, a list of strings. DIRECTORY adds a
   trailing slash. The bundle root (NIL segments) is always just \"/\",
   never \"//\"."
  (if (null segments)
      "/"
      (format nil "/~{~a~^/~}~:[~;/~]" segments directory)))

(defun strip-md-extension (segment)
  (let ((len (length segment)))
    (if (and (>= len 3) (string-equal (subseq segment (- len 3)) ".md"))
        (subseq segment 0 (- len 3))
        segment)))

;;; ---------------------------------------------------------------------
;;; Content resolution
;;; ---------------------------------------------------------------------

(defstruct page
  segments      ; list of strings identifying this page, e.g. ("tooling"
                ; "sbcl-bridge"); NIL for the bundle root.
  pathname      ; the .md file backing this page.
  directory-p)  ; T if this page is a directory's index.md.

(defun page-dir-segments (page)
  "The segments of the directory PAGE's file actually lives in -- used
   as the base for resolving that file's own relative markdown links."
  (if (page-directory-p page)
      (page-segments page)
      (butlast (page-segments page))))

(defun find-page (segments)
  "Resolve SEGMENTS (already stripped of any trailing empty/slash
   segment) to a PAGE, or NIL if nothing on disk matches."
  (when (valid-segments-p segments)
    (if (null segments)
        (let ((index (segments->pathname nil :name "index" :type "md")))
          (when (probe-file index)
            (make-page :segments nil :pathname index :directory-p t)))
        (let ((concept (segments->pathname (butlast segments)
                                           :name (car (last segments))
                                           :type "md")))
          (if (probe-file concept)
              (make-page :segments segments :pathname concept :directory-p nil)
              (let ((index (segments->pathname segments :name "index" :type "md")))
                (when (probe-file index)
                  (make-page :segments segments :pathname index :directory-p t))))))))

;;; ---------------------------------------------------------------------
;;; Frontmatter handling
;;;
;;; Concept files open with a YAML frontmatter block; index.md files
;;; normally don't (except the bundle-root index.md, which may carry
;;; okf_version) -- see specification/core-spec.md. We parse whatever
;;; frontmatter block is present into an ordered (KEY . VALUE) alist
;;; (KEY lowercase, as written) before handing the body to 3bmd (a
;;; literal "---" line would otherwise be read as Markdown itself), so
;;; every field -- not just title -- can be displayed.
;;;
;;; This is a pragmatic parser for exactly the shapes this bundle's own
;;; template-concept.md and core-spec.md establish (simple scalars,
;;; quoted scalars, flow-sequences like "[a, b, c]", and ">" folded
;;; block scalars folded into one space-joined line) -- not a general
;;; YAML parser.
;;; ---------------------------------------------------------------------

(defun unquote (s)
  (if (and (>= (length s) 2) (char= (char s 0) #\") (char= (char s (1- (length s))) #\"))
      (subseq s 1 (1- (length s)))
      s))

(defun parse-frontmatter-lines (lines)
  "LINES is a vector of the raw lines strictly between the two '---'
   delimiters. Returns an ordered alist of (key . value) strings."
  (let ((fields nil) (i 0) (n (length lines)))
    (loop while (< i n) do
      (let ((line (string-right-trim '(#\Return) (aref lines i))))
        (multiple-value-bind (whole regs)
            (cl-ppcre:scan-to-strings "^([A-Za-z_][A-Za-z0-9_-]*):[ \\t]*(.*)$" line)
          (if whole
              (let ((key (aref regs 0))
                    (rest-val (string-trim '(#\Space #\Tab) (aref regs 1))))
                (incf i)
                (cond
                  ((member rest-val '(">" ">-" "|" "|-") :test #'string=)
                   (let ((chunk-lines nil))
                     (loop while (and (< i n)
                                      (let ((l (aref lines i)))
                                        (or (zerop (length (string-trim '(#\Return) l)))
                                            (and (plusp (length l))
                                                 (member (char l 0) '(#\Space #\Tab))))))
                           do (push (string-trim '(#\Space #\Tab #\Return) (aref lines i)) chunk-lines)
                              (incf i))
                     (push (cons key (format nil "~{~a~^ ~}"
                                             (remove "" (nreverse chunk-lines) :test #'string=)))
                           fields)))
                  (t
                   (push (cons key (unquote rest-val)) fields))))
              (incf i)))))
    (nreverse fields)))

(defun parse-frontmatter (text)
  "Returns (VALUES BODY FIELDS), FIELDS an ordered (key . value) alist."
  (let ((lines (cl-ppcre:split "\\n" text)))
    (if (and lines (string= (string-right-trim '(#\Return) (first lines)) "---"))
        (let ((end (position "---" (rest lines)
                             :key (lambda (l) (string-right-trim '(#\Return) l))
                             :test #'string=)))
          (if end
              (values (format nil "~{~a~^~%~}" (nthcdr (+ end 2) lines))
                      (parse-frontmatter-lines (coerce (subseq lines 1 (1+ end)) 'vector)))
              (values text nil)))
        (values text nil))))

(defun field-value (fields name)
  (cdr (assoc name fields :test #'string-equal)))

(defun humanize-field-name (name)
  (format nil "~{~a~^ ~}"
          (mapcar (lambda (word) (if (string-equal word "okf") "OKF" (string-capitalize word)))
                  (cl-ppcre:split "_" name))))

(defun format-field-value (value)
  "Cosmetic only: a YAML flow-sequence like \"[a, b, c]\" displays
   without its brackets."
  (if (and (>= (length value) 2)
           (char= (char value 0) #\[)
           (char= (char value (1- (length value))) #\]))
      (subseq value 1 (1- (length value)))
      value))

(defun parse-tag-list (raw-value)
  "RAW-VALUE is a frontmatter field's raw string, e.g.
   \"[tooling, common-lisp, parser]\" -- returns the individual tag
   strings, trimmed. Reuses FORMAT-FIELD-VALUE's bracket-stripping so a
   single, bracket-less tag also parses correctly."
  (remove "" (mapcar (lambda (s) (string-trim '(#\Space #\Tab) s))
                     (cl-ppcre:split "," (format-field-value raw-value)))
          :test #'string=))

(defun render-frontmatter-block (fields)
  "Renders every frontmatter field as a Field/Value table, except
   'description', which -- being typically a full sentence or more --
   gets its own styled callout below the table instead of a cramped
   table cell, and 'tags', whose value renders as one link per tag
   (see TAG-INDEX-ROUTE) instead of plain text."
  (let* ((description (field-value fields "description"))
         (table-fields (remove "description" fields :key #'car :test #'string-equal)))
    (spinneret:with-html-string
      (when (or table-fields description)
        (:div :class "meta"
          (when table-fields
            (:table :class "meta-table"
              (dolist (kv table-fields)
                (:tr (:th (humanize-field-name (car kv)))
                     (:td (if (string-equal (car kv) "tags")
                              (dolist (tag (parse-tag-list (cdr kv)))
                                (:a :class "tag-link" :href (format nil "/tags/~a" tag) tag))
                              (format-field-value (cdr kv))))))))
          (when description
            (:p :class "meta-description" description)))))))

;;; ---------------------------------------------------------------------
;;; Markdown link rewriting
;;;
;;; Rewrites href="....md" (relative, or absolute bundle-root-relative
;;; per specification/core-spec.md section 5.1) targets emitted by 3bmd
;;; into internal routes. External (scheme-prefixed) links are left
;;; untouched.
;;; ---------------------------------------------------------------------

(defparameter *md-href-scanner*
  (cl-ppcre:create-scanner "href=\"([^\"#?]+\\.md)((?:[#?][^\"]*)?)\""))

(defun external-link-p (target)
  (cl-ppcre:scan "^[a-zA-Z][a-zA-Z0-9+.-]*://" target))

(defun target-segments->route (segments)
  "SEGMENTS is a list of path segments whose last element still carries
   a .md suffix, e.g. (\"tooling\" \"sbcl-bridge.md\") or (\"index.md\").
   A trailing \"index\" component collapses to its directory's route."
  (let* ((butl (butlast segments))
         (last-seg (strip-md-extension (car (last segments)))))
    (if (string= last-seg "index")
        (segments->route butl :directory t)
        (segments->route (append butl (list last-seg))))))

(defun rewrite-target (target current-dir-segments)
  "Returns the rewritten route for TARGET, or NIL if TARGET should be
   left as-is (an external link)."
  (cond
    ((external-link-p target) nil)
    ((and (plusp (length target)) (char= (char target 0) #\/))
     (target-segments->route (split-segments (subseq target 1))))
    (t
     (target-segments->route
      (resolve-segments current-dir-segments (split-segments target))))))

(defun rewrite-markdown-links (html current-dir-segments)
  (cl-ppcre:regex-replace-all
   *md-href-scanner*
   html
   (lambda (target-string start end match-start match-end reg-starts reg-ends)
     (declare (ignore start end match-start match-end))
     (let* ((target (subseq target-string (aref reg-starts 0) (aref reg-ends 0)))
            (suffix (if (aref reg-starts 1)
                        (subseq target-string (aref reg-starts 1) (aref reg-ends 1))
                        ""))
            (route (rewrite-target target current-dir-segments)))
       (format nil "href=\"~a~a\"" (or route target) suffix)))))

(defun render-markdown (markdown-text current-dir-segments)
  (rewrite-markdown-links
   (with-output-to-string (s) (3bmd:parse-string-and-print-to-stream markdown-text s))
   current-dir-segments))

;;; ---------------------------------------------------------------------
;;; Sidebar (persistent hierarchical index)
;;;
;;; Walks the real directory tree at request time -- always reflects
;;; what's actually on disk, no separate index to keep in sync.
;;; ---------------------------------------------------------------------

(defun bundle-directory-p (dir)
  "T if DIR (a directory pathname) is itself part of the OKF bundle --
   i.e. has its own index.md. A directory with none is excluded from the
   sidebar entirely, not just left unexpanded, since without an
   index.md it has no page of its own to link to and, per the bundle's
   own convention, nothing beneath it (.git and the like) is bundle
   content either."
  (probe-file (merge-pathnames (make-pathname :name "index" :type "md") dir)))

(defun list-md-children (segments)
  "Alphabetically sorted (:file name) / (:dir name) entries directly
   under SEGMENTS: markdown files (excluding index.md, represented by
   the directory entry itself) and subdirectories that are themselves
   part of the bundle (see BUNDLE-DIRECTORY-P)."
  (let ((dir (segments->pathname segments)))
    (sort
     (append
      (loop for f in (uiop:directory-files dir)
            when (and (equal (pathname-type f) "md")
                      (not (string-equal (pathname-name f) "index")))
              collect (list :file (pathname-name f)))
      (loop for d in (uiop:subdirectories dir)
            when (bundle-directory-p d)
              collect (list :dir (car (last (pathname-directory d))))))
     #'string-lessp :key #'second)))

(defun render-sidebar-tree (segments current-segments &optional (depth 0))
  "Emits <li> entries directly into the active Spinneret HTML stream --
   must be called from within a WITH-HTML/WITH-HTML-STRING body."
  (when (< depth 16)
    (dolist (entry (list-md-children segments))
      (destructuring-bind (kind name) entry
        (let* ((child-segments (append segments (list name)))
               (dir-p (eq kind :dir))
               (href (segments->route child-segments :directory dir-p))
               (active-p (equal child-segments current-segments)))
          (spinneret:with-html
            (:li :class (if active-p "active" nil)
              (:a :href href name)
              (when dir-p
                (:ul (render-sidebar-tree child-segments current-segments (1+ depth)))))))))))

(defun render-sidebar (current-segments)
  (spinneret:with-html
    (:nav :class "sidebar"
      (:a :href "/" :class (if (null current-segments) "active root" "root") "OKF Repository")
      (:ul (render-sidebar-tree nil current-segments)))))

;;; ---------------------------------------------------------------------
;;; Tag index
;;;
;;; Backs the clickable tags rendered by RENDER-FRONTMATTER-BLOCK: walks
;;; the same bundle-membership rules as the sidebar (LIST-MD-CHILDREN /
;;; BUNDLE-DIRECTORY-P), flattened into one list instead of a tree, so a
;;; tag page can look up every match at request time -- no separate tag
;;; index to keep in sync, same reasoning as the sidebar itself.
;;; ---------------------------------------------------------------------

(defstruct tagged-page
  segments   ; list of strings identifying this page, NIL for the bundle root
  title      ; frontmatter "title", or the last segment/"OKF Repository"
  tags)      ; list of tag strings, possibly empty

(defun page-frontmatter-fields (pathname)
  (nth-value 1 (parse-frontmatter (uiop:read-file-string pathname))))

(defun page->tagged-page (segments pathname)
  (let* ((fields (page-frontmatter-fields pathname))
         (raw-tags (field-value fields "tags")))
    (make-tagged-page
     :segments segments
     :title (or (field-value fields "title")
                (if segments (car (last segments)) "OKF Repository"))
     :tags (when raw-tags (parse-tag-list raw-tags)))))

(defun collect-tagged-pages (&optional segments)
  "Recursively collects a TAGGED-PAGE for every real content page under
   SEGMENTS -- that directory's own index.md (if any), its leaf .md
   files, and the same recursion into bundle subdirectories that
   LIST-MD-CHILDREN/RENDER-SIDEBAR-TREE already do."
  (let ((dir (segments->pathname segments))
        (results nil))
    (let ((index (segments->pathname segments :name "index" :type "md")))
      (when (probe-file index)
        (push (page->tagged-page segments index) results)))
    (dolist (f (uiop:directory-files dir))
      (when (and (equal (pathname-type f) "md")
                 (not (string-equal (pathname-name f) "index")))
        (push (page->tagged-page (append segments (list (pathname-name f))) f)
              results)))
    (dolist (d (uiop:subdirectories dir))
      (when (bundle-directory-p d)
        (setf results
              (nconc (collect-tagged-pages
                      (append segments (list (car (last (pathname-directory d))))))
                     results))))
    results))

(defun pages-tagged (tag)
  (sort (remove-if-not (lambda (p) (member tag (tagged-page-tags p) :test #'string-equal))
                       (collect-tagged-pages nil))
        #'string-lessp :key #'tagged-page-title))

;;; ---------------------------------------------------------------------
;;; Styles (LASS)
;;; ---------------------------------------------------------------------

(defun page-css ()
  (lass:compile-and-write
   '("*" :box-sizing "border-box")
   '("body" :margin 0 :font-family "sans-serif" :line-height 1.6 :color "#222")
   '(".layout" :display "flex" :min-height "100vh")
   ;; Sticky + its own height/overflow, rather than the flex default of
   ;; stretching to match .content's height, is what makes the sidebar
   ;; stay in view and scroll independently once it's taller than the
   ;; viewport itself -- a plain "overflow-y: auto" alone does nothing
   ;; when the box has already stretched to fit everything.
   '(".sidebar" :width "280px" :flex "0 0 280px" :align-self "flex-start"
     :position "sticky" :top 0 :height "100vh" :overflow-y "auto"
     :background "#f4f4f6" :border-right "1px solid #ddd" :padding "1rem")
   '(".sidebar ul" :list-style-type "none" :padding-left "1rem" :margin 0)
   '(".sidebar > ul" :padding-left 0)
   '(".sidebar a" :color "#333" :text-decoration "none" :display "inline-block"
     :padding "0.1rem 0")
   '(".sidebar a.root" :font-weight "bold" :font-size "1.1rem")
   '(".sidebar a:hover" :text-decoration "underline")
   '(".sidebar li.active > a" :color "#007bff" :font-weight "bold")
   ;; Directory (index-page) entries vs. leaf content-page entries:
   ;; distinguished purely structurally -- an <li> only has a nested <ul>
   ;; when RENDER-SIDEBAR-TREE emitted one for a :DIR entry -- so this
   ;; needs no change to the markup generation at all.
   '(".sidebar li:has(> ul) > a" :font-weight "600" :color "#222")
   '(".sidebar li:has(> ul) > a::before"
     :content "▸ " :display "inline-block" :width "0.9em" :color "#888")
   '(".sidebar li:not(:has(> ul)) > a" :color "#555")
   '(".content" :flex "1" :padding "2rem 3rem" :max-width "56rem")
   '("h1" :color "#222" :margin-top 0)
   '("a" :color "#007bff")
   '("code" :background "#f0f0f2" :padding "0.1rem 0.3rem" :border-radius "3px"
     :font-size "0.9em")
   '("pre" :background "#f0f0f2" :padding "1rem" :overflow-x "auto"
     :border-radius "4px")
   '("pre code" :background "none" :padding 0)
   '(".missing" :color "#a00")
   '(".meta" :margin-bottom "2rem")
   '(".meta-table" :border-collapse "collapse" :margin-bottom "1rem")
   '(".meta-table th" :text-align "left" :font-weight "600" :color "#555"
     :padding "0.25rem 1rem 0.25rem 0" :vertical-align "top" :white-space "nowrap")
   '(".meta-table td" :padding "0.25rem 0" :color "#222")
   '(".meta-description" :font-size "1.05rem" :font-style "italic" :color "#444"
     :border-left "3px solid #007bff" :padding "0.25rem 1rem" :margin "0"
     :background "#f7f9fc")
   '(".tag-link" :display "inline-block" :background "#eef4ff" :color "#007bff"
     :border-radius "3px" :padding "0.05rem 0.5rem" :font-size "0.9em"
     :margin-right "0.3rem" :text-decoration "none")
   '(".tag-link:hover" :background "#dceaff" :text-decoration "none")
   '(".tag-page-list" :list-style-type "none" :padding-left 0)
   '(".tag-page-list li" :padding "0.2rem 0")))

;;; ---------------------------------------------------------------------
;;; Page shell
;;; ---------------------------------------------------------------------

(defparameter *sidebar-scroll-script*
  "document.addEventListener('DOMContentLoaded', function () {
  var sidebar = document.querySelector('.sidebar');
  var active = sidebar && sidebar.querySelector('.active');
  if (!active) return;
  var target = active.offsetTop - (sidebar.clientHeight / 2) + (active.clientHeight / 2);
  sidebar.scrollTop = Math.max(0, target);
});"
  "Scrolls the sidebar so the active (current-page) entry lands as close
   to the middle of the panel as possible, without ever scrolling the
   panel's first row above its own top -- Math.max(0, ...) is exactly
   that clamp, since a negative target only arises when ACTIVE is close
   enough to the top that centering it would require scrolling past 0.
   Runs on every full page load (this app has no client-side routing),
   so it must re-run after each navigation, not just once.")

(defun render-page (title current-segments body-html)
  (spinneret:with-html-string
    (:doctype)
    (:html
     (:head
      (:meta :charset "utf-8")
      (:title title)
      ;; :RAW, not a plain string child -- CSS is not HTML text, and
      ;; <style>'s content model is "raw text" per the HTML spec (browsers
      ;; never entity-decode inside it), so an HTML-escaped ">" or """
      ;; here would reach the browser as the literal characters "&gt;"/
      ;; "&quot;" and silently fail to parse as CSS. Caught by actually
      ;; inspecting the rendered page source, not assumed safe just
      ;; because earlier CSS happened to need no escapable characters.
      (:style (:raw (page-css)))
      ;; Same raw-content-model reasoning as the <style> tag above
      ;; applies to <script>.
      (:script (:raw *sidebar-scroll-script*)))
     (:body
      (:div :class "layout"
        (render-sidebar current-segments)
        (:div :class "content"
          (:raw body-html)))))))

(defun render-not-found (segments)
  (setf (hunchentoot:return-code*) hunchentoot:+http-not-found+)
  (render-page "Not Found" nil
               (spinneret:with-html-string
                 (:h1 "Not Found")
                 (:p :class "missing"
                   (format nil "No OKF page for /~{~a~^/~}" segments)))))

;;; ---------------------------------------------------------------------
;;; Routes
;;; ---------------------------------------------------------------------

(easy-routes:defroute okf-root-route ("/" :method :get :decorators (@html)) ()
  (let ((page (find-page nil)))
    (if page
        (multiple-value-bind (body fields)
            (parse-frontmatter (uiop:read-file-string (page-pathname page)))
          (render-page (or (field-value fields "title") "OKF Repository") nil
                       (concatenate 'string
                                    (render-frontmatter-block fields)
                                    (render-markdown body (page-dir-segments page)))))
        (render-not-found nil))))

(easy-routes:defroute tag-index-route ("/tags/:tag" :method :get :decorators (@html)) ()
  ;; Registered ahead of the "/*path" catch-all below: cl-routes prefers
  ;; a literal-prefix match ("tags" + a variable) over a bare wildcard
  ;; regardless of definition order, but keeping the more specific route
  ;; first in the file still reads correctly to a human.
  (render-page (format nil "Tag: ~a" tag) nil
               (spinneret:with-html-string
                 (:h1 (format nil "Tag: ~a" tag))
                 (let ((matches (pages-tagged tag)))
                   (if matches
                       (:ul :class "tag-page-list"
                         (dolist (p matches)
                           (:li (:a :href (segments->route (tagged-page-segments p))
                                    (tagged-page-title p)))))
                       (:p :class "missing"
                         (format nil "No pages tagged \"~a\"." tag)))))))

(easy-routes:defroute okf-page-route ("/*path" :method :get :decorators (@html)) ()
  (let* ((segments (remove "" path :test #'string=))
         (page (find-page segments)))
    (if page
        (multiple-value-bind (body fields)
            (parse-frontmatter (uiop:read-file-string (page-pathname page)))
          (render-page (or (field-value fields "title") (car (last segments)) "OKF Repository")
                       (page-segments page)
                       (concatenate 'string
                                    (render-frontmatter-block fields)
                                    (render-markdown body (page-dir-segments page)))))
        (render-not-found segments))))

;;; ---------------------------------------------------------------------
;;; Server control
;;; ---------------------------------------------------------------------

(defun start-server ()
  "Starts the Hunchentoot acceptor with easy-routes. Safe to call again
   after STOP-SERVER; signals an error if already running."
  (when *acceptor*
    (error "Server already running on port ~a" *server-port*))
  (setf *acceptor* (make-instance 'easy-routes:easy-routes-acceptor :port *server-port*))
  (hunchentoot:start *acceptor*)
  (format t "~&OKF web server started on port ~a, serving ~a~%" *server-port* *okf-root*)
  *acceptor*)

(defun stop-server ()
  "Stops the running Hunchentoot acceptor, if any."
  (if *acceptor*
      (progn
        (hunchentoot:stop *acceptor*)
        (setf *acceptor* nil)
        (format t "~&OKF web server stopped.~%"))
      (format t "~&OKF web server is not running.~%")))

;;; --- Entry point for testing ---
;;; (okf-web-server:start-server)
;;; (okf-web-server:stop-server)

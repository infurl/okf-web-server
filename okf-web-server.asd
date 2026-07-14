(asdf:defsystem "okf-web-server"
  :description "Renders an OKF markdown bundle as browsable HTML: every
concept file and index.md gets its own page, internal .md links are
rewritten into routes, YAML frontmatter is displayed per-page with tags
as clickable links to a per-tag page listing, and a persistent
hierarchical index tracks the real directory tree."
  :author "OKF project"
  :license "MIT"
  :depends-on ("hunchentoot" "easy-routes" "spinneret" "lass" "3bmd" "cl-ppcre")
  :components ((:file "okf-web-server")))

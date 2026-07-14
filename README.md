# OKF Web Server

A small [Hunchentoot](https://edicl.github.io/hunchentoot/) server that
renders an **Open Knowledge Format (OKF)** markdown bundle — a directory
tree of frontmatter'd `.md` files, described below — as a browsable,
hyperlinked website. No build step, no database, no generated index to
keep in sync: every page, link, and sidebar entry is produced by walking
the real files on disk at request time.

## What it does

* **URLs mirror the filesystem path** — `database/index.md` serves at
  `/database/`, `tooling/sbcl-bridge.md` at `/tooling/sbcl-bridge`.
* **Internal `.md` links are rewritten** to the matching route, so links
  between concept files work the same in the browser as they do reading
  the plain markdown.
* **A persistent hierarchical sidebar** is built by walking the real
  directory tree on every request, so it can never drift from what's
  actually on disk. Only directories that are themselves part of the
  bundle (i.e. have their own `index.md`) are included — a `.git`
  directory or similar stray sibling is never shown or recursed into.
  Navigating to a new page scrolls the sidebar so that page's entry
  lands near the middle of the panel, not buried off-screen.
* **YAML frontmatter renders as a Field/Value table** at the top of each
  page. `description` gets its own styled callout instead of a table
  cell, and `tags` render as clickable pills — clicking one lists every
  page in the bundle carrying that tag.
* Markdown body rendering via [3bmd](https://github.com/3b/3bmd); CSS
  generated with [LASS](https://github.com/Shirakumo/LASS).

## What's an OKF bundle?

[Open Knowledge Format (OKF)](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md)
is a real, versioned, open spec from Google Cloud Platform's
`knowledge-catalog` project — an open, human- and agent-friendly format
for representing knowledge as a directory of markdown files. This server
implements a compliant subset: every concept file (anything other than
`index.md`) opens with a YAML frontmatter block carrying at least a
`type` field, plus optional `title`/`description`/`tags`/`timestamp`.
`index.md` files carry no frontmatter (except optionally at the bundle
root) and are just a heading plus bulleted links to the concepts in that
directory — the same shape this server's own sidebar renders
automatically. `bootstrap-okf.sh`, included in this repo, scaffolds a
minimal compliant bundle from scratch if you don't already have one.

Not yet covered here: the spec's optional `resource` field (a canonical
URI for the concept's underlying asset) — this server displays whatever
frontmatter fields a bundle actually has, so a bundle carrying `resource`
already renders fine, but `bootstrap-okf.sh`'s generated bundle doesn't
document or demonstrate it yet.

## Requirements

SBCL, and via Quicklisp: `hunchentoot`, `easy-routes`, `spinneret`,
`lass`, `3bmd`, `cl-ppcre` (all declared in `okf-web-server.asd`).

## Getting started

```lisp
(push #p"/path/to/okf-web-server/" asdf:*central-registry*)
(ql:quickload :okf-web-server)

;; point it at your bundle and pick a port before starting, if the
;; defaults in okf-web-server.lisp (currently a specific local path,
;; and port 8090) aren't what you want:
(setf okf-web-server::*okf-root* (uiop:ensure-directory-pathname #p"/path/to/your/okf-bundle/"))
(setf okf-web-server::*server-port* 8080)

(okf-web-server:start-server)   ; => http://localhost:8080/
(okf-web-server:stop-server)
```

No existing bundle to point it at? `sh bootstrap-okf.sh` in an empty
directory creates a minimal one (including its own `validate.sh`
structural checker) to render immediately.

## Known gotchas

* **Spinneret HTML-escapes plain string children, including inside
  `(:style ...)`/`(:script ...)`.** Both have a "raw text" content model
  in HTML — browsers never entity-decode their contents — so injecting
  generated CSS/JS as a plain string silently produces broken output
  (`&gt;`, `&quot;`, etc.) that still *looks* fine in a text dump of the
  response but won't parse in a real browser. Wrap it in `(:raw ...)`.
* **`cl-ppcre:regex-replace-all`'s callback signature is not
  `(match &rest registers)`.** It's `(target-string start end
  match-start match-end reg-starts reg-ends)`, where `reg-starts`/
  `reg-ends` are arrays of positions — extract a register with
  `(subseq target-string (aref reg-starts n) (aref reg-ends n))`.

> **Provenance and AI Disclosure**
>
> This project was built through close collaboration between an
  experienced human programmer and Claude Sonnet 5 (Anthropic).
>
> It is published openly for community scrutiny and iteration.

## License

[MIT](LICENSE)

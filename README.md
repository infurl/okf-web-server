# OKF Web Server

A small [Hunchentoot](https://edicl.github.io/hunchentoot/) server that
renders an **Open Knowledge Format (OKF)** markdown bundle — a directory
tree of frontmatter'd `.md` files — as a browsable, hyperlinked website.
No build step, no database, no generated index to keep in sync: every
page, link, and sidebar entry is produced by walking the real files on
disk at request time.

For design rationale and internals, see [MAINTENANCE.md](MAINTENANCE.md).

> **Provenance and AI Disclosure**
>
> This project was built through close collaboration between an
  experienced human programmer and Claude Sonnet 5 (Anthropic).
>
> It is published openly for community scrutiny and iteration.

## What it does

* **URLs mirror the filesystem path** — `database/index.md` serves at
  `/database/`, `tooling/sbcl-bridge.md` at `/tooling/sbcl-bridge`.
* **Internal `.md` links are rewritten** to the matching route, and a
  link to a `.md` file outside the bundle is rewritten to a read-only
  `/file/...` view instead (with syntax highlighting for non-markdown
  source files).
* **A persistent hierarchical sidebar**, built by walking the real
  directory tree on every request, so it can never drift from what's
  on disk.
* **YAML frontmatter renders as a Field/Value table** at the top of
  each page, with `tags` as clickable pills (`/tags/:tag` lists every
  page carrying that tag).
* Markdown body rendering via [3bmd](https://github.com/3b/3bmd)
  (including GitHub-style fenced code blocks with syntax highlighting);
  CSS generated with [LASS](https://github.com/Shirakumo/LASS).

### What's an OKF bundle?

[Open Knowledge Format (OKF)](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md)
is a real, versioned, open spec from Google Cloud Platform's
`knowledge-catalog` project — a directory of markdown files as a
human- and agent-friendly knowledge representation. This server
implements a compliant subset: every concept file (anything other
than `index.md`) opens with a YAML frontmatter block carrying at least
a `type` field, plus optional `title`/`description`/`tags`/
`timestamp`. `index.md` files carry no frontmatter (except optionally
at the bundle root) and are just a heading plus bulleted links to the
concepts in that directory. No existing bundle to point this at? `sh
bootstrap-okf.sh` scaffolds a minimal compliant one at `./okf/` (with
its own `automation/validate.sh` structural checker).

## Quickstart

```lisp
(push #p"/path/to/okf-web-server/" asdf:*central-registry*)
(ql:quickload :okf-web-server)

;; point it at your bundle before starting -- the only default in
;; okf-web-server.lisp you'll always need to override, since it's a
;; specific local path:
(setf okf-web-server::*okf-root* (uiop:ensure-directory-pathname #p"/path/to/your/okf-bundle/"))

(okf-web-server:start-server)   ; => http://localhost:8080/ (default port; see Cookbook to change it)
```

Verify it's actually serving your bundle:

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/
# 200
```

...and open that URL in a browser — the sidebar should show your
bundle's real directory structure.

```lisp
(okf-web-server:stop-server)
```

## Reference

* **Exported symbols**: `start-server`, `stop-server` — the full public
  API. Everything else, including the two configuration variables used
  above (`okf-web-server::*okf-root*`, `okf-web-server::*server-port*`),
  is internal and accessed via `::`, not `:`.
* **Requirements**: SBCL, and via Quicklisp: `hunchentoot`,
  `easy-routes`, `spinneret`, `lass`, `3bmd`, `3bmd-ext-code-blocks`,
  `cl-ppcre`, `colorize` (all declared in `okf-web-server.asd`).
* **Routes**:
  - `/` and `/*path` — a bundle page (`index.md` for a directory route,
    the matching `.md` concept file otherwise).
  - `/tags/:tag` — every bundle page carrying that tag.
  - `/audit` — bundle-wide structural report (see MAINTENANCE.md for
    what it checks).
  - `/file/*path` — read-only view of a file outside the bundle
    (markdown rendered, recognized source languages syntax-highlighted
    via `colorize`, everything else as plain text or an image).

## Cookbook

**Point the server at a different bundle or port without editing the
source**, from a fresh image before calling `start-server`:

```lisp
(setf okf-web-server::*okf-root* (uiop:ensure-directory-pathname #p"/path/to/other-bundle/"))
(setf okf-web-server::*server-port* 8081)
```

**Scaffold a new bundle from scratch:**

```bash
mkdir my-bundle && cd my-bundle
sh /path/to/okf-web-server/bootstrap-okf.sh
# creates ./okf/ -- run 'sh okf/automation/validate.sh okf' to check it
```

**Check a bundle for structural problems from the REPL**, without
starting the Hunchentoot server at all:

```lisp
(okf-web-server::audit-bundle)   ; => a list of FINDING structs, () if clean
```

Or start the server and visit `/audit` for the same report rendered as
HTML — see MAINTENANCE.md for what the checks actually look for.

## License

[MIT](LICENSE)

# OKF Web Server: maintenance notes

Design rationale and internals for whoever is changing this code rather
than just running it. For usage, see [README.md](README.md).

## File map

* **`okf-web-server.lisp`** — the core: configuration, frontmatter
  parsing, markdown rendering (`render-markdown`), the sidebar, and the
  bundle-page routes (`/`, `/*path`, `/tags/:tag`).
* **`external-files.lisp`** — the `/file/*path` route: read-only
  rendering of files outside the bundle (markdown via 3bmd, source code
  via `colorize`, images, or plain text, chosen by `file-kind`).
* **`audit.lisp`** — the `/audit` route: a Lisp-native structural audit
  of the whole bundle, reusing this project's own frontmatter/link
  helpers rather than re-parsing YAML/Markdown in shell the way
  `automation/validate.sh` (part of the OKF bundle spec, not this
  project) does. Separates hard spec violations ("errors") from
  spec-tolerated-but-worth-flagging issues ("warnings") per
  `specification/core-spec.md` section 4's "broken links are tolerated,
  not malformed" wording — a distinction `validate.sh` doesn't make.
  Not run automatically on every request to `/`: walking the whole tree
  and parsing every frontmatter block is real per-request cost not
  worth paying on the busiest route. `validate.sh` is deliberately left
  alone alongside it (still useful standalone, no SBCL dependency, fine
  for CI/pre-commit) — `/audit` is a richer, web-facing companion, not
  a replacement.
* **`bootstrap-okf.sh`** — scaffolds a minimal compliant bundle
  (including its own `validate.sh`) from scratch.

## Known gotchas

* **Spinneret HTML-escapes plain string children, including inside
  `(:style ...)`/`(:script ...)`.** Both have a "raw text" content
  model in HTML — browsers never entity-decode their contents — so
  injecting generated CSS/JS as a plain string silently produces broken
  output (`&gt;`, `&quot;`, etc.) that still *looks* fine in a text
  dump of the response but won't parse in a real browser. Wrap it in
  `(:raw ...)`.
* **`cl-ppcre:regex-replace-all`'s callback signature is not `(match
  &rest registers)`.** It's `(target-string start end match-start
  match-end reg-starts reg-ends)`, where `reg-starts`/`reg-ends` are
  arrays of positions — extract a register with `(subseq target-string
  (aref reg-starts n) (aref reg-ends n))`.
* **Plain `3bmd` doesn't render GitHub-style ` ``` ` fenced code
  blocks as `<pre><code>` at all** — it falls through to CommonMark's
  original inline-code-span rule, producing one giant `<p><code>` with
  the language tag as the first "word" and every line-wrap coming from
  ordinary paragraph flow, not a stylesheet issue. Needs
  `3bmd-ext-code-blocks` loaded and `3bmd-code-blocks:*code-blocks*`
  bound `T` around every `3bmd:parse-string-and-print-to-stream` call
  site — there are two independent ones (`render-markdown` in
  `okf-web-server.lisp` for bundle pages, `serve-external-markdown` in
  `external-files.lisp` for `/file/...` pages), and missing the
  binding on just one of them silently produces literal backtick text
  on that route while the other renders correctly — confirmed directly
  by hitting both routes and inspecting the actual HTML, not diagnosed
  from a stylesheet guess (2026-07-19: this is exactly what happened —
  the fix landed on the bundle-page call site first, and the `/file/`
  one was found broken separately). That extension also does its own
  `colorize`-based syntax highlighting by default, which needs
  `colorize:*coloring-css*` injected into the page `<head>` (see
  `render-page`) or the highlighting `<span>`s render with no color at
  all.
* **Hot-reloading the whole file re-runs every top-level `defparameter`
  unconditionally** (that's what `defparameter` is for) — this used to
  silently undo a runtime `(setf *server-port* ...)` override from a
  previous session, back when the source default was a different port.
  Fixed by making the real intended default match the source itself,
  so this class of trap can't recur for `*server-port*` specifically —
  still worth remembering for any *other* parameter someone overrides
  at eval time instead of in the source.

## Design note: external file linking (`external-files.lisp`)

A markdown link whose target resolves to a real file outside the
bundle renders instead of being silently broken: `.md` as HTML, images
served raw, and known source extensions syntax-highlighted via
`colorize` (Common Lisp/C/C++/Java/Python/Haskell/Scheme/Clojure/
Elisp — its actual language coverage, no more; other recognized text
falls back to a plain `<pre>` view). A target starting with exactly
`/workspace/` is treated as a literal absolute filesystem path
(currently hardcoded to this one path prefix — a real portability
limitation for anyone deploying this outside a `/workspace/`-rooted
container, not yet made configurable); any other leading `/` stays
bundle-root-relative per the OKF spec's own link-resolution rule.
External `http(s)` links get a small "↗" badge — assumed reachable
from a real browser, never fetched/verified server-side.

Checked directly whether this duplicated the OKF spec's own `resource`
frontmatter field, or diverged from other independent OKF
implementations — neither: `resource` is unrelated (single canonical
metadata URI per concept, not body-content link rendering), and no
other implementation found (`understory`, `okf-lint`, `okfbundle.com`)
actually resolves or renders links to non-bundle files this way —
`understory` notably went the opposite way, sandboxing all paths to
the bundle root rather than resolving out. (Full research trail
recorded in the OKF bundle this project was developed alongside,
`lessons-learned/research/okf-external-link-policy.md`, if you have
access to it — not included in this repo.)

**Policy adopted**: reference a file outside the bundle via a real
markdown link carrying its full absolute path, with a reader-friendly
partial name kept as the visible display text, rather than a bare-text
mention this server has no way to turn into a working link.

## Known gaps

* The OKF spec's optional `resource` field (a canonical URI for a
  concept's underlying asset) isn't demonstrated anywhere yet — this
  server displays whatever frontmatter fields a bundle actually has, so
  a bundle carrying `resource` already renders fine, but
  `bootstrap-okf.sh`'s generated bundle doesn't document or demonstrate
  it, and no bundle in this workspace uses it yet either (see the
  workspace inbox NOTES.md).

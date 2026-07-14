#!/bin/sh
# bootstrap_okf.sh
#
# Initializes an OKF (Open Knowledge Format) repository containing
# meta-knowledge on how to build, extend, and maintain OKF repositories.
#
# OKF itself is a real, external, versioned spec, not invented here:
# https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md
# (v0.1 as of this writing). What this script generates is a distilled,
# practical subset of that spec -- see okf/specification/core-spec.md's
# own "Provenance" section in the generated bundle for exactly what's
# covered and what isn't yet.
#
# This is a synthesis of two earlier drafts, both written with explicit
# reference to the spec above:
#   - v1 contributed the detailed core-spec content, the deprecation
#     workflow, and the synchronous code/context update rules.
#   - v2 contributed the hierarchical progressive-disclosure layout,
#     the concept template, and the YAML conflict-resolution rules.
#
# Corrections made during synthesis:
#   - index.md files now contain NO frontmatter, per the actual OKF spec
#     ("Index files contain no frontmatter"). Both source drafts violated
#     this. Every index.md below is body-only markdown link listings.
#   - The meta-repo now follows its own progressive-disclosure rule:
#     every module directory (specification/, maintenance/, automation/,
#     database/, logic/) gets its own local index.md, not just the two
#     "application" modules.
#   - automation/pipelines.md no longer just describes a validation
#     script in prose -- automation/validate.sh actually exists and
#     implements the checks it describes.
#   - validate.sh strips inline-code spans before scanning for links, and
#     every illustrative link in the generated content points at a real
#     file, so a fresh bundle passes its own validator out of the box.
#   - Dropped a 7-bit US-ASCII requirement that appeared in earlier
#     drafts. It is NOT part of the OKF spec -- section 4 of the spec
#     states concept files are UTF-8 markdown. Enforcing ASCII-only text
#     in a bundle meant for public, multi-language use would gratuitously
#     exclude non-English names, quotes, and terms. If you personally
#     want an ASCII-only check for your own local files, keep it in your
#     own editor/linter config, not in the shared bundle rules.
#   - index.md files still carry no frontmatter, with one spec-defined
#     exception: the bundle ROOT index.md MAY declare `okf_version` in a
#     frontmatter block (the only field the spec assigns meaning to
#     there). validate.sh now reflects that exception.
#
# Revised 2026-07-14, after roughly a week of real use building on a
# bundle this script generated:
#   - Dropped the hardcoded "database" and "logic" application modules.
#     Both baked in domain assumptions (PostgreSQL, Common Lisp) specific
#     to whatever project this script was first written for, not to OKF
#     generally -- and in a week of real, active use, "database" was
#     never touched even once, because that project never had one.
#     Guessing a project's domain shape upfront turned out to be the
#     wrong call; real modules (tooling references, day-to-day workflow
#     notes) emerged organically instead, added by hand once the
#     project's actual shape became clear.
#   - Added lessons-learned/ (with notebook.md) as a default module
#     instead, since a running, dated log of non-obvious gotchas and
#     verified findings proved genuinely universal across that same week
#     -- unlike "database", every project accumulates knowledge like
#     this regardless of domain.
#   - validate.sh gained a check: a directory containing markdown content
#     (directly, or in a subdirectory) but missing its own index.md is
#     now flagged as an error. This was a real, previously-invisible gap
#     -- a real renderer built against this spec (okf-web-server) treats
#     a directory without index.md as entirely outside the bundle, never
#     shown, never recursed into, and validate.sh had no way to catch
#     that mistake before shipping it.
#
# Revised again 2026-07-14, same day, after realizing this script (and
# its generated core-spec.md) never actually credited OKF's real source:
#   - core-spec.md gained a "Provenance" section citing the real spec URL
#     explicitly, and this header comment now names it too, rather than
#     only describing "two earlier drafts" without saying what grounded
#     them.
#   - Documented the real spec's `resource` field (a canonical URI for a
#     concept's underlying asset) in core-spec.md's optional-fields list
#     -- present in the real spec since it was first published, so this
#     was an oversight in the original drafting, not a recent spec
#     change. Not yet demonstrated in any of this script's own generated
#     example content.
#
# Compatible with Debian stable (POSIX sh).

set -e

# ---------------------------------------------------------------------
# Create the directory structure
# ---------------------------------------------------------------------
mkdir -p okf/specification
mkdir -p okf/maintenance
mkdir -p okf/automation
mkdir -p okf/lessons-learned

# ---------------------------------------------------------------------
# okf/index.md  (root index -- NO frontmatter, per spec)
# ---------------------------------------------------------------------
cat << 'EOF' > okf/index.md
---
okf_version: "0.1"
---
# OKF Repository Management Meta-Knowledge Base

This repository is a self-referential, machine-readable guide for AI coding
agents and human developers. It documents the structural standards,
maintenance procedures, and automation strategies needed to keep an Open
Knowledge Format (OKF) bundle accurate and useful, including this one.

This index intentionally stays shallow. Each linked sub-index describes its
own module in more depth, so an agent only needs to load the sections it
actually needs.

## Core System Documentation

* [Specification Module](specification/index.md) - rules governing
  directory structure, YAML frontmatter, and file identity.
* [Maintenance Module](maintenance/index.md) - how to update concepts,
  retire dead knowledge, and resolve conflicts.
* [Automation Module](automation/index.md) - scripts and CI rules that
  validate compliance and generate metadata.
* [Standard Concept Template](template-concept.md) - blueprint for
  creating new concept files.

## Project-Specific Modules

This bundle intentionally starts with no project-specific modules of its
own -- guessing a project's domain shape upfront (a database module? a
core-logic module?) turned out to be the wrong call in practice. Add
modules here as your own project's real shape becomes clear (a
schema/data module, a core-logic module, a reference module for external
tools you depend on, ...), using
[Standard Concept Template](template-concept.md) as the starting point
for each new concept file, and give every new module its own `index.md`
linked from here.

## Development Practices

* [Lessons Learned Module](lessons-learned/index.md) - a running,
  reverse-chronological notebook of non-obvious gotchas and verified
  findings from actually building and using this project.

## History

* [Change Log](log.md) - chronological record of updates to this bundle.
EOF

# ---------------------------------------------------------------------
# okf/log.md  (changelog -- frontmatter allowed, not a reserved-empty file)
# ---------------------------------------------------------------------
cat << 'EOF' > okf/log.md
---
type: Changelog
title: Repository Change Log
description: >
  Chronological tracking of structural updates made to this OKF repository.
timestamp: 2026-07-04T18:00:00Z
---

# Repository Change Log

All major modifications, re-architectures, or bulk additions to this OKF
knowledge base are recorded here in reverse chronological order.

## [2026-07-04] - Synthesis of v1 and v2
* Merged the flat, detail-rich structure of the original bootstrap script
  with the hierarchical, progressive-disclosure structure of the second
  draft.
* Corrected index.md files across the repository to remove frontmatter,
  in line with the OKF specification.
* Extended progressive disclosure to every module directory, not only
  the application-facing ones.
* Added `automation/validate.sh`, a real implementation of the checks
  previously only described in prose.
* Consolidated the deprecation workflow (v1) and the YAML conflict
  resolution rules (v2) into a single maintenance guide.

## [2026-07-04] - Spec accuracy pass
* Removed a 7-bit US-ASCII text constraint inherited from earlier
  drafts. It was never part of the OKF spec (which requires UTF-8) and
  would have needlessly excluded non-English contributors.
* Corrected validate.sh and core-spec.md: the bundle-root index.md may
  declare `okf_version` in frontmatter; every other index.md still
  carries none.
* validate.sh now also resolves absolute, bundle-root-relative links
  (leading `/`), matching section 5.1 of the spec.

## [2026-07-14] - Dropped presumed application modules; added lessons-learned
* Removed the hardcoded `database`/`logic` starter modules. A week of
  real use on the bundle this bootstrapper was revised against showed
  they baked in domain assumptions (PostgreSQL, Common Lisp) that don't
  generalize, and one went entirely unused for a project with no
  database at all.
* Added `lessons-learned/` (with `notebook.md`) as a starter module
  instead -- a running gotchas/findings log proved genuinely
  domain-agnostic in that same week, unlike the modules it replaces.
* `validate.sh` now flags a directory that contains markdown content but
  has no `index.md` of its own, since a real renderer built against this
  spec treats such a directory as entirely outside the bundle.

## [2026-07-14] - Credited OKF's real source; documented the `resource` field
* `core-spec.md` gained a "Provenance" section: OKF is a real, external,
  versioned spec from Google Cloud Platform's `knowledge-catalog`
  project, not invented for this bundle. Previously undocumented here.
* Documented the real spec's optional `resource` field (a canonical URI
  for a concept's underlying asset) in `core-spec.md`'s optional-fields
  list. It has been in the real spec since publication, so this was an
  oversight in the original drafting, not something the spec only
  recently added.
EOF

# ---------------------------------------------------------------------
# okf/template-concept.md
# ---------------------------------------------------------------------
cat << 'EOF' > okf/template-concept.md
---
type: Concept_Template
title: Placeholder Title
description: >
  A single-sentence description of the concept, wrapped using the YAML
  folded block scalar style for readable diffs and terminal viewing.
tags: [template, placeholder]
timestamp: 2026-07-04T18:00:00Z
---

# Concept Title

Provide a high-quality overview of the component, dataset, or logic block
here. Write for an agent that has no other context: state what this thing
is before describing how it works.

## Structural Elements

Use regular markdown headings, bullet points, or tables to break down
technical specifications clearly.

## Dependencies

* Link to related concepts using relative markdown links, e.g.
  [Lessons Learned Module](lessons-learned/index.md).

## Notes

* Delete this template file's frontmatter fields you don't need, but never
  remove `type`.
* Update `timestamp` whenever you materially change this file's content.
EOF

# ---------------------------------------------------------------------
# okf/specification/index.md
# ---------------------------------------------------------------------
cat << 'EOF' > okf/specification/index.md
# Specification Module

Structural rules that every concept file in this bundle must follow.

## Concepts

* [Core Specification](core-spec.md) - mandatory fields, file identity,
  linking rules, and encoding constraints.
EOF

# ---------------------------------------------------------------------
# okf/specification/core-spec.md
# ---------------------------------------------------------------------
cat << 'EOF' > okf/specification/core-spec.md
---
type: Specification
title: Open Knowledge Format Core Rules
description: >
  Detailed structural guidelines, mandatory metadata fields, and semantic
  linking rules for OKF concepts.
tags: [spec, yaml, markdown, syntax]
timestamp: 2026-07-14T21:00:00Z
---

# Open Knowledge Format Core Specification

The Open Knowledge Format (OKF) is optimized for deterministic context
injection into Large Language Models (LLMs). It relies on plain text files
organized logically within a directory tree. No database, runtime, or SDK
is required to read or write it.

## 0. Provenance

OKF is a real, external, versioned spec, not invented for this bundle:
https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md
(v0.1 as of this writing). This document is a distilled, practical
subset covering the structural rules a bundle and its tooling need day
to day; it is not a substitute for the real spec, and does not yet cover
everything in it. Known gap: the real spec's optional `resource` field
(see section 3) is documented here but not yet demonstrated in this
bundle's own generated content.

## 1. File Structure

Every concept must exist as an independent Markdown file with the `.md`
extension, divided into two sections:

1. **YAML Frontmatter Block:** at the absolute beginning of the file,
   enclosed between triple-dash (`---`) lines.
2. **Markdown Body:** follows immediately after the closing frontmatter
   block.

## 2. Reserved Filenames

Two filenames have defined meaning at any level of the directory tree and
MUST NOT be used for ordinary concept documents:

* `index.md` - a directory listing for progressive disclosure. Index
  files contain NO frontmatter, with one exception: the bundle's ROOT
  `index.md` MAY carry a frontmatter block whose only defined field is
  `okf_version` (e.g. `okf_version: "0.1"`), declaring which version of
  the spec the bundle targets. Every other index.md, at any deeper
  level, stays frontmatter-free. The body is one or more sections, each
  a heading followed by a bulleted list of markdown links, ideally
  including the linked concept's description.
* `log.md` - a chronological history of updates at that level of the
  hierarchy. Unlike index.md, log.md files DO carry frontmatter, since a
  changelog is itself a concept with a type.

## 3. Mandatory and Optional Frontmatter Fields (concept files only)

### The `type` Field (Mandatory)

Every concept file MUST contain the `type` key. The value should be a
PascalCase or snake_case string classifying the resource, e.g.
`Database_Table`, `Lisp_Macro`, `API_Endpoint`, `System_Architecture`.

### Standard Optional Fields

* `title`: a short, human-readable name for the concept.
* `description`: a one- or two-sentence summary of the file's content.
* `resource`: a canonical URI identifying the underlying asset this
  concept describes (e.g. a link to a live dashboard, a database
  console, an API's own documentation page). Omit entirely for concepts
  describing an abstract idea or process rather than a concrete,
  linkable asset.
* `tags`: an array of strings used for broad categorization.
* `timestamp`: an ISO 8601 UTC string tracking when the concept was last
  verified.

Consumer tools are fault-tolerant: unrecognized custom fields in the
frontmatter block should be safely ignored, not treated as errors.

## 4. Concept Identity and Linking

* **Identity:** a concept's unique identifier is its relative path from
  the OKF root, with the `.md` suffix removed. The identity of this file
  is `specification/core-spec`.
* **Linking:** concepts connect using standard relative Markdown links.
  For example, the root index links to this file with a target path of
  `specification/core-spec.md`.
* **Broken links are tolerated, not malformed:** a link whose target does
  not yet exist may simply represent not-yet-written knowledge. Treat
  this as a warning during validation, not necessarily a hard failure.

## 5. Progressive Disclosure via Sub-Indexes

Any directory representing a distinct module (a subsystem, a schema, a
package) SHOULD include its own local `index.md`. The root index links to
module sub-indexes rather than enumerating every concept directly, so an
agent can load only the section of the knowledge base relevant to its
current task instead of the whole bundle.

## 6. Text Encoding

Every concept file is UTF-8 markdown, per the OKF spec. There is no
ASCII-only requirement, and none should be added for a bundle meant to
be read and contributed to by non-English speakers. If a particular
tool in your own pipeline needs ASCII-safe filenames or paths, constrain
that at the tool boundary rather than in the bundle's content rules.
EOF

# ---------------------------------------------------------------------
# okf/maintenance/index.md
# ---------------------------------------------------------------------
cat << 'EOF' > okf/maintenance/index.md
# Maintenance Module

Procedures for keeping this OKF bundle synchronized with the codebase it
describes, and for resolving conflicts when multiple contributors (human
or AI) edit it concurrently.

## Concepts

* [Maintenance and Review Workflows](workflows.md) - synchronous update
  rules, deprecation handling, and YAML conflict resolution.
EOF

# ---------------------------------------------------------------------
# okf/maintenance/workflows.md
# ---------------------------------------------------------------------
cat << 'EOF' > okf/maintenance/workflows.md
---
type: Procedure_Guide
title: OKF Maintenance and Review Workflows
description: >
  Step-by-step procedures for human operators and AI agents to update,
  sync, deprecate, and resolve conflicts in knowledge concepts.
tags: [maintenance, git, workflow, concurrency]
timestamp: 2026-07-04T18:00:00Z
---

# OKF Maintenance and Review Workflows

An OKF repository is an active reflection of a software project. If the
code changes, the corresponding OKF concepts must change within the same
development cycle. Stale knowledge is worse than missing knowledge,
because it is trusted by default.

## 1. Synchronous Code and Context Updates

When implementing a new feature, refactoring existing logic, or modifying
a database schema:

1. Modify the source code files.
2. Locate the corresponding OKF concept files via the relevant module
   sub-index (whichever project-specific module you've created for this
   part of the system -- see the [root index](../index.md) -- or the
   [Lessons Learned Module](../lessons-learned/index.md) if it's a
   general finding rather than a specific concept).
3. Update the Markdown body and the YAML frontmatter inside the affected
   concept files. Use [template-concept.md](../template-concept.md) if a
   new concept is required.
4. Update the `timestamp` field to the current UTC time.
5. Commit both the code changes and the OKF file updates in the same Git
   commit or pull request.

## 2. Managing Deprecated Knowledge

Do not delete old concept files immediately if other parts of the system
still refer to them historically. Instead:

1. Change the `type` field in the frontmatter to `Deprecated_Concept`.
2. Append a short warning block at the top of the Markdown body explaining
   what replaced the concept and linking to its replacement.
3. Remove links to the deprecated file from any `index.md` that lists it,
   so it no longer surfaces during normal progressive disclosure, while
   the file itself remains resolvable for anything that still links to it
   directly.

## 3. Conflict Resolution in YAML Blocks

To prevent automated utilities and coding agents from creating avoidable
merge conflicts:

* **Validation hooks stay read-only.** Pre-commit hooks may check that
  `type` and `timestamp` exist and that the file is valid YAML/Markdown,
  but they must never silently rewrite a file during a commit.
* **Whoever edits a file owns its metadata for that edit.** The human or
  agent making a content change is responsible for updating that file's
  frontmatter values themselves, rather than a separate automated pass
  doing so out-of-band.
* **Treat conflicts as ordinary text conflicts.** If concurrent edits
  collide, resolve the YAML block the same way you would resolve any
  other text conflict, with standard Git merge tooling. There is no
  special-cased OKF merge strategy.

## 4. Local Coding Agent Instructions

When you, the local coding agent, are asked to write code that changes
system behavior:

* Scan the relevant module sub-index first to understand current
  architecture before writing new code.
* Modify or create the necessary OKF concept files as part of the same
  change, not as a follow-up task.
* Never leave the OKF directory in a stale state after modifying
  application logic. If you are unsure which concept file covers the
  code you changed, create a new one from
  [template-concept.md](../template-concept.md) rather than skipping
  documentation entirely.
EOF

# ---------------------------------------------------------------------
# okf/automation/index.md
# ---------------------------------------------------------------------
cat << 'EOF' > okf/automation/index.md
# Automation Module

Scripts and CI rules that keep this bundle structurally sound.

## Concepts

* [Verification and Generation Pipelines](pipelines.md) - what gets
  checked and why.
* [validate.sh](validate.sh) - a working implementation of the checks
  described in pipelines.md. Not a concept file; a runnable script.
EOF

# ---------------------------------------------------------------------
# okf/automation/pipelines.md
# ---------------------------------------------------------------------
cat << 'EOF' > okf/automation/pipelines.md
---
type: Automation_Guide
title: Verification and Generation Pipelines
description: >
  Specifications for automated scripts that validate OKF compliance and
  auto-generate structural metadata.
tags: [automation, testing, scripts, validation]
timestamp: 2026-07-04T18:00:00Z
---

# Verification and Generation Pipelines

Automation ensures that the OKF repository remains structurally sound,
syntax-compliant, and free of broken internal links, without requiring a
human to check every file by hand.

## 1. Validation Checks

[validate.sh](validate.sh) in this directory implements the following
checks and can be run locally or wired into CI:

* **Frontmatter validation:** every `.md` file except `index.md` must
  begin with a `---` delimited YAML frontmatter block, and that block
  must contain a `type` key.
* **Index purity:** `index.md` files must NOT contain a frontmatter
  block, with one exception: the bundle-root `index.md` MAY declare
  `okf_version` in its frontmatter, since that is the only place the
  spec assigns meaning to frontmatter on an index file.
* **Link integrity:** every relative markdown link to a `.md` file is
  checked to confirm the target exists, whether the link is relative to
  the linking file's own directory or written as an absolute,
  bundle-root-relative path starting with `/`.
* **Directory membership:** every directory containing markdown content
  (directly, or in a subdirectory) must have its own `index.md`. Without
  one, a bundle-aware renderer has no way to know the directory belongs
  to the bundle at all, and silently treats it and everything beneath it
  as outside it -- never shown, never linked, never recursed into.

This bundle follows the spec's UTF-8 requirement for concept files;
there is no ASCII-only rule to check, intentionally, since this bundle
is meant to be read and extended by non-English speakers too.

Run it with:

    sh okf/automation/validate.sh okf

## 2. Automated Generation

You can write build scripts to auto-generate parts of the repository.
For instance, a pre-commit hook can parse a PostgreSQL migration folder
and automatically draft an OKF concept file for a newly added table,
filling in `type: Database_Table` and a starter description, which a
human or agent then refines.

## 3. Tooling Ecosystem

Because this bundle is strict Markdown plus standard YAML block scalars,
it can also be compiled by ordinary static-site tools such as MkDocs, or
rendered locally with a terminal Markdown viewer like glow, without any
OKF-specific tooling at all.
EOF

# ---------------------------------------------------------------------
# okf/automation/validate.sh  (actual working validator)
# ---------------------------------------------------------------------
cat << 'VALIDATE_EOF' > okf/automation/validate.sh
#!/bin/sh
# validate.sh
# Validates an OKF bundle for structural compliance:
#   - every concept .md file has a frontmatter block with a `type` field
#   - index.md files have NO frontmatter, EXCEPT the bundle-root
#     index.md, which may declare `okf_version` in its frontmatter
#   - every relative markdown link to a .md file resolves to a real file
#   - every directory containing markdown content (directly, or in a
#     subdirectory) has its own index.md -- without one, a bundle-aware
#     renderer has no way to know the directory is part of the bundle at
#     all, and silently omits it and everything beneath it
#
# Usage: sh validate.sh [path-to-okf-root]
# Exit status: 0 if clean, 1 if any errors were found.

ROOT="${1:-.}"
ROOT_ABS=$(cd "$ROOT" 2>/dev/null && pwd)
ERRFILE=$(mktemp)
trap 'rm -f "$ERRFILE"' EXIT

if [ -z "$ROOT_ABS" ]; then
  echo "ERROR: '$ROOT' is not a directory"
  exit 1
fi

find "$ROOT" -name '*.md' -print | while IFS= read -r f; do
  base=$(basename "$f")
  dir=$(dirname "$f")
  dir_abs=$(cd "$dir" && pwd)
  first_line=$(head -n 1 "$f")

  if [ "$base" = "index.md" ]; then
    if [ "$first_line" = "---" ] && [ "$dir_abs" != "$ROOT_ABS" ]; then
      echo "ERROR: $f is a non-root index.md but contains YAML frontmatter (only the bundle-root index.md may declare okf_version)" >> "$ERRFILE"
    fi
  else
    if [ "$first_line" != "---" ]; then
      echo "ERROR: $f is missing a YAML frontmatter block" >> "$ERRFILE"
    else
      type_found=$(awk '
        /^---$/ { delim++; next }
        delim == 1 && /^type:/ { print "yes"; exit }
        delim == 2 { exit }
      ' "$f")
      if [ -z "$type_found" ]; then
        echo "ERROR: $f is missing the mandatory type field in its frontmatter" >> "$ERRFILE"
      fi
    fi
  fi

  sed -E 's/`[^`]*`//g' "$f" | grep -o '\[[^]]*\]([^)]*\.md)' 2>/dev/null | sed -E 's/.*\(([^)]*)\)/\1/' | while IFS= read -r link; do
    case "$link" in
      http://*|https://*) continue ;;
      /*) target="$ROOT_ABS$link" ;;
      *) target="$dir/$link" ;;
    esac
    if [ ! -f "$target" ]; then
      echo "ERROR: $f links to missing file: $link" >> "$ERRFILE"
    fi
  done
done

find "$ROOT" -type d ! -path '*/.git' ! -path '*/.git/*' | while IFS= read -r d; do
  if [ ! -f "$d/index.md" ] && find "$d" -name '*.md' ! -path '*/.git/*' -print -quit | grep -q .; then
    echo "ERROR: $d contains markdown content (directly or in a subdirectory) but has no index.md of its own -- a bundle-aware renderer (e.g. okf-web-server) will treat it as outside the bundle entirely, never shown, never recursed into" >> "$ERRFILE"
  fi
done

if [ -s "$ERRFILE" ]; then
  cat "$ERRFILE"
  echo ""
  echo "Validation FAILED for '$ROOT'."
  exit 1
else
  echo "Validation PASSED: '$ROOT' is a compliant OKF bundle."
  exit 0
fi
VALIDATE_EOF
chmod +x okf/automation/validate.sh

# ---------------------------------------------------------------------
# okf/lessons-learned/index.md
# ---------------------------------------------------------------------
cat << 'EOF' > okf/lessons-learned/index.md
# Lessons Learned Module

A generic notebook for non-obvious gotchas, workarounds, and verified
findings from actual use of this project's tools and codebase -- the
things that are easy to rediscover the hard way if not written down.
Distinct from the root [Change Log](../log.md), which tracks structural
changes to this OKF bundle itself, not knowledge about the project.

## Concepts

* [Lessons Learned Notebook](notebook.md) - a running, reverse-chronological
  log of dated entries.
EOF

# ---------------------------------------------------------------------
# okf/lessons-learned/notebook.md
# ---------------------------------------------------------------------
cat << 'EOF' > okf/lessons-learned/notebook.md
---
type: Lessons_Log
title: Lessons Learned Notebook
description: >
  A running, reverse-chronological log of non-obvious gotchas and verified
  findings from actual use of this project's tools and codebase.
tags: [lessons, gotchas, notebook]
timestamp: 2026-07-04T18:00:00Z
---

# Lessons Learned Notebook

Entries are added as they're discovered, newest first. Unlike the root
[Change Log](../log.md), this tracks knowledge about the project, not
structural edits to OKF itself. If an entry grows into something that
deserves its own reference doc, move it to whichever project-specific
module fits it and leave a short pointer here. If the entry itself is
substantial primary-source material (e.g. a raw research transcript)
rather than a short summary, consider a `research/` sub-module here
instead, with its own `index.md`, so a reader can skip the raw material
unless they want the full trail behind a summarized finding.

## [Date] - Title of the finding

* Entries go here as they're discovered. Delete this placeholder once
  the first real one is added.
EOF

# ---------------------------------------------------------------------
# Final Execution Notice
# ---------------------------------------------------------------------
echo "OKF repository initialized successfully in the './okf' directory."
echo "Run 'sh okf/automation/validate.sh okf' to check compliance."

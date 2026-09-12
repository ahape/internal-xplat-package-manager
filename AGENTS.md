## What this repo is

Cross-platform bootstrap for the toolchain this package manager expects:
jq, ripgrep, GitHub CLI, Azure CLI, .NET SDK, Node (nvm on Unix, fnm on
Windows), and PowerShell LTS. Unix uses a shell script (Homebrew on
macOS, apt on Debian/Ubuntu). Windows uses cmd or native Windows PowerShell
with Chocolatey.

## Style

- Whitespace rules: `.editorconfig`. Encoding rules: `.gitattributes`.
- ASCII-only prose: '-' not em dash, '->' not arrow.
- No decorative comment dividers, no emojis, no ASCII art unless it is
 rot-resistant and dramatically simplifies complexity.

### Comments

Comments answer _why_ or surface non-obvious constraints; they never restate
the code or point at things that move.

- Good: design or performance trade-offs
 (`// Long-lived validator avoids 200 ms spin-up per request`), decoding
 dense code, minimal ticket refs (`// Fixes DEV-1234`).
- Bad: call-graph or file references (`// Called from FooAdapter.Process()`),
 ticket narratives, restating the obvious or future intentions.

Longer context belongs in module- or file-level comments.

### Documentation

- Lead with the TL;DR and the constraints that actually matter.
- Informative over didactic; write for a competent engineer who is not a
 specialist in this subsystem.
- Perennial knowledge only (architecture, invariants, operational gotchas).
 No absolute paths, exact symbol names, or ticket histories -- they rot.

# Oh-My-OpenAgent Portable Assets

This directory contains repo-managed portable fragments for Oh-My-OpenAgent configuration.

It is **not** a live `.omo` home and must not contain machine-local runtime state, caches, logs, session data, secrets, or generated files. The installer may create `~/.omo` as a machine-local runtime directory, but only explicitly allowlisted children are managed from this repository.

Use these subdirectories for portable fragments that are safe to version and move between machines:

- `rules/` — reusable rule fragments.
- `teams/` — reusable team fragments.
- `templates/` — reusable template fragments.

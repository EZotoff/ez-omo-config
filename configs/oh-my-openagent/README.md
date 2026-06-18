# Oh-My-OpenAgent Configuration

This directory contains the repo-managed Oh-My-OpenAgent configuration and portable OMO fragments.

| Path | Purpose | Install target |
|---|---|---|
| `oh-my-openagent.json` | Agent/category model assignments, skills, prompt contracts, Team Mode enablement, and default mode preferences | `$HOME/.config/opencode/oh-my-openagent.json` |
| `portable-assets/` | Portable `rules/`, `teams`, and `templates` fragments only | allowlisted children under `$HOME/.omo/` |

## Portable Assets Layout

```
portable-assets/
├── README.md          # This file
├── rules/             # Reusable rule fragments installed to `$HOME/.omo/rules`
│   └── README.md
├── teams/             # Reusable team fragments installed to `$HOME/.omo/teams`
│   └── README.md
└── templates/         # Reusable template fragments installed to `$HOME/.omo/templates`
    └── README.md
```

`portable-assets/` is **not** a live `.omo` home. Do not store runtime state, caches, logs, sessions, secrets, or generated machine-local files there.

The installer creates `$HOME/.omo` as a machine-local runtime directory with `mkdir-only` mode and manages only the allowlisted portable children (`rules`, `teams`, `templates`) using the selected `--symlink` or `--copy` mode.

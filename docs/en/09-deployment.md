# 10 - Environment & Deployment: From Laptop to Cloud Cluster

> **Scope**: Deployment and operations configuration — `Dockerfile` (67 lines), `docker-compose.yml`, `setup-hermes.sh` (399-line install script), `cli-config.yaml.example` (1,002-line config template), `hermes_cli/profiles.py` (multi-profile mechanism), `flake.nix` (Nix packaging), `packaging/` (Homebrew).

## Where an Agent Lives

The previous nine chapters focused on Hermes's internals — the Agent core, tools, skills, plugins, and gateway. But for an Agent to run, it needs somewhere to live. On your Mac locally? Isolated inside a Docker container? On a remote server accessed via SSH? Or spinning up on-demand in Modal's cloud, billed by the second?

Hermes's answer is: **all of the above** — and you can switch between them without changing a single line of code.

## Six Terminal Backends

The underlying environment where the Agent executes commands (the `terminal` tool) is determined by the terminal backend. `cli-config.yaml.example:148-237` defines six:

| Backend | Use Case | Isolation Level | Characteristics |
|---------|----------|----------------|-----------------|
| `local` | Day-to-day development | None (runs directly on the host) | Default, fastest, zero config |
| `docker` | Reproducible environments | Container-level | Supports mounting the working directory; approvals auto-granted inside containers |
| `ssh` | Remote servers | Network-level | Configure host/user/port/key |
| `singularity` | HPC clusters | Container-level (no root) | Suited for academic computing environments |
| `modal` | GPU cloud / Serverless | Cloud-level | Starts on demand, sleeps when idle |
| `daytona` | Cloud development environments | Cloud-level | Similar to GitHub Codespaces; supports disk persistence |

The last four are containerized or remote environments. When the Agent executes commands in these environments, **security approvals are automatically bypassed** (`approval.py:889-891`) — because the container or sandbox itself is the security boundary, so an additional confirmation layer is unnecessary.

General resource limits are configurable (applicable to docker/singularity/modal/daytona): CPU cores, memory (default 5 GB), disk (default 50 GB), and whether state is persisted.

## Docker Deployment

The `Dockerfile` (67 lines) uses a three-stage build:

```
Stage 1 (uv_source):   Extract the uv/uvx binaries
Stage 2 (gosu_source):  Extract gosu (for runtime UID switching)
Stage 3 (debian:13.4):  Final runtime image
```

Several design choices stand out:

**Layer cache optimization.** `package.json` / `package-lock.json` are copied and npm dependencies installed before the source code is copied — so a source-code change doesn't invalidate the npm layer. Python dependencies are installed via `uv pip install` (a package manager written in Rust), which is an order of magnitude faster than pip.

**Non-root execution.** A `hermes` user (UID 10000) is created; at runtime the `HERMES_UID` environment variable can override this — `docker/entrypoint.sh` uses `gosu` to switch to the specified UID. This aligns file ownership inside the container with the host, avoiding permission issues with volume mounts.

**PID 1 management.** The entrypoint is wrapped with `tini` (a minimal init process), ensuring that orphan processes — MCP stdio child processes and git are typical examples — are properly reaped rather than accumulating as zombies.

`docker-compose.yml` defines two services: `gateway` (the message gateway) and `dashboard` (the web management interface), both using `network_mode: host` and a `~/.hermes:/opt/data` volume mount.

## Installation Wizard

`setup-hermes.sh` is a one-liner install script (`curl -fsSL ... | bash`). Its flow is:

1. Detect the platform (Linux / macOS / Android Termux)
2. Install the `uv` package manager
3. Ensure Python 3.11+ is available
4. Create a virtual environment
5. Install dependencies (preferring `uv sync --locked` with hash verification; falls back to `uv pip install` on failure)
6. Optionally install `ripgrep` (full-text search tool)
7. Create a symlink for the `hermes` command
8. Sync pre-bundled skills
9. Optionally run an interactive configuration wizard

Termux (Android) has a separate dependency path — the `.[termux]` extra excludes voice dependencies that are incompatible with Android.

## Multi-Profile Mechanism

A single machine may need to run multiple Hermes instances — for example, using different API keys and memory stores for work and personal contexts. `hermes --profile <name>` switches profiles; each profile is an independent `~/.hermes/profiles/<name>/` directory containing its own config, memory, sessions, skills, and cron jobs (`hermes_cli/profiles.py`).

The `default` profile is `~/.hermes` itself — zero migration. When creating a new profile you can choose to clone an existing config (`clone_config=True`) or start completely fresh. `hermes profile export/import` handles import and export via tar.gz (with path traversal protection).

One convenient design detail: creating a profile automatically generates a wrapper script in `~/.local/bin/` — if you create a profile named `work`, you can run the `work` command directly (equivalent to `hermes --profile work`).

## Nix and Homebrew

In addition to pip/uv installation, Hermes provides a Nix flake (`flake.nix`) and a Homebrew formula (`packaging/homebrew/hermes-agent.rb`).

The Nix flake uses `uv2nix` to convert Python dependencies into Nix derivations, exporting three packages (default/tui/web) and supporting declarative deployment via a NixOS module. The Homebrew formula uses the `Language::Python::Virtualenv` mixin and creates `env_script` wrappers for the three entry points (hermes/hermes-agent/hermes-acp).

## What's Next

Deployment answers the question of "where the Agent runs." The next chapter, **10 - Batch Runs & RL**, focuses on Hermes's research side — how to generate training data in bulk and how to do reinforcement learning.

---

*This article is based on analysis of the hermes-agent v0.11.0 source code. All code references have been independently verified.*

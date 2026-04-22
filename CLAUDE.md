# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a [chezmoi](https://www.chezmoi.io/) dotfiles repository managing configuration files across Linux and macOS systems. Files prefixed with `dot_` are deployed to `~/.` and `executable_` prefixed files get execute permissions.

## Commands

### Chezmoi Operations
```bash
chezmoi apply              # Apply dotfiles to home directory
chezmoi diff               # Preview changes before applying
chezmoi add ~/.config/foo  # Add a new config file to the repo
chezmoi edit ~/.bashrc     # Edit a managed file
```

### Home Manager (Nix)
```bash
# Linux
export NIXPKGS_ALLOW_INSECURE=1
home-manager switch --flake .#ryankanno@linux --impure

# macOS (macmini)
export NIXPKGS_ALLOW_INSECURE=1
home-manager switch --flake .#ryankanno@macmini --impure
```

## Architecture

### Directory Structure
- `dot_*` - Files deployed to `~/.*` (bash configs, gitconfig, tmux.conf, etc.)
- `dot_config/` - Files deployed to `~/.config/` (home-manager, nvim, btop, direnv)
- `dot_claude/` - Claude Code global configuration:
  - `CLAUDE.md` - global instructions loaded every session
  - `settings.json` - permissions, hooks, plugins, env vars, status line
  - `agents/` - subagent definitions (e.g. `diataxis-expert`)
  - `skills/` - model-invoked skills (`preflight`, `bootstrap-python-project`, `diataxis-knowledge`)
  - `scripts/` - shared hook helpers (`ntfy-notify.sh` for push notifications)
  - `commands/` - slash commands (currently empty; built-ins and skills cover common workflows)
- `dot_hammerspoon/` - macOS window management and key bindings
- `dot_githooks/` - Git hooks (prepare-commit-msg for conventional commits)
- `scripts/` - Utility scripts (git workflows, ssh setup)

### Platform-Specific Handling
The `.chezmoiignore` file uses chezmoi templating to exclude macOS-specific files (hammerspoon, finicky) on Linux systems.

### Home Manager Configuration
- `dot_config/home-manager/flake.nix` - Nix flake defining user environments
- `dot_config/home-manager/darwin.nix` - macOS-specific packages and settings
- `dot_config/home-manager/linux.nix` - Linux-specific packages and settings

### Runtime Version Management
- [mise](https://mise.jdx.dev/) manages Python, Node, Ruby, and other runtimes (replaces anyenv/pyenv/nodenv/rbenv)
- Activated via `mise activate bash` in `dot_bashrc`
- Global tool versions live in `~/.config/mise/config.toml` (not versioned here)
- Per-project versions declared in `.mise.toml` under `[tools]`; env vars under `[env]` (e.g. `UV_PYTHON`)
- direnv integration: `use_mise()` in `dot_config/direnv/direnvrc` enables `use mise` in `.envrc` files, which loads mise's environment into direnv's context before other layout commands (e.g. `use uv`)

### Git Configuration
- Uses `~/.githooks` for custom hooks (set via `core.hooksPath`)
- Includes `.gitconfig.local` for machine-specific settings (email, signing key)
- GPG signing enabled with SSH format

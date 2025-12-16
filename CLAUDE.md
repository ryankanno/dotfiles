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
- `dot_claude/` - Claude Code configuration (slash commands in `commands/`)
- `dot_hammerspoon/` - macOS window management and key bindings
- `dot_githooks/` - Git hooks (prepare-commit-msg for conventional commits)
- `scripts/` - Utility scripts (git workflows, ssh setup)

### Platform-Specific Handling
The `.chezmoiignore` file uses chezmoi templating to exclude macOS-specific files (hammerspoon, finicky) on Linux systems.

### Home Manager Configuration
- `dot_config/home-manager/flake.nix` - Nix flake defining user environments
- `dot_config/home-manager/darwin.nix` - macOS-specific packages and settings
- `dot_config/home-manager/linux.nix` - Linux-specific packages and settings

### Git Configuration
- Uses `~/.githooks` for custom hooks (set via `core.hooksPath`)
- Includes `.gitconfig.local` for machine-specific settings (email, signing key)
- GPG signing enabled with SSH format

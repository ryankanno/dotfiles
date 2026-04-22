# dotfiles

## hic sunt dracones

I have some serious dotfiles.  Here they are.

## claude code

Global config under `dot_claude/` (deploys to `~/.claude/`):

- `CLAUDE.md` — global instructions
- `settings.json` — permissions, hooks, plugins, env, status line
- `skills/` — `preflight`, `bootstrap-python-project`, `diataxis-knowledge`
- `agents/` — `diataxis-expert`
- `scripts/` — `ntfy-notify.sh` (push notifications via ntfy)

Notifications require `NTFY_SERVER_URL` in the shell environment; without it, hooks silently no-op.

## mise (runtime version management)

mise manages Python, Node, Ruby, and other runtimes. It replaces anyenv/pyenv/nodenv/rbenv and is installed via home-manager.

### Setting global tool versions

After a fresh install, set your global defaults:

```bash
mise use --global python@3.11 node@22 ruby@3.3
```

This writes to `~/.config/mise/config.toml`.

### Per-project setup

Create a `.mise.toml` in the project root:

```toml
[tools]
python = "3.11"
node = "22"

[env]
UV_PYTHON = "3.11"   # pins uv to the mise-managed Python
```

Then run `mise install` to download any missing versions.

### direnv integration

Projects using direnv should call `use mise` before any layout commands:

```bash
# .envrc
use mise      # loads mise runtimes + [env] vars into direnv context
use uv        # now sees mise's Python via UV_PYTHON
```

`use_venv` (create/activate venv only) and `use_uv` (venv + uv sync, requires pyproject.toml) are defined in `dot_config/direnv/direnvrc`.

## home-manager (linux/macmini)

### Switching configurations

```bash
export NIXPKGS_ALLOW_INSECURE=1
home-manager switch --flake .#ryankanno@{linux,macmini} --impure
```

### Upgrading nix channels

To upgrade to a newer nixpkgs version (e.g., from 24.05 to 24.11):

1. Update the channel versions in `dot_config/home-manager/flake.nix`:
   ```nix
   inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
   inputs.nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-24.11-darwin";
   inputs.home-manager.url = "github:nix-community/home-manager/release-24.11";
   ```

2. Update the flake lock:
   ```bash
   cd ~/.local/share/chezmoi/dot_config/home-manager
   nix flake update
   ```

3. Apply the changes:
   ```bash
   export NIXPKGS_ALLOW_INSECURE=1
   home-manager switch --flake .#ryankanno@{linux,macmini} --impure
   ```

4. Commit the updated `flake.nix` and `flake.lock`:
   ```bash
   cd ~/.local/share/chezmoi
   chezmoi add ~/.config/home-manager/flake.nix
   chezmoi add ~/.config/home-manager/flake.lock
   git commit -m "chore: upgrade nixpkgs to 24.11"
   ```

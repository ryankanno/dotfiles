# open file descriptor 5 such that anything written to /dev/fd/5
# is piped through ts and then to /tmp/bash_timestamps
# exec 5> >(/usr/local/bin/ts -i "%.s" >> /tmp/bash_timestamps)

# https://www.gnu.org/software/bash/manual/html_node/Bash-Variables.html
# export BASH_XTRACEFD=5

# Enable tracing
# set -x

function include() { [[ -f "$1" ]] && source "$1"; }

# macports
export PATH="/opt/local/bin:/opt/local/sbin:/usr/local/sbin:$PATH"

# cargo
export PATH="$HOME/.cargo/bin:$PATH"

# poetry
export PATH="$HOME/.poetry/bin:$PATH"

# anyenv
if [[ -n $(which anyenv) ]]; then
    eval "$(anyenv init -)"
fi

# nodenv
[[ -f "${HOME}/.anyenv/envs/nodenv/.nodenvrc" ]] && include "$HOME/.anyenv/envs/nodenv/.nodenvrc"

# pyenv
[[ -f "${HOME}/.anyenv/envs/pyenv/.pyenvrc" ]] && include "$HOME/.anyenv/envs/pyenv/.pyenvrc"

# rbenv
[[ -f "${HOME}/.anyenv/envs/rbenv/.rbenvrc" ]] && include "$HOME/.anyenv/envs/rbenv/.rbenvrc"


if [ -f $HOME/.bashrc ]; then
    source $HOME/.bashrc
fi

# always just bounce into tmux
if command -v tmux &> /dev/null && [ -z "$TMUX" ]; then
    tmux attach -t default || tmux new -s default
fi

function include() { [[ -f "$1" ]] && source "$1"; }

export PATH=/opt/local/bin:/opt/local/sbin:$PATH

# pyenv
[[ -f "${HOME}/.anyenv/envs/pyenv/.pyenvrc" ]] && include "$HOME/.anyenv/envs/pyenv/.pyenvrc"

# pyenv-virtualenv
eval "$(pyenv virtualenv-init -)"

# rbenv
[[ -f "${HOME}/.anyenv/envs/rbenv/.rbenvrc" ]] && include "$HOME/.anyenv/envs/rbenv/.rbenvrc"

# inputrc
[[ -f "${HOME}/.inputrc" ]] && export INPUTRC="${HOME}/.inputrc"

# ssh-agent -> http://mah.everybody.org/docs/ssh
SSH_ENV="${HOME}/.ssh/environment"

function start_agent {
     echo "Initialising new SSH agent..."
     /usr/bin/ssh-agent | sed 's/^echo/#echo/' > "${SSH_ENV}"
     echo succeeded
     chmod 600 "${SSH_ENV}"
     . "${SSH_ENV}" > /dev/null
     /usr/bin/ssh-add;
}

if [ -f "${SSH_ENV}" ]; then
     source "${SSH_ENV}" > /dev/null
     ps -ef | grep ${SSH_AGENT_PID} | grep ssh-agent$ > /dev/null || { start_agent; }
else
     start_agent;
fi

# vi mode
set -o vi

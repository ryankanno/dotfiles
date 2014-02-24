function include() { [[ -f "$1" ]] && source "$1"; }

# bash-it
export BASH=$HOME/Projects/github/others/bash-it
export BASH_THEME='hawaii50'
export hchtstoredir="$HOME/.hcht"
source $BASH/bash_it.sh

# bashmarks -> https://github.com/huyng/bashmarks
include "${HOME}/.local/bin/bashmarks.sh"

# editors -> TODO: OS detection, duh.
export EDITOR='/opt/local/bin/mvim -p'
export GIT_EDITOR='/opt/local/bin/vim'

# grep
export GREP_OPTIONS='--color=auto'

# history
HISTCONTROL=ignoreboth
shopt -s histappend # append
HISTSIZE=5000
HISTFILESIZE=20000

# inputrc
[[ -f "${HOME}/.inputrc" ]] && export INPUTRC="${HOME}/.inputrc"

# irc
export IRC_CLIENT='irssi'

# less++ -> TODO: OS detection, duh
[ -x /opt/local/bin/lesspipe.sh ] && eval "$(SHELL=/bin/sh /opt/local/bin/lesspipe.sh)"

# mail
unset MAILCHECK

# rvm
[[ -s $HOME/.rvm/scripts/rvm ]] && source $HOME/.rvm/scripts/rvm

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

# virtualenv
include "/usr/local/bin/virtualenvwrapper.sh"

export WORKON_HOME=$HOME/.virtualenvs
export PIP_VIRTUALENV_BASE=$WORKON_HOME
export PIP_REQUIRE_VIRTUALENV=true
export PIP_RESPECT_VIRTUALENV=true

# Load bash command completion if present
include "/opt/local/etc/bash_completion"

# Load aliases
include "${HOME}/.bash_aliases"

# Load functions
include "${HOME}/.bash_functions"

# Load private things
include "${HOME}/.bash_local"

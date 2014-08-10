function include() { [[ -f "$1" ]] && source "$1"; }

export PATH=/opt/local/bin:/opt/local/sbin:$PATH

# bash-it
export BASH=$HOME/.bash_it
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
export HISTCONTROL=ignoreboth
shopt -s histappend # append
export HISTSIZE=32768
export HISTFILESIZE=32768
export HISTTIMEFORMAT='%F %T '
export HISTIGNORE="ls:ls *:cd:cd -:pwd;exit:date:* --help"

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

# teamocil
complete -W "$(teamocil --list)" teamocil

# vi mode
set -o vi

# virtualenv
export WORKON_HOME=$HOME/.virtualenvs
export PIP_VIRTUALENV_BASE=$WORKON_HOME
export PIP_RESPECT_VIRTUALENV=true
export PIP_REQUIRE_VIRTUALENV=true
export VIRTUALENVWRAPPER_PYTHON=/opt/local/bin/python
export VIRTUALENVWRAPPER_VIRTUALENV=/opt/local/bin/virtualenv-2.7
export VIRTUALENVWRAPPER_VIRTUALENV_ARGS='--no-site-packages'

if [[ -r /opt/local/bin/virtualenvwrapper.sh-2.7 ]]; then
	source /opt/local/bin/virtualenvwrapper.sh-2.7
else
	echo "WARNING: Can't find virtualenvwrapper.sh"
fi

# Load bash command completion if present
[[ -s "/opt/local/etc/bash_completion" ]] && source "/opt/local/etc/bash_completion"

# Load aliases
[[ -s "${HOME}/.bash_aliases" ]] && source "${HOME}/.bash_aliases"

# Load functions
[[ -s "${HOME}/.bash_functions" ]] && source "${HOME}/.bash_functions"

# Load private things
[[ -s "${HOME}/.bash_local" ]] && source "${HOME}/.bash_local"

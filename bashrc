function include() { [[ -f "$1" ]] && source "$1"; }

export PATH=/opt/local/bin:/opt/local/sbin:$PATH

# bash-it
export BASH_IT=$HOME/.bash_it
export BASH_IT_THEME='hawaii50'
export TODO="t"
source $BASH_IT/bash_it.sh

# pyenv
[[ -f "${HOME}/.anyenv/envs/pyenv/.pyenvrc" ]] && include "$HOME/.anyenv/envs/pyenv/.pyenvrc"

# pyenv-virtualenv
eval "$(pyenv virtualenv-init -)"

# rbenv
[[ -f "${HOME}/.anyenv/envs/rbenv/.rbenvrc" ]] && include "$HOME/.anyenv/envs/rbenv/.rbenvrc"

# bashmarks
[[ -f "${HOME}/.local/bin/bashmarks.sh" ]] && source "${HOME}/.local/bin/bashmarks.sh"

# grep
export GREP_OPTIONS='--color=auto'

# remove annoying you got mail
unset MAILCHECK

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

# history
export HISTCONTROL=ignoreboth
shopt -s histappend
export HISTSIZE=32768
export HISTFILESIZE=32768
export HISTTIMEFORMAT='%F %T '
export HISTIGNORE="ls:ls *:cd:cd -:pwd;exit:date:* --help"

# os specific
if [[ "$OSTYPE" == "darwin"* ]]; then
    export EDITOR='/opt/local/bin/mvim -p'
    export GIT_EDITOR='/opt/local/bin/vim'
    eval "$(boot2docker shellinit)"
fi

# teamocil
complete -W "$(teamocil --list)" teamocil

# load all the bash things
[[ -s "/opt/local/etc/bash_completion" ]] && source "/opt/local/etc/bash_completion"
[[ -s "${HOME}/.bash_aliases" ]] && source "${HOME}/.bash_aliases"
[[ -s "${HOME}/.bash_functions" ]] && source "${HOME}/.bash_functions"
[[ -s "${HOME}/.bash_local" ]] && source "${HOME}/.bash_local"

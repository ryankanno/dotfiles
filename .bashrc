function include() { [[ -f "$1" ]] && source "$1"; }

# rvm
[[ -s $HOME/.rvm/scripts/rvm ]] && source $HOME/.rvm/scripts/rvm

# bash-it
export BASH=$HOME/Projects/github/others/bash-it
export BASH_THEME='hawaii50'
export hchtstoredir="$HOME/.hcht"
source $BASH/bash_it.sh

# bashmarks -> https://github.com/huyng/bashmarks
include "${HOME}/.local/bin/bashmarks.sh"

# editors
export EDITOR='/opt/local/bin/mvim -p'
export GIT_EDITOR='/opt/local/bin/vim'

# unset mail
unset MAILCHECK

# irc
export IRC_CLIENT='irssi'

# history
HISTCONTROL=ignoreboth
shopt -s histappend # append
HISTSIZE=5000
HISTFILESIZE=20000

# grep
export GREP_OPTIONS='--color=auto'

# inputrc
[[ -f "${HOME}/.inputrc" ]] && export INPUTRC="${HOME}/.inputrc"

# virtualenv
include "/usr/local/bin/virtualenvwrapper.sh"

export WORKON_HOME=$HOME/.virtualenvs
export PIP_VIRTUALENV_BASE=$WORKON_HOME
export PIP_REQUIRE_VIRTUALENV=true
export PIP_RESPECT_VIRTUALENV=true

# vi mode
set -o vi

# Load bash command completion if present
include "/opt/local/etc/bash_completion"

# Load aliases
include "${HOME}/.bash_aliases"

# Load functions
include "${HOME}/.bash_functions"

# Load private things
include "${HOME}/.bash_local"

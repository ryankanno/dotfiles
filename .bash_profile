#!/bin/bash

# Load RVM, if you are using it
[[ -s $HOME/.rvm/scripts/rvm ]] && source $HOME/.rvm/scripts/rvm

# Path to the bash it configuration
export BASH=$HOME/Projects/github/others/bash-it

# Lock and Load a custom theme file
# location /.bash_it/themes/
export BASH_THEME='minimal'

# Set my editor and git editor
export EDITOR="/opt/local/bin/mvim -p"
export GIT_EDITOR="/usr/bin/vim"

# Don't check mail when opening terminal.
unset MAILCHECK

# Change this to your console based IRC client of choice.
export IRC_CLIENT='irssi'

# Set store directory for handmade commandline history tool 
export hchtstoredir="$HOME/.hcht"

# Load VirtualEnvWrapper into a shell session
if [ -f /usr/local/bin/virtualenvwrapper.sh ]; then
    source /usr/local/bin/virtualenvwrapper.sh
fi

# VirtualEnv exports
export WORKON_HOME=$HOME/.virtualenvs
export PIP_VIRTUALENV_BASE=$WORKON_HOME
export PIP_REQUIRE_VIRTUALENV=true
export PIP_RESPECT_VIRTUALENV=true

# SVN editor
export SVN_EDITOR="$EDITOR --nofork"

# Load Bash It
source $BASH/bash_it.sh

# Load bash command completion if present
if [ -f /opt/local/etc/bash_completion ]; then
    . /opt/local/etc/bash_completion
fi

set -o vi

alias gvim=mvim

# Load local commands
source $HOME/.bash_local

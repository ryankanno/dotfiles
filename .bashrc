# Load RVM, if you are using it
[[ -s $HOME/.rvm/scripts/rvm ]] && source $HOME/.rvm/scripts/rvm

# Path to the bash it configuration
export BASH=$HOME/Projects/github/others/bash-it

# Lock and Load a custom theme file in ~/.bash_it/themes/
export BASH_THEME='hawaii50'

# Set my editor and git editor
export EDITOR='/opt/local/bin/mvim -p'
export GIT_EDITOR='/opt/local/bin/vim'

# Don't check mail when opening terminal.
unset MAILCHECK

# Change this to your console based IRC client of choice.
export IRC_CLIENT='irssi'

# Set store directory for handmade commandline history tool 
export hchtstoredir="$HOME/.hcht"

# History
HISTCONTROL=ignoreboth
shopt -s histappend # append
HISTSIZE=5000
HISTFILESIZE=20000

# Inputrc
[[ -f "${HOME}/.inputrc" ]] && export INPUTRC="${HOME}/.inputrc"

# Load VirtualEnvWrapper into a shell session
if [ -f /usr/local/bin/virtualenvwrapper.sh ]; then
    source /usr/local/bin/virtualenvwrapper.sh
fi

# VirtualEnv exports
export WORKON_HOME=$HOME/.virtualenvs
export PIP_VIRTUALENV_BASE=$WORKON_HOME
export PIP_REQUIRE_VIRTUALENV=true
export PIP_RESPECT_VIRTUALENV=true

# Load Bash It
source $BASH/bash_it.sh

# Load Bashmarks
source ~/.local/bin/bashmarks.sh

# Load bash command completion if present
if [ -f /opt/local/etc/bash_completion ]; then
    . /opt/local/etc/bash_completion
fi

# VI mode
set -o vi

# General aliases
alias ll='ls -l'
alias la='ls -A'
alias c='clear'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../../'

# Custom aliases
alias gvim=mvim
alias fakesmtp='python -m smtpd -n -c DebuggingServer localhost:1025'

# Functions from http://github.com/Sirupsen
function mkcd() {
    mkdir -p $1
    cd $1
}

function extract() {
    if [ -f $1 ] 
    then
        case $1 in
            *.tar.bz2)  tar -jxvf $1;;
            *.tar.gz)   tar -zxvf $1;;
            *.bz2)      bzip2 -d $1;;
            *.gz)       gunzip -d $1;;
            *.tar)      tar -xvf $1;;
            *.tgz)      tar -zxvf $1;;
            *.zip)      unzip $1;;
            *.Z)        uncompress $1;;
            *.rar)      unrar x $1;;
            *)          echo "'$1' Error. Unsupported filetype.";;
        esac
    else
        echo "'$1' not a valid file"
  fi
}

pjson () {
    python -c "import json; import sys; print json.dumps(json.loads(sys.stdin.read()), sort_keys = True, indent = 2)"
}

# Load aliases
if [ -f "${HOME}/.bash_aliases" ]; then
    source "${HOME}/.bash_aliases"
fi

# Load local commands
if [ -f "${HOME}/.bash_local" ]; then
    source "${HOME}/.bash_local"
fi

#!/bin/bash

# Load RVM, if you are using it
[[ -s $HOME/.rvm/scripts/rvm ]] && source $HOME/.rvm/scripts/rvm

# Add rvm gems 
export PATH=$PATH:$HOME/.gem/ruby/1.8/bin:$HOME/Projects/libs/google_appengine

# Path to the bash it configuration
export BASH=$HOME/Projects/github/others/bash-it

# Lock and Load a custom theme file
# location /.bash_it/themes/
export BASH_THEME='minimal'

# Set my editor and git editor
export EDITOR="/usr/bin/gvim -p"
export GIT_EDITOR="/usr/bin/vim"

# Don't check mail when opening terminal.
unset MAILCHECK

# Change this to the path of your local jekyll root to use the jekyll aliases

export JEKYLL_LOCAL_ROOT="$HOME/Sites/jekyllsite"

# And change this to the remote server and root

export JEKYLL_REMOTE_ROOT="user@server:/path/to/jekyll/root"

# And, for the last of the jekyll variables, this is the formatting you use, eg: markdown,
# textile, etc. Basically whatever you use as the extension for posts, without the preceding dot

export JEKYLL_FORMATTING="markdown"

# Change this to your console based IRC client of choice.

export IRC_CLIENT='irssi'

# Set this to the command you use for todo.txt-cli
export TODO="t"

# Set store directory for handmade commandline history tool 
export hchtstoredir="$HOME/.hcht"

# Load VirtualEnvWrapper into a shell session
if [ -f /usr/local/bin/virtualenvwrapper.sh ]; then
    source /usr/local/bin/virtualenvwrapper.sh
fi

# VirtualEnv exports
export WORKON_HOME=$HOME/.virtualenvs/
export PIP_VIRTUALENV_BASE=$WORKON_HOME
export PIP_REQUIRE_VIRTUALENV=true
export PIP_RESPECT_VIRTUALENV=true

export SVN_EDITOR="$EDITOR --nofork"

# Load Bash It
source $BASH/bash_it.sh

# Load aliases
source $HOME/.bash_aliases

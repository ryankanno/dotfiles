# install_config

**install_config** is a Bash script to install configuration files hosted on
Dropbox to your local machine.  It helps me keep consistency between my various
OSX/Ubuntu machines.  Currently, it supports my **screen**, **vim**, and
**conky** configurations.

For every application, you need to have a file called ".&lt;app&gt;install" (e.g. .screeninstall)
that defines the following variables:

  - DROPBOX_DIR - path to the configuration files
  - GIT_EXEC - path to your git executable
  - GIT_REPO - path to the git repo holding your configuration files
  - APP_CONFIG_FILE - the application rc file

There are also three function callbacks that if defined will be
called during the installation process.  These three function calls include:

  - pre_install
  - install
  - post_install

Here are some sample .<app>install files that are loaded on my machine

## vim

    #!/bin/bash

    DROPBOX_DIR=/home/ryankanno/Dropbox/Install/vim
    GIT_EXEC=/usr/bin/git
    GIT_REPO=git://github.com/ryankanno/vim.git
    APP_CONFIG_FILE=.vimrc

    function install () { 
        update_symlink ".vim"
    }

## screen

    #!/bin/bash

    DROPBOX_DIR=/home/ryankanno/Dropbox/Install/dotfiles
    GIT_EXEC=/usr/bin/git
    GIT_REPO=git://github.com/ryankanno/dotfiles.git
    APP_CONFIG_FILE=.screenrc

    function install () { 
        update_symlink ".screen_files"
    }

## conky

    #!/bin/bash

    DROPBOX_DIR=/home/ryankanno/Dropbox/Install/dotfiles
    GIT_EXEC=/usr/bin/git
    GIT_REPO=git://github.com/ryankanno/dotfiles.git
    APP_CONFIG_FILE=.conkyrc

    function install () { return 0; }

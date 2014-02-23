#!/usr/bin/env bash

# i create a lot of tar backups before i do things :)
function backup() {
    if [ -z "$1" ]; then
        echo "Usage: backup DIRECTORY"
    else
        DIR="$( cd $1 && pwd )"
        if [ $? -eq 0 ]; then
            local dirname=$(basename ${DIR})
            local date=$(date +%Y%m%d-%H%M%S)
            local tarball="${dirname}.${date}.tar.gz"
            echo "Backing up ${dirname} to ${tarball}"
            echo ""
            tar -zcvf ${tarball} ${dirname}
        else
            echo "Unable to backup $1. Does it exist?"
        fi
    fi
}

# https://github.com/necolas/dotfiles/blob/master/shell/functions/datauri
function datauri() {
    local mimeType=$(file -b --mime-type "$1")
    if [[ $mimeType == text/* ]]; then
        mimeType="${mimeType};charset=utf-8"
    fi
    printf "data:${mimeType};base64,$(openssl base64 -in "$1" | tr -d '\n')" | pbcopy | printf "=> data URI copied to pasteboard.\n"
}

# https://github.com/anthonypdawson/dotfiles/blob/master/bash_functions
function ex() {
    if [ -f $1 ]; then
        case $1 in
            *.tar.bz2)   tar xjf $1   ;;
            *.tar.gz)    tar xzf $1   ;;
            *.bz2)       bunzip2 $1   ;;
            *.rar)       rar x $1     ;;
            *.gz)        gunzip $1    ;;
            *.tar)       tar xf $1    ;;
            *.tbz2)      tar xjf $1   ;;
            *.tgz)       tar xzf $1   ;;
            *.zip)       unzip $1     ;;
            *.Z)         uncompress $1;;
            *.7z)        7z x $1      ;;
            *)           echo "'$1' cannot be extracted via ex()" ;;
        esac
    else
        echo "'$1' is not a valid file"
    fi
}

function mkcd() {
    mkdir -p $1
    cd $1
}

function pyjson() {
    python -c "import json; import sys; print json.dumps(json.loads(sys.stdin.read()), sort_keys = True, indent = 2)"
}

# https://github.com/necolas/dotfiles/blob/master/shell/functions/pyserver
function pyserver() {
    local port="${1:-8000}"
    open "http://localhost:${port}/"
    python -c $'import SimpleHTTPServer;\nSimpleHTTPServer.SimpleHTTPRequestHandler.extensions_map[""] = "text/plain";\nSimpleHTTPServer.test();' "$port"
}

function tm() {
    if [[ $1 ]]; then
        tmux attach -t $1
    else
        tmux list-sessions
    fi
}

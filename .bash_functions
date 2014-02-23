#!/usr/bin/env bash

# https://github.com/necolas/dotfiles/blob/master/shell/functions/datauri
function datauri() {
    local mimeType=$(file -b --mime-type "$1")
    if [[ $mimeType == text/* ]]; then
        mimeType="${mimeType};charset=utf-8"
    fi
    printf "data:${mimeType};base64,$(openssl base64 -in "$1" | tr -d '\n')" | pbcopy | printf "=> data URI copied to pasteboard.\n"
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


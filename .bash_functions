#!/usr/bin/env bash

# i create a lot of tar backups before i do things :)
function backup() {
    if [ -z "$1" ]; then
        echo "Usage: backup DIRECTORY"
    else
        DIR="$( (cd $1 && pwd) | tail -1 )"
        if [ $? -eq 0 ]; then
            local dirname=$(basename ${DIR})
            local date=$(date +%Y%m%d-%H%M%S)
            local tarball="${dirname}.${date}.tar.gz"
            echo "Backing up ${1} to ${tarball}"
            echo ""
            tar -zcvf ${tarball} ${1}
        else
            echo "Unable to backup $1. Does it exist?"
        fi
    fi
}

function bak() {
    cp $1 $1_$(date +%Y%m%d-%H%M%S)
}

function calc() {
    echo "$*" | bc;
}

# https://unix.stackexchange.com/questions/6/what-are-your-favorite-command-line-features-or-tricks/122#122
function cd {
    builtin cd "$@" && ls
}

# https://github.com/michaelkitson/dotfiles/blob/master/bash_functions
function define() {
    curl -s "www.thefreedictionary.com/$1" | \grep -Eo '<div class="pseg">.*?<hr>' | sed 's/<div class="pseg">//' | sed -E 's/<div class="etyseg">.*//' | sed 's/<script>.*<\/script>//g' | sed -E 's/<div[^>]*>/@/g' | tr '@' '\n' | sed 's/<[^>]*>//g' | sed 's/^[a-z]\.  /    /g'
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

function newrepo() {
    if [ -d $1 ]; then
        echo "Directory with identical name as repo exists. Please create in another folder."
    else
        mkdir $1
        pushd . > /dev/null
        cd "$1"
        touch README.md
        git init
        git add README.md
        git commit -m "first commit"
        git remote add origin git@github.com:${USER}/$1.git
        git push -u origin master
        popd > /dev/null
    fi
}

function port() {
    lsof -i:$1
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

# shorten all the things
function shorten() {
    if [ -z "${BITLY_USERNAME}" -a -z "${BITLY_API_KEY}" -a -f "${HOME}/.bitly.cfg" ]; then
        source "${HOME}/.bitly.cfg"
    fi

    if [ -z "${BITLY_USERNAME}" -o -z "${BITLY_API_KEY}" ]; then
        echo "Please set BITLY_USERNAME and BITLY_API_KEY env vars"
    else
        if [ -n "$1" ]; then
            curl -s "http://api.bitly.com/v3/shorten?login=${BITLY_USERNAME}&apiKey=${BITLY_API_KEY}&longUrl=${1}&format=txt"
        else
            echo "Usage: shorten URL"
        fi
    fi
}

function tm() {
    if [[ $1 ]]; then
        tmux attach -t $1
    else
        tmux list-sessions
    fi
}

# not sure where i found this one, but queries wikipedia
function wiki() {
    dig +short txt $1.wp.dg.cx;
}

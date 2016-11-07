#!/usr/bin/env bash

function agvim() {
    ag -l $@ | mvim -p
}

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

function cdf {
    cd -- "$(gfind . -name "$1" -type f -printf '%h' -quit)"
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

function ed() {
    find  . -type d -empty
}

function ef() {
    find  . -type f -empty
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

# find a file
function ff() {
    find . -type f -iname '*'$*'*' -ls;
}

# find and execute
function fe() {
    find . -type f -iname '*'${1:-}'*' -exec ${2:-file} {} \;
}

function matrix() {
    LC_ALL=C tr -c "[:print:]" " " < /dev/urandom | dd cbs=$COLUMNS conv=unblock | GREP_COLOR="1;32" grep --color "[^ ]"
}

function members() {
    cat /etc/group | grep --regex "^$1:.*" | cut -d: -f4
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

function port_clean() {
    sudo port -f clean --all all && sudo port -f uninstall inactive
}

function prompt_yes_no() {
    read -p "$@ [y/N] " ans
    case "$ans" in
        y|Y|yes|Yes) return 0;;
        *) return 1;;
    esac
}

function pyjson() {
    local cmd='python -c "import json; import sys; print json.dumps(json.loads(sys.stdin.read()), sort_keys = True, indent = 2)"'
    if command -v pygmentize >/dev/null 2>/dev/null; then
        eval $cmd | pygmentize -l javascript
    else
        eval $cmd
    fi
}

# https://github.com/necolas/dotfiles/blob/master/shell/functions/pyserver
function pyserver() {
    local port="${1:-8000}"
    open "http://localhost:${port}/"
    python -c $'import SimpleHTTPServer;\nSimpleHTTPServer.SimpleHTTPRequestHandler.extensions_map[""] = "text/plain";\nSimpleHTTPServer.test();' "$port"
}

function python() {
    test -z "$1" && ipython || command python "$@"
}

# scan local network
function scan() {
    if [ -z "$1" ]; then
        echo "Usage: scan CIDR"
    else
        if command -v nmap >/dev/null 2>&1; then
            nmap -sn $@ -oG - | awk '$4=="Status:" && $5=="Up" {print $2, $3}'
        else
            echo "Nmap is not installed. Please install and try again."
        fi
    fi
}

# share a file on 8080 using netcat, just redirect (e.g. share < file.txt)
function share() {
    sudo nc -v -l "${1:-8080}"
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
    if [ -n "$1" ]; then
        tmux attach -t $1 2>/dev/null || tmux new -s $1
    else
        tmux list-sessions 2> >(grep -q 'failed')
        if [ "$?" -eq 1 ]; then
            echo "No available tmux sessions. Please create one."
        fi
    fi
}

function _tm_sessions () {
    local cur
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=( $( compgen -W "$(tmux list-sessions -F '#{session_name}' | cut -d' ' -f1)" -- "${cur}") )
    return 0
}

complete -F _tm_sessions tm

function tmk() {
    if [ -n "$1" ]; then
        tmux kill-session -t $1 2>/dev/null
    else
        echo "Please pass in a named tmux session to kill."
    fi
}

function used() {
    du -x -k 2>/dev/null | sort -nr | head -$1
}

function uuid() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen
    else
        python -c 'import uuid; print uuid.uuid1()'
    fi
}

# not sure where i found this one, but queries wikipedia
function wiki() {
    dig +short txt $1.wp.dg.cx;
}

# helpers
function fn_exists() {
    command -v $1 >/dev/null 2>&1
    return $?
}

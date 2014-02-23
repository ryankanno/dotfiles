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

pjson () {
    python -c "import json; import sys; print json.dumps(json.loads(sys.stdin.read()), sort_keys = True, indent = 2)"
}

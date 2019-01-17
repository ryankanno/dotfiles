# nav
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../../'

# short
alias c='clear'
alias f='find'
alias ll='ls -l'
alias m='man'

# network
alias ip="dig +short myip.opendns.com @resolver1.opendns.com"

# dev
alias fakesmtp='python -m smtpd -n -c DebuggingServer localhost:1025'

# grep
alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'

# docker
dalias() { alias | grep 'docker' | sed "s/^\([^=]*\)=\(.*\)/\1 => \2/"| sed "s/['|\']//g" | sort; }
alias di='docker images'
alias dip='docker inspect --format "{{ .NetworkSettings.IPAddress }}"'
alias dlatest="docker ps -l | sed -n 2p | awk '{print \$1}'"
alias dps='docker ps -a'
alias drm='docker rm $(docker ps --no-trunc -a -q)'
alias drmf='docker rm -f $(docker ps -a -q)'
alias drmi='docker rmi $(docker images -q --filter "dangling=true")'
alias drm_theworld='docker stop $(docker ps -a -q) && docker rm -f $(docker ps -a -q)'
alias di-remove-all='docker images -a | grep -v ^REPOSITORY | awk "{print \$3}" | xargs docker rmi'
alias di-remove-orphans='docker images | grep "^<none>" | awk "{print \$3}" | xargs docker rmi'
alias drund='docker run -d -P'
alias druni='docker run -t -i -P'
dbash() { docker exec -it $(docker ps -aqf "name=$1") /bin/bash; }
dbashstart() { docker run -i -t --entrypoint /bin/sh "$1"; }

# python
alias pi='pip install'
alias pir='pip install -r requirements.txt'

# rsync
rsync_cmd='rsync --verbose --progress --human-readable --compress --archive --hard-links --one-file-system'

# http://www.bombich.com/rsync.html
if [[ "$OSTYPE" == darwin* ]] && grep -q 'file-flags' <(rsync --help 2>&1); then
  # rsync_cmd="${rsync_cmd} --crtimes --acls --xattrs --fileflags --protect-decmpfs --force-change"
  rsync_cmd="${rsync_cmd} --crtimes --acls --xattrs --fileflags --force-change"
fi

alias rsync-copy="${rsync_cmd}"
alias rsync-move="${rsync_cmd} --remove-source-files"
alias rsync-update="${rsync_cmd} --update"
alias rsync-sync="${rsync_cmd} --update --delete"

alias dry-rsync-copy="${rsync_cmd} --dry-run"
alias dry-rsync-move="${rsync_cmd} --remove-source-files --dry-run"
alias dry-rsync-update="${rsync_cmd} --update --dry-run"
alias dry-rsync-sync="${rsync_cmd} --update --delete --dry-run"

unset rsync_cmd

# vagrant
alias v='vagrant'
alias vd='vagrant destroy'
alias vdf='vagrant destroy --force'
alias vh='vagrant halt'
alias vp='vagrant provision'
alias vssh='vagrant ssh'
alias vs='vagrant status'
alias vu='vagrant up'

# macvim
alias macvim='open -a MacVim.app'

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
alias dki='docker images'
alias dkip='docker inspect --format "{{ .NetworkSettings.IPAddress }}"'
alias dklatest="docker ps -l | sed -n 2p | awk '{print \$1}'"
alias dkps='docker ps -a'
alias dkrm='docker rm $(docker ps -notrunc -a -q)'
alias dk-images-remove-all='docker images -a | grep -v ^REPOSITORY | awk "{print \$3}" | xargs docker rmi'
alias dk-images-remove-orphans='docker images | grep "^<none>" | awk "{print \$3}" | xargs docker rmi'
alias dkrund='docker run -d -P'
alias dkruni='docker run -t -i -P'

# rsync
rsync_cmd='rsync --verbose --progress --human-readable --compress --archive --hard-links --one-file-system'

# http://www.bombich.com/rsync.html
if [[ "$OSTYPE" == darwin* ]] && grep -q 'file-flags' <(rsync --help 2>&1); then
  rsync_cmd="${rsync_cmd} --crtimes --acls --xattrs --fileflags --protect-decmpfs --force-change"
fi

alias rsync-copy="${rsync_cmd}"
alias rsync-move="${rsync_cmd} --remove-source-files"
alias rsync-update="${rsync_cmd} --update"
alias rsync-sync="${rsync_cmd} --update --delete"

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

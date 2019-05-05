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

# print docker aliases
dkalias() { alias | grep 'docker' | sed "s/^\([^=]*\)=\(.*\)/\1 => \2/"| sed "s/['|\']//g" | sort; }

# docker attach (detach with ctrl-a)
alias dkatt='docker attach --detach-keys="ctrl-a"'

# docker attach latest (detach with ctrl-a)
alias dkattlatest='dkatt $(docker ps -l -q)'

# get images
alias dki='docker images'

# inspect
alias dkin='docker inspect'

# get container ip
alias dkip='docker inspect --format "{{ .NetworkSettings.IPAddress }}"'

# inspect latest container
alias dkinlatest='docker inspect $(docker ps -l -q)'

# latest container id
alias dklatest='docker ps -l -q'

# logs
alias dklogs='docker logs'

# logs w/follow
alias dklogsf='docker logs -f'

# get process - including stopped containers
alias dkps='docker ps -a'

# remove all containers
alias dkrm='docker rm $(docker ps --no-trunc -a -q)'

# force remove all containers
alias dkrmf='docker rm -f $(docker ps -a -q)'

# remove all dangling images
alias dkrmi='docker rmi $(docker images -q --filter "dangling=true")'

# stop and remove all containers
alias dkrm-the-world='docker stop $(docker ps -a -q) && docker rm -f $(docker ps -a -q)'

# remove all images
alias dki-remove-all='docker images -a | grep -v ^REPOSITORY | awk "{print \$3}" | xargs docker rmi'

# remove all image orphans
alias dki-remove-orphans='docker images | grep "^<none>" | awk "{print \$3}" | xargs docker rmi'

# run daemonized container
alias dkrund='docker run -d -P'

# run interactive container
alias dkruni='docker run -t -i -P'

# exec latest container id
alias dkelatest='dkexe $(docker ps -l -q)'

# shell latest container id
alias dkshlatest='dkexshc $(docker ps -l -q)'

# get stats
alias dks='docker stats --no-stream'

# stop all containers
alias dkstop='docker stop $(docker ps -a -q)'

# exec command ($2) in container by id ($1)
dkexe() { docker exec -it $1 $2; }

# exec command ($2) in container by name ($1)
dkexcn() { dkexe $(docker ps -aqf "name=$1") /bin/sh -c '"$2"'; }

# shell into container by id
dkexshc() { dkexe "$1" /bin/sh; }

# shell into container by name
dkexshcn() { dkexe $(docker ps -aqf "name=$1") /bin/sh; }

# run image
dkrun() { docker run -it --entrypoint /bin/sh "$1"; }

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

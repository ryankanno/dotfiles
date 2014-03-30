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
alias dkrmi='docker rmi $(docker images | grep "^<none>" | awk "{print $3}")'
alias dkrund='docker run -d -P'
alias dkruni='docker run -t -i -P'

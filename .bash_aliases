# nav
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../../'

# short
alias ll='ls -l'
alias c='clear'
alias m='man'

# network
alias ip="dig +short myip.opendns.com @resolver1.opendns.com"

# dev
alias fakesmtp='python -m smtpd -n -c DebuggingServer localhost:1025'

# grep
alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'

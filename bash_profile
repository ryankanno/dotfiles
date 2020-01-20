# open file descriptor 5 such that anything written to /dev/fd/5
# is piped through ts and then to /tmp/bash_timestamps
# exec 5> >(/usr/local/bin/ts -i "%.s" >> /tmp/bash_timestamps)

# https://www.gnu.org/software/bash/manual/html_node/Bash-Variables.html
# export BASH_XTRACEFD=5

# Enable tracing
# set -x

if [ -f $HOME/.bashrc ]; then
    source $HOME/.bashrc
fi

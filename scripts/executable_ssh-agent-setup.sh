#!/usr/bin/env bash

unset SSH_AUTH_SOCK

SSH_ENV="$HOME/.ssh/agent.env"

start_agent() {
    echo "Starting new ssh-agent..."
    ssh-agent | sed 's/^echo/#echo/' > "${SSH_ENV}"
    chmod 600 "${SSH_ENV}"
    . "${SSH_ENV}" > /dev/null
    ssh-add
}

if [ -f "${SSH_ENV}" ]; then
    . "${SSH_ENV}" > /dev/null
    if ! ssh-add -l >/dev/null 2>&1; then
        # Agent is dead or has no keys, start new one
        start_agent
    else
        echo "Using existing ssh-agent ($(ssh-add -l | wc -l) key(s) loaded)"
    fi
else
    start_agent
fi

alias git='git -c gpg.ssh.program=/usr/bin/ssh-keygen'

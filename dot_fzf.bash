command -v fzf &>/dev/null && eval "$(fzf --bash)"

# w/ modifications
if hash fd 2> /dev/null; then
    export FZF_DEFAULT_COMMAND="fd --color=never --hidden --exclude .git --exclude .tox --exclude .direnv --exclude node_modules --type f"
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND="fd --color=never --hidden --exclude .git --type d"
fi

export FZF_DEFAULT_OPTS="--preview 'bat --color=always --style=numbers --line-range=:500 {} 2>/dev/null || cat {}'"

rga-fzf() {
    RG_PREFIX='rga --files-with-matches --no-ignore --hidden --follow -g "!{.git,.tox,.direnv,node_modules}/*" -g "!{*.pyi,*.pyc}" 2> /dev/null'
    echo "$(
        FZF_DEFAULT_COMMAND="$RG_PREFIX '$1'" \
            fzf --sort --preview="[[ ! -z {} ]] && rga --pretty --context 5 {q} {}" \
				--phony -q "$1" \
				--bind "change:reload:$RG_PREFIX {q}" \
				--preview-window="70%:wrap"
	)"
}

if [ -t 1 ]
then
    bind -x '"\C-p": nvim $(fzf);'
    bind -x '"\C-f": nvim $(rga-fzf);'
fi

# enable fzf keybindings
if [[ "$OSTYPE" == "darwin"* ]]; then
  source /opt/local/share/fzf/shell/key-bindings.bash

  # enable fzf fuzzy completion
  [[ $- == *i* ]] && source /opt/local/share/fzf/shell/completion.bash 2> /dev/null
fi

if [[ "$OSTYPE" == "linux-gnu" ]]; then
  source /usr/share/doc/fzf/examples/key-bindings.bash

  # enable fzf fuzzy completion
  [[ $- == *i* ]] && source /usr/share/doc/fzf/examples/completion.bash 2> /dev/null
fi

# w/ modifications
if hash fd 2> /dev/null; then
    export FZF_DEFAULT_COMMAND="fd --color=never --hidden --exclude .git --exclude .tox --exclude .direnv --exclude node_modules --type f"
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND="fd --color=never --hidden --exclude .git --type d"
fi

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

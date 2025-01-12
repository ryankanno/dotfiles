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
export FZF_DEFAULT_COMMAND='rg --files --no-ignore --hidden --follow -g "!{.git,node_modules,.direnv,.tox,.*cache,**/__*cache__}/*" -g "!{*.pyi,*.pyc}" 2> /dev/null'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND='bfs -type d -nohidden'

rga-fzf() {
    RG_PREFIX='rga --files-with-matches --no-ignore --hidden --follow -g "!{.git,node_modules,.direnv,.tox,.*cache,**/__*cache__}/*" -g "!{*.pyi,*.pyc}" 2> /dev/null'
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

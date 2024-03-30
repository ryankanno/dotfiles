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
export FZF_DEFAULT_COMMAND='rg --files --no-ignore --hidden --follow -g "!{.git,.tox,node_modules,.*cache,__*cache__}/*" 2> /dev/null'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND="bfs -type d -nohidden"

if [ -t 1 ]
then
    bind -x '"\C-p": nvim $(fzf);'
fi

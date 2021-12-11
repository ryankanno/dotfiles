# enable fzf keybindings
source /opt/local/share/fzf/shell/key-bindings.bash

# w/ modifications
export FZF_DEFAULT_COMMAND='rg --files --no-ignore --hidden --follow -g "!{.git,node_modules,.*cache,__*cache__}/*" 2> /dev/null'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND="bfs -type d -nohidden"
bind -x '"\C-p": nvim $(fzf);'

# enable fzf fuzzy completion
[[ $- == *i* ]] && source /opt/local/share/fzf/shell/completion.bash 2> /dev/null

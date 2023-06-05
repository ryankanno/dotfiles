let g:python3_host_prog="~/.anyenv/envs/pyenv/versions/nvim-python3/bin/python"
let g:loaded_python_provider=0

if exists('g:vscode')
    set runtimepath+=~/.vim,~/.vim/after,~/.local/share/nvim/plugged/vim-shortcut,~/.local/share/nvim/site
else
    set runtimepath+=~/.vim,~/.vim/after,~/.local/share/nvim/plugged/vim-shortcut
end

set packpath+=~/.vim
source ~/.vimrc

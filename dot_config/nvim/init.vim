let g:python3_host_prog="~/.anyenv/envs/pyenv/versions/nvim-python3/bin/python"
let g:loaded_python_provider=0
set runtimepath+=~/.vim,~/.vim/after
set packpath+=~/.vim
source ~/.vimrc
lua << EOF
require'hop'.setup{
  quit_key = '<SPC>',
}
EOF

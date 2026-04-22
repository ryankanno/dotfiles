{ pkgs, unstable, lib, ... }: let

common-tools-packages = with unstable; [
    age            # encryption tool (https://github.com/FiloSottile/age)
    atuin          # shell history (https://github.com/atuinsh/atuin)
    awscli2
    bandwhich      # terminal bandwidth (https://github.com/imsnif/bandwhich)
    bat            # cat alternative (https://github.com/sharkdp/bat)
    btop           # resource monitor (https://github.com/aristocratics/btop)
    clipboard-jh   # clipboard (https://github.com/Slackadays/Clipboard)
    coreutils
    curl
    delta          # pager (https://github.com/dandavison/delta)
    difftastic     # structural diff (https://github.com/Wilfred/difftastic)
    dua            # disk usage (https://github.com/Byron/dua-cli)
    eza            # ls alternative (https://github.com/eza-community/eza)
    fd             # find alternative (https://github.com/sharkdp/fd)
    findutils
    fq             # jq for binary (https://github.com/wader/fq)
    fx             # terminal json (https://github.com/antonmedv/fx)
    git-crypt
    git-open       # https://github.com/paulirish/git-open
    glow           # terminal markdown (https://github.com/charmbracelet/glow)
    hyperfine      # benchmarking (https://github.com/sharkdp/hyperfine)
    jq             # json processor (https://github.com/jqlang/jq)
    just           # command runner (https://github.com/casey/just)
    killall
    miller         # https://github.com/johnkerl/miller
    mise           # dev tools version manager (https://github.com/jdx/mise)
    moreutils      # https://joeyh.name/code/moreutils/
    onefetch       # git info tool (https://github.com/o2sh/onefetch)
    (lib.hiPrio parallel)
    prettyping     # ping wrapper (https://github.com/denilsonsa/prettyping)
    procs          # ps alternative (https://github.com/dalance/procs)
    progress       # show progress (https://github.com/Xfennec/progress)
    pv
    restic         # backup (https://github.com/restic/restic)
    ripgrep
    ripgrep-all    # https://github.com/phiresky/ripgrep-all
    sd             # sed alternative (https://github.com/chmln/sd)
    shellcheck
    taplo          # toml (https://github.com/tamasfe/taplo)
    tealdeer       # tldr (https://github.com/dbrgn/tealdeer)
    tmux
    toastify       # command line tool using notify-rust (https://github.com/hoodie/toastify)
    tokei          # cloc alternative (https://github.com/XAMPPRocky/tokei)
    trash-cli      # trash cli (https://github.com/andreafrancia/trash-cli)
    tree
    tree-sitter    # parser generator (https://github.com/tree-sitter/tree-sitter)
    unzip
    upterm         # terminal sharing (https://github.com/owenthereal/upterm)
    vim-full
    watchexec      # runs commands on modification (https://github.com/watchexec/watchexec)
    wget
    zip
    zoxide         # smarter cd (https://github.com/ajeetdsouza/zoxide)

    # funsies
    figlet         # https://github.com/cmatsuoka/figlet
    toilet         # https://github.com/cacalabs/toilet
];

common-language-packages = with unstable; [
    cargo
    rustc
    go
];

stable-packages = with pkgs; [
    gh
    cargo-cache
    cargo-expand
];

in
{
    home.file = {};
    home.sessionVariables = {};
    home.packages = stable-packages ++ common-tools-packages ++ common-language-packages;
    programs.home-manager.enable = true;
    programs.git = {
        enable = true;
        lfs.enable = true;
    };
}

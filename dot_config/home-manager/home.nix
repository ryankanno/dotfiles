{
    config, pkgs, unstable, ...
}: let

unstable-packages = with unstable; [
    bat
    bottom
    btop
    cloc
    coreutils
    curl
    delta
    difftastic
    du-dust
    eza
    fd
    findutils
    fq
    fx
    git
    git-crypt
    htop
    hyperfine
    jq
    killall
    miller
    mosh
    ncdu
    neovim
    onefetch
    procs
    restic
    ripgrep
    sd
    tealdeer
    tmux
    tokei
    trash-cli
    tree
    tree-sitter
    unzip
    vim
    wget
    zip
    zoxide

    # funsies
    figlet
    toilet
];

stable-packages = with pkgs; [
    gh
    cargo-cache
    cargo-expand
];
in
{
    home.username = "ryankanno";
    home.homeDirectory = "/home/ryankanno";
    home.stateVersion = "23.11"; # Please read the comment before changing.
    home.packages = stable-packages ++ unstable-packages ++ [];
    home.file = {};
    home.sessionVariables = {};
    programs.home-manager.enable = true;
}

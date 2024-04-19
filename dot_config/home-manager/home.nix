{
    config, pkgs, unstable, ...
}: let

unstable-packages = with unstable; [
    bat
    bottom
    coreutils
    curl
    du-dust
    fd
    findutils
    fx
    git
    git-crypt
    htop
    jq
    killall
    lunarvim
    mosh
    neovim
    procs
    ripgrep
    sd
    tmux
    tree
    unzip
    vim
    wget
    zip
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

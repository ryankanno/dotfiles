{
    config, pkgs, unstable, ...
}: let

unstable-packages = with unstable; [
    atuin          # shell history (https://github.com/atuinsh/atuin)
    bandwhich      # terminal bandwidth (https://github.com/imsnif/bandwhich)
    bat            # cat alternative (https://github.com/sharkdp/bat)
    btop           # resource monitor (https://github.com/aristocratos/btop)
    coreutils
    curl
    delta          # pager (https://github.com/dandavison/delta)
    difftastic     # structural diff (https://github.com/Wilfred/difftastic)
    diskonaut      # disk usage (https://github.com/imsnif/diskonaut)
    dua            # disk usage (https://github.com/Byron/dua-cli)
    duc            # disk usage (https://duc.zevv.nl/)
    du-dust        # disk usage (https://github.com/bootandy/dust)
    erdtree        # fs + disk usage (https://github.com/solidiquis/erdtree)
    eza            # ls alternative (https://github.com/eza-community/eza)
    fd             # find alternative (https://github.com/sharkdp/fd)
    findutils
    fq             # jq for binary (https://github.com/wader/fq)
    fx             # terminal json (https://github.com/antonmedv/fx)
    git
    git-crypt
    glow           # terminal markdown (https://github.com/charmbracelet/glow)
    hyperfine      # benchmarking (https://github.com/sharkdp/hyperfine)
    jq             # json processor (https://github.com/jqlang/jq)
    killall
    miller         # https://github.com/johnkerl/miller
    mosh           # mobile shell (https://github.com/mobile-shell/mosh)
    neofetch       # system info tool (https://github.com/dylanaraps/neofetch)
    neovim
    onefetch       # git info tool (https://github.com/o2sh/onefetch)
    parallel
    prettyping     # ping wrapper (https://github.com/denilsonsa/prettyping)
    procs          # ps alternative (https://github.com/dalance/procs)
    progress       # show progress (https://github.com/Xfennec/progress)
    pv
    restic         # backup (https://github.com/restic/restic)
    ripgrep
    sd             # sed alternative (https://github.com/chmln/sd)
    taplo          # toml (https://github.com/tamasfe/taplo)
    tealdeer       # tldr (https://github.com/dbrgn/tealdeer)
    tmux
    tokei          # cloc alternative (https://github.com/XAMPPRocky/tokei)
    trash-cli      # trash cli (https://github.com/andreafrancia/trash-cli)
    tree
    tree-sitter    # parser generator (https://github.com/tree-sitter/tree-sitter)
    unzip
    vim
    wget
    zip
    zoxide         # smarter cd (https://github.com/ajeetdsouza/zoxide)

    # funsies
    figlet         # https://github.com/cmatsuoka/figlet
    toilet         # https://github.com/cacalabs/toilet
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

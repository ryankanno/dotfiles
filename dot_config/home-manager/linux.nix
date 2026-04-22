{
    config, pkgs, unstable, lib, ...
}: let

linux-packages = with unstable; [
    calibre        # ebook manager (https://github.com/kovidgoyal/calibre)
    dust           # disk usage (https://github.com/bootandy/dust)
    fastfetch      # system info tool (https://github.com/fastfetch-cli/fastfetch)
    litestream     # https://github.com/benbjohnson/litestream
    mosh           # mobile shell (https://github.com/mobile-shell/mosh)
    nix-prefetch
    rofi           # https://github.com/davatorium/rofi
];

in
{
    imports = [ ./common.nix ];

    home.username = "ryankanno";
    home.homeDirectory = "/home/ryankanno";
    home.stateVersion = "23.11"; # Please read the comment before changing.
    home.packages = linux-packages;
}

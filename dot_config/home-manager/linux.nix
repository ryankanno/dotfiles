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
    ntfy-sh        # ntfy client (https://github.com/binwiederhier/ntfy)
    rofi           # https://github.com/davatorium/rofi
];

in
{
    imports = [ ./common.nix ];

    home.username = "ryankanno";
    home.homeDirectory = "/home/ryankanno";
    home.stateVersion = "23.11"; # Please read the comment before changing.
    home.packages = linux-packages;

    # ntfy ships no daemon: `subscribe --from-config` is a foreground process
    # that reads ~/.config/ntfy/client.yml and runs each topic's command per
    # message. Started by hand it dies with its shell and notifications stop
    # with nothing to show for it.
    systemd.user.services.ntfy-subscriber = {
        Unit = {
            Description = "ntfy desktop notification subscriber";
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
        };

        # The topic commands call notify-send and date, both under /usr/bin,
        # which systemd puts on the default user PATH.
        Service = {
            ExecStart = "${unstable.ntfy-sh}/bin/ntfy subscribe --from-config";
            Restart = "always";
            RestartSec = 5;
        };

        Install.WantedBy = [ "graphical-session.target" ];
    };
}

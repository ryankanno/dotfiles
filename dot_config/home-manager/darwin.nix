{
    config, pkgs, unstable, lib, ...
}: let

darwin-packages = with unstable; [
    colima         # container runtime (https://github.com/abiosoft/colima)
    dust           # disk usage (https://github.com/bootandy/dust)
    fastfetch      # system info tool (https://github.com/fastfetch-cli/fastfetch)
];

in
{
    imports = [ ./common.nix ];

    home.username = "ryankanno";
    home.homeDirectory = "/Users/ryankanno";
    home.stateVersion = "23.11"; # Please read the comment before changing.
    home.packages = darwin-packages;
}

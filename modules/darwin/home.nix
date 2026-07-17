# Darwin-only home-manager extras (GUI apps Nix can provide).
#
# Package notes:
# - ghostty-bin: official macOS .dmg repackage (pkgs.ghostty is Linux GTK)
# - zed-editor: code editor (pkgs.zed is an unrelated data-lake package)
# - signal-desktop / slack / whatsapp-for-mac: proprietary DMGs in nixpkgs
# - Microsoft Outlook: not in nixpkgs — install manually
#
# Not here (zerobrew / uv instead):
# - aerospace, rtk, mole → modules/darwin/zerobrew.nix
# - headroom → modules/agents (uv tool install)
{ lib, pkgs, ... }:
let
  optionalPkg = name: lib.optional (pkgs ? ${name}) pkgs.${name};
in
{
  home.packages =
    optionalPkg "ghostty-bin"
    ++ optionalPkg "zed-editor"
    ++ optionalPkg "signal-desktop"
    ++ optionalPkg "slack"
    ++ optionalPkg "whatsapp-for-mac";
}

# Darwin-only home-manager extras.
# Ghostty is zerobrew/brew cask only (see zerobrew.nix) — do not install pkgs.ghostty here.
{ lib, pkgs, ... }:
{
  home.packages = lib.optional (pkgs ? aerospace) pkgs.aerospace;
}

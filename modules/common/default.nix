{ lib, pkgs, ... }:
let
  modernCli = with pkgs; [
    stow
    git
    gh
    neovim
    zellij
    atuin
    lazygit
    ripgrep
    fd
    eza
    zoxide
    bat
    dust
    sd
    delta
    procs
    uv
    bun
    zola
    jq
    curl
    wget
    tree
    unzip
    gnutar
    cloudflared
  ];
in
{
  # home.stateVersion: only in flake.nix user / homeConfiguration blocks
  # nixpkgs.config.allowUnfree: set on darwin module / Linux pkgs import (useGlobalPkgs)
  #
  # rtk: Darwin via zerobrew (not Nix). Linux: install manually (see modules/linux).
  # headroom: uv tool install in modules/agents (not Nix).

  home.packages = modernCli;

  xdg.enable = true;

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    PAGER = "bat";
  };

  home.activation.checkDotfilesStow = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -e "$HOME/.config/nushell/config.nu" ]; then
      echo "WARNING: ~/.config/nushell/config.nu missing — clone .dotfiles and run: stow ."
    fi
  '';
}

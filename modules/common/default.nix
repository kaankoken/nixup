{ lib, pkgs, ... }:
let
  # Prefer nixpkgs package when present; skip silently otherwise.
  optionalPkg = name: lib.optional (pkgs ? ${name}) pkgs.${name};

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
  ];

  # rtk: install when packaged in nixpkgs; otherwise zerobrew/brew on Mac (see modules/darwin/zerobrew.nix)
  rtkPkgs = optionalPkg "rtk";
in
{
  # home.stateVersion: only in flake.nix user / homeConfiguration blocks
  # nixpkgs.config.allowUnfree: set on darwin module / Linux pkgs import (useGlobalPkgs)

  home.packages = modernCli ++ rtkPkgs;

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

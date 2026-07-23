{ lib, pkgs, ... }:
let
  modernCli = with pkgs; [
    stow
    git
    gh
    neovim
    zellij
    yazi
    atuin
    lazygit
    # Git UX — wired in ~/.gitconfig / ~/.gitattributes (not lazygit-specific):
    #   diff.external = difft; diff.tool = difftastic; merge driver = mergiraf
    difftastic
    mergiraf
    git-filter-repo # occasional history rewrite (strip secrets, extract subdir, …)
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
    # Rust workflow helpers (toolchain itself via rustup in modules/agents — not nixpkgs rustc)
    bacon
    cargo-nextest
  ];
in
{
  # home.stateVersion: only in flake.nix user / homeConfiguration blocks
  # nixpkgs.config.allowUnfree: set on darwin module / Linux pkgs import (useGlobalPkgs)
  #
  # rtk / codex / caveman: official curl installers in modules/agents (not Nix).
  # codex is standalone only — agents purges legacy bun/npm wrappers on activate.
  # headroom: uv tool install in modules/agents (not Nix).
  # rustc/cargo: rustup activation; bacon + cargo-nextest from Nix.
  # JS CLIs still on bun: pi only — do not add nodejs/npm to this flake.

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

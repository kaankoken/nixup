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
    # Structural search/rewrite for agents + tokensave_ast_grep_rewrite
    ast-grep
    # Agents.md documents `sg`; nixpkgs only ships `ast-grep`.
    (writeShellScriptBin "sg" ''
      exec ${lib.getExe ast-grep} "$@"
    '')
    # Nix rebuild UX (nh uses nom under the hood when available)
    nh
    nix-output-monitor
  ];
in
{
  # home.stateVersion: only in flake.nix user / homeConfiguration blocks
  # nixpkgs.config.allowUnfree: set on darwin module / Linux pkgs import (useGlobalPkgs)
  #
  # rtk / codex / caveman / ponytail / tokensave / context-mode: modules/agents (not Nix packages).
  # codex is standalone only — agents purges legacy bun/npm wrappers on activate.
  # headroom: uv tool install in modules/agents (not Nix).
  # rustc/cargo: rustup activation; bacon + cargo-nextest from Nix.
  # JS CLIs still on bun: pi + context-mode; no system nodejs/npm in this flake.
  # Shared agent stack + local CLI toolkit (rg/fd/eza/bat/sd/ast-grep/…):
  # see AGENTS.md (prefer modern binaries; agents must not fall back to grep/find/sed).

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

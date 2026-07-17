{
  config,
  lib,
  pkgs,
  user,
  hostName,
  ...
}:
{
  imports = [
    # cloudflare-remote-access: host-only (see hosts/*/default.nix)
    ./zerobrew.nix
  ];

  # Determinate Nix owns the daemon / Nix install. Letting nix-darwin manage
  # Nix aborts activation — see error: "Determinate detected, aborting activation".
  # Flakes and trusted-users are configured by Determinate (not nix-darwin).
  nix.enable = false;

  nixpkgs.config.allowUnfree = true;

  # Primary user for nix-darwin defaults
  system.primaryUser = user;

  users.users.${user} = {
    shell = pkgs.nushell;
  };

  # Register nu as a valid shell
  environment.shells = with pkgs; [
    bashInteractive
    zsh
    nushell
  ];

  # System-visible packages (also on PATH for GUI apps).
  # aerospace / rtk / mole: zerobrew (see zerobrew.nix), not Nix.
  environment.systemPackages = with pkgs; [
    nushell
    git
    vim
  ];

  # Fonts matching current Ghostty/dotfiles setup
  fonts.packages = with pkgs; [
    nerd-fonts.fira-code
    nerd-fonts.jetbrains-mono
  ];

  # Reasonable defaults (non-destructive)
  programs.zsh.enable = true; # keep for recovery / scripts
  security.pam.services.sudo_local.touchIdAuth = true;

  system.stateVersion = 5;

  # Host-specific module can override
  networking.computerName = lib.mkDefault hostName;
  networking.localHostName = lib.mkDefault hostName;
}

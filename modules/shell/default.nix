{ pkgs, ... }:
{
  # Binaries only — configs stay in .dotfiles via stow.
  # Do not enable programs.nushell / programs.starship (they fight stow).
  home.packages = with pkgs; [
    nushell
    starship
  ];

  home.sessionVariables = {
    SHELL = "${pkgs.nushell}/bin/nu";
  };

  home.sessionPath = [
    "$HOME/.local/bin"
    "$HOME/.cargo/bin"
    "$HOME/.radicle/bin"
  ];
}

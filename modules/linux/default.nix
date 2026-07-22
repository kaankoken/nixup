{ lib, pkgs, ... }:
{
  # Linux home-manager extras (no zerobrew / aerospace / mole).
  home.packages = with pkgs; [
    # xdg helpers often useful on desktop linux
    xdg-utils
  ];

  # mole / aerospace are Darwin zerobrew packages; rtk is agents curl install (all OS).
  home.activation.linuxDarwinOnlyHint = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if ! command -v rtk >/dev/null 2>&1; then
      echo "[linux] rtk not on PATH yet — agents activation: curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh"
    fi
  '';
}

{ lib, pkgs, ... }:
{
  # Linux home-manager extras (no zerobrew / aerospace / mole).
  home.packages = with pkgs; [
    # xdg helpers often useful on desktop linux
    xdg-utils
  ];

  # rtk / mole / aerospace are Darwin zerobrew packages; on Linux install manually.
  home.activation.linuxRtkHint = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if ! command -v rtk >/dev/null 2>&1; then
      echo "[linux] rtk not on PATH — https://github.com/rtk-ai/rtk (or brew if available)"
    fi
  '';
}

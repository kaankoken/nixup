{ lib, pkgs, ... }:
{
  # Linux home-manager extras (no zerobrew / aerospace / mole).
  home.packages = with pkgs; [
    # xdg helpers often useful on desktop linux
    xdg-utils
  ];

  # rtk: if not in nixpkgs, user installs manually (smoke will report)
  home.activation.linuxRtkHint = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if ! command -v rtk >/dev/null 2>&1; then
      echo "[linux] rtk not on PATH — install from https://www.rtk-ai.app/ if headroom/agents need it"
    fi
  '';
}

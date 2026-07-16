#!/usr/bin/env nu
# Day-0 bootstrap for nix-setup
# Usage: nu scripts/bootstrap.nu [--host kaan-macmini]

def main [
  --host: string = "kaan-macmini"  # flake host attr (darwin) or ignore for linux
  --linux                              # use home-manager instead of darwin-rebuild
  --linux-attr: string = "legolas@linux"
] {
  # scripts/ lives under repo root
  let repo_root = (
    if ($env | get -o FILE_PWD) != null {
      $env.FILE_PWD | path dirname
    } else {
      $env.PWD
    }
  )

  print $"=== nix-setup bootstrap ==="
  print $"repo: ($repo_root)"
  print $"host: ($host)"

  # 1) Ensure Nix
  if (which nix | is-empty) {
    print "Nix not found. Installing via Determinate Systems installer..."
    print "(You will be prompted for sudo / admin)"
    ^curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | ^sh -s -- install
    print "Nix install finished. Open a new shell or source nix profile, then re-run this script."
    print "  source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish  # or bash equivalent"
    return
  } else {
    print $"Nix OK: (^nix --version | str trim)"
  }

  # 2) Apply flake
  cd $repo_root
  if $linux {
    print $"Applying home-manager: .#($linux_attr)"
    if (which home-manager | is-empty) {
      print "Installing home-manager into user profile (one-time)..."
      ^nix run home-manager/master -- switch --flake $".#($linux_attr)"
    } else {
      ^home-manager switch --flake $".#($linux_attr)"
    }
  } else {
    print $"Applying nix-darwin: .#($host)"
    ^nix run nix-darwin -- switch --flake $".#($host)"
  }

  # 3) Dotfiles reminder
  let dotfiles = ($env.HOME | path join ".dotfiles")
  if not ($dotfiles | path exists) {
    print "Clone dotfiles next:"
    print "  git clone git@github.com:kaankoken/.dotfiles.git ~/.dotfiles"
  } else {
    print $"Dotfiles found at ($dotfiles)"
    print "Apply stow from that repo:"
    print "  cd ~/.dotfiles; stow ."
  }

  print ""
  print "Then run smoke tests:"
  print $"  nu ($repo_root)/scripts/smoke.nu"
  print $"  nu ($repo_root)/scripts/smoke.nu --strict"
}

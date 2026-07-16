#!/usr/bin/env nu
# Smoke-test declared tooling. Default: report all. --strict: non-zero if required missing.
# rtk is optional (nixpkgs conditional / Linux manual).

def is_mac [] {
  (uname | get kernel-name) == "Darwin"
}

def check_cmd [name: string, required: bool = true] {
  let found = (which $name | is-not-empty)
  if $found {
    let path = (which $name | get 0.path)
    { name: $name, ok: true, required: $required, detail: $path }
  } else {
    { name: $name, ok: false, required: $required, detail: "MISSING" }
  }
}

def main [
  --strict  # exit 1 if any required tool is missing
] {
  mut checks = []

  # Guaranteed post-apply via nixpkgs / rustup activation
  let required = [
    "nu" "starship" "stow" "git" "gh"
    "nvim" "zellij" "atuin" "lazygit"
    "rg" "fd" "eza" "zoxide" "bat" "dust" "sd" "delta" "procs"
    "uv" "bun" "zola"
    "rustc" "cargo"
  ]

  for name in $required {
    $checks = ($checks | append (check_cmd $name true))
  }

  # Soft / agent tools (rtk optional — not required for --strict)
  # grok: official x.ai CLI binary is `grok` (install.sh); not a separate `grok-build` command
  for name in ["rtk" "headroom" "claude" "codex" "bd" "beads" "rad" "grok"] {
    $checks = ($checks | append (check_cmd $name false))
  }

  if (is_mac) {
    for name in ["aerospace" "mole"] {
      $checks = ($checks | append (check_cmd $name false))
    }
    for app in ["Ghostty" "Zed" "Signal" "Slack" "WhatsApp"] {
      let path = $"/Applications/($app).app"
      let ok = ($path | path exists)
      $checks = ($checks | append {
        name: $"app:($app)"
        ok: $ok
        required: false
        detail: (if $ok { $path } else { "MISSING" })
      })
    }
  }

  print "=== smoke results ==="
  for row in $checks {
    let mark = (if $row.ok { "OK  " } else { "FAIL" })
    let req = (if $row.required { "req" } else { "opt" })
    print $"($mark) [($req)] ($row.name) — ($row.detail)"
  }

  print ""
  print "=== which (PATH provenance) ==="
  for name in ["nu" "rg" "nvim" "uv" "starship"] {
    if (which $name | is-not-empty) {
      print $"($name): (which $name | get 0.path)"
    }
  }

  # Pre-Nix: Nix profile dirs may not exist — only check order when they do
  print ""
  print "=== PATH order (Nix vs brew, if present) ==="
  let path_list = ($env.PATH | split row (char esep))
  let interesting = ($path_list | where {|p|
    ($p | str contains "nix") or ($p | str contains "homebrew") or ($p | str contains "profiles/per-user")
  })
  if ($interesting | is-empty) {
    print "(no nix/homebrew entries visible yet — OK pre-Nix)"
  } else {
    $interesting | each {|p| print $p}
  }

  let failed_req = ($checks | where {|r| (not $r.ok) and $r.required })
  let failed_opt = ($checks | where {|r| (not $r.ok) and (not $r.required) })

  print ""
  print $"Required missing: ($failed_req | length)"
  print $"Optional missing: ($failed_opt | length)"

  if $strict and ($failed_req | length) > 0 {
    print "STRICT mode: failing due to required tools missing"
    exit 1
  }
}

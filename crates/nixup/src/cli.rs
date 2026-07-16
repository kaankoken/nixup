//! Clap surface for `nixup`.

use std::path::PathBuf;

use clap::{
    Parser,
    Subcommand,
};

/// nixup: bootstrap, apply, and smoke-test multi-host Nix flakes.
#[derive(Debug, Parser)]
#[command(name = "nixup", version, about, long_about = None)]
pub struct Cli {
    /// Path to the flake root (directory with flake.nix). Walks up from cwd if omitted.
    #[arg(long, global = true)]
    pub flake: Option<PathBuf>,

    /// Path to nixup.toml (overrides discovery).
    #[arg(long, global = true)]
    pub config: Option<PathBuf>,

    /// Skip confirmation prompts.
    #[arg(long, short = 'y', global = true)]
    pub yes: bool,

    /// Extra diagnostics on stderr.
    #[arg(long, short = 'v', global = true)]
    pub verbose: bool,

    #[command(subcommand)]
    pub command: Command,
}

/// Subcommands.
#[derive(Debug, Subcommand)]
pub enum Command {
    /// Ensure Nix, apply flake, run smoke, remind about stow.
    Bootstrap {
        /// Host id from nixup.toml.
        #[arg(long)]
        host:       Option<String>,
        /// Skip smoke after apply.
        #[arg(long)]
        skip_smoke: bool,
    },
    /// Apply the flake for this (or --host) machine.
    Apply {
        /// Host id from nixup.toml.
        #[arg(long)]
        host: Option<String>,
    },
    /// Alias for apply.
    Switch {
        /// Host id from nixup.toml.
        #[arg(long)]
        host: Option<String>,
    },
    /// Check required and optional tools.
    Smoke {
        /// Exit 2 if any required tool is missing.
        #[arg(long)]
        strict: bool,
    },
    /// Health: nix, flake root, config, host mapping, light smoke.
    Doctor,
    /// Run `nix flake update`.
    Update,
    /// List configured hosts, or create host modules from nixup.toml.
    Hosts {
        #[command(subcommand)]
        action: Option<HostsAction>,
    },
    /// Short status: OS, hostname, flake root, nix version, resolved host.
    Status,
    /// Clone and/or stow dotfiles.
    Stow {
        /// Clone `defaults.dotfiles_url` if path is missing.
        #[arg(long)]
        clone: bool,
    },
    /// Install Nix via Determinate Systems installer.
    InstallNix,
}

/// `nixup hosts` subcommands.
#[derive(Debug, Subcommand)]
pub enum HostsAction {
    /// List hosts from config and which one matches this machine (default).
    List,
    /// Create `hosts/<id>/` modules + `hosts/inventory.nix` from nixup.toml.
    Sync {
        /// Overwrite existing `default.nix` files.
        #[arg(long)]
        force: bool,
    },
}

//! Domain models and pure helpers for the `nixup` CLI.

#![forbid(unsafe_code)]

pub mod config;
pub mod error;
pub mod flake;
pub mod hosts;
pub mod scaffold;

pub use config::{
    ApplyKind,
    Defaults,
    HostEntry,
    HostOs,
    NixupConfig,
    SmokeConfig,
    SmokeDarwinConfig,
    discover_config_path,
    load_config,
};
pub use error::{
    CoreError,
    CoreResult,
};
pub use flake::{
    find_flake_root,
    resolve_flake_root,
};
pub use hosts::{
    RuntimeIdentity,
    resolve_host,
};
pub use scaffold::{
    HostSyncItem,
    HostsSyncReport,
    default_system,
    default_user,
    host_dir_name,
    render_host_default_nix,
    render_inventory_nix,
    sync_hosts,
};

//! Core error types for nixup-core.

use std::path::PathBuf;

use thiserror::Error;

/// Errors from config loading, host resolution, and path discovery.
#[derive(Debug, Error)]
pub enum CoreError {
    /// No `flake.nix` found walking up from the start directory.
    #[error("flake root not found (no flake.nix walking up from {start})")]
    FlakeRootNotFound {
        /// Directory where the search started.
        start: PathBuf,
    },

    /// Config file missing at all discovery locations.
    #[error(
        "nixup config not found; create nixup.toml next to flake.nix \
         (or pass --config / set NIXUP_CONFIG)"
    )]
    ConfigNotFound,

    /// Failed to read a config file.
    #[error("failed to read config at {path}: {source}")]
    ConfigRead {
        /// Path that failed.
        path: PathBuf,
        /// Underlying I/O error.
        #[source]
        source: std::io::Error,
    },

    /// Failed to parse TOML config.
    #[error("failed to parse config at {path}: {source}")]
    ConfigParse {
        /// Path that failed.
        path: PathBuf,
        /// Underlying parse error.
        #[source]
        source: toml::de::Error,
    },

    /// Unsupported schema version.
    #[error("unsupported schema_version {found} (supported: {supported})")]
    UnsupportedSchema {
        /// Version found in the file.
        found: u32,
        /// Maximum supported version.
        supported: u32,
    },

    /// Requested host id is not in the config.
    #[error("unknown host id `{id}`; known: {known}")]
    UnknownHost {
        /// Requested host id.
        id: String,
        /// Comma-separated known ids.
        known: String,
    },

    /// Could not resolve a host for this machine.
    #[error(
        "could not resolve host for os={os} hostname={hostname:?}; \
         pass --host or update match_hostnames in nixup.toml (known: {known})"
    )]
    HostUnresolved {
        /// Detected OS label.
        os: String,
        /// Detected hostname, if any.
        hostname: Option<String>,
        /// Comma-separated known ids.
        known: String,
    },

    /// Config has no hosts array.
    #[error("config has no [[hosts]] entries")]
    NoHosts,
}

/// Result alias for core operations.
pub type CoreResult<T> = Result<T, CoreError>;

//! Errors from external process operations.

use std::path::PathBuf;

use thiserror::Error;

/// Ops-layer failures (nix, installers, git, stow).
#[derive(Debug, Error)]
pub enum OpsError {
    /// A required command is not on PATH.
    #[error("command not found on PATH: {0}")]
    CommandNotFound(String),

    /// Process exited non-zero.
    #[error("`{command}` failed with status {status}: {stderr}")]
    CommandFailed {
        /// Command name or argv0.
        command: String,
        /// Exit status code if available.
        status:  i32,
        /// Captured stderr (truncated).
        stderr:  String,
    },

    /// I/O error around a process or path.
    #[error("io error for {context}: {source}")]
    Io {
        /// Human context.
        context: String,
        /// Underlying error.
        #[source]
        source:  std::io::Error,
    },

    /// User declined a confirmation-gated operation.
    #[error("operation aborted by user: {0}")]
    Aborted(String),

    /// Dotfiles path missing and clone not requested.
    #[error("dotfiles path does not exist: {0}")]
    DotfilesMissing(PathBuf),
}

/// Result alias for ops.
pub type OpsResult<T> = Result<T, OpsError>;

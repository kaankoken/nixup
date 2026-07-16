//! External process adapters for `nixup`.

#![forbid(unsafe_code)]

pub mod error;
pub mod nix;
pub mod process;
pub mod stow;

pub use error::{
    OpsError,
    OpsResult,
};
pub use nix::{
    DETERMINATE_INSTALL_URL,
    apply_host,
    flake_update,
    install_nix_determinate,
    nix_available,
    nix_version,
};
pub use process::{
    command_exists,
    find_bin,
};
pub use stow::{
    clone_dotfiles,
    expand_tilde,
    stow_dotfiles,
};

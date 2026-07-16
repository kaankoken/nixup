//! Dotfiles clone and stow helpers.

use std::path::{
    Path,
    PathBuf,
};

use crate::{
    error::{
        OpsError,
        OpsResult,
    },
    process::{
        find_bin,
        run_status,
    },
};

/// Expand a leading `~` using `$HOME`.
#[must_use]
pub fn expand_tilde(path: &str) -> PathBuf {
    if let Some(rest) = path.strip_prefix("~/") {
        if let Ok(home) = std::env::var("HOME") {
            return PathBuf::from(home).join(rest);
        }
    }
    if path == "~" {
        if let Ok(home) = std::env::var("HOME") {
            return PathBuf::from(home);
        }
    }
    PathBuf::from(path)
}

/// Clone a git repo into `dest` if it does not exist.
pub fn clone_dotfiles(url: &str, dest: &Path) -> OpsResult<()> {
    if dest.exists() {
        return Ok(());
    }
    find_bin("git")?;
    if let Some(parent) = dest.parent() {
        std::fs::create_dir_all(parent).map_err(|source| OpsError::Io {
            context: format!("create parent of {}", dest.display()),
            source,
        })?;
    }
    run_status("git", &["clone", url, &dest.display().to_string()], None)
}

/// Run `stow .` from the dotfiles directory.
pub fn stow_dotfiles(dotfiles_dir: &Path) -> OpsResult<()> {
    if !dotfiles_dir.is_dir() {
        return Err(OpsError::DotfilesMissing(dotfiles_dir.to_path_buf()));
    }
    find_bin("stow")?;
    run_status("stow", &["."], Some(dotfiles_dir))
}

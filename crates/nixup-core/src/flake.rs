//! Discover the flake root directory containing `flake.nix`.

use std::path::{
    Path,
    PathBuf,
};

use crate::error::{
    CoreError,
    CoreResult,
};

/// Walk up from `start` until a directory containing `flake.nix` is found.
pub fn find_flake_root(start: &Path) -> CoreResult<PathBuf> {
    let mut current = if start.is_absolute() {
        start.to_path_buf()
    } else {
        std::env::current_dir()
            .unwrap_or_else(|_| PathBuf::from("."))
            .join(start)
    };

    // Canonicalize when possible so parents work from relative paths.
    if let Ok(canonical) = current.canonicalize() {
        current = canonical;
    }

    loop {
        let candidate = current.join("flake.nix");
        if candidate.is_file() {
            return Ok(current);
        }
        if !current.pop() {
            break;
        }
    }

    Err(CoreError::FlakeRootNotFound {
        start: start.to_path_buf(),
    })
}

/// Resolve flake root: explicit `--flake` path, or walk from cwd.
pub fn resolve_flake_root(explicit: Option<&Path>) -> CoreResult<PathBuf> {
    if let Some(path) = explicit {
        let path = if path.is_file() {
            path.parent()
                .map_or_else(|| path.to_path_buf(), Path::to_path_buf)
        } else {
            path.to_path_buf()
        };
        let flake = path.join("flake.nix");
        if flake.is_file() {
            Ok(path)
        } else {
            Err(CoreError::FlakeRootNotFound { start: path })
        }
    } else {
        let cwd = std::env::current_dir().map_err(|source| CoreError::ConfigRead {
            path: PathBuf::from("."),
            source,
        })?;
        find_flake_root(&cwd)
    }
}

#[cfg(test)]
mod tests {
    use std::fs;

    use tempfile::tempdir;

    use super::*;

    #[test]
    fn finds_flake_walking_up() {
        let dir = tempdir().expect("temp");
        let root = dir.path();
        fs::write(root.join("flake.nix"), "{}\n").expect("write flake");
        let nested = root.join("a").join("b");
        fs::create_dir_all(&nested).expect("mkdir");
        let found = find_flake_root(&nested).expect("find");
        assert_eq!(found, root.canonicalize().expect("canon"));
    }

    #[test]
    fn missing_flake_errors() {
        let dir = tempdir().expect("temp");
        let err = find_flake_root(dir.path()).expect_err("missing");
        assert!(matches!(err, CoreError::FlakeRootNotFound { .. }));
    }

    #[test]
    fn explicit_directory_with_flake() {
        let dir = tempdir().expect("temp");
        fs::write(dir.path().join("flake.nix"), "{}\n").expect("write");
        let found = resolve_flake_root(Some(dir.path())).expect("resolve");
        assert_eq!(found, dir.path());
    }
}

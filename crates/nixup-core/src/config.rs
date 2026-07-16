//! Load and represent `nixup.toml` configuration.

use std::{
    fs,
    path::{
        Path,
        PathBuf,
    },
};

use serde::Deserialize;

use crate::error::{
    CoreError,
    CoreResult,
};

/// Maximum `schema_version` this binary understands.
pub const SUPPORTED_SCHEMA_VERSION: u32 = 1;

/// Top-level nixup configuration.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct NixupConfig {
    /// Schema version for future migrations.
    #[serde(default = "default_schema_version")]
    pub schema_version: u32,
    /// Shared defaults (dotfiles, etc.).
    #[serde(default)]
    pub defaults:       Defaults,
    /// Configured devices / flake hosts.
    #[serde(default)]
    pub hosts:          Vec<HostEntry>,
    /// Smoke-test tool lists.
    #[serde(default)]
    pub smoke:          SmokeConfig,
}

fn default_schema_version() -> u32 {
    1
}

/// Defaults used by stow / clone helpers.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Default)]
pub struct Defaults {
    /// Git remote for cloning dotfiles.
    #[serde(default)]
    pub dotfiles_url:  Option<String>,
    /// Local path for stow root.
    #[serde(default)]
    pub dotfiles_path: Option<String>,
}

/// One machine / flake attribute mapping.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct HostEntry {
    /// Stable id used with `--host` (also default `hosts/<id>/` directory name).
    pub id:              String,
    /// Hostnames that auto-select this entry.
    #[serde(default)]
    pub match_hostnames: Vec<String>,
    /// `darwin` or `linux`.
    pub os:              HostOs,
    /// Flake attribute for switch (e.g. `kaan-macmini` or `legolas@linux`).
    pub flake_attr:      String,
    /// Explicit apply backend; default derived from `os`.
    #[serde(default)]
    pub apply:           Option<ApplyKind>,
    /// Nixpkgs system (default: `aarch64-darwin` / `x86_64-linux`).
    #[serde(default)]
    pub system:          Option<String>,
    /// Unix username for home-manager / darwin user (default: `legolas`).
    #[serde(default)]
    pub user:            Option<String>,
}

impl HostEntry {
    /// Resolve apply kind: explicit field, else darwin → Darwin, linux → `HomeManager`.
    #[must_use]
    pub fn apply_kind(&self) -> ApplyKind {
        self.apply.unwrap_or(match self.os {
            HostOs::Darwin => ApplyKind::Darwin,
            HostOs::Linux => ApplyKind::HomeManager,
        })
    }
}

/// Operating system class for host matching.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum HostOs {
    /// macOS / nix-darwin.
    Darwin,
    /// Linux / home-manager.
    Linux,
}

impl HostOs {
    /// Parse from runtime kernel name (`Darwin` / `Linux`).
    #[must_use]
    pub fn from_kernel_name(name: &str) -> Option<Self> {
        match name {
            "Darwin" => Some(Self::Darwin),
            "Linux" => Some(Self::Linux),
            _ => None,
        }
    }

    /// Label for errors and status.
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Darwin => "darwin",
            Self::Linux => "linux",
        }
    }
}

/// How to apply a flake host.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum ApplyKind {
    /// `nix run nix-darwin -- switch --flake`
    Darwin,
    /// `home-manager switch` or `nix run home-manager`
    HomeManager,
}

/// Smoke check configuration.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Default)]
pub struct SmokeConfig {
    /// Required command names (strict mode).
    #[serde(default)]
    pub required: Vec<String>,
    /// Optional command names.
    #[serde(default)]
    pub optional: Vec<String>,
    /// Darwin-only extras.
    #[serde(default)]
    pub darwin:   SmokeDarwinConfig,
}

/// Darwin-specific smoke extras.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Default)]
pub struct SmokeDarwinConfig {
    /// Optional CLI tools on macOS only.
    #[serde(default)]
    pub optional_commands: Vec<String>,
    /// App names under `/Applications/{name}.app`.
    #[serde(default)]
    pub optional_apps:     Vec<String>,
}

impl NixupConfig {
    /// Parse config from a TOML string (path used only for errors).
    pub fn parse_str(path: &Path, contents: &str) -> CoreResult<Self> {
        let config: Self = toml::from_str(contents).map_err(|source| CoreError::ConfigParse {
            path: path.to_path_buf(),
            source,
        })?;
        if config.schema_version > SUPPORTED_SCHEMA_VERSION {
            return Err(CoreError::UnsupportedSchema {
                found:     config.schema_version,
                supported: SUPPORTED_SCHEMA_VERSION,
            });
        }
        if config.hosts.is_empty() {
            return Err(CoreError::NoHosts);
        }
        Ok(config)
    }

    /// Read and parse a config file.
    pub fn load_file(path: &Path) -> CoreResult<Self> {
        let contents = fs::read_to_string(path).map_err(|source| CoreError::ConfigRead {
            path: path.to_path_buf(),
            source,
        })?;
        Self::parse_str(path, &contents)
    }

    /// Comma-separated host ids for error messages.
    #[must_use]
    pub fn known_host_ids(&self) -> String {
        self.hosts
            .iter()
            .map(|host| host.id.as_str())
            .collect::<Vec<_>>()
            .join(", ")
    }
}

/// Discover which config path to load.
///
/// Order: explicit path → `NIXUP_CONFIG` → user config → `<flake_root>/nixup.toml`.
pub fn discover_config_path(flake_root: &Path, explicit: Option<&Path>) -> CoreResult<PathBuf> {
    if let Some(path) = explicit {
        return Ok(path.to_path_buf());
    }
    if let Ok(from_env) = std::env::var("NIXUP_CONFIG") {
        let path = PathBuf::from(from_env);
        if path.is_file() {
            return Ok(path);
        }
    }
    if let Some(user_path) = user_config_path() {
        if user_path.is_file() {
            return Ok(user_path);
        }
    }
    let repo_path = flake_root.join("nixup.toml");
    if repo_path.is_file() {
        return Ok(repo_path);
    }
    Err(CoreError::ConfigNotFound)
}

fn user_config_path() -> Option<PathBuf> {
    if let Ok(xdg) = std::env::var("XDG_CONFIG_HOME") {
        let path = PathBuf::from(xdg).join("nixup").join("config.toml");
        return Some(path);
    }
    let home = std::env::var_os("HOME")?;
    Some(
        PathBuf::from(home)
            .join(".config")
            .join("nixup")
            .join("config.toml"),
    )
}

/// Load config using discovery rules.
pub fn load_config(
    flake_root: &Path,
    explicit: Option<&Path>,
) -> CoreResult<(PathBuf, NixupConfig)> {
    let path = discover_config_path(flake_root, explicit)?;
    let config = NixupConfig::load_file(&path)?;
    Ok((path, config))
}

#[cfg(test)]
mod tests {
    use tempfile::tempdir;

    use super::*;

    const MINIMAL: &str = r#"
schema_version = 1
[[hosts]]
id = "dev"
match_hostnames = ["devbox"]
os = "darwin"
flake_attr = "dev"
"#;

    #[test]
    fn parse_minimal_config() {
        let config = NixupConfig::parse_str(Path::new("test.toml"), MINIMAL).expect("parse");
        assert_eq!(config.hosts.len(), 1);
        let host = config.hosts.first().expect("host");
        assert_eq!(host.id, "dev");
        assert_eq!(host.apply_kind(), ApplyKind::Darwin);
    }

    #[test]
    fn reject_empty_hosts() {
        let err = NixupConfig::parse_str(Path::new("x.toml"), "schema_version = 1\n")
            .expect_err("empty hosts");
        assert!(matches!(err, CoreError::NoHosts));
    }

    #[test]
    fn reject_future_schema() {
        let toml = "schema_version = 99\n[[hosts]]\nid=\"a\"\nos=\"linux\"\nflake_attr=\"a\"\n";
        let err = NixupConfig::parse_str(Path::new("x.toml"), toml).expect_err("schema");
        assert!(matches!(
            err,
            CoreError::UnsupportedSchema { found: 99, .. }
        ));
    }

    #[test]
    fn load_file_roundtrip() {
        let dir = tempdir().expect("temp");
        let path = dir.path().join("nixup.toml");
        fs::write(&path, MINIMAL).expect("write");
        let config = NixupConfig::load_file(&path).expect("load");
        assert_eq!(config.hosts.first().expect("host").flake_attr, "dev");
    }

    #[test]
    fn discover_prefers_repo_nixup_toml() {
        let dir = tempdir().expect("temp");
        let flake_root = dir.path();
        fs::write(flake_root.join("nixup.toml"), MINIMAL).expect("write");
        let found = discover_config_path(flake_root, None).expect("discover");
        assert_eq!(found, flake_root.join("nixup.toml"));
    }
}

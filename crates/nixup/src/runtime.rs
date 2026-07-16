//! Shared context loading for commands.

use std::{
    path::PathBuf,
    process::Command,
};

use anyhow::{
    Context,
    Result,
    bail,
};
use nixup_core::{
    HostEntry,
    HostOs,
    NixupConfig,
    RuntimeIdentity,
    load_config,
    resolve_flake_root,
    resolve_host,
};

/// Loaded paths + config for a command invocation.
pub struct AppContext {
    /// Directory containing flake.nix.
    pub flake_root:  PathBuf,
    /// Path of the loaded config file.
    pub config_path: PathBuf,
    /// Parsed config.
    pub config:      NixupConfig,
    /// Detected runtime identity.
    pub identity:    RuntimeIdentity,
}

/// Build context from global CLI flags.
pub fn load_context(
    flake: Option<&std::path::Path>,
    config: Option<&std::path::Path>,
) -> Result<AppContext> {
    let flake_root = resolve_flake_root(flake).context("resolve flake root")?;
    let (config_path, config) = load_config(&flake_root, config).context("load nixup config")?;
    let identity = detect_identity()?;
    Ok(AppContext {
        flake_root,
        config_path,
        config,
        identity,
    })
}

/// Detect OS and hostname for host resolution.
pub fn detect_identity() -> Result<RuntimeIdentity> {
    let kernel = uname_kernel()?;
    let os = HostOs::from_kernel_name(&kernel)
        .with_context(|| format!("unsupported kernel: {kernel}"))?;
    let hostname = detect_hostname(os);
    Ok(RuntimeIdentity { os, hostname })
}

fn uname_kernel() -> Result<String> {
    let output = Command::new("uname")
        .arg("-s")
        .output()
        .context("run uname -s")?;
    if !output.status.success() {
        bail!("uname -s failed");
    }
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_owned())
}

fn detect_hostname(os: HostOs) -> Option<String> {
    if os == HostOs::Darwin {
        if let Ok(output) = Command::new("scutil")
            .arg("--get")
            .arg("LocalHostName")
            .output()
        {
            if output.status.success() {
                let name = String::from_utf8_lossy(&output.stdout).trim().to_owned();
                if !name.is_empty() {
                    return Some(name);
                }
            }
        }
    }
    if let Ok(output) = Command::new("hostname").arg("-s").output() {
        if output.status.success() {
            let name = String::from_utf8_lossy(&output.stdout).trim().to_owned();
            if !name.is_empty() {
                return Some(name);
            }
        }
    }
    None
}

/// Resolve host entry from context + optional `--host`.
pub fn host_for<'a>(ctx: &'a AppContext, host_flag: Option<&str>) -> Result<&'a HostEntry> {
    resolve_host(&ctx.config, &ctx.identity, host_flag).map_err(Into::into)
}

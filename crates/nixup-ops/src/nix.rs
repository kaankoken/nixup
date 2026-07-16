//! Nix presence, version, apply, and flake update.

use std::path::Path;

use nixup_core::{
    ApplyKind,
    HostEntry,
};

use crate::{
    error::{
        OpsError,
        OpsResult,
    },
    process::{
        command_exists,
        find_bin,
        run_output,
        run_status,
    },
};

/// Determinate Systems installer pipeline (curl | sh).
pub const DETERMINATE_INSTALL_URL: &str = "https://install.determinate.systems/nix";

/// Whether `nix` is on PATH.
#[must_use]
pub fn nix_available() -> bool {
    command_exists("nix")
}

/// `nix --version` first line, if available.
pub fn nix_version() -> OpsResult<String> {
    find_bin("nix")?;
    let output = run_output("nix", &["--version"], None)?;
    let text = String::from_utf8_lossy(&output.stdout);
    Ok(text.lines().next().unwrap_or("nix").trim().to_owned())
}

/// Install Nix via Determinate Systems installer (requires network + often sudo).
pub fn install_nix_determinate() -> OpsResult<()> {
    // curl --proto '=https' --tlsv1.2 -sSf -L URL | sh -s -- install
    let status = std::process::Command::new("sh")
        .arg("-c")
        .arg(format!(
            "curl --proto '=https' --tlsv1.2 -sSf -L {DETERMINATE_INSTALL_URL} | sh -s -- install"
        ))
        .status()
        .map_err(|source| OpsError::Io {
            context: "run Determinate installer".into(),
            source,
        })?;
    if status.success() {
        Ok(())
    } else {
        Err(OpsError::CommandFailed {
            command: "determinate-nix-installer".into(),
            status:  status.code().unwrap_or(-1),
            stderr:  "installer exited non-zero".into(),
        })
    }
}

/// Apply flake for the given host entry.
pub fn apply_host(flake_root: &Path, host: &HostEntry) -> OpsResult<()> {
    find_bin("nix")?;
    let flake_ref = format!(".#{}", host.flake_attr);
    match host.apply_kind() {
        ApplyKind::Darwin => run_status(
            "nix",
            &["run", "nix-darwin", "--", "switch", "--flake", &flake_ref],
            Some(flake_root),
        ),
        ApplyKind::HomeManager => {
            if command_exists("home-manager") {
                run_status(
                    "home-manager",
                    &["switch", "--flake", &flake_ref],
                    Some(flake_root),
                )
            } else {
                run_status(
                    "nix",
                    &[
                        "run",
                        "home-manager/master",
                        "--",
                        "switch",
                        "--flake",
                        &flake_ref,
                    ],
                    Some(flake_root),
                )
            }
        }
    }
}

/// Run `nix flake update` in the flake root.
pub fn flake_update(flake_root: &Path) -> OpsResult<()> {
    find_bin("nix")?;
    run_status("nix", &["flake", "update"], Some(flake_root))
}

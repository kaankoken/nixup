//! Nix presence, version, apply, and flake update.

use std::{
    fs,
    path::Path,
};

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

/// Personal `hosts/inventory.nix` + host dirs are gitignored so pure flake eval
/// cannot see them. Force-stage them for the duration of apply, then unstage.
///
/// Returns relative paths that were staged (empty if nothing to do).
fn stage_personal_hosts_for_flake(flake_root: &Path) -> OpsResult<Vec<String>> {
    let inventory = flake_root.join("hosts").join("inventory.nix");
    if !inventory.is_file() {
        return Ok(Vec::new());
    }
    // Non-git trees already expose all files to path: flakes.
    if !flake_root.join(".git").exists() {
        return Ok(Vec::new());
    }
    find_bin("git")?;

    let mut paths = vec!["hosts/inventory.nix".to_owned()];
    let hosts_dir = flake_root.join("hosts");
    let entries = fs::read_dir(&hosts_dir).map_err(|source| OpsError::Io {
        context: format!("read {}", hosts_dir.display()),
        source,
    })?;
    for entry in entries {
        let entry = entry.map_err(|source| OpsError::Io {
            context: format!("read entry in {}", hosts_dir.display()),
            source,
        })?;
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if name == "inventory.nix" ||
            name == "inventory.example.nix" ||
            name == "my-mac" ||
            name == "my-linux"
        {
            continue;
        }
        if entry.path().is_dir() {
            paths.push(format!("hosts/{name}"));
        }
    }

    let mut args: Vec<&str> = vec!["add", "-f", "--"];
    let owned: Vec<&str> = paths.iter().map(String::as_str).collect();
    args.extend(owned);
    run_status("git", &args, Some(flake_root))?;
    Ok(paths)
}

fn unstage_paths(flake_root: &Path, paths: &[String]) {
    if paths.is_empty() {
        return;
    }
    if !command_exists("git") {
        return;
    }
    let mut args: Vec<&str> = vec!["restore", "--staged", "--"];
    let owned: Vec<&str> = paths.iter().map(String::as_str).collect();
    args.extend(owned);
    // Best-effort: leave staged on failure so the user can re-run apply.
    drop(run_status("git", &args, Some(flake_root)));
}

/// Apply flake for the given host entry.
///
/// Darwin uses `sudo -H` because nix-darwin requires root for system activation.
/// The absolute `nix` path is passed so sudo's `secure_path` still finds it.
///
/// Personal (gitignored) host inventory is force-staged for pure flake eval,
/// then unstaged after the switch attempt.
pub fn apply_host(flake_root: &Path, host: &HostEntry) -> OpsResult<()> {
    let nix = find_bin("nix")?;
    let nix_bin = nix.to_str().ok_or_else(|| OpsError::Io {
        context: "nix path is not valid UTF-8".into(),
        source:  std::io::Error::new(std::io::ErrorKind::InvalidData, "non-utf8 path"),
    })?;
    let flake_ref = format!(".#{}", host.flake_attr);

    let staged = stage_personal_hosts_for_flake(flake_root)?;
    let result = match host.apply_kind() {
        ApplyKind::Darwin => run_status(
            "sudo",
            &[
                "-H",
                nix_bin,
                "run",
                "nix-darwin",
                "--",
                "switch",
                "--flake",
                &flake_ref,
            ],
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
                    nix_bin,
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
    };
    // Always try to unstage personal hosts so `git status` stays clean.
    unstage_paths(flake_root, &staged);
    result
}

/// Run `nix flake update` in the flake root.
pub fn flake_update(flake_root: &Path) -> OpsResult<()> {
    find_bin("nix")?;
    run_status("nix", &["flake", "update"], Some(flake_root))
}

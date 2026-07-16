//! Subcommand handlers.

use std::process::ExitCode;

use anyhow::{
    Context,
    Result,
    bail,
};
use nixup_core::sync_hosts;
use nixup_ops::{
    OpsError,
    apply_host,
    clone_dotfiles,
    expand_tilde,
    flake_update,
    install_nix_determinate,
    nix_available,
    nix_version,
    stow_dotfiles,
};
use nixup_smoke::run_smoke;

use crate::{
    output::Console,
    runtime::{
        AppContext,
        detect_identity,
        host_for,
        load_context,
    },
};

/// Ensure Nix is present, optionally installing with confirmation.
fn ensure_nix(console: &Console) -> Result<()> {
    if nix_available() {
        if let Ok(version) = nix_version() {
            console.info(&format!("Nix OK: {version}"));
        } else {
            console.info("Nix OK");
        }
        return Ok(());
    }
    console.warn("Nix not found on PATH.");
    if !console.confirm("Install Nix via Determinate Systems installer?") {
        return Err(OpsError::Aborted("Nix install declined".into()).into());
    }
    console.info("Running Determinate installer…");
    install_nix_determinate().context("install Nix")?;
    console.warn(
        "Nix install finished. Open a new shell (or source the nix profile), then re-run nixup.",
    );
    Ok(())
}

/// `nixup bootstrap`
pub fn cmd_bootstrap(
    console: &Console,
    flake: Option<&std::path::Path>,
    config: Option<&std::path::Path>,
    host: Option<&str>,
    skip_smoke: bool,
) -> Result<ExitCode> {
    ensure_nix(console)?;
    if !nix_available() {
        return Ok(ExitCode::from(3));
    }

    let ctx = load_context(flake, config)?;
    console.info(&format!("flake: {}", ctx.flake_root.display()));
    console.info(&format!("config: {}", ctx.config_path.display()));

    let host_entry = host_for(&ctx, host)?;
    console.info(&format!(
        "host: {} → flake attr {}",
        host_entry.id, host_entry.flake_attr
    ));

    if !console.confirm(&format!("Apply flake .#{}?", host_entry.flake_attr)) {
        bail!("apply declined");
    }

    apply_host(&ctx.flake_root, host_entry).context("apply flake")?;
    console.info("Apply finished.");

    if !skip_smoke {
        let report = run_smoke(&ctx.config.smoke, ctx.identity.os);
        console.print_smoke(&report);
    }

    remind_dotfiles(console, &ctx);
    Ok(ExitCode::SUCCESS)
}

/// `nixup apply` / `switch`
pub fn cmd_apply(
    console: &Console,
    flake: Option<&std::path::Path>,
    config: Option<&std::path::Path>,
    host: Option<&str>,
) -> Result<ExitCode> {
    // Resolve host before the nix gate so unknown-host exits 4 even when nix is missing.
    let ctx = load_context(flake, config)?;
    let host_entry = host_for(&ctx, host)?;
    if !nix_available() {
        console.warn("Nix not found. Run `nixup install-nix` or `nixup bootstrap`.");
        return Ok(ExitCode::from(3));
    }
    if !console.confirm(&format!("Apply flake .#{}?", host_entry.flake_attr)) {
        bail!("apply declined");
    }
    apply_host(&ctx.flake_root, host_entry).context("apply flake")?;
    console.info("Apply finished.");
    Ok(ExitCode::SUCCESS)
}

/// `nixup smoke`
pub fn cmd_smoke(
    console: &Console,
    flake: Option<&std::path::Path>,
    config: Option<&std::path::Path>,
    strict: bool,
) -> Result<ExitCode> {
    let ctx = load_context(flake, config)?;
    let report = run_smoke(&ctx.config.smoke, ctx.identity.os);
    console.print_smoke(&report);
    if strict && !report.required_ok() {
        return Ok(ExitCode::from(2));
    }
    Ok(ExitCode::SUCCESS)
}

/// `nixup doctor`
#[allow(clippy::unnecessary_wraps)]
pub fn cmd_doctor(
    console: &Console,
    flake: Option<&std::path::Path>,
    config: Option<&std::path::Path>,
) -> Result<ExitCode> {
    let mut issues = 0u32;

    match detect_identity() {
        Ok(identity) => {
            console.info(&format!(
                "OS: {}  hostname: {}",
                identity.os.as_str(),
                identity.hostname.as_deref().unwrap_or("(unknown)")
            ));
        }
        Err(err) => {
            console.warn(&format!("identity: {err}"));
            issues += 1;
        }
    }

    if nix_available() {
        match nix_version() {
            Ok(v) => console.info(&format!("nix: {v}")),
            Err(err) => console.warn(&format!("nix present but version failed: {err}")),
        }
    } else {
        console.warn("nix: MISSING");
        issues += 1;
    }

    match load_context(flake, config) {
        Ok(ctx) => {
            console.info(&format!("flake root: {}", ctx.flake_root.display()));
            console.info(&format!("config: {}", ctx.config_path.display()));
            match host_for(&ctx, None) {
                Ok(host) => {
                    console.info(&format!("resolved host: {} ({})", host.id, host.flake_attr));
                }
                Err(err) => {
                    console.warn(&format!("host resolve: {err}"));
                    issues += 1;
                }
            }
            let report = run_smoke(&ctx.config.smoke, ctx.identity.os);
            let missing_req = report.checks.iter().filter(|c| c.required && !c.ok).count();
            console.info(&format!(
                "smoke required missing: {missing_req}/{}",
                report.checks.iter().filter(|c| c.required).count()
            ));
        }
        Err(err) => {
            console.warn(&format!("context: {err}"));
            issues += 1;
        }
    }

    if issues == 0 {
        console.info("doctor: OK");
        Ok(ExitCode::SUCCESS)
    } else {
        console.warn(&format!("doctor: {issues} issue(s)"));
        Ok(ExitCode::from(1))
    }
}

/// `nixup update`
pub fn cmd_update(
    console: &Console,
    flake: Option<&std::path::Path>,
    config: Option<&std::path::Path>,
) -> Result<ExitCode> {
    if !nix_available() {
        console.warn("Nix not found.");
        return Ok(ExitCode::from(3));
    }
    let ctx = load_context(flake, config)?;
    if !console.confirm("Run `nix flake update`?") {
        bail!("update declined");
    }
    flake_update(&ctx.flake_root).context("flake update")?;
    console.info("flake.lock updated.");
    console.info(&format!(
        "Suggested commit:\n  git -C {} add flake.lock && git -C {} commit -m \"chore: update flake.lock\"",
        ctx.flake_root.display(),
        ctx.flake_root.display()
    ));
    Ok(ExitCode::SUCCESS)
}

/// `nixup hosts` / `nixup hosts list`
pub fn cmd_hosts_list(
    console: &Console,
    flake: Option<&std::path::Path>,
    config: Option<&std::path::Path>,
) -> Result<ExitCode> {
    let ctx = load_context(flake, config)?;
    let resolved = host_for(&ctx, None).ok();
    console.info("=== configured hosts (from nixup.toml) ===");
    for host in &ctx.config.hosts {
        let marker = if resolved.is_some_and(|r| r.id == host.id) {
            " *"
        } else {
            ""
        };
        let dir = ctx.flake_root.join("hosts").join(&host.id);
        let on_disk = if dir.join("default.nix").is_file() {
            "ok"
        } else {
            "MISSING — run: nixup hosts sync"
        };
        console.info(&format!(
            "{id}{marker}  os={}  attr={}  match={:?}  hosts/{} [{on_disk}]",
            host.os.as_str(),
            host.flake_attr,
            host.match_hostnames,
            host.id,
            id = host.id,
        ));
    }
    if resolved.is_none() {
        console.warn("No host matched this machine (pass --host or fix match_hostnames).");
    }
    console.info("Create/update host modules: nixup hosts sync");
    Ok(ExitCode::SUCCESS)
}

/// `nixup hosts sync` — materialize host dirs + inventory from config.
pub fn cmd_hosts_sync(
    console: &Console,
    flake: Option<&std::path::Path>,
    config: Option<&std::path::Path>,
    force: bool,
) -> Result<ExitCode> {
    let ctx = load_context(flake, config)?;
    if !console.confirm(&format!(
        "Create/update host modules under {}/hosts from {}?",
        ctx.flake_root.display(),
        ctx.config_path.display()
    )) {
        bail!("hosts sync declined");
    }

    let report = sync_hosts(&ctx.flake_root, &ctx.config, force).context("hosts sync")?;
    for item in &report.hosts {
        let status = if item.created {
            "created"
        } else if item.skipped_existing {
            "exists (skipped)"
        } else {
            "updated"
        };
        console.info(&format!(
            "  [{status}] {} → {}",
            item.id,
            item.path.display()
        ));
    }
    if report.inventory_written {
        console.info(&format!(
            "Wrote inventory: {}",
            report.inventory_path.display()
        ));
        console.info(
            "Nix flakes only see tracked files: stage generated hosts for local pure eval; personal inventory/hosts stay gitignored (examples only are committed).",
        );
    }
    console
        .info("Re-run after editing nixup.toml. Personal config stays in (gitignored) nixup.toml.");
    Ok(ExitCode::SUCCESS)
}

/// `nixup status`
pub fn cmd_status(
    console: &Console,
    flake: Option<&std::path::Path>,
    config: Option<&std::path::Path>,
) -> Result<ExitCode> {
    let ctx = load_context(flake, config)?;
    console.info(&format!("flake: {}", ctx.flake_root.display()));
    console.info(&format!("config: {}", ctx.config_path.display()));
    console.info(&format!(
        "os: {}  hostname: {}",
        ctx.identity.os.as_str(),
        ctx.identity.hostname.as_deref().unwrap_or("(unknown)")
    ));
    if nix_available() {
        if let Ok(v) = nix_version() {
            console.info(&format!("nix: {v}"));
        }
    } else {
        console.info("nix: MISSING");
    }
    match host_for(&ctx, None) {
        Ok(h) => console.info(&format!("host: {} → {}", h.id, h.flake_attr)),
        Err(err) => console.warn(&format!("host: {err}")),
    }
    Ok(ExitCode::SUCCESS)
}

/// `nixup stow`
pub fn cmd_stow(
    console: &Console,
    flake: Option<&std::path::Path>,
    config: Option<&std::path::Path>,
    clone: bool,
) -> Result<ExitCode> {
    let ctx = load_context(flake, config)?;
    let path_str = ctx
        .config
        .defaults
        .dotfiles_path
        .as_deref()
        .unwrap_or("~/.dotfiles");
    let dest = expand_tilde(path_str);

    if !dest.exists() {
        if clone {
            let url = ctx
                .config
                .defaults
                .dotfiles_url
                .as_deref()
                .context("defaults.dotfiles_url is required for --clone")?;
            if !console.confirm(&format!("Clone {url} → {}?", dest.display())) {
                bail!("clone declined");
            }
            clone_dotfiles(url, &dest).context("clone dotfiles")?;
        } else {
            console.warn(&format!(
                "Dotfiles missing at {}. Clone with:\n  nixup stow --clone",
                dest.display()
            ));
            return Ok(ExitCode::from(1));
        }
    }

    if !console.confirm(&format!("Run `stow .` in {}?", dest.display())) {
        bail!("stow declined");
    }
    stow_dotfiles(&dest).context("stow")?;
    console.info("stow finished.");
    Ok(ExitCode::SUCCESS)
}

/// `nixup install-nix`
pub fn cmd_install_nix(console: &Console) -> Result<ExitCode> {
    if nix_available() {
        console.info("Nix already on PATH.");
        return Ok(ExitCode::SUCCESS);
    }
    if !console.confirm("Install Nix via Determinate Systems installer?") {
        return Err(OpsError::Aborted("Nix install declined".into()).into());
    }
    install_nix_determinate().context("install Nix")?;
    console.warn("Re-open your shell so `nix` is on PATH, then continue.");
    Ok(ExitCode::SUCCESS)
}

fn remind_dotfiles(console: &Console, ctx: &AppContext) {
    let path_str = ctx
        .config
        .defaults
        .dotfiles_path
        .as_deref()
        .unwrap_or("~/.dotfiles");
    let dest = expand_tilde(path_str);
    if dest.exists() {
        console.info(&format!(
            "Dotfiles found at {}. Apply with: nixup stow",
            dest.display()
        ));
    } else {
        let url = ctx
            .config
            .defaults
            .dotfiles_url
            .as_deref()
            .unwrap_or("git@github.com:USER/dotfiles.git");
        console.info("Clone dotfiles next:");
        console.info(&format!("  nixup stow --clone   # uses {url}"));
    }
}

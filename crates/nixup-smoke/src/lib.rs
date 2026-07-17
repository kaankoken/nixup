//! Smoke checks driven by [`nixup_core::SmokeConfig`].

#![forbid(unsafe_code)]

use std::path::PathBuf;

use nixup_core::{
    HostOs,
    SmokeConfig,
};
use which::which;

/// Result of a single tool / app probe.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CheckResult {
    /// Display name (command or `app:Name`).
    pub name:     String,
    /// Whether the tool was found.
    pub ok:       bool,
    /// Whether missing fails `--strict`.
    pub required: bool,
    /// Path or `MISSING`.
    pub detail:   String,
}

/// Full smoke report.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SmokeReport {
    /// Individual checks in order.
    pub checks: Vec<CheckResult>,
}

impl SmokeReport {
    /// True if every required check passed.
    #[must_use]
    pub fn required_ok(&self) -> bool {
        self.checks
            .iter()
            .filter(|check| check.required)
            .all(|check| check.ok)
    }
}

/// Run smoke checks for the given config and OS.
#[must_use]
pub fn run_smoke(config: &SmokeConfig, os: HostOs) -> SmokeReport {
    let mut checks = Vec::new();

    for name in &config.required {
        checks.push(check_command(name, true));
    }
    for name in &config.optional {
        checks.push(check_command(name, false));
    }

    if os == HostOs::Darwin {
        for name in &config.darwin.required_commands {
            checks.push(check_command(name, true));
        }
        for name in &config.darwin.optional_commands {
            checks.push(check_command(name, false));
        }
        for app in &config.darwin.optional_apps {
            checks.push(check_app(app));
        }
    }

    SmokeReport { checks }
}

fn check_command(name: &str, required: bool) -> CheckResult {
    match which(name) {
        Ok(path) => CheckResult {
            name: name.to_owned(),
            ok: true,
            required,
            detail: path.display().to_string(),
        },
        Err(_) => CheckResult {
            name: name.to_owned(),
            ok: false,
            required,
            detail: "MISSING".into(),
        },
    }
}

fn check_app(app_name: &str) -> CheckResult {
    let bundle = format!("{app_name}.app");
    let mut candidates = vec![
        PathBuf::from("/Applications").join(&bundle),
        PathBuf::from("/Applications/Nix Apps").join(&bundle),
    ];
    if let Ok(home) = std::env::var("HOME") {
        let home = PathBuf::from(home);
        candidates.push(home.join("Applications").join(&bundle));
        candidates.push(home.join("Applications/Home Manager Apps").join(&bundle));
    }
    if let Some(path) = candidates.into_iter().find(|p| p.is_dir()) {
        CheckResult {
            name:     format!("app:{app_name}"),
            ok:       true,
            required: false,
            detail:   path.display().to_string(),
        }
    } else {
        CheckResult {
            name:     format!("app:{app_name}"),
            ok:       false,
            required: false,
            detail:   "MISSING".into(),
        }
    }
}

#[cfg(test)]
mod tests {
    use nixup_core::SmokeDarwinConfig;

    use super::*;

    #[test]
    fn required_ok_false_when_missing() {
        let config = SmokeConfig {
            required: vec!["this-binary-should-not-exist-nixup-xyz".into()],
            optional: vec![],
            darwin:   SmokeDarwinConfig::default(),
        };
        let report = run_smoke(&config, HostOs::Linux);
        assert!(!report.required_ok());
        assert_eq!(report.checks.len(), 1);
        assert!(!report.checks.first().expect("check").ok);
    }

    #[test]
    fn optional_missing_still_required_ok() {
        let config = SmokeConfig {
            required: vec![],
            optional: vec!["this-binary-should-not-exist-nixup-xyz".into()],
            darwin:   SmokeDarwinConfig::default(),
        };
        let report = run_smoke(&config, HostOs::Linux);
        assert!(report.required_ok());
    }

    #[test]
    fn darwin_required_commands_fail_strict() {
        let config = SmokeConfig {
            required: vec![],
            optional: vec![],
            darwin:   SmokeDarwinConfig {
                required_commands: vec!["this-binary-should-not-exist-nixup-xyz".into()],
                optional_commands: vec![],
                optional_apps:     vec![],
            },
        };
        let report = run_smoke(&config, HostOs::Darwin);
        assert!(!report.required_ok());
        assert!(report.checks.iter().any(|c| c.required && !c.ok));
    }

    #[test]
    fn darwin_required_ignored_on_linux() {
        let config = SmokeConfig {
            required: vec![],
            optional: vec![],
            darwin:   SmokeDarwinConfig {
                required_commands: vec!["this-binary-should-not-exist-nixup-xyz".into()],
                optional_commands: vec![],
                optional_apps:     vec![],
            },
        };
        let report = run_smoke(&config, HostOs::Linux);
        assert!(report.required_ok());
        assert!(report.checks.is_empty());
    }
}

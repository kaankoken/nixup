//! The only module allowed to print or prompt.
#![allow(clippy::print_stdout, clippy::print_stderr)]

use std::io::{
    self,
    Write,
};

use nixup_smoke::{
    CheckResult,
    SmokeReport,
};

/// User-facing console adapter.
pub struct Console {
    /// When true, confirmations always return true.
    pub yes: bool,
}

impl Console {
    /// Construct with global `--yes`.
    #[must_use]
    pub const fn new(yes: bool) -> Self {
        Self { yes }
    }

    /// Informational line on stdout.
    #[allow(clippy::unused_self)]
    pub fn info(&self, message: &str) {
        println!("{message}");
    }

    /// Warning / diagnostic on stderr.
    #[allow(clippy::unused_self)]
    pub fn warn(&self, message: &str) {
        eprintln!("{message}");
    }

    /// Confirm with `[y/N]`. Returns true if `--yes` or user types y/yes.
    pub fn confirm(&self, prompt: &str) -> bool {
        if self.yes {
            self.info(&format!("{prompt} [yes]"));
            return true;
        }
        print!("{prompt} [y/N] ");
        let _ = io::stdout().flush();
        let mut line = String::new();
        if io::stdin().read_line(&mut line).is_err() {
            return false;
        }
        matches!(line.trim().to_ascii_lowercase().as_str(), "y" | "yes")
    }

    /// Print smoke report table.
    pub fn print_smoke(&self, report: &SmokeReport) {
        self.info("=== smoke results ===");
        for row in &report.checks {
            self.print_check(row);
        }
    }

    fn print_check(&self, row: &CheckResult) {
        let mark = if row.ok { "OK  " } else { "FAIL" };
        let req = if row.required { "req" } else { "opt" };
        self.info(&format!("{mark} [{req}] {} — {}", row.name, row.detail));
    }
}

/// Map domain / ops failures to process exit codes.
#[must_use]
pub fn exit_code_for(err: &anyhow::Error) -> i32 {
    use nixup_core::CoreError;
    use nixup_ops::OpsError;

    if let Some(core) = err.downcast_ref::<CoreError>() {
        return match core {
            CoreError::HostUnresolved { .. } | CoreError::UnknownHost { .. } => 4,
            _ => 1,
        };
    }
    if let Some(ops) = err.downcast_ref::<OpsError>() {
        return match ops {
            OpsError::Aborted(_) => 3,
            OpsError::CommandNotFound(name) if name == "nix" => 3,
            _ => 1,
        };
    }
    1
}

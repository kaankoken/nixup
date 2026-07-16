//! User-facing console (stdout/stderr via `Write`, not `print!` macros).

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
    pub yes:     bool,
    /// When true, emit extra diagnostics on stderr.
    pub verbose: bool,
}

impl Console {
    /// Construct from global flags.
    #[must_use]
    pub const fn new(yes: bool, verbose: bool) -> Self {
        Self { yes, verbose }
    }

    /// Informational line on stdout.
    pub fn info(&self, message: &str) {
        self.write_line(&mut io::stdout(), message);
    }

    /// Warning / diagnostic on stderr.
    pub fn warn(&self, message: &str) {
        self.write_line(&mut io::stderr(), message);
    }

    /// Extra diagnostics when `--verbose` is set.
    pub fn debug(&self, message: &str) {
        if self.verbose {
            self.write_line(&mut io::stderr(), &format!("verbose: {message}"));
        }
    }

    fn write_line(&self, writer: &mut dyn Write, message: &str) {
        drop(writeln!(writer, "{message}"));
        if self.verbose {
            drop(writer.flush());
        }
    }

    /// Confirm with `[y/N]`. Returns true if `--yes` or user types y/yes.
    pub fn confirm(&self, prompt: &str) -> bool {
        if self.yes {
            self.info(&format!("{prompt} [yes]"));
            return true;
        }
        drop(write!(io::stdout(), "{prompt} [y/N] "));
        drop(io::stdout().flush());
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

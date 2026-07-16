//! Thin wrappers around `std::process::Command`.

use std::{
    path::Path,
    process::{
        Command,
        Output,
    },
};

use which::which;

use crate::error::{
    OpsError,
    OpsResult,
};

/// Locate a binary on PATH.
pub fn find_bin(name: &str) -> OpsResult<std::path::PathBuf> {
    which(name).map_err(|_| OpsError::CommandNotFound(name.to_owned()))
}

/// Whether a command is present on PATH.
#[must_use]
pub fn command_exists(name: &str) -> bool {
    which(name).is_ok()
}

/// Run a command, inherit stdio, require success.
pub fn run_status(program: &str, args: &[&str], cwd: Option<&Path>) -> OpsResult<()> {
    let mut cmd = Command::new(program);
    cmd.args(args);
    if let Some(dir) = cwd {
        cmd.current_dir(dir);
    }
    let status = cmd.status().map_err(|source| OpsError::Io {
        context: format!("spawn {program}"),
        source,
    })?;
    if status.success() {
        Ok(())
    } else {
        Err(OpsError::CommandFailed {
            command: format!("{program} {}", args.join(" ")),
            status: status.code().unwrap_or(-1),
            stderr: String::new(),
        })
    }
}

/// Run a command and capture stdout/stderr.
pub fn run_output(program: &str, args: &[&str], cwd: Option<&Path>) -> OpsResult<Output> {
    let mut cmd = Command::new(program);
    cmd.args(args);
    if let Some(dir) = cwd {
        cmd.current_dir(dir);
    }
    let output = cmd.output().map_err(|source| OpsError::Io {
        context: format!("spawn {program}"),
        source,
    })?;
    if output.status.success() {
        Ok(output)
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let stderr = truncate(stderr.as_ref(), 2_000);
        Err(OpsError::CommandFailed {
            command: format!("{program} {}", args.join(" ")),
            status: output.status.code().unwrap_or(-1),
            stderr,
        })
    }
}

fn truncate(text: &str, max: usize) -> String {
    if text.chars().count() <= max {
        text.to_owned()
    } else {
        let truncated: String = text.chars().take(max).collect();
        format!("{truncated}…")
    }
}

//! Basic CLI smoke tests without requiring Nix.

use assert_cmd::Command;
use predicates::prelude::*;

#[test]
fn help_succeeds() {
    let mut cmd = Command::cargo_bin("nixup").expect("bin");
    cmd.arg("--help")
        .assert()
        .success()
        .stdout(predicate::str::contains("bootstrap"))
        .stdout(predicate::str::contains("smoke"));
}

#[test]
fn version_succeeds() {
    let mut cmd = Command::cargo_bin("nixup").expect("bin");
    cmd.arg("--version")
        .assert()
        .success()
        .stdout(predicate::str::contains("nixup"));
}

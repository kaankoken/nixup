// crates/nixup/tests/cli_config.rs
use assert_cmd::Command;
use predicates::prelude::*;
use std::fs;
use tempfile::tempdir;

#[allow(clippy::unwrap_used, clippy::expect_used)]
fn write_mini_flake(dir: &std::path::Path) {
    fs::write(dir.join("flake.nix"), "{ outputs = _: {}; }\n").expect("write flake.nix");
    fs::write(
        dir.join("nixup.toml"),
        r#"
schema_version = 1
[[hosts]]
id = "dev"
match_hostnames = ["devbox"]
os = "darwin"
flake_attr = "dev"
[[hosts]]
id = "linux"
match_hostnames = []
os = "linux"
flake_attr = "user@linux"
apply = "home-manager"
[smoke]
required = ["sh"]
optional = ["this-binary-must-not-exist-nixup-zzz"]
"#,
    )
    .expect("write nixup.toml");
}

#[test]
fn hosts_lists_config_and_exits_zero() {
    let dir = tempdir().unwrap();
    write_mini_flake(dir.path());
    let flake = dir.path().to_str().unwrap();
    let config = dir.path().join("nixup.toml");
    Command::cargo_bin("nixup")
        .unwrap()
        .args([
            "--flake",
            flake,
            "--config",
            config.to_str().unwrap(),
            "hosts",
        ])
        .assert()
        .success()
        .stdout(predicate::str::contains("dev"))
        .stdout(predicate::str::contains("linux"));
}

#[test]
fn apply_unknown_host_exits_four() {
    let dir = tempdir().unwrap();
    write_mini_flake(dir.path());
    let flake = dir.path().to_str().unwrap();
    let config = dir.path().join("nixup.toml");
    Command::cargo_bin("nixup")
        .unwrap()
        .args([
            "--flake",
            flake,
            "--config",
            config.to_str().unwrap(),
            "apply",
            "--host",
            "nope",
            "--yes",
        ])
        .assert()
        .failure()
        .code(4);
}

#[test]
fn smoke_strict_missing_required_exits_two() {
    let dir = tempdir().unwrap();
    write_mini_flake(dir.path());
    // required tool that does not exist
    fs::write(
        dir.path().join("nixup.toml"),
        r#"
schema_version = 1
[[hosts]]
id = "linux"
match_hostnames = []
os = "linux"
flake_attr = "u@linux"
[smoke]
required = ["this-binary-must-not-exist-nixup-required-zzz"]
"#,
    )
    .expect("write strict smoke nixup.toml");
    let flake = dir.path().to_str().unwrap();
    let config = dir.path().join("nixup.toml");
    Command::cargo_bin("nixup")
        .unwrap()
        .args([
            "--flake",
            flake,
            "--config",
            config.to_str().unwrap(),
            "smoke",
            "--strict",
        ])
        .assert()
        .failure()
        .code(2);
}

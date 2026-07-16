//! `nixup` binary entrypoint.

mod cli;
mod commands;
mod output;
mod runtime;

use std::process::ExitCode;

use clap::Parser;

use crate::{
    cli::{
        Cli,
        Command,
        HostsAction,
    },
    output::{
        Console,
        exit_code_for,
    },
};

fn main() -> ExitCode {
    let cli = Cli::parse();
    let console = Console::new(cli.yes, cli.verbose);
    let result = dispatch(&console, &cli);
    match result {
        Ok(code) => code,
        Err(err) => {
            console.warn(&format!("error: {err:#}"));
            ExitCode::from(u8::try_from(exit_code_for(&err)).unwrap_or(1))
        }
    }
}

fn dispatch(console: &Console, cli: &Cli) -> anyhow::Result<ExitCode> {
    let flake = cli.flake.as_deref();
    let config = cli.config.as_deref();
    match &cli.command {
        Command::Bootstrap { host, skip_smoke } => {
            commands::cmd_bootstrap(console, flake, config, host.as_deref(), *skip_smoke)
        }
        Command::Apply { host } | Command::Switch { host } => {
            commands::cmd_apply(console, flake, config, host.as_deref())
        }
        Command::Smoke { strict } => commands::cmd_smoke(console, flake, config, *strict),
        Command::Doctor => Ok(commands::cmd_doctor(console, flake, config)),
        Command::Update => commands::cmd_update(console, flake, config),
        Command::Hosts { action } => match action {
            None | Some(HostsAction::List) => commands::cmd_hosts_list(console, flake, config),
            Some(HostsAction::Sync { force }) => {
                commands::cmd_hosts_sync(console, flake, config, *force)
            }
        },
        Command::Status => commands::cmd_status(console, flake, config),
        Command::Stow { clone } => commands::cmd_stow(console, flake, config, *clone),
        Command::InstallNix => commands::cmd_install_nix(console),
    }
}

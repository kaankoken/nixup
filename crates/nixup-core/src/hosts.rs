//! Host resolution from config + runtime environment.

use crate::config::{
    HostEntry,
    HostOs,
    NixupConfig,
};
use crate::error::{
    CoreError,
    CoreResult,
};

/// Runtime facts used for host resolution.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuntimeIdentity {
    /// Detected OS class.
    pub os: HostOs,
    /// Hostname (`LocalHostName` / hostname), if known.
    pub hostname: Option<String>,
}

/// Resolve which configured host applies.
///
/// 1. Explicit `--host` id  
/// 2. Exact match against `match_hostnames`  
/// 3. Exactly one host with matching `os` and empty `match_hostnames`  
/// 4. Error
pub fn resolve_host<'a>(
    config: &'a NixupConfig,
    identity: &RuntimeIdentity,
    explicit_host_id: Option<&str>,
) -> CoreResult<&'a HostEntry> {
    let known = config.known_host_ids();

    if let Some(id) = explicit_host_id {
        return config
            .hosts
            .iter()
            .find(|host| host.id == id)
            .ok_or_else(|| CoreError::UnknownHost {
                id: id.to_owned(),
                known,
            });
    }

    if let Some(hostname) = identity.hostname.as_deref() {
        if let Some(host) = config.hosts.iter().find(|host| {
            host.match_hostnames
                .iter()
                .any(|candidate| candidate == hostname)
        }) {
            return Ok(host);
        }
    }

    let empty_match_for_os: Vec<&HostEntry> = config
        .hosts
        .iter()
        .filter(|host| host.os == identity.os && host.match_hostnames.is_empty())
        .collect();

    if empty_match_for_os.len() == 1 {
        return empty_match_for_os
            .into_iter()
            .next()
            .ok_or_else(|| CoreError::HostUnresolved {
                os: identity.os.as_str().to_owned(),
                hostname: identity.hostname.clone(),
                known: known.clone(),
            });
    }

    Err(CoreError::HostUnresolved {
        os: identity.os.as_str().to_owned(),
        hostname: identity.hostname.clone(),
        known,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::NixupConfig;
    use std::path::Path;

    fn sample_config() -> NixupConfig {
        let toml = r#"
schema_version = 1
[[hosts]]
id = "kaan-macmini"
match_hostnames = ["kaan-macmini"]
os = "darwin"
flake_attr = "kaan-macmini"
[[hosts]]
id = "kaanezgi"
match_hostnames = ["kaanezgi"]
os = "darwin"
flake_attr = "kaanezgi"
[[hosts]]
id = "linux"
match_hostnames = []
os = "linux"
flake_attr = "legolas@linux"
apply = "home-manager"
"#;
        NixupConfig::parse_str(Path::new("t.toml"), toml).expect("parse")
    }

    #[test]
    fn resolve_by_hostname() {
        let config = sample_config();
        let identity = RuntimeIdentity {
            os: HostOs::Darwin,
            hostname: Some("kaanezgi".into()),
        };
        let host = resolve_host(&config, &identity, None).expect("resolve");
        assert_eq!(host.id, "kaanezgi");
    }

    #[test]
    fn resolve_explicit_overrides_hostname() {
        let config = sample_config();
        let identity = RuntimeIdentity {
            os: HostOs::Darwin,
            hostname: Some("kaan-macmini".into()),
        };
        let host = resolve_host(&config, &identity, Some("kaanezgi")).expect("resolve");
        assert_eq!(host.id, "kaanezgi");
    }

    #[test]
    fn resolve_linux_empty_match() {
        let config = sample_config();
        let identity = RuntimeIdentity {
            os: HostOs::Linux,
            hostname: Some("randombox".into()),
        };
        let host = resolve_host(&config, &identity, None).expect("resolve");
        assert_eq!(host.flake_attr, "legolas@linux");
    }

    #[test]
    fn unknown_explicit_host() {
        let config = sample_config();
        let identity = RuntimeIdentity {
            os: HostOs::Darwin,
            hostname: None,
        };
        let err = resolve_host(&config, &identity, Some("nope")).expect_err("fail");
        assert!(matches!(err, CoreError::UnknownHost { .. }));
    }

    #[test]
    fn unresolved_darwin_unknown_hostname() {
        let config = sample_config();
        let identity = RuntimeIdentity {
            os: HostOs::Darwin,
            hostname: Some("someone-else".into()),
        };
        let err = resolve_host(&config, &identity, None).expect_err("fail");
        assert!(matches!(err, CoreError::HostUnresolved { .. }));
    }
}

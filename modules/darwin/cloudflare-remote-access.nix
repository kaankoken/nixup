{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.cloudflareRemoteAccess;
  configPath = "/etc/cloudflared/config.yml";
  stateDirectory = "/var/lib/cloudflared";

  sshIngress = ''
    - hostname: ${cfg.hostname}
      service: ssh://127.0.0.1:22
  '';

  httpIngress = lib.concatMapStrings (
    hostname: ''
      - hostname: ${hostname}
        service: ${cfg.httpServices.${hostname}}
    ''
  ) (builtins.attrNames cfg.httpServices);

  catchAllIngress = ''
    - service: http_status:404
  '';

  ingressBlock = sshIngress + httpIngress + catchAllIngress;
in
{
  # Import this feature module only from hosts that need remote access.
  options.services.cloudflareRemoteAccess = {
    tunnelId = lib.mkOption {
      type = lib.types.str;
      description = "Cloudflare Tunnel UUID for this host.";
    };

    hostname = lib.mkOption {
      type = lib.types.str;
      description = "Public hostname for SSH (typically behind Cloudflare Access).";
    };

    httpServices = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        "vault.kkoken.com" = "http://127.0.0.1:8000";
      };
      description = ''
        Extra public hostnames mapped to local HTTP origins for this tunnel.
        Rendered as ingress rules after the SSH hostname and before the 404 catch-all.
      '';
    };
  };

  config = {
    services.openssh.enable = true;

    # Note: modern cloudflared rejects `warp-routing.enabled` (removed from WarpRoutingConfig).
    # Private-network / WARP routing is controlled by tunnel routes in the Zero Trust dashboard.
    environment.etc."cloudflared/config.yml".text = ''
      tunnel: ${cfg.tunnelId}
      credentials-file: ${stateDirectory}/${cfg.tunnelId}.json

      ingress:
      ${ingressBlock}
    '';

    launchd.daemons.cloudflare-tunnel.serviceConfig = {
      ProgramArguments = [
        "${pkgs.cloudflared}/bin/cloudflared"
        "tunnel"
        "--no-autoupdate"
        "--config"
        configPath
        "run"
      ];
      WorkingDirectory = stateDirectory;
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Background";
      ThrottleInterval = 10;
      # Capture crash loops (permission may require rebuild to take effect on Darwin)
      StandardOutPath = "/var/log/cloudflared.log";
      StandardErrorPath = "/var/log/cloudflared.log";
    };
  };
}

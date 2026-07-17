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
      description = "Public hostname protected by Cloudflare Access.";
    };
  };

  config = {
    services.openssh.enable = true;

    environment.etc."cloudflared/config.yml".text = ''
      tunnel: ${cfg.tunnelId}
      credentials-file: ${stateDirectory}/${cfg.tunnelId}.json

      ingress:
        - hostname: ${cfg.hostname}
          service: ssh://127.0.0.1:22
        - service: http_status:404
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
    };
  };
}

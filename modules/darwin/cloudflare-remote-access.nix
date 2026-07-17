{
  hostName,
  lib,
  ...
}:
{
  config = lib.mkIf (hostName == "kaan-macmini") {
    # Enable Apple's socket-activated SSH server. Hardening is added only
    # after local key access and the Cloudflare route are proven.
    services.openssh.enable = true;
  };
}

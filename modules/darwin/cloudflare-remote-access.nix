{
  # Feature module: import only from the host that needs it
  # (e.g. hosts/kaan-macmini). Do not gate on hostName strings here.
  ...
}:
{
  # Enable Apple's socket-activated SSH server. Hardening is added only
  # after local key access and the Cloudflare route are proven.
  services.openssh.enable = true;
}

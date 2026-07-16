# Example inventory for third parties / CI fallback when hosts/inventory.nix is absent.
# Copy nixup.toml.example → nixup.toml, edit [[hosts]], then: nixup hosts sync
{
  darwin = {
    "my-mac" = {
      hostName = "my-mac";
      hostPath = ./my-mac;
      system = "aarch64-darwin";
      user = "you";
    };
  };
  linux = {
    "you@linux" = {
      hostName = "linux";
      hostPath = ./my-linux;
      system = "x86_64-linux";
      user = "you";
    };
  };
}

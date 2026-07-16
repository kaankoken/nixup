{ lib, ... }:
{
  # Example darwin host (see nixup.toml.example). Replace via: nixup hosts sync
  networking.hostName = lib.mkDefault "my-mac";
  networking.localHostName = lib.mkDefault "my-mac";
  networking.computerName = lib.mkDefault "my-mac";
}

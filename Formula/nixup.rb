# typed: false
# frozen_string_literal: true

class Nixup < Formula
  desc "Bootstrap, apply, and smoke-test multi-host Nix flakes"
  homepage "https://github.com/kaankoken/nix-setup"
  version "0.1.0"
  license "MIT"

  on_macos do
    depends_on arch: :arm64
    on_arm do
      url "https://github.com/kaankoken/nix-setup/releases/download/v0.1.0/nixup-aarch64-apple-darwin.tar.gz"
      sha256 "0000000000000000000000000000000000000000000000000000000000000000"
    end
  end

  on_linux do
    on_intel do
      url "https://github.com/kaankoken/nix-setup/releases/download/v0.1.0/nixup-x86_64-unknown-linux-musl.tar.gz"
      sha256 "0000000000000000000000000000000000000000000000000000000000000000"
    end
    on_arm do
      url "https://github.com/kaankoken/nix-setup/releases/download/v0.1.0/nixup-aarch64-unknown-linux-musl.tar.gz"
      sha256 "0000000000000000000000000000000000000000000000000000000000000000"
    end
  end

  def install
    bin.install "nixup"
  end

  def caveats
    <<~EOS
      Point nixup at a flake with nixup.toml (hosts + smoke lists):
        nixup --flake /path/to/flake status
        nixup bootstrap --yes
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/nixup --version")
  end
end

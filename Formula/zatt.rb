class Zatt < Formula
  desc "macOS CLI to control MacBook battery charging via SMC"
  homepage "https://github.com/maximbilan/zatt"
  url "https://github.com/maximbilan/zatt/releases/download/v0.1.3/zatt-macos-arm64.tar.gz"
  sha256 "a29575cb40a4b49629d188763bf38122ad2d0ba8dbc048c8bdf0194088a1b886"
  version "0.1.3"
  license "MIT"

  depends_on arch: :arm64
  depends_on macos: :ventura

  on_arm do
    def install
      bin.install "bin/zatt"
    end
  end

  test do
    system "#{bin}/zatt", "status"
  end
end

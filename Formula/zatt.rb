class Zatt < Formula
  desc "macOS CLI to control MacBook battery charging via SMC"
  homepage "https://github.com/maximbilan/zatt"
  url "https://github.com/maximbilan/zatt/releases/download/v0.1.0/zatt-macos-arm64.tar.gz"
  sha256 "5c7530a991976c03b73872264a617b39d6391ac8a218b40cd3ed6a56f7c9ce06"
  version "0.1.0"
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

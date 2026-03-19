class Zatt < Formula
  desc "macOS CLI to control MacBook battery charging via SMC"
  homepage "https://github.com/maximbilan/zatt"
  url "https://github.com/maximbilan/zatt/releases/download/v0.1.2/zatt-macos-arm64.tar.gz"
  sha256 "9f2c4e6b6c863d959b5ad5a65264409335afbc331c1b59efb2369b5e4e68e398"
  version "0.1.2"
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

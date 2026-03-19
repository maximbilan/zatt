# zatt

Minimal macOS CLI for controlling MacBook battery charging over the Apple SMC.

## Install

```bash
brew tap maximbilan/zatt
brew install zatt
```

## Usage

```bash
zatt status
sudo zatt disable
sudo zatt enable
sudo zatt limit 80
sudo zatt limit reset
```

## Build

```bash
zig build
zig build release
```

`zig build release` produces:

- `zig-out/bin/zatt`
- `zig-out/zatt-macos-arm64.tar.gz`

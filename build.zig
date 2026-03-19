const std = @import("std");

fn detectSdkRoot(b: *std.Build) ?[]const u8 {
    if (b.graph.env_map.get("SDKROOT")) |sdk_root| {
        return b.dupePath(sdk_root);
    }

    const candidates = [_][]const u8{
        "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk",
        "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk",
    };

    for (candidates) |candidate| {
        std.fs.accessAbsolute(candidate, .{}) catch continue;
        return b.dupePath(candidate);
    }

    return null;
}

fn addZattExecutable(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = "zatt",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    if (b.sysroot) |sdk_root| {
        exe.addFrameworkPath(.{ .cwd_relative = b.pathJoin(&.{ sdk_root, "System/Library/Frameworks" }) });
    }

    exe.linkFramework("IOKit");
    exe.linkFramework("CoreFoundation");

    return exe;
}

fn addBatteryTests(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const tests = b.addTest(.{
        .name = "battery-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/battery.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    if (b.sysroot) |sdk_root| {
        tests.addFrameworkPath(.{ .cwd_relative = b.pathJoin(&.{ sdk_root, "System/Library/Frameworks" }) });
    }

    tests.linkFramework("IOKit");
    tests.linkFramework("CoreFoundation");

    return tests;
}

pub fn build(b: *std.Build) void {
    b.sysroot = detectSdkRoot(b);

    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .aarch64,
            .os_tag = .macos,
        },
        .whitelist = &.{
            .{
                .cpu_arch = .aarch64,
                .os_tag = .macos,
            },
        },
    });

    const exe = addZattExecutable(b, target, optimize);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run zatt");
    run_step.dependOn(&run_cmd.step);

    const tests = addBatteryTests(b, target, optimize);
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    const release_target = b.resolveTargetQuery(.{
        .cpu_arch = .aarch64,
        .os_tag = .macos,
    });
    const release_exe = addZattExecutable(b, release_target, .ReleaseSafe);
    const install_release = b.addInstallArtifact(release_exe, .{});

    const package_dir = b.getInstallPath(.prefix, "zatt-macos-arm64");
    const package_bin_dir = b.pathJoin(&.{ package_dir, "bin" });
    const package_binary = b.pathJoin(&.{ package_bin_dir, "zatt" });
    const tarball = b.getInstallPath(.prefix, "zatt-macos-arm64.tar.gz");

    const mkdir_cmd = b.addSystemCommand(&.{ "mkdir", "-p", package_bin_dir });
    mkdir_cmd.step.dependOn(&install_release.step);

    const copy_cmd = b.addSystemCommand(&.{ "cp" });
    copy_cmd.addArg(b.getInstallPath(.bin, "zatt"));
    copy_cmd.addArg(package_binary);
    copy_cmd.step.dependOn(&mkdir_cmd.step);

    const tar_cmd = b.addSystemCommand(&.{ "tar", "-C", b.install_path, "-czf", tarball, "zatt-macos-arm64" });
    tar_cmd.step.dependOn(&copy_cmd.step);

    // zig build release -> zig-out/bin/zatt
    const release_step = b.step("release", "Build release binary for Homebrew");
    release_step.dependOn(&tar_cmd.step);
}

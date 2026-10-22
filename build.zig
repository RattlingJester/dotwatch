const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    mod.linkSystemLibrary("libgit2", .{});

    const exe = b.addExecutable(.{
        .name = "dotwatch",
        .root_module = mod,
        .linkage = .dynamic,
    });

    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());

    run.addPassthruArgs();

    const run_step = b.step("run", "run the app");
    run_step.dependOn(&run.step);
}

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zlox_mod = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const zlox_exe = b.addExecutable(.{
        .name = "zlox",
        .root_module = zlox_mod,
    });

    b.installArtifact(zlox_exe);

    const zlox_run = b.addRunArtifact(zlox_exe);
    if (b.args) |args| zlox_run.addArgs(args);

    b.step("run", "run zlox").dependOn(&zlox_run.step);
}

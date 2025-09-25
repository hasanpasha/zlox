const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.addModule("zlox", .{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "zlox",
        .root_module = exe_mod,
    });

    const options = b.addOptions();
    exe.root_module.addOptions("config", options);

    const trace_option = b.option(bool, "trace", "log instructions") orelse false;
    options.addOption(bool, "trace", trace_option);

    const exe_install = b.addInstallArtifact(exe, .{});

    const exe_run = b.addRunArtifact(exe);
    exe_run.step.dependOn(&exe_install.step);

    const run_step = b.step("run", "run zlox");
    run_step.dependOn(&exe_run.step);

    const check_step = b.step("check", "check build");
    check_step.dependOn(&exe.step);
}

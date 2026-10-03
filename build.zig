const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // --- Library module: yamori ---
    const lib = b.addModule("yamori", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // --- Executable ---
    const exe_root = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_root.addImport("yamori", lib);

    const exe = b.addExecutable(.{
        .name = "yamori",
        .root_module = exe_root,
    });
    b.installArtifact(exe);

    // --- Tests ---
    const test_exe_root = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_exe_root.addImport("yamori", lib);

    const test_exe = b.addTest(.{
        .name = "yamori-tests",
        .root_module = test_exe_root,
    });

    const run_test = b.addRunArtifact(test_exe);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_test.step);
}

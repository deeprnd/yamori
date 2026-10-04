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

    // --- Capability module ---
    const cap_mod = b.addModule("capability", .{
        .root_source_file = b.path("src/capability.zig"),
        .target = target,
        .optimize = optimize,
    });

    // --- Error module ---
    const error_mod = b.addModule("error", .{
        .root_source_file = b.path("src/error.zig"),
        .target = target,
        .optimize = optimize,
    });

    // --- Registry module ---
    const reg_mod = b.addModule("registry", .{
        .root_source_file = b.path("src/registry.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "capability", .module = cap_mod },
        },
    });

    // --- GSL adapter module ---
    const gsl_mod = b.addModule("gsl_adapter", .{
        .root_source_file = b.path("src/gsl_adapter.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "capability", .module = cap_mod },
            .{ .name = "error", .module = error_mod },
        },
    });

    // --- Arrow adapter module ---
    const arrow_mod = b.addModule("arrow_adapter", .{
        .root_source_file = b.path("src/arrow_adapter.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "error", .module = error_mod },
        },
    });

    // --- Backend policy module ---
    const backend_policy_mod = b.addModule("backend_policy", .{
        .root_source_file = b.path("src/backend_policy.zig"),
        .target = target,
        .optimize = optimize,
    });

    // --- Provenance module ---
    const provenance_mod = b.addModule("provenance", .{
        .root_source_file = b.path("src/provenance.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "backend_policy", .module = backend_policy_mod },
        },
    });

    // --- Dispatch module ---
    const dispatch_mod = b.addModule("dispatch", .{
        .root_source_file = b.path("src/dispatch.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "capability", .module = cap_mod },
            .{ .name = "registry", .module = reg_mod },
            .{ .name = "arrow_adapter", .module = arrow_mod },
            .{ .name = "gsl_adapter", .module = gsl_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "backend_policy", .module = backend_policy_mod },
            .{ .name = "provenance", .module = provenance_mod },
        },
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
    test_exe_root.addImport("capability", cap_mod);
    test_exe_root.addImport("registry", reg_mod);
    test_exe_root.addImport("gsl_adapter", gsl_mod);
    test_exe_root.addImport("arrow_adapter", arrow_mod);
    test_exe_root.addImport("error", error_mod);
    test_exe_root.addImport("dispatch", dispatch_mod);
    test_exe_root.addImport("backend_policy", backend_policy_mod);
    test_exe_root.addImport("provenance", provenance_mod);

    const test_exe = b.addTest(.{
        .name = "yamori-tests",
        .root_module = test_exe_root,
    });

    const run_test = b.addRunArtifact(test_exe);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_test.step);

    // ── Per-subsystem test steps ─────────────────────────────────────────────

    // Formula subsystem tests
    const formula_test_exe = b.addTest(.{
        .name = "yamori-formula-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    formula_test_exe.root_module.addImport("yamori", lib);
    formula_test_exe.root_module.addImport("capability", cap_mod);
    formula_test_exe.root_module.addImport("registry", reg_mod);
    formula_test_exe.root_module.addImport("gsl_adapter", gsl_mod);
    formula_test_exe.root_module.addImport("arrow_adapter", arrow_mod);
    formula_test_exe.root_module.addImport("error", error_mod);
    formula_test_exe.root_module.addImport("dispatch", dispatch_mod);
    formula_test_exe.root_module.addImport("backend_policy", backend_policy_mod);
    formula_test_exe.root_module.addImport("provenance", provenance_mod);
    const run_formula_test = b.addRunArtifact(formula_test_exe);
    const formula_test_step = b.step("test-formula", "Run formula tests");
    formula_test_step.dependOn(&run_formula_test.step);

    // Registry subsystem tests
    const registry_test_exe = b.addTest(.{
        .name = "yamori-registry-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    registry_test_exe.root_module.addImport("yamori", lib);
    registry_test_exe.root_module.addImport("capability", cap_mod);
    registry_test_exe.root_module.addImport("registry", reg_mod);
    registry_test_exe.root_module.addImport("gsl_adapter", gsl_mod);
    registry_test_exe.root_module.addImport("arrow_adapter", arrow_mod);
    registry_test_exe.root_module.addImport("error", error_mod);
    registry_test_exe.root_module.addImport("dispatch", dispatch_mod);
    registry_test_exe.root_module.addImport("backend_policy", backend_policy_mod);
    registry_test_exe.root_module.addImport("provenance", provenance_mod);
    const run_registry_test = b.addRunArtifact(registry_test_exe);
    const registry_test_step = b.step("test-registry", "Run registry tests");
    registry_test_step.dependOn(&run_registry_test.step);

    // Cycle detection tests
    const cycle_test_exe = b.addTest(.{
        .name = "yamori-cycle-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    cycle_test_exe.root_module.addImport("yamori", lib);
    cycle_test_exe.root_module.addImport("capability", cap_mod);
    cycle_test_exe.root_module.addImport("registry", reg_mod);
    cycle_test_exe.root_module.addImport("gsl_adapter", gsl_mod);
    cycle_test_exe.root_module.addImport("arrow_adapter", arrow_mod);
    cycle_test_exe.root_module.addImport("error", error_mod);
    cycle_test_exe.root_module.addImport("dispatch", dispatch_mod);
    cycle_test_exe.root_module.addImport("backend_policy", backend_policy_mod);
    cycle_test_exe.root_module.addImport("provenance", provenance_mod);
    const run_cycle_test = b.addRunArtifact(cycle_test_exe);
    const cycle_test_step = b.step("test-cycle", "Run cycle detection tests");
    cycle_test_step.dependOn(&run_cycle_test.step);

    // Dependency resolver tests
    const dep_test_exe = b.addTest(.{
        .name = "yamori-dep-resolve-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    dep_test_exe.root_module.addImport("yamori", lib);
    dep_test_exe.root_module.addImport("capability", cap_mod);
    dep_test_exe.root_module.addImport("registry", reg_mod);
    dep_test_exe.root_module.addImport("gsl_adapter", gsl_mod);
    dep_test_exe.root_module.addImport("arrow_adapter", arrow_mod);
    dep_test_exe.root_module.addImport("error", error_mod);
    dep_test_exe.root_module.addImport("dispatch", dispatch_mod);
    dep_test_exe.root_module.addImport("backend_policy", backend_policy_mod);
    dep_test_exe.root_module.addImport("provenance", provenance_mod);
    const run_dep_test = b.addRunArtifact(dep_test_exe);
    const dep_test_step = b.step("test-dep-resolve", "Run dependency resolver tests");
    dep_test_step.dependOn(&run_dep_test.step);

    // Arrow adapter tests
    const arrow_test_exe = b.addTest(.{
        .name = "yamori-arrow-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    arrow_test_exe.root_module.addImport("yamori", lib);
    arrow_test_exe.root_module.addImport("capability", cap_mod);
    arrow_test_exe.root_module.addImport("registry", reg_mod);
    arrow_test_exe.root_module.addImport("gsl_adapter", gsl_mod);
    arrow_test_exe.root_module.addImport("arrow_adapter", arrow_mod);
    arrow_test_exe.root_module.addImport("error", error_mod);
    arrow_test_exe.root_module.addImport("dispatch", dispatch_mod);
    arrow_test_exe.root_module.addImport("backend_policy", backend_policy_mod);
    arrow_test_exe.root_module.addImport("provenance", provenance_mod);
    const run_arrow_test = b.addRunArtifact(arrow_test_exe);
    const arrow_test_step = b.step("test-arrow", "Run arrow adapter tests");
    arrow_test_step.dependOn(&run_arrow_test.step);

    // Result frame tests
    const result_test_exe = b.addTest(.{
        .name = "yamori-result-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    result_test_exe.root_module.addImport("yamori", lib);
    result_test_exe.root_module.addImport("capability", cap_mod);
    result_test_exe.root_module.addImport("registry", reg_mod);
    result_test_exe.root_module.addImport("gsl_adapter", gsl_mod);
    result_test_exe.root_module.addImport("arrow_adapter", arrow_mod);
    result_test_exe.root_module.addImport("error", error_mod);
    result_test_exe.root_module.addImport("dispatch", dispatch_mod);
    result_test_exe.root_module.addImport("backend_policy", backend_policy_mod);
    result_test_exe.root_module.addImport("provenance", provenance_mod);
    const run_result_test = b.addRunArtifact(result_test_exe);
    const result_test_step = b.step("test-result", "Run result frame tests");
    result_test_step.dependOn(&run_result_test.step);

    // Provenance tests
    const provenance_test_exe = b.addTest(.{
        .name = "yamori-provenance-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    provenance_test_exe.root_module.addImport("yamori", lib);
    provenance_test_exe.root_module.addImport("capability", cap_mod);
    provenance_test_exe.root_module.addImport("registry", reg_mod);
    provenance_test_exe.root_module.addImport("gsl_adapter", gsl_mod);
    provenance_test_exe.root_module.addImport("arrow_adapter", arrow_mod);
    provenance_test_exe.root_module.addImport("error", error_mod);
    provenance_test_exe.root_module.addImport("dispatch", dispatch_mod);
    provenance_test_exe.root_module.addImport("backend_policy", backend_policy_mod);
    provenance_test_exe.root_module.addImport("provenance", provenance_mod);
    const run_provenance_test = b.addRunArtifact(provenance_test_exe);
    const provenance_test_step = b.step("test-provenance", "Run provenance tests");
    provenance_test_step.dependOn(&run_provenance_test.step);

    // ── Coverage build: compile test binaries without running them ────────
    const cov_step = b.step("cov", "Compile test binaries for kcov coverage");
    cov_step.dependOn(&test_exe.step);
    cov_step.dependOn(&formula_test_exe.step);
    cov_step.dependOn(&registry_test_exe.step);
    cov_step.dependOn(&cycle_test_exe.step);
    cov_step.dependOn(&dep_test_exe.step);
    cov_step.dependOn(&arrow_test_exe.step);
    cov_step.dependOn(&result_test_exe.step);
    cov_step.dependOn(&provenance_test_exe.step);
}

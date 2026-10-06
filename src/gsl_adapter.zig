// GSLAdapter — comptime GSL function map + validation helpers. Heap-free.

const std = @import("std");

pub const GSLAdapterError = error{
    LibraryNotFound,
    FunctionNotFound,
    InvalidInput,
    ComputeFailed,
    MemoryAllocationFailed,
};

/// Import YamoriError for mapping GSL errors to the unified error set.
const yamori_err = @import("error");
const YamoriError = yamori_err.YamoriError;

/// Import capability module for Capability type.
const capability_mod = @import("capability");

pub const GSLFunctionMap = struct {
    const Entry = struct {
        capability_name: []const u8,
        gsl_fn: []const u8,
        gsl_header: []const u8,
    };

    pub const all: []const Entry = &.{
        .{ .capability_name = "mean", .gsl_fn = "gsl_stats_mean", .gsl_header = "mean" },
        .{ .capability_name = "variance", .gsl_fn = "gsl_stats_variance", .gsl_header = "variance" },
        .{ .capability_name = "std_dev", .gsl_fn = "gsl_stats_sd", .gsl_header = "sd" },
        .{ .capability_name = "covariance", .gsl_fn = "gsl_stats_covariance", .gsl_header = "covariance" },
        .{ .capability_name = "correlation", .gsl_fn = "gsl_stats_correlation", .gsl_header = "correlation" },
        .{ .capability_name = "quantile", .gsl_fn = "gsl_stats_quantile", .gsl_header = "quantile" },
        .{ .capability_name = "median", .gsl_fn = "gsl_stats_median_from_sorted_data", .gsl_header = "median" },
        .{ .capability_name = "percentile", .gsl_fn = "gsl_stats_percentile_from_sorted_data", .gsl_header = "percentile" },
    };

    /// Look up the GSL function name for a given capability name.
    /// Returns null if the capability is not mapped.
    pub fn lookup(capability_name: []const u8) ?[]const u8 {
        for (all) |entry| {
            if (std.mem.eql(u8, entry.capability_name, capability_name)) {
                return entry.gsl_fn;
            }
        }
        return null;
    }
};

/// Input validation helpers for GSL compute dispatch.
pub const GSLAdapter = struct {
    /// Validate that all input slices are non-empty f64 vectors of matching lengths.
    pub fn validateGSLInput(inputs: []const []const f64) GSLAdapterError!void {
        if (inputs.len == 0) return GSLAdapterError.InvalidInput;

        const first_len = inputs[0].len;
        if (first_len == 0) return GSLAdapterError.InvalidInput;

        var i: usize = 1;
        while (i < inputs.len) : (i += 1) {
            if (inputs[i].len != first_len) {
                return GSLAdapterError.InvalidInput;
            }
        }
    }

    /// Map GSL-specific errors to unified YamoriError types.
    pub fn mapGSLAdapterError(gsl_err: GSLAdapterError) YamoriError {
        const tag = @intFromError(gsl_err);
        return switch (tag) {
            @intFromError(GSLAdapterError.LibraryNotFound) => YamoriError.BackendNotAvailable,
            @intFromError(GSLAdapterError.FunctionNotFound) => YamoriError.UnknownOperation,
            @intFromError(GSLAdapterError.InvalidInput) => YamoriError.InvalidOperationInput,
            @intFromError(GSLAdapterError.ComputeFailed) => YamoriError.BackendComputeFailed,
            @intFromError(GSLAdapterError.MemoryAllocationFailed) => YamoriError.BackendInsufficientMemory,
            else => unreachable,
        };
    }

    /// Register all GSL statistical functions behind the capability registry.
    /// Each capability is registered with backend_selector = .gsl.
    pub fn register_gsl_backends(
        cap_reg: *capability_mod.CapabilityRegistry,
    ) !void {
        inline for (GSLFunctionMap.all) |entry| {
            const cap = capability_mod.Capability.init(
                entry.capability_name,
                1,
                "GSL " ++ entry.capability_name,
                &.{capability_mod.TypeDescriptor{ .category = .vector, .element_type = .f64 }},
                capability_mod.TypeDescriptor{ .category = .scalar, .element_type = .f64 },
                .gsl,
            );
            try cap_reg.register(&cap);
        }
    }
};

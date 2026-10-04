// GSLFunctionMap — comptime mapping from Yamori capability names to GSL function names.

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

/// Registry that maps capability names to GSL function metadata.
pub const GSLFunctionRegistry = struct {
    allocator: std.mem.Allocator,
    functions: std.StringHashMap(GSLFunctionEntry),

    pub const GSLFunctionEntry = struct {
        name: []const u8,
        gsl_fn_name: []const u8,
        gsl_header: []const u8,
        min_inputs: usize,
        max_inputs: usize,
    };

    pub fn init(gpa: std.mem.Allocator) GSLFunctionRegistry {
        return GSLFunctionRegistry{
            .allocator = gpa,
            .functions = std.StringHashMap(GSLFunctionEntry).init(gpa),
        };
    }

    pub fn deinit(self: *GSLFunctionRegistry) void {
        var it = self.functions.iterator();
        while (it.next()) |kv| {
            self.allocator.free(kv.key_ptr.*);
            self.allocator.free(kv.value_ptr.gsl_fn_name);
            self.allocator.free(kv.value_ptr.gsl_header);
        }
        self.functions.deinit();
    }

    pub fn register(self: *GSLFunctionRegistry, entry: GSLFunctionEntry) !void {
        const name_dupe = (self.allocator.dupe(u8, entry.name)) catch return GSLAdapterError.MemoryAllocationFailed;
        const fn_name_dupe = (self.allocator.dupe(u8, entry.gsl_fn_name)) catch {
            self.allocator.free(name_dupe);
            return GSLAdapterError.MemoryAllocationFailed;
        };
        const header_dupe = (self.allocator.dupe(u8, entry.gsl_header)) catch {
            self.allocator.free(name_dupe);
            self.allocator.free(fn_name_dupe);
            return GSLAdapterError.MemoryAllocationFailed;
        };
        const val = GSLFunctionEntry{
            .name = name_dupe,
            .gsl_fn_name = fn_name_dupe,
            .gsl_header = header_dupe,
            .min_inputs = entry.min_inputs,
            .max_inputs = entry.max_inputs,
        };
        try self.functions.put(name_dupe, val);
    }

    pub fn get(self: *const GSLFunctionRegistry, name: []const u8) ?*const GSLFunctionEntry {
        return self.functions.getPtr(name);
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
};

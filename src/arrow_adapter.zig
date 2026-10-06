// ArrowAdapter — comptime Arrow function map + validation helpers. Heap-free.

const std = @import("std");

pub const ArrowError = error{
    FunctionNotFound,
    InvalidDataType,
    InvalidInputLength,
    ComputeFailed,
    NullInput,
};

/// Import YamoriError for mapping Arrow errors to the unified error set.
const yamori_err = @import("error");
const YamoriError = yamori_err.YamoriError;

pub const ArrowComputeMap = struct {
    const Entry = struct {
        capability_name: []const u8,
        arrow_fn: []const u8,
    };

    pub const all: []const Entry = &.{
        .{ .capability_name = "add", .arrow_fn = "add" },
        .{ .capability_name = "subtract", .arrow_fn = "subtract" },
        .{ .capability_name = "multiply", .arrow_fn = "multiply" },
        .{ .capability_name = "divide", .arrow_fn = "divide" },
        .{ .capability_name = "sum", .arrow_fn = "sum" },
        .{ .capability_name = "mean", .arrow_fn = "mean" },
        .{ .capability_name = "min", .arrow_fn = "min" },
        .{ .capability_name = "max", .arrow_fn = "max" },
        .{ .capability_name = "count", .arrow_fn = "count" },
        .{ .capability_name = "std_dev", .arrow_fn = "stddev" },
        .{ .capability_name = "variance", .arrow_fn = "variance" },
    };

    /// Look up the Arrow Compute function name for a given capability name.
    /// Returns null if the capability is not mapped.
    pub fn lookup(capability_name: []const u8) ?[]const u8 {
        for (all) |entry| {
            if (std.mem.eql(u8, entry.capability_name, capability_name)) {
                return entry.arrow_fn;
            }
        }
        return null;
    }
};

/// Input validation helpers for Arrow compute dispatch.
pub const ArrowAdapter = struct {
    /// Validate that all input slices are non-empty and have matching lengths.
    pub fn validateInputLengths(inputs: []const []const f64) ArrowError!void {
        if (inputs.len == 0) return ArrowError.NullInput;

        const first_len = inputs[0].len;
        if (first_len == 0) return ArrowError.InvalidInputLength;

        var i: usize = 1;
        while (i < inputs.len) : (i += 1) {
            if (inputs[i].len != first_len) {
                return ArrowError.InvalidInputLength;
            }
        }
    }

    /// Map Arrow-specific errors to unified YamoriError types.
    pub fn mapArrowError(arrow_err: ArrowError) YamoriError {
        const tag = @intFromError(arrow_err);
        return switch (tag) {
            @intFromError(ArrowError.FunctionNotFound) => YamoriError.UnknownOperation,
            @intFromError(ArrowError.InvalidDataType) => YamoriError.BackendInvalidDataType,
            @intFromError(ArrowError.InvalidInputLength) => YamoriError.InvalidOperationInput,
            @intFromError(ArrowError.ComputeFailed) => YamoriError.BackendComputeFailed,
            @intFromError(ArrowError.NullInput) => YamoriError.InvalidOperationInput,
            else => unreachable,
        };
    }
};

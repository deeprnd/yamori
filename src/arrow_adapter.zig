// ArrowComputeMap — comptime mapping from Yamori capability names to Arrow Compute function names.

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

/// Registry that maps capability names to Arrow Compute function wrappers.
pub const ArrowFunctionRegistry = struct {
    allocator: std.mem.Allocator,
    functions: std.StringHashMap(*ArrowComputeFunction),

    /// Represents an Arrow Compute function entry.
    pub const ArrowComputeFunction = struct {
        name: []const u8,
        /// The Arrow Compute function name string.
        arrow_fn_name: []const u8,
    };

    pub fn init(gpa: std.mem.Allocator) ArrowFunctionRegistry {
        return ArrowFunctionRegistry{
            .allocator = gpa,
            .functions = std.StringHashMap(*ArrowComputeFunction).init(gpa),
        };
    }

    pub fn deinit(self: *ArrowFunctionRegistry) void {
        var it = self.functions.iterator();
        while (it.next()) |entry| {
            const stored: *ArrowComputeFunction = entry.value_ptr.*;
            // Free the key (duped_name from register).
            self.allocator.free(entry.key_ptr.*);
            // Free arrow_fn_name (separate heap allocation from register).
            // Zero .name so destroy() doesn't double-free it.
            const afn = stored.arrow_fn_name;
            stored.arrow_fn_name = "";
            stored.name = "";
            self.allocator.free(afn);
            self.allocator.destroy(stored);
        }
        self.functions.deinit();
    }

    /// Register an Arrow compute function. Returns ArrowError.ComputeFailed
    /// if the name is already registered.
    pub fn register(
        self: *ArrowFunctionRegistry,
        fn_entry: ArrowComputeFunction,
    ) ArrowError!void {
        const duped_name = self.allocator.dupe(u8, fn_entry.name) catch return ArrowError.ComputeFailed;
        const duped_arrow = self.allocator.dupe(u8, fn_entry.arrow_fn_name) catch {
            self.allocator.free(duped_name);
            return ArrowError.ComputeFailed;
        };

        // Check for duplicate before allocating stored struct.
        if (self.functions.contains(duped_name)) {
            self.allocator.free(duped_name);
            self.allocator.free(duped_arrow);
            return ArrowError.ComputeFailed;
        }

        const stored = self.allocator.create(ArrowComputeFunction) catch {
            self.allocator.free(duped_name);
            self.allocator.free(duped_arrow);
            return ArrowError.ComputeFailed;
        };
        stored.name = duped_name;
        stored.arrow_fn_name = duped_arrow;
        self.functions.put(duped_name, stored) catch {
            self.allocator.free(duped_name);
            self.allocator.free(duped_arrow);
            self.allocator.destroy(stored);
            return ArrowError.ComputeFailed;
        };
    }

    /// Lookup a registered Arrow compute function by capability name.
    /// Returns null if not found.
    pub fn get(
        self: *const ArrowFunctionRegistry,
        name: []const u8,
    ) ?*const ArrowComputeFunction {
        const slot = self.functions.getPtr(name) orelse return null;
        // slot is ?*(*ArrowComputeFunction); dereference to get ?*ArrowComputeFunction, then cast.
        return @ptrCast(@alignCast(slot.*));
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

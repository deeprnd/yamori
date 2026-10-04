// ArrowComputeMap — comptime mapping from Yamori capability names to Arrow Compute function names.

const std = @import("std");

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

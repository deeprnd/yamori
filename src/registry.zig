// CapabilityRegistry — stores and looks up Capability entries.

const std = @import("std");
const capability = @import("capability.zig");
const Capability = capability.Capability;

pub const RegistryError = error{
    DuplicateCapability,
    AllocationFailed,
};

pub const CapabilityRegistry = struct {
    allocator: std.mem.Allocator,
    capabilities: std.StringHashMap(Capability),

    pub fn init(gpa: std.mem.Allocator) CapabilityRegistry {
        return CapabilityRegistry{
            .allocator = gpa,
            .capabilities = std.StringHashMap(Capability).init(gpa),
        };
    }

    pub fn deinit(self: *CapabilityRegistry) void {
        var it = self.capabilities.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.capabilities.deinit();
    }

    /// Register a capability. Returns DuplicateCapability if name already exists.
    pub fn register(self: *CapabilityRegistry, cap: Capability) RegistryError!void {
        if (self.capabilities.contains(cap.name)) {
            return RegistryError.DuplicateCapability;
        }
        self.capabilities.put(cap.name, cap) catch return RegistryError.AllocationFailed;
    }

    /// Lookup a capability by name. Returns null if not found.
    pub fn get(self: *const CapabilityRegistry, name: []const u8) ?*const Capability {
        const ptr = self.capabilities.getPtr(name) orelse return null;
        return @constCast(ptr);
    }

    /// Check if a capability name exists.
    pub fn contains(self: *const CapabilityRegistry, name: []const u8) bool {
        return self.capabilities.contains(name);
    }

    /// Iterate over all registered capability names.
    pub fn iterator(self: *const CapabilityRegistry) std.StringHashMap(Capability).Iterator {
        return self.capabilities.iterator();
    }

    /// Count registered capabilities.
    pub fn count(self: *const CapabilityRegistry) usize {
        return self.capabilities.count();
    }

    /// Serialize the registry to a JSON string.
    pub fn toJson(self: *const CapabilityRegistry, gpa: std.mem.Allocator) ![]u8 {
        var buf = try std.ArrayList(u8).initCapacity(gpa, 0);
        errdefer buf.deinit(gpa);

        try buf.appendSlice(gpa, "{\"capabilities\":[");

        var first = true;
        var it = self.capabilities.iterator();
        while (it.next()) |entry| {
            if (!first) try buf.appendSlice(gpa, ",");
            first = false;
            const ver_buf = blk: {
                var tmp: [20]u8 = undefined;
                break :blk std.fmt.bufPrint(&tmp, "{d}", .{entry.value_ptr.version}) catch "0";
            };
            const tag = @tagName(entry.value_ptr.backend_selector);
            try buf.appendSlice(gpa, "{\"name\":\"");
            try buf.appendSlice(gpa, entry.value_ptr.name);
            try buf.appendSlice(gpa, "\",\"version\":");
            try buf.appendSlice(gpa, ver_buf);
            try buf.appendSlice(gpa, ",\"description\":\"");
            try buf.appendSlice(gpa, entry.value_ptr.description);
            try buf.appendSlice(gpa, "\",\"backend_selector\":\"");
            try buf.appendSlice(gpa, tag);
            try buf.appendSlice(gpa, "\"}");
        }

        try buf.appendSlice(gpa, "]}");
        return buf.toOwnedSlice(gpa);
    }
};

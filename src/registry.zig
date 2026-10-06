// CapabilityRegistry — fixed-size array storage for Capability entries.
// Heap-free: no allocator, no allocation, no deinit.

const std = @import("std");
const capability = @import("capability");
const Capability = capability.Capability;

pub const RegistryError = error{
    DuplicateCapability,
    CapacityExceeded,
};

pub const CapabilityRegistry = struct {
    capabilities: [64]?Capability,
    capacity: usize,
    capability_count: usize,

    pub fn init(registry: *CapabilityRegistry, cap_buf: []const Capability, buf_cap: usize) void {
        var i: usize = 0;
        while (i < 64) : (i += 1) {
            registry.capabilities[i] = null;
        }
        registry.capability_count = 0;
        // Copy capabilities from caller's buffer (up to capacity).
        if (cap_buf.len > 0) {
            var j: usize = 0;
            while (j < cap_buf.len and j < buf_cap) : (j += 1) {
                registry.capabilities[j] = cap_buf[j];
                registry.capability_count += 1;
            }
        }
        registry.capacity = buf_cap;
    }

    /// Register a capability. Returns DuplicateCapability if name already exists,
    /// CapacityExceeded if registry is full.
    pub fn register(self: *CapabilityRegistry, cap: *const Capability) RegistryError!void {
        // Check for duplicate first — even a full registry shouldn't silently reject duplicates.
        if (self.lookupByName(cap.name)) |_| {
            return RegistryError.DuplicateCapability;
        }
        if (self.capability_count >= self.capacity) {
            return RegistryError.CapacityExceeded;
        }
        // Find first null slot.
        var i: usize = 0;
        while (i < self.capacity) : (i += 1) {
            if (self.capabilities[i] == null) {
                self.capabilities[i] = cap.*;
                self.capability_count += 1;
                return;
            }
        }
        unreachable; // already checked capacity
    }

    /// Lookup a capability by name. Returns null if not found.
    pub fn get(self: *const CapabilityRegistry, name: []const u8) ?*const Capability {
        const idx = self.lookupByName(name) orelse return null;
        return &self.capabilities[idx].?;
    }

    /// Check if a capability name exists.
    pub fn contains(self: *const CapabilityRegistry, name: []const u8) bool {
        return self.lookupByName(name) != null;
    }

    /// Iterate over all registered capability indices.
    pub fn iterate(self: *const CapabilityRegistry, comptime cb: fn (usize) void) void {
        var i: usize = 0;
        while (i < self.capacity) : (i += 1) {
            if (self.capabilities[i] != null) {
                cb(i);
            }
        }
    }

    /// Count registered capabilities.
    pub fn count(self: *const CapabilityRegistry) usize {
        return self.capability_count;
    }

    /// Serialize the registry to a string (caller owns the buffer).
    pub fn toJson(self: *const CapabilityRegistry, buf: []u8) ![]u8 {
        var offset: usize = 0;
        const len = buf.len;

        if (len < 24) return buf[0..offset];
        const prefix = "{\"capabilities\":[";
        var i: usize = 0;
        while (i < prefix.len and offset < len) : (i += 1) {
            buf[offset] = prefix[i];
            offset += 1;
        }
        if (offset >= len) return buf[0..offset];

        if (self.capability_count == 0) {
            if (offset < len) { buf[offset] = ']'; offset += 1; }
            if (offset < len) { buf[offset] = '}'; offset += 1; }
            return buf[0..offset];
        }

        var ci: usize = 0;
        while (ci < self.capability_count) : (ci += 1) {
            if (self.capabilities[ci] == null) continue;
            if (ci > 0) {
                if (offset < len) { buf[offset] = ','; offset += 1; }
            }

            const cap = self.capabilities[ci].?;

            // {
            if (offset < len) { buf[offset] = '{'; offset += 1; }

            // "name":"<name>"
            const name_hdr = "\"name\":\"";
            for (name_hdr) |ch| {
                if (offset < len) { buf[offset] = ch; offset += 1; } else break;
            }
            var ni: usize = 0;
            while (ni < cap.name.len and offset < len) : (ni += 1) {
                buf[offset] = cap.name[ni];
                offset += 1;
            }
            if (offset >= len) break;
            if (offset < len) { buf[offset] = '"'; offset += 1; }

            // ,"version":<version>
            const ver_hdr = "\",\"version\":";
            for (ver_hdr) |ch| {
                if (offset < len) { buf[offset] = ch; offset += 1; } else break;
            }
            var tmp: [20]u8 = undefined;
            const ver_str = std.fmt.bufPrint(&tmp, "{d}", .{cap.version}) catch "0";
            for (ver_str) |ch| {
                if (offset < len) { buf[offset] = ch; offset += 1; } else break;
            }

            // ,"description":"<description>"
            const desc_hdr = "\",\"description\":\"";
            for (desc_hdr) |ch| {
                if (offset < len) { buf[offset] = ch; offset += 1; } else break;
            }
            ni = 0;
            while (ni < cap.description.len and offset < len) : (ni += 1) {
                buf[offset] = cap.description[ni];
                offset += 1;
            }
            if (offset >= len) break;
            if (offset < len) { buf[offset] = '"'; offset += 1; }

            // ,"backend_selector":"<selector>"
            const bs_hdr = "\",\"backend_selector\":\"";
            for (bs_hdr) |ch| {
                if (offset < len) { buf[offset] = ch; offset += 1; } else break;
            }
            const bs = @tagName(cap.backend_selector);
            for (bs) |ch| {
                if (offset < len) { buf[offset] = ch; offset += 1; } else break;
            }
            if (offset < len) { buf[offset] = '"'; offset += 1; }

            // }
            if (offset < len) { buf[offset] = '}'; offset += 1; }
        }

        if (offset < len) { buf[offset] = ']'; offset += 1; }
        if (offset < len) { buf[offset] = '}'; offset += 1; }

        return buf[0..offset];
    }

    fn lookupByName(self: *const CapabilityRegistry, name: []const u8) ?usize {
        var i: usize = 0;
        while (i < self.capacity) : (i += 1) {
            if (self.capabilities[i] == null) continue;
            if (std.mem.eql(u8, self.capabilities[i].?.name, name)) {
                return i;
            }
        }
        return null;
    }
};

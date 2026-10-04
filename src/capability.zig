// Capability registry types for V1.2-S1.

const std = @import("std");

pub const CapabilityCategory = enum {
    scalar,
    vector,
};

pub const ElementType = enum {
    f64,
    i32,
    bool,
};

pub const TypeDescriptor = struct {
    category: CapabilityCategory,
    element_type: ?ElementType = null,
};

pub const BackendSelector = enum {
    default,
    arrow,
    gsl,
};

pub const Capability = struct {
    name: []const u8,
    version: u32,
    description: []const u8,
    input_types: []const TypeDescriptor,
    output_type: TypeDescriptor,
    backend_selector: BackendSelector,

    pub fn init(
        allocator: std.mem.Allocator,
        name: []const u8,
        version: u32,
        description: []const u8,
        input_types: []const TypeDescriptor,
        output_type: TypeDescriptor,
        backend_selector: BackendSelector,
    ) Capability {
        return Capability{
            .name = name,
            .version = version,
            .description = description,
            .input_types = allocator.dupe(TypeDescriptor, input_types) catch @panic("oom"),
            .output_type = output_type,
            .backend_selector = backend_selector,
        };
    }

    pub fn deinit(self: *const Capability, allocator: std.mem.Allocator) void {
        allocator.free(self.input_types);
    }
};

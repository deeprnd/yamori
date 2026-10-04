// Backend selection policy for runtime and compile-time backend routing.
//
// BackendPolicy controls which backend (Arrow, GSL, or auto-detect) is used
// when dispatching a capability call. Compile-time defaults come from the
// capability registry; runtime overrides let callers swap backends without
// modifying capability definitions.

const std = @import("std");

/// Backend selection policy.
/// - arrow: always route to Arrow backend.
/// - gsl: always route to GSL backend.
/// - auto: fall back to the capability's default selector.
pub const BackendPolicy = enum { arrow, gsl, auto };

/// BackendSelector manages runtime overrides and compile-time defaults.
///
/// Lookup order: runtime override for the operation → capability default →
/// compile-time default.
pub const BackendSelector = struct {
    runtime_overrides: std.StringHashMap(BackendPolicy),
    compile_time_default: BackendPolicy,

    pub fn init(gpa: std.mem.Allocator, default: BackendPolicy) BackendSelector {
        return BackendSelector{
            .runtime_overrides = std.StringHashMap(BackendPolicy).init(gpa),
            .compile_time_default = default,
        };
    }

    pub fn deinit(self: *BackendSelector) void {
        self.runtime_overrides.deinit();
    }

    /// Set a runtime override for a specific operation.
    pub fn setOverride(self: *BackendSelector, op_name: []const u8, policy: BackendPolicy) !void {
        try self.runtime_overrides.put(op_name, policy);
    }

    /// Clear the runtime override for a specific operation.
    pub fn clearOverride(self: *BackendSelector, op_name: []const u8) void {
        self.runtime_overrides.remove(op_name);
    }

    /// Select the backend policy for an operation.
    /// Checks runtime overrides first, then falls back to the provided
    /// default_policy (usually the capability's backend_selector).
    pub fn select(self: *const BackendSelector, op_name: []const u8, default_policy: BackendPolicy) BackendPolicy {
        if (self.runtime_overrides.get(op_name)) |override| {
            return override;
        }
        return default_policy;
    }
};

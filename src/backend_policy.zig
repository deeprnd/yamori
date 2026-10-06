// Backend selection policy for runtime and compile-time backend routing.
//
// BackendPolicy controls which backend (Arrow, GSL, or auto-detect) is used
// when dispatching a capability call. Compile-time defaults come from the
// capability registry; runtime overrides let callers swap backends without
// modifying capability definitions.
//
// Heap-free: fixed-size array for overrides, no allocator.

const std = @import("std");

/// Backend selection policy.
/// - arrow: always route to Arrow backend.
/// - gsl: always route to GSL backend.
/// - auto: fall back to the capability's default selector.
pub const BackendPolicy = enum { arrow, gsl, auto };

pub const MaxOverrides = 32;

/// BackendSelector manages runtime overrides and compile-time defaults.
///
/// Lookup order: runtime override for the operation → capability default →
/// compile-time default.
pub const BackendSelector = struct {
    runtime_overrides: [MaxOverrides]?OverrideEntry,
    override_count: usize,
    compile_time_default: BackendPolicy,

    pub const OverrideEntry = struct {
        op_name: []const u8,
        policy: BackendPolicy,
    };

    pub fn init(selector: *BackendSelector, default: BackendPolicy) void {
        selector.* = BackendSelector{
            .runtime_overrides = undefined,
            .override_count = 0,
            .compile_time_default = default,
        };
        var idx: usize = 0;
        while (idx < MaxOverrides) : (idx += 1) {
            selector.runtime_overrides[idx] = null;
        }
    }

    /// Set a runtime override for a specific operation.
    pub fn setOverride(self: *BackendSelector, op_name: []const u8, policy: BackendPolicy) !void {
        if (self.override_count >= MaxOverrides) return error.Overflow;
        // Check if already exists
        var idx: usize = 0;
        while (idx < self.override_count) : (idx += 1) {
            if (self.runtime_overrides[idx]) |*entry| {
                if (std.mem.eql(u8, entry.op_name, op_name)) {
                    entry.policy = policy;
                    return;
                }
            }
        }
        // Add new override
        var new_idx: usize = 0;
        while (new_idx < MaxOverrides) : (new_idx += 1) {
            if (self.runtime_overrides[new_idx] == null) {
                self.runtime_overrides[new_idx] = OverrideEntry{
                    .op_name = op_name,
                    .policy = policy,
                };
                self.override_count += 1;
                return;
            }
        }
        unreachable; // already checked override_count
    }

    /// Clear the runtime override for a specific operation.
    pub fn clearOverride(self: *BackendSelector, op_name: []const u8) void {
        var i: usize = 0;
        while (i < self.override_count) : (i += 1) {
            if (self.runtime_overrides[i]) |*entry| {
                if (std.mem.eql(u8, entry.op_name, op_name)) {
                    self.runtime_overrides[i] = null;
                    self.override_count -= 1;
                    // Compact: move last non-null entry into this slot
                    var j: usize = i;
                    while (j < self.override_count) : (j += 1) {
                        self.runtime_overrides[j] = self.runtime_overrides[j + 1];
                    }
                    return;
                }
            }
        }
    }

    /// Select the backend policy for an operation.
    /// Checks runtime overrides first, then falls back to the provided
    /// default_policy (usually the capability's backend_selector).
    pub fn select(self: *const BackendSelector, op_name: []const u8, default_policy: BackendPolicy) BackendPolicy {
        var i: usize = 0;
        while (i < self.override_count) : (i += 1) {
            if (self.runtime_overrides[i]) |entry| {
                if (std.mem.eql(u8, entry.op_name, op_name)) {
                    return entry.policy;
                }
            }
        }
        return default_policy;
    }

    // No deinit — nothing owned.
};

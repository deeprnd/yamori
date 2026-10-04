// Backend-agnostic dispatch API for Yamori.
// Domain code calls dispatch(op, inputs) without knowing which backend
// implements the operation.

const std = @import("std");
const capability_mod = @import("capability");
const Capability = capability_mod.Capability;
const BackendSelector = capability_mod.BackendSelector;
const registry_mod = @import("registry");
const CapabilityRegistry = registry_mod.CapabilityRegistry;
const arrow_mod = @import("arrow_adapter");
const ArrowFunctionRegistry = arrow_mod.ArrowFunctionRegistry;
const ArrowAdapter = arrow_mod.ArrowAdapter;
const ArrowError = arrow_mod.ArrowError;
const gsl_mod = @import("gsl_adapter");
const GSLFunctionRegistry = gsl_mod.GSLFunctionRegistry;
const GSLAdapter = gsl_mod.GSLAdapter;
const GSLAdapterError = gsl_mod.GSLAdapterError;
const yamori_err = @import("error");
const YamoriError = yamori_err.YamoriError;
const backend_policy_mod = @import("backend_policy");
const BackendPolicy = backend_policy_mod.BackendPolicy;
const provenance_mod = @import("provenance");
const ProvenanceBuffer = provenance_mod.ProvenanceBuffer;
const captureProvenance = provenance_mod.capture;

/// Unified result of a dispatch call.
/// Caller is responsible for calling deinit(result, gpa) on success.
pub const DispatchResult = struct {
    data: []f64,
    count: usize,

    pub fn deinit(self: *DispatchResult, gpa: std.mem.Allocator) void {
        if (self.data.len > 0) {
            gpa.free(self.data);
            self.data = &.{};
        }
        self.count = 0;
    }
};

/// Unified error type for dispatch operations.
/// Combines YamoriError variants with dispatch-specific errors.
pub const DispatchError = error{
    InternalError,
} || YamoriError;

/// Dispatcher routes capability calls across Arrow and GSL backends
/// without adapter-specific leakage.
pub const Dispatcher = struct {
    cap_reg: *const CapabilityRegistry,
    arrow_reg: *const ArrowFunctionRegistry,
    gsl_reg: *const GSLFunctionRegistry,
    backend_selector: *const backend_policy_mod.BackendSelector,
    provenance: *ProvenanceBuffer,

    pub fn init(
        cap_reg: *const CapabilityRegistry,
        arrow_reg: *const ArrowFunctionRegistry,
        gsl_reg: *const GSLFunctionRegistry,
        backend_selector: *const backend_policy_mod.BackendSelector,
        provenance: *ProvenanceBuffer,
    ) Dispatcher {
        return Dispatcher{
            .cap_reg = cap_reg,
            .arrow_reg = arrow_reg,
            .gsl_reg = gsl_reg,
            .backend_selector = backend_selector,
            .provenance = provenance,
        };
    }

    /// Dispatch an operation to its registered backend.
    /// Caller is responsible for deinit(result) on success.
    pub fn dispatch(
        self: Dispatcher,
        gpa: std.mem.Allocator,
        op_name: []const u8,
        inputs: []const []const f64,
    ) DispatchError!DispatchResult {
        // 1. Look up capability in registry
        const cap = self.cap_reg.get(op_name) orelse {
            const record = captureProvenance(gpa, op_name, .arrow, inputs, 0, false, "UnknownOperation") catch return YamoriError.InternalError;
            self.provenance.append(record) catch {};
            return YamoriError.UnknownOperation;
        };

        // 2. Select backend policy: runtime override → capability default
        // Convert capability.BackendSelector to backend_policy.BackendPolicy via tag comparison
        // to avoid comptime-only type errors on runtime switch.
        const capability_policy: BackendPolicy = if (std.mem.eql(u8, @tagName(cap.backend_selector), "arrow"))
            .arrow
        else if (std.mem.eql(u8, @tagName(cap.backend_selector), "gsl"))
            .gsl
        else
            .auto;
        const policy = self.backend_selector.select(
            op_name,
            capability_policy,
        );

        // 3. Route based on resolved policy
        return switch (policy) {
            .arrow => dispatchArrow(self, gpa, op_name, inputs, policy),
            .gsl => dispatchGSL(self, gpa, op_name, inputs, policy),
            .auto => switch (capability_policy) {
                .arrow => dispatchArrow(self, gpa, op_name, inputs, .arrow),
                .gsl => dispatchGSL(self, gpa, op_name, inputs, .gsl),
                .auto => dispatchArrow(self, gpa, op_name, inputs, .arrow),
            },
        };
    }
};

/// Dispatch to the Arrow backend.
fn dispatchArrow(
    self: Dispatcher,
    gpa: std.mem.Allocator,
    op_name: []const u8,
    inputs: []const []const f64,
    backend: BackendPolicy,
) DispatchError!DispatchResult {
    if (self.arrow_reg.get(op_name) == null) {
        const record = captureProvenance(gpa, op_name, backend, inputs, 0, false, "BackendNotAvailable") catch return YamoriError.InternalError;
        self.provenance.append(record) catch {};
        return YamoriError.BackendNotAvailable;
    }

    // Validate inputs first
    ArrowAdapter.validateInputLengths(inputs) catch {
        const record = captureProvenance(gpa, op_name, backend, inputs, 0, false, "InvalidOperationInput") catch return YamoriError.InternalError;
        self.provenance.append(record) catch {};
        return YamoriError.InvalidOperationInput;
    };

    const output = (gpa.alloc(f64, inputs[0].len)) catch return YamoriError.BackendInsufficientMemory;
    errdefer gpa.free(output);

    // Mock compute: return the first input array as the result.
    // In S6 this will call the actual Arrow Compute C API.
    @memcpy(output, inputs[0]);

    const record = captureProvenance(gpa, op_name, backend, inputs, output.len, true, null) catch return YamoriError.InternalError;
    self.provenance.append(record) catch {};

    return DispatchResult{
        .data = output,
        .count = output.len,
    };
}

/// Dispatch to the GSL backend.
fn dispatchGSL(
    self: Dispatcher,
    gpa: std.mem.Allocator,
    op_name: []const u8,
    inputs: []const []const f64,
    backend: BackendPolicy,
) DispatchError!DispatchResult {
    const gsl_fn = self.gsl_reg.get(op_name) orelse {
        const record = captureProvenance(gpa, op_name, backend, inputs, 0, false, "BackendNotAvailable") catch return YamoriError.InternalError;
        self.provenance.append(record) catch {};
        return YamoriError.BackendNotAvailable;
    };

    _ = gsl_fn; // reserved for S6 actual GSL call

    GSLAdapter.validateGSLInput(inputs) catch {
        const record = captureProvenance(gpa, op_name, backend, inputs, 0, false, "InvalidOperationInput") catch return YamoriError.InternalError;
        self.provenance.append(record) catch {};
        return YamoriError.InvalidOperationInput;
    };

    const output = (gpa.alloc(f64, 1)) catch return YamoriError.BackendInsufficientMemory; // GSL functions typically return scalar
    errdefer gpa.free(output);

    // Mock compute: return a placeholder value.
    // In S6 this will call the actual GSL function.
    output[0] = 0.0;

    const record = captureProvenance(gpa, op_name, backend, inputs, output.len, true, null) catch return YamoriError.InternalError;
    self.provenance.append(record) catch {};

    return DispatchResult{
        .data = output,
        .count = 1,
    };
}

// Backend-agnostic dispatch API for Yamori.
// Heap-free: uses comptime ArrowComputeMap/GSLFunctionMap instead of registries.
// Caller provides result_buf and scratch — no gpa.alloc.

const std = @import("std");
const capability_mod = @import("capability");
const Capability = capability_mod.Capability;
const BackendSelector = backend_policy_mod.BackendSelector;
const registry_mod = @import("registry");
const CapabilityRegistry = registry_mod.CapabilityRegistry;
const arrow_mod = @import("arrow_adapter");
const ArrowComputeMap = arrow_mod.ArrowComputeMap;
const ArrowAdapter = arrow_mod.ArrowAdapter;
const ArrowError = arrow_mod.ArrowError;
const gsl_mod = @import("gsl_adapter");
const GSLFunctionMap = gsl_mod.GSLFunctionMap;
const GSLAdapter = gsl_mod.GSLAdapter;
const GSLAdapterError = gsl_mod.GSLAdapterError;
const yamori_err = @import("error");
const YamoriError = yamori_err.YamoriError;
const backend_policy_mod = @import("backend_policy");
const BackendPolicy = backend_policy_mod.BackendPolicy;
const provenance_mod = @import("provenance");
const ProvenanceBuffer = provenance_mod.ProvenanceBuffer;
const capture = provenance_mod.capture;
const MaxProvenanceInputLengths = provenance_mod.MaxProvenanceInputLengths;

/// GSL FFI bindings module.
const gsl_bindings = @import("gsl_bindings");

/// Unified result of a dispatch call.
/// Caller owns result_buf — no deinit needed.
pub const DispatchResult = struct {
    data: []f64,
    count: usize,
};

/// Unified error type for dispatch operations.
pub const DispatchError = error{
    InternalError,
} || YamoriError;

/// Dispatcher routes capability calls across Arrow and GSL backends
/// without adapter-specific leakage.
pub const Dispatcher = struct {
    cap_reg: *const CapabilityRegistry,
    backend_selector: *const BackendSelector,
    provenance: *ProvenanceBuffer,
    // scratch buffer for output allocation
    scratch: []f64,
    // input lengths buffer for provenance
    prov_lengths_buf: [MaxProvenanceInputLengths]usize,

    pub fn init(
        cap_reg: *const CapabilityRegistry,
        backend_selector: *const BackendSelector,
        provenance: *ProvenanceBuffer,
        scratch: []f64,
        prov_lengths_buf: [MaxProvenanceInputLengths]usize,
    ) Dispatcher {
        return Dispatcher{
            .cap_reg = cap_reg,
            .backend_selector = backend_selector,
            .provenance = provenance,
            .scratch = scratch,
            .prov_lengths_buf = prov_lengths_buf,
        };
    }

    /// Dispatch an operation to its registered backend.
    /// Maximum allowed length for an operation name at the trust boundary.
    pub const maxOpNameLen: usize = 256;

    pub fn dispatch(
        self: Dispatcher,
        op_name: []const u8,
        inputs: []const []const f64,
        result_buf: []f64,
    ) DispatchError!DispatchResult {
        // Outermost input validation at the trust boundary.
        if (op_name.len > maxOpNameLen) {
            var lengths = self.prov_lengths_buf;
            const record = capture(op_name, .arrow, inputs, 0, false, "InvalidOperationInput", &lengths, MaxProvenanceInputLengths);
            self.provenance.append(record) catch {};
            return YamoriError.InvalidOperationInput;
        }
        for (inputs) |inp| {
            for (inp) |v| {
                if (std.math.isNan(v) or std.math.isInf(v)) {
                    var lengths = self.prov_lengths_buf;
                    const record = capture(op_name, .arrow, inputs, 0, false, "InvalidOperationInput", &lengths, MaxProvenanceInputLengths);
                    self.provenance.append(record) catch {};
                    return YamoriError.InvalidOperationInput;
                }
            }
        }

        // 1. Look up capability in registry
        const cap = self.cap_reg.get(op_name) orelse {
            var lengths = self.prov_lengths_buf;
            const record = capture(op_name, .arrow, inputs, 0, false, "UnknownOperation", &lengths, MaxProvenanceInputLengths);
            self.provenance.append(record) catch {};
            return YamoriError.UnknownOperation;
        };

        // 2. Select backend policy
        const capability_policy: BackendPolicy = if (std.mem.eql(u8, @tagName(cap.backend_selector), "arrow"))
            .arrow
        else if (std.mem.eql(u8, @tagName(cap.backend_selector), "gsl"))
            .gsl
        else
            .auto;
        const policy = self.backend_selector.*.select(
            op_name,
            capability_policy,
        );

        // 3. Route based on resolved policy
        return switch (policy) {
            .arrow => dispatchArrow(self, op_name, inputs, result_buf, capability_policy),
            .gsl => dispatchGSL(self, op_name, inputs, result_buf, capability_policy),
            .auto => switch (capability_policy) {
                .arrow => dispatchArrow(self, op_name, inputs, result_buf, .arrow),
                .gsl => dispatchGSL(self, op_name, inputs, result_buf, .gsl),
                .auto => dispatchArrow(self, op_name, inputs, result_buf, .arrow),
            },
        };
    }
};

/// Dispatch to the Arrow backend.
fn dispatchArrow(
    self: Dispatcher,
    op_name: []const u8,
    inputs: []const []const f64,
    result_buf: []f64,
    backend: BackendPolicy,
) DispatchError!DispatchResult {
    // Check if Arrow function exists in comptime map
    if (ArrowComputeMap.lookup(op_name) == null) {
        var lengths = self.prov_lengths_buf;
        const record = capture(op_name, backend, inputs, 0, false, "BackendNotAvailable", &lengths, MaxProvenanceInputLengths);
        self.provenance.append(record) catch {};
        return YamoriError.BackendNotAvailable;
    }

    ArrowAdapter.validateInputLengths(inputs) catch {
        var lengths = self.prov_lengths_buf;
        const record = capture(op_name, backend, inputs, 0, false, "InvalidOperationInput", &lengths, MaxProvenanceInputLengths);
        self.provenance.append(record) catch {};
        return YamoriError.InvalidOperationInput;
    };

    const output_len = inputs[0].len;
    if (output_len > result_buf.len) return YamoriError.BackendInsufficientMemory;

    // Mock compute: return the first input array as the result.
    @memcpy(result_buf[0..output_len], inputs[0]);

    var lengths = self.prov_lengths_buf;
    const record = capture(op_name, backend, inputs, output_len, true, null, &lengths, MaxProvenanceInputLengths);
    self.provenance.append(record) catch {};

    return DispatchResult{
        .data = result_buf[0..output_len],
        .count = output_len,
    };
}

/// Dispatch to the GSL backend.
fn dispatchGSL(
    self: Dispatcher,
    op_name: []const u8,
    inputs: []const []const f64,
    result_buf: []f64,
    backend: BackendPolicy,
) DispatchError!DispatchResult {
    // Check if GSL function exists in comptime map
    if (GSLFunctionMap.lookup(op_name) == null) {
        var lengths = self.prov_lengths_buf;
        const record = capture(op_name, backend, inputs, 0, false, "BackendNotAvailable", &lengths, MaxProvenanceInputLengths);
        self.provenance.append(record) catch {};
        return YamoriError.BackendNotAvailable;
    }

    GSLAdapter.validateGSLInput(inputs) catch {
        var lengths = self.prov_lengths_buf;
        const record = capture(op_name, backend, inputs, 0, false, "InvalidOperationInput", &lengths, MaxProvenanceInputLengths);
        self.provenance.append(record) catch {};
        return YamoriError.InvalidOperationInput;
    };

    if (result_buf.len < 1) return YamoriError.BackendInsufficientMemory;

    const fn_name = GSLFunctionMap.lookup(op_name).?;
    if (std.mem.eql(u8, fn_name, "gsl_stats_mean")) {
        result_buf[0] = gsl_bindings.mean(inputs[0]);
    } else if (std.mem.eql(u8, fn_name, "gsl_stats_variance")) {
        result_buf[0] = gsl_bindings.variance(inputs[0]);
    } else if (std.mem.eql(u8, fn_name, "gsl_stats_sd")) {
        result_buf[0] = gsl_bindings.sd(inputs[0]);
    } else if (std.mem.eql(u8, fn_name, "gsl_stats_covariance")) {
        result_buf[0] = gsl_bindings.covariance(inputs[0], inputs[1]);
    } else if (std.mem.eql(u8, fn_name, "gsl_stats_correlation")) {
        result_buf[0] = gsl_bindings.correlation(inputs[0], inputs[1]);
    } else if (std.mem.eql(u8, fn_name, "gsl_stats_quantile")) {
        result_buf[0] = gsl_bindings.quantile(inputs[0], 0.5);
    } else if (std.mem.eql(u8, fn_name, "gsl_stats_median_from_sorted_data")) {
        result_buf[0] = gsl_bindings.median(inputs[0]);
    } else {
        var lengths = self.prov_lengths_buf;
        const record = capture(op_name, backend, inputs, 0, false, "UnknownOperation", &lengths, MaxProvenanceInputLengths);
        self.provenance.append(record) catch {};
        return YamoriError.UnknownOperation;
    }

    var lengths = self.prov_lengths_buf;
    const record = capture(op_name, backend, inputs, 1, true, null, &lengths, MaxProvenanceInputLengths);
    self.provenance.append(record) catch {};

    return DispatchResult{
        .data = result_buf[0..1],
        .count = 1,
    };
}

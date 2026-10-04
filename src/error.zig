// YamoriError — unified error hierarchy for all backend dispatch failures.
// Every backend (Arrow, GSL, etc.) maps its native errors to these types
// so callers always deal with a single, stable error set.

pub const YamoriError = error{
    // Operation errors
    UnknownOperation,
    OperationNotSupported,
    InvalidOperationInput,
    OperationTimeout,

    // Backend errors
    BackendNotAvailable,
    BackendComputeFailed,
    BackendInvalidDataType,
    BackendInsufficientMemory,

    // Registry errors
    CapabilityNotFound,
    DuplicateCapability,
    InvalidCapability,

    // System errors
    InitializationFailed,
    InternalError,
};

/// Map YamoriError to human-readable strings.
pub fn errorDescription(err: YamoriError) []const u8 {
    const tag = @intFromError(err);
    return switch (tag) {
        @intFromError(YamoriError.UnknownOperation) => "Operation not found in capability registry",
        @intFromError(YamoriError.OperationNotSupported) => "Operation not supported by selected backend",
        @intFromError(YamoriError.InvalidOperationInput) => "Invalid input types or lengths for operation",
        @intFromError(YamoriError.OperationTimeout) => "Operation exceeded time limit",
        @intFromError(YamoriError.BackendNotAvailable) => "Requested backend is not available",
        @intFromError(YamoriError.BackendComputeFailed) => "Backend computation failed",
        @intFromError(YamoriError.BackendInvalidDataType) => "Backend does not support input data type",
        @intFromError(YamoriError.BackendInsufficientMemory) => "Backend ran out of memory",
        @intFromError(YamoriError.CapabilityNotFound) => "Capability not found in registry",
        @intFromError(YamoriError.DuplicateCapability) => "Capability already registered",
        @intFromError(YamoriError.InvalidCapability) => "Invalid capability definition",
        @intFromError(YamoriError.InitializationFailed) => "Failed to initialize Yamori",
        @intFromError(YamoriError.InternalError) => "Internal Yamori error",
        else => unreachable,
    };
}

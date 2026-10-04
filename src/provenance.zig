// Provenance tracking module for Yamori dispatch operations.
//
// Tracks audit trail for every dispatch: operation name, backend used,
// input metadata, output metadata, timestamp, and success/error status.
// Maintains a bounded buffer of recent dispatch events.

const std = @import("std");
const backend_policy_mod = @import("backend_policy");
const BackendPolicy = backend_policy_mod.BackendPolicy;

/// ProvenanceRecord represents a single dispatch event.
/// Caller owns input_lengths and error_message; deinit frees them.
pub const ProvenanceRecord = struct {
    operation_name: []const u8,
    backend_used: BackendPolicy,
    input_count: usize,
    input_lengths: []usize,
    output_count: usize,
    timestamp_ns: u64,
    success: bool,
    error_message: ?[]const u8,

    /// Free dynamically allocated fields (input_lengths, error_message).
    pub fn deinit(self: *ProvenanceRecord, gpa: std.mem.Allocator) void {
        if (self.input_lengths.len > 0) {
            gpa.free(self.input_lengths);
            self.input_lengths = &.{};
        }
        if (self.error_message) |msg| {
            gpa.free(msg);
            self.error_message = null;
        }
    }
};

/// ProvenanceError for provenance-related failures.
pub const ProvenanceError = error{
    AllocationFailed,
};

/// ProvenanceBuffer stores a bounded history of dispatch event records.
/// Oldest records are evicted when the buffer exceeds max_size.
pub const ProvenanceBuffer = struct {
    allocator: std.mem.Allocator,
    records: std.ArrayListUnmanaged(ProvenanceRecord),
    max_size: usize,

    /// Initialize a new provenance buffer with the given maximum capacity.
    pub fn init(gpa: std.mem.Allocator, max_size: usize) ProvenanceBuffer {
        return ProvenanceBuffer{
            .allocator = gpa,
            .records = .empty,
            .max_size = max_size,
        };
    }

    /// Deinitialize all records and the internal list.
    pub fn deinit(self: *ProvenanceBuffer) void {
        var i: usize = 0;
        while (i < self.records.items.len) : (i += 1) {
            self.records.items[i].deinit(self.allocator);
        }
        self.records.deinit(self.allocator);
    }

    /// Append a record to the buffer. Evicts oldest records if max_size exceeded.
    pub fn append(self: *ProvenanceBuffer, record: ProvenanceRecord) !void {
        try self.records.append(self.allocator, record);

        // Maintain bounded size: evict oldest records
        while (self.records.items.len > self.max_size) {
            self.records.items[0].deinit(self.allocator);
            _ = self.records.orderedRemove(0);
        }
    }

    /// Get a record by index. Returns null if index is out of bounds.
    pub fn get(self: *const ProvenanceBuffer, index: usize) ?*const ProvenanceRecord {
        if (index < self.records.items.len) {
            return &self.records.items[index];
        }
        return null;
    }

    /// Get the number of records in the buffer.
    pub fn count(self: *const ProvenanceBuffer) usize {
        return self.records.items.len;
    }

    /// Find the most recent record matching the given operation name.
    /// Searches backwards from the end for efficiency.
    pub fn findByOperation(self: *const ProvenanceBuffer, op_name: []const u8) ?*const ProvenanceRecord {
        var i: usize = self.records.items.len;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, self.records.items[i].operation_name, op_name)) {
                return &self.records.items[i];
            }
        }
        return null;
    }

    /// Count the number of records matching the given operation name.
    pub fn countByOperation(self: *const ProvenanceBuffer, op_name: []const u8) usize {
        var n: usize = 0;
        for (self.records.items) |record| {
            if (std.mem.eql(u8, record.operation_name, op_name)) {
                n += 1;
            }
        }
        return n;
    }
};

/// ProvenanceCapture helper: builds a ProvenanceRecord from dispatch context.
/// Allocates input_lengths array and duplicates error_msg (if not null);
/// the resulting record owns both and must be cleaned up via record.deinit(gpa).
pub fn capture(
    gpa: std.mem.Allocator,
    op_name: []const u8,
    backend: BackendPolicy,
    inputs: []const []const f64,
    output_count: usize,
    success: bool,
    error_msg: ?[]const u8,
) ProvenanceError!ProvenanceRecord {
    const lengths = (gpa.alloc(usize, inputs.len)) catch return ProvenanceError.AllocationFailed;

    var i: usize = 0;
    while (i < inputs.len) : (i += 1) {
        lengths[i] = inputs[i].len;
    }

    const posix = std.posix;
    var ts: posix.timespec = undefined;
    const ret = std.os.linux.clock_gettime(std.os.linux.CLOCK.MONOTONIC, &ts);
    _ = ret;
    const timestamp_ns: u64 = @as(u64, @intCast(@as(i64, ts.sec) * @as(i64, std.time.ns_per_s))) + @as(u64, @intCast(ts.nsec));

    // Duplicate error_msg so the record owns it — avoids double-free on
    // literal strings and lets deinit always free safely.
    const error_msg_owned: ?[]const u8 = if (error_msg) |m| (gpa.dupe(u8, m)) catch return ProvenanceError.AllocationFailed else null;

    const record = ProvenanceRecord{
        .operation_name = op_name,
        .backend_used = backend,
        .input_count = inputs.len,
        .input_lengths = lengths,
        .output_count = output_count,
        .timestamp_ns = timestamp_ns,
        .success = success,
        .error_message = error_msg_owned,
    };

    return record;
}

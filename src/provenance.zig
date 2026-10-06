// Provenance tracking module for Yamori dispatch operations.
//
// Tracks audit trail for every dispatch: operation name, backend used,
// input metadata, output metadata, timestamp, and success/error status.
// Maintains a bounded ring buffer of recent dispatch events.
// Heap-free: caller-owned buffers, no allocations.

const std = @import("std");
const backend_policy_mod = @import("backend_policy");
const BackendPolicy = backend_policy_mod.BackendPolicy;

pub const MaxProvenanceInputLengths = 8;

/// ProvenanceRecord represents a single dispatch event.
/// All string fields point into caller-owned memory (or are static literals).
pub const ProvenanceRecord = struct {
    operation_name: []const u8,
    backend_used: BackendPolicy,
    input_count: usize,
    input_lengths: [MaxProvenanceInputLengths]usize,
    input_lengths_len: usize,
    output_count: usize,
    timestamp_ns: u64,
    success: bool,
    error_message: ?[]const u8,
};

/// ProvenanceError for provenance-related failures.
pub const ProvenanceError = error{
    BufferFull,
};

pub const MaxProvenanceEntries = 256;

/// ProvenanceBuffer stores a bounded ring buffer of dispatch event records.
/// Caller owns the records_buf array; no heap allocations.
pub const ProvenanceBuffer = struct {
    records: [MaxProvenanceEntries]ProvenanceRecord,
    capacity: usize,
    record_count: usize,
    head: usize, // circular write position

    /// Initialize a new provenance buffer with caller-owned storage.
    pub fn init(buffer: *ProvenanceBuffer, records_buf: [*]ProvenanceRecord, buf_capacity: usize) void {
        _ = records_buf;
        buffer.* = ProvenanceBuffer{
            .records = undefined,
            .capacity = buf_capacity,
            .record_count = 0,
            .head = 0,
        };
    }

    /// Append a record to the buffer. Evicts oldest records if full.
    pub fn append(self: *ProvenanceBuffer, record: ProvenanceRecord) !void {
        if (self.record_count >= self.capacity) {
            // Evict oldest: overwrite head, advance
            self.head = (self.head + 1) % self.capacity;
        } else {
            self.record_count += 1;
        }
        self.records[self.head] = record;
        self.head = (self.head + 1) % self.capacity;
    }

    /// Get a record by index (0 = newest). Returns null if index >= count.
    pub fn get(self: *const ProvenanceBuffer, index: usize) ?*const ProvenanceRecord {
        if (index >= self.record_count) return null;
        // Newest is at (head - 1), next newest at (head - 2), etc.
        const idx = if (index == 0)
            if (self.head == 0) self.capacity - 1 else self.head - 1
        else
            (self.head - 1 - index + self.capacity) % self.capacity;
        return &self.records[idx];
    }

    /// Get the number of records in the buffer.
    pub fn count(self: *const ProvenanceBuffer) usize {
        return self.record_count;
    }

    /// Find the most recent record matching the given operation name.
    pub fn findByOperation(self: *const ProvenanceBuffer, op_name: []const u8) ?*const ProvenanceRecord {
        var i: usize = 0;
        while (i < self.record_count) : (i += 1) {
            const rec = self.get(i) orelse break;
            if (std.mem.eql(u8, rec.operation_name, op_name)) {
                return rec;
            }
        }
        return null;
    }

    /// Count the number of records matching the given operation name.
    pub fn countByOperation(self: *const ProvenanceBuffer, op_name: []const u8) usize {
        var n: usize = 0;
        var i: usize = 0;
        while (i < self.record_count) : (i += 1) {
            const rec = self.get(i) orelse break;
            if (std.mem.eql(u8, rec.operation_name, op_name)) {
                n += 1;
            }
        }
        return n;
    }

    // No deinit — nothing owned.
};

/// ProvenanceCapture helper: builds a ProvenanceRecord from dispatch context.
/// No allocations — all data goes into the caller-owned record.
pub fn capture(
    op_name: []const u8,
    backend: BackendPolicy,
    inputs: []const []const f64,
    output_count: usize,
    success: bool,
    error_msg: ?[]const u8,
    input_lengths_buf: [*]usize,
    input_lengths_capacity: usize,
) ProvenanceRecord {
    const input_lengths_len = if (inputs.len > input_lengths_capacity) input_lengths_capacity else inputs.len;
    var i: usize = 0;
    while (i < input_lengths_len) : (i += 1) {
        input_lengths_buf[i] = inputs[i].len;
    }

    const posix = std.posix;
    var ts: posix.timespec = undefined;
    const ret = std.os.linux.clock_gettime(std.os.linux.CLOCK.MONOTONIC, &ts);
    _ = ret;
    const timestamp_ns: u64 = @as(u64, @intCast(@as(i64, ts.sec) * @as(i64, std.time.ns_per_s))) + @as(u64, @intCast(ts.nsec));

    return ProvenanceRecord{
        .operation_name = op_name,
        .backend_used = backend,
        .input_count = inputs.len,
        .input_lengths = undefined,
        .input_lengths_len = input_lengths_len,
        .output_count = output_count,
        .timestamp_ns = timestamp_ns,
        .success = success,
        .error_message = error_msg,
    };
}

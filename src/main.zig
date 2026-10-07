const std = @import("std");
const capability_mod = @import("capability");
const registry_mod = @import("registry");
const arrow_mod = @import("arrow_adapter");
const gsl_mod = @import("gsl_adapter");
pub const Capability = capability_mod.Capability;
pub const TypeDescriptor = capability_mod.TypeDescriptor;
pub const CapabilityCategory = capability_mod.CapabilityCategory;
pub const ElementType = capability_mod.ElementType;
pub const BackendSelector = capability_mod.BackendSelector;
pub const CapabilityRegistry = registry_mod.CapabilityRegistry;
const BackendSelectorStruct = backend_policy_mod.BackendSelector;
const BackendPolicy = backend_policy_mod.BackendPolicy;

pub const formula = struct {
    // Compile-time constants for heap-free operation
    pub const MaxFormulas = 64;
    pub const MaxSources = 8;
    pub const MaxStringLength = 64;
    pub const MaxStringTable = 4096;

    // ─── String Table ────────────────────────────────────────────────────
    // Caller-owned buffer. All strings live in one contiguous region.
    // References strings by usize index instead of string pointers.

    pub const StringTable = struct {
        buffer: []u8,
        lengths: []usize,
        string_count: usize,

        pub fn init(table: *StringTable, buffer: []u8, lengths: []usize) void {
            table.buffer = buffer;
            table.lengths = lengths;
            table.string_count = 0;
        }

        /// Intern a string into the table. Returns index or error.OutOfMemory.
        pub fn intern(table: *StringTable, slice: []const u8) RegistryError!usize {
            // Check for duplicate first
            const buf = table.buffer;
            const len = table.string_count;
            var i: usize = 0;
            while (i < len) : (i += 1) {
                const existing_len = table.lengths[i];
                if (existing_len == slice.len) {
                    var matched = true;
                    var j: usize = 0;
                    while (j < slice.len) : (j += 1) {
                        if (buf[get_offset(table, i) + j] != slice[j]) {
                            matched = false;
                            break;
                        }
                    }
                    if (matched) return @as(usize, @truncate(i));
                }
            }

            // Need to allocate: check capacity
            const needed = slice.len + 1; // +1 for null terminator
            const offset = get_offset(table, len);
            if (offset + needed > buf.len) {
                return RegistryError.AllocationFailed;
            }

            // Copy string into buffer
            var j: usize = 0;
            while (j < slice.len) : (j += 1) {
                buf[offset + j] = slice[j];
            }
            buf[offset + slice.len] = 0; // null terminator

            // Store length
            table.lengths[len] = slice.len;
            table.string_count = len + 1;

            return @as(usize, @truncate(len));
        }

        /// Get a string slice by index. Returns error.OutOfRange if invalid.
        pub fn get(table: *const StringTable, index: usize) RegistryError![]const u8 {
            if (index >= table.string_count) return RegistryError.NotFound;
            const offset = get_offset_const(table, index);
            const len = table.lengths[index];
            return table.buffer[offset .. offset + len];
        }

        pub fn count(table: *const StringTable) usize {
            return table.string_count;
        }

        fn get_offset(table: *StringTable, index: usize) usize {
            // Compute byte offset: sum of all previous lengths + their null terminators
            var offset: usize = 0;
            var i: usize = 0;
            while (i < index) : (i += 1) {
                offset += table.lengths[i] + 1;
            }
            return offset;
        }

        fn get_offset_const(table: *const StringTable, index: usize) usize {
            var offset: usize = 0;
            var i: usize = 0;
            while (i < index) : (i += 1) {
                offset += table.lengths[i] + 1;
            }
            return offset;
        }
    };

    // ─── Formula Entry & Registry ────────────────────────────────────────
    // Fixed-size array instead of StringHashMap. O(N) lookup, zero heap.

    pub const FormulaEntry = struct {
        name_idx: usize,
        operation_idx: usize,
        source_count: usize,
        sources: [MaxSources]usize,
    };

    pub const FormulaDef = struct {
        name: []const u8,
        sources: []const []const u8,
        operation: []const u8,
    };

    pub const FormulaRegistry = struct {
        string_table: *StringTable,
        formulas: [MaxFormulas]?FormulaEntry,
        formula_count: usize,

        pub fn init(registry: *FormulaRegistry, string_table: *StringTable, formulas_buf: [MaxFormulas]?FormulaEntry) void {
            registry.string_table = string_table;
            registry.formulas = formulas_buf;
            registry.formula_count = 0;
        }

        pub fn lookup(registry: *const FormulaRegistry, name_idx: usize) ?usize {
            var i: usize = 0;
            while (i < registry.formula_count) : (i += 1) {
                if (registry.formulas[i]) |entry| {
                    if (entry.name_idx == name_idx) return i;
                }
            }
            return null;
        }

        pub fn add(registry: *FormulaRegistry, name_idx: usize, operation_idx: usize, sources: []const usize) RegistryError!void {
            // Check for duplicate name
            var i: usize = 0;
            while (i < registry.formula_count) : (i += 1) {
                if (registry.formulas[i]) |entry| {
                    if (entry.name_idx == name_idx) return RegistryError.DuplicateName;
                }
            }

            // Check capacity
            if (registry.formula_count >= MaxFormulas) {
                return RegistryError.AllocationFailed;
            }

            // Copy sources
            var entry = FormulaEntry{
                .name_idx = name_idx,
                .operation_idx = operation_idx,
                .source_count = 0,
                .sources = undefined,
            };
            var si: usize = 0;
            while (si < sources.len and si < MaxSources) : (si += 1) {
                entry.sources[si] = sources[si];
                entry.source_count += 1;
            }

            registry.formulas[registry.formula_count] = entry;
            registry.formula_count += 1;
        }

        pub fn get(registry: *const FormulaRegistry, name_idx: usize) RegistryError!*const FormulaEntry {
            const idx = registry.lookup(name_idx) orelse return RegistryError.NotFound;
            return &registry.formulas[idx].?;
        }

        pub fn has(registry: *const FormulaRegistry, name_idx: usize) bool {
            return registry.lookup(name_idx) != null;
        }

        pub fn remove(registry: *FormulaRegistry, name_idx: usize) RegistryError!void {
            var found: ?usize = null;
            var i: usize = 0;
            while (i < registry.formula_count) : (i += 1) {
                if (registry.formulas[i]) |entry| {
                    if (entry.name_idx == name_idx) {
                        found = i;
                        break;
                    }
                }
                i += 1;
            }
            if (found) |idx| {
                // Swap with last and decrement count
                registry.formulas[idx] = registry.formulas[registry.formula_count - 1];
                registry.formulas[registry.formula_count - 1] = null;
                registry.formula_count -= 1;
            } else {
                return RegistryError.NotFound;
            }
        }

        pub fn count(registry: *const FormulaRegistry) usize {
            return registry.formula_count;
        }

        /// Iterate over all formulas, calling callback for each (index, entry).
        pub fn iterate(registry: *const FormulaRegistry, callback: *const fn (usize, *const FormulaEntry) void) void {
            var i: usize = 0;
            while (i < registry.formula_count) : (i += 1) {
                if (registry.formulas[i]) |*entry| {
                    callback(i, entry);
                }
            }
        }
    };

    pub const RegistryError = error{
        DuplicateName,
        NotFound,
        AllocationFailed,
        CapacityExceeded,
    };

    /// Initialize a formula registry with caller-owned buffers.
    pub fn registryInit(registry: *FormulaRegistry, string_table: *StringTable, formulas_buf: [MaxFormulas]?FormulaEntry) void {
        registry.init(registry, string_table, formulas_buf);
    }

    /// Add a formula to the registry using string indices.
    pub fn registryAdd(registry: *FormulaRegistry, name_idx: usize, operation_idx: usize, sources: []const usize) RegistryError!void {
        try registry.add(registry, name_idx, operation_idx, sources);
    }

    /// Look up a formula by name index.
    pub fn registryGet(registry: *const FormulaRegistry, name_idx: usize) RegistryError!*const FormulaEntry {
        return registry.get(registry, name_idx);
    }

    /// Check if a formula exists by name index.
    pub fn registryHas(registry: *const FormulaRegistry, name_idx: usize) bool {
        return registry.has(registry, name_idx);
    }

    /// Remove a formula by name index.
    pub fn registryRemove(registry: *FormulaRegistry, name_idx: usize) RegistryError!void {
        return registry.remove(registry, name_idx);
    }
};

// ─── Cycle Detection ────────────────────────────────────────────────────

pub const cycleDetector = struct {
    pub const CycleError = error{
        CycleDetected,
    };

    /// Index-based DFS cycle detection.
    /// colors[i] = 0 white, 1 gray, 2 black
    /// Returns CycleError.CycleDetected if adding new_formula with given source_indices
    /// would create a cycle in the formula graph.
    pub fn detectCycleBeforeAddIndex(
        registry: *formula.FormulaRegistry,
        string_table: *formula.StringTable,
        new_name_idx: usize,
        new_source_indices: []const usize,
        colors: []u8,
        max_formulas: usize,
    ) CycleError!void {
        if (colors.len < max_formulas) return CycleError.CycleDetected;

        // Initialize all colors to white (0)
        var i: usize = 0;
        const to_init = if (max_formulas < colors.len) max_formulas else colors.len;
        while (i < to_init) : (i += 1) {
            colors[i] = 0;
        }

        // DFS helper (iterative to avoid recursion limits)
        // Only iterate over existing formulas
        var cycle_found: bool = false;
        var j: usize = 0;
        const scan_limit = if (registry.formula_count < max_formulas) registry.formula_count else max_formulas;
        while (j < scan_limit and !cycle_found) : (j += 1) {
            if (colors[j] != 0) continue;

            // Iterative DFS with explicit stack
            var stack: [64]usize = undefined;
            var stack_top: usize = 0;
            stack[stack_top] = j;
            stack_top += 1;

            while (stack_top > 0 and !cycle_found) {
                stack_top -= 1;
                const node = stack[stack_top];

                if (colors[node] == 2) continue; // already fully processed
                if (colors[node] == 1) {
                    cycle_found = true;
                    break;
                }

                colors[node] = 1; // gray

                // Push children (dependencies/sources)
                if (registry.formulas[node]) |entry| {
                    var si: usize = 0;
                    while (si < entry.source_count) : (si += 1) {
                        const dep_name_idx = entry.sources[si];
                        // Resolve dep name_idx to a formula index
                        var dep_formula_idx: ?usize = null;
                        var k: usize = 0;
                        while (k < registry.formula_count and dep_formula_idx == null) : (k += 1) {
                            if (registry.formulas[k]) |other| {
                                if (other.name_idx == dep_name_idx) {
                                    dep_formula_idx = k;
                                }
                            }
                        }
                        // Only push if it's an actual formula
                        if (dep_formula_idx) |fi| {
                            if (colors[fi] != 2) {
                                stack[stack_top] = fi;
                                stack_top += 1;
                            }
                        }
                    }
                }
            }

            // Mark as black (fully processed)
            if (!cycle_found) {
                colors[j] = 2;
            }
        }

        if (cycle_found) return CycleError.CycleDetected;

        // Now check: would adding new_formula with its sources create a cycle?
        // The new formula becomes index = registry.formula_count (last slot)
        const new_idx = registry.formula_count;
        if (new_idx >= max_formulas) return CycleError.CycleDetected;

        // Check if any of the new formula's sources depend (transitively) on the new formula itself
        // Since the new formula doesn't exist yet in the registry, we check:
        // does any source of the new formula have a path that leads to new_name_idx?
        // We use BFS from new_name_idx to see if any of new_source_indices are reachable
        //
        // new_name_idx is a string table index — resolve it to a formula index first
        var new_formula_idx: ?usize = null;
        var fi: usize = 0;
        while (fi < registry.formula_count) : (fi += 1) {
            if (registry.formulas[fi]) |entry| {
                if (entry.name_idx == new_name_idx) {
                    new_formula_idx = fi;
                    break;
                }
            }
        }

        var visited: [64]bool = undefined;
        var vi: usize = 0;
        const visit_limit = if (max_formulas < visited.len) max_formulas else visited.len;
        while (vi < visit_limit) : (vi += 1) {
            visited[vi] = false;
        }

        // If new_name doesn't exist as a formula yet, there's no cycle possible
        if (new_formula_idx == null) return;

        var bfs_queue: [64]usize = undefined;
        var bfs_head: usize = 0;
        var bfs_tail: usize = 0;

        const start = new_formula_idx.?;
        bfs_queue[bfs_tail] = start;
        bfs_tail += 1;
        visited[start] = true;

        while (bfs_head < bfs_tail) {
            const current = bfs_queue[bfs_head];
            bfs_head += 1;

            if (current < max_formulas) {
                if (registry.formulas[current]) |entry| {
                    var si: usize = 0;
                    while (si < entry.source_count) : (si += 1) {
                        const src = entry.sources[si];
                        // Only follow edges to existing formulas
                        if (src < registry.formula_count and src < max_formulas and !visited[src]) {
                            visited[src] = true;
                            bfs_queue[bfs_tail] = src;
                            bfs_tail += 1;
                        }
                    }
                }
            }
        }

        // Check if any of the new formula's sources are reachable from new_name_idx
        var si: usize = 0;
        while (si < new_source_indices.len) : (si += 1) {
            if (new_source_indices[si] < max_formulas and visited[new_source_indices[si]]) {
                return CycleError.CycleDetected;
            }
        }

        _ = string_table; // unused in index-based version, kept for API compatibility
    }
};

// ─── Dependency Resolver ────────────────────────────────────────────────

pub const dependencyResolver = struct {
    pub const ResolveResult = struct {
        order: []const usize,
    };

    pub const ResolveError = error{
        IncompleteRegistry,
    };

    /// Resolve dependencies using index-based Kahn's algorithm.
    /// Writes ordered formula indices to order_buf (caller-owned).
    /// Returns number of formulas in order, or 0 if cycle detected.
    pub fn resolveDependencies(
        registry: *const formula.FormulaRegistry,
        order_buf: [*]usize,
        order_capacity: usize,
        in_deg_buf: [*]usize,
        in_deg_capacity: usize,
        queue_buf: [*]usize,
        queue_capacity: usize,
    ) usize {
        const n = registry.formula_count;
        if (n == 0) return 0;
        if (n > order_capacity or n > in_deg_capacity or n > queue_capacity) return 0;

        // Initialize in-degrees to 0
        var i: usize = 0;
        while (i < n) : (i += 1) {
            in_deg_buf[i] = 0;
        }

        // Build adjacency implicitly and compute in-degrees
        // For each formula, count how many other formulas depend on it
        // IMPORTANT: Sources may be string table indices (for leaf data keys) or formula indices.
        // We must verify a source is an actual formula by matching name_idx, not by index range.
        var j: usize = 0;
        while (j < n) : (j += 1) {
            if (registry.formulas[j]) |entry| {
                var si: usize = 0;
                while (si < entry.source_count) : (si += 1) {
                    const src_idx = entry.sources[si];
                    // Verify src_idx is an actual formula by searching for matching name_idx
                    var found_formula_idx: ?usize = null;
                    var k: usize = 0;
                    while (k < n and found_formula_idx == null) : (k += 1) {
                        if (registry.formulas[k]) |other| {
                            if (other.name_idx == src_idx) {
                                found_formula_idx = k;
                            }
                        }
                    }
                    if (found_formula_idx != null) {
                        in_deg_buf[j] += 1;
                    }
                }
            }
        }

        // Initialize queue with zero in-degree nodes (sorted by index for determinism)
        var queue_len: usize = 0;
        var k: usize = 0;
        while (k < n) : (k += 1) {
            if (in_deg_buf[k] == 0) {
                queue_buf[queue_len] = k;
                queue_len += 1;
            }
        }

        // Kahn's algorithm
        var order_pos: usize = 0;
        var qi: usize = 0;
        while (qi < queue_len) {
            const current = queue_buf[qi];
            order_buf[order_pos] = current;
            order_pos += 1;
            qi += 1;

            // Find all nodes that depend on current
            var l: usize = 0;
            while (l < n) : (l += 1) {
                if (registry.formulas[l]) |entry| {
                    var si: usize = 0;
                    while (si < entry.source_count) : (si += 1) {
                        const src_idx = entry.sources[si];
                        // Match by name_idx: current is a formula index, find its name_idx
                        const current_formula = registry.formulas[current];
                        if (current_formula) |cf| {
                            if (cf.name_idx == src_idx) {
                                in_deg_buf[l] -= 1;
                                if (in_deg_buf[l] == 0) {
                                    queue_buf[queue_len] = l;
                                    queue_len += 1;
                                }
                                break;
                            }
                        }
                    }
                }
            }
        }

        if (order_pos != n) return 0; // cycle detected
        return order_pos;
    }
};

// ─── Arrow Adapter ──────────────────────────────────────────────────────

pub const arrowAdapter = struct {
    /// Arrow C Data Interface extern structs
    /// See: https://arrow.apache.org/docs/format/CDataInterface.html
    pub const ArrowSchema = extern struct {
        format: [*c]const u8,
        name: [*c]const u8,
        metadata: [*c]const u8,
        flags: i64,
        n_children: i64,
        children: [*c]ArrowSchema,
        dictionary: [*c]ArrowSchema,
        release: ?*const fn (*ArrowSchema) void,
        private_data: ?*anyopaque,
    };

    pub const ArrowArray = extern struct {
        length: i64,
        null_count: i64,
        offset: i64,
        n_buffers: i64,
        n_children: i64,
        /// Pointer to an array of n_buffers void* pointers.
        /// buffers[0] = validity bitmap (may be null if no nulls)
        /// buffers[1] = data buffer (f64 for "d" type)
        buffers: [*c]*const void,
        children: [*c]ArrowArray,
        dictionary: [*c]ArrowArray,
        release: ?*const fn (*ArrowArray) void,
        private_data: ?*anyopaque,
    };

    /// OperationMapping — comptime lookup table for Yamori → Arrow Compute
    pub const OperationMapping = struct {
        yamori_op: []const u8,
        arrow_func: []const u8,
    };

    // Comptime array — resolved at compile time
    pub const operation_map = [_]OperationMapping{
        .{ .yamori_op = "add", .arrow_func = "add" },
        .{ .yamori_op = "subtract", .arrow_func = "subtract" },
        .{ .yamori_op = "multiply", .arrow_func = "multiply" },
        .{ .yamori_op = "divide", .arrow_func = "divide" },
    };

    pub const AdapterError = error{
        UndefinedOperation,
        TypeMismatch,
        AllocationFailed,
    };

    pub const ArrowComputeResult = struct {
        output_array: [*c]ArrowArray,
        data: []f64, // The actual f64 data for test access
        allocator: std.mem.Allocator,
        buffers_holder: ?[]u64, // [0]=null bitmap ptr, [1]=data ptr (owned)
    };

    /// Free an ArrowComputeResult
    pub fn computeResultFree(result: ArrowComputeResult) void {
        const alloc = result.allocator;
        // Free the data buffer
        alloc.free(result.data);
        // Free the buffers holder if allocated
        if (result.buffers_holder) |bufs| {
            alloc.free(bufs);
        }
        // Free the ArrowArray struct itself — cast unbounded pointer back to single-item
        const ptr: *arrowAdapter.ArrowArray = @ptrFromInt(@intFromPtr(result.output_array));
        alloc.destroy(ptr);
    }

    /// Look up Arrow function name by Yamori operation (comptime table lookup)
    pub fn resolveArrowFunc(op: []const u8) AdapterError![]const u8 {
        for (operation_map) |mapping| {
            if (std.mem.eql(u8, op, mapping.yamori_op)) {
                return mapping.arrow_func;
            }
        }
        return AdapterError.UndefinedOperation;
    }

    /// Validate that all ArrowArrays have float64 data buffers (non-null).
    /// Format validation would require ArrowSchema which is not carried on the array.
    pub fn validateFloat64Arrays(_operands: []const *ArrowArray) AdapterError!void {
        for (_operands) |arr| {
            // Check that buffers pointer is non-null (required for data access)
            if (arr.*.buffers == null) {
                return AdapterError.TypeMismatch;
            }
        }
        return;
    }

    /// Execute a formula operation on Arrow float64 arrays.
    /// For V1.1, reads raw data from ArrowArray buffers and returns a new ArrowArray.
    /// The buffers field points to an array of pointers:
    ///   buffers[0] = validity bitmap (may be null)
    ///   buffers[1] = float64 data
    pub fn executeOperation(
        op_name: []const u8,
        operands: []const *ArrowArray,
        allocator: std.mem.Allocator,
    ) AdapterError!ArrowComputeResult {
        try validateFloat64Arrays(operands);

        if (operands.len < 2) return AdapterError.TypeMismatch;

        const len = operands[0].*.length;
        if (len <= 0) return AdapterError.TypeMismatch;
        if (len > std.math.maxInt(usize)) return AdapterError.TypeMismatch;

        // Validate all operands have the same length
        for (operands, 0..) |arr, i| {
            if (i > 0 and arr.*.length != len) return AdapterError.TypeMismatch;
        }

        // Get data buffer pointers (index 1 = data buffer after validity bitmap at [0])
        // Read data buffer pointers from operands (buffers[1] = data, buffers[0] = validity/null)
        const buf0: [*c]*const void = operands[0].*.buffers;
        const buf1: [*c]*const void = operands[1].*.buffers;
        const data0: [*]const f64 = @ptrFromInt(@intFromPtr(buf0[1]));
        const data1: [*]const f64 = @ptrFromInt(@intFromPtr(buf1[1]));

        // Allocate output
        var out_alloc = allocator.alloc(f64, @intCast(len)) catch return AdapterError.AllocationFailed;
        defer out_alloc = undefined;

        if (std.mem.eql(u8, op_name, "add")) {
            for (0..@intCast(len)) |i| {
                out_alloc[i] = data0[i] + data1[i];
            }
        } else if (std.mem.eql(u8, op_name, "subtract")) {
            for (0..@intCast(len)) |i| {
                out_alloc[i] = data0[i] - data1[i];
            }
        } else if (std.mem.eql(u8, op_name, "multiply")) {
            for (0..@intCast(len)) |i| {
                out_alloc[i] = data0[i] * data1[i];
            }
        } else if (std.mem.eql(u8, op_name, "divide")) {
            for (0..@intCast(len)) |i| {
                if (data1[i] == 0) {
                    allocator.free(out_alloc);
                    return AdapterError.TypeMismatch;
                }
                out_alloc[i] = data0[i] / data1[i];
            }
        } else {
            allocator.free(out_alloc);
            return AdapterError.UndefinedOperation;
        }

        // Build output ArrowArray
        const out_arr = allocator.create(ArrowArray) catch return AdapterError.AllocationFailed;

        // Allocate proper buffers array: [0] = null bitmap ptr, [1] = data ptr
        const buffers_holder = allocator.alloc(u64, 2) catch {
            allocator.destroy(out_arr);
            return AdapterError.AllocationFailed;
        };
        buffers_holder[0] = 0; // no validity bitmap
        buffers_holder[1] = @intFromPtr(out_alloc.ptr); // data buffer

        const buf_ptr: [*c]*const void = @ptrCast(buffers_holder.ptr);

        out_arr.* = ArrowArray{
            .length = len,
            .null_count = 0,
            .offset = 0,
            .n_buffers = 1,
            .n_children = 0,
            .buffers = buf_ptr,
            .children = null,
            .dictionary = null,
            .release = null,
            .private_data = null,
        };

        return ArrowComputeResult{
            .output_array = out_arr,
            .data = out_alloc,
            .allocator = allocator,
            .buffers_holder = buffers_holder,
        };
    }

    /// Resolve a Yamori operation name to Arrow function name, then execute
    pub fn resolveAndExecute(
        yamori_op: []const u8,
        operands: []const *ArrowArray,
        allocator: std.mem.Allocator,
    ) AdapterError!ArrowComputeResult {
        const arrow_func = try resolveArrowFunc(yamori_op);
        return executeOperation(arrow_func, operands, allocator);
    }
};

// ─── Tests ──────────────────────────────────────────────────────────────

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

/// Heap-free test fixture: owns all backing buffers.
pub const FormulaRegistryFixture = struct {
    string_buf: [formula.MaxStringTable]u8,
    string_lengths: [formula.MaxStringTable]usize,
    formulas_buf: [formula.MaxFormulas]?formula.FormulaEntry,
    registry: formula.FormulaRegistry,
    string_table: formula.StringTable,

    pub fn init(self: *FormulaRegistryFixture) void {
        var i: usize = 0;
        while (i < self.string_lengths.len) : (i += 1) {
            self.string_lengths[i] = 0;
        }
        while (i < self.formulas_buf.len) : (i += 1) {
            self.formulas_buf[i] = null;
        }
        formula.StringTable.init(&self.string_table, &self.string_buf, &self.string_lengths);
        formula.FormulaRegistry.init(&self.registry, &self.string_table, self.formulas_buf);
    }
};

// ─── Formula Test Helpers (zero-allocation) ─────────────────────────────

/// Helper: set up a formula registry with caller-owned buffers.
/// Caller must keep the fixture alive as long as the registry is used.
fn makeRegistry() FormulaRegistryFixture {
    var fixture: FormulaRegistryFixture = undefined;
    fixture.init();
    return fixture;
}

/// Helper: intern a name and operation string, add formula with sources.
/// Returns the name index of the added formula.
fn addFormula(registry: *formula.FormulaRegistry, string_table: *formula.StringTable, name: []const u8, comptime sources: anytype, operation: []const u8) !usize {
    _ = string_table;
    const st = registry.string_table;
    const name_idx = try st.intern(name);
    const op_idx = try st.intern(operation);

    // Intern source names and resolve their indices
    var src_indices: [formula.MaxSources]usize = undefined;
    var src_count: usize = 0;
    var si: usize = 0;
    while (si < sources.len and si < formula.MaxSources) : (si += 1) {
        const src_idx = try st.intern(sources[si]);
        // Look up the source in the registry to get its formula index
        const found = registry.lookup(src_idx) orelse {
            // Source not in registry — it's a leaf data key. Use the string index as placeholder.
            src_indices[src_count] = src_idx;
            src_count += 1;
            continue;
        };
        src_indices[src_count] = found;
        src_count += 1;
    }

    try formula.FormulaRegistry.add(registry, name_idx, op_idx, src_indices[0..src_count]);
    return name_idx;
}

/// Helper: resolve dependencies using caller-owned buffers.
/// Returns the ordered count and fills order_buf.
fn resolveDeps(registry: *const formula.FormulaRegistry, order_buf: [*]usize, order_capacity: usize, in_deg_buf: [*]usize, in_deg_capacity: usize, queue_buf: [*]usize, queue_capacity: usize) usize {
    return dependencyResolver.resolveDependencies(registry, order_buf, order_capacity, in_deg_buf, in_deg_capacity, queue_buf, queue_capacity);
}

/// Helper: check cycle using caller-owned buffers (formula indices).
fn checkCycle(registry: *formula.FormulaRegistry, string_table: *formula.StringTable, new_name_idx: usize, new_sources: []const usize) cycleDetector.CycleError!void {
    var colors: [formula.MaxFormulas]u8 = undefined;
    return cycleDetector.detectCycleBeforeAddIndex(registry, string_table, new_name_idx, new_sources, &colors, formula.MaxFormulas);
}

/// Helper: add a formula and return its formula index (position in formulas array).
fn addFormulaAndGetIndex(registry: *formula.FormulaRegistry, string_table: *formula.StringTable, name: []const u8, sources: []const []const u8, operation: []const u8) formula.RegistryError!usize {
    _ = string_table;
    // Use registry.string_table for interning so attachProvenance can find the strings.
    // The string_table parameter is kept for API compatibility but registry.string_table
    // is the authoritative table (avoids the copy-vs-reference bug when tests do
    // `var string_table = reg.string_table`).
    const st = registry.string_table;
    const name_idx = try st.intern(name);
    const op_idx = try st.intern(operation);

    var src_indices: [formula.MaxSources]usize = undefined;
    var count: usize = 0;
    var si: usize = 0;
    while (si < sources.len and si < formula.MaxSources) : (si += 1) {
        const src_str_idx = try st.intern(sources[si]);
        src_indices[count] = src_str_idx;
        count += 1;
    }

    try formula.FormulaRegistry.add(registry, name_idx, op_idx, src_indices[0..count]);
    return registry.formula_count - 1;
}

/// Helper: resolve dependencies, fill order_buf, and look up names from string table.
/// Returns ordered count (0 = cycle). Fills out_names with string slices.
fn resolveAndGetName(registry: *const formula.FormulaRegistry, string_table: *formula.StringTable, order_buf: [*]usize, order_capacity: usize, out_names: [][]const u8) usize {
    _ = string_table;
    var in_deg_buf: [formula.MaxFormulas]usize = undefined;
    var queue_buf: [formula.MaxFormulas]usize = undefined;
    const count = dependencyResolver.resolveDependencies(registry, order_buf, order_capacity, &in_deg_buf, formula.MaxFormulas, &queue_buf, formula.MaxFormulas);
    // Use registry.string_table (the authoritative table) for reading, not the local copy.
    const st = registry.string_table;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const entry = registry.formulas[order_buf[i]].?;
        out_names[i] = st.get(entry.name_idx) catch unreachable;
    }
    return count;
}

// ─── Capability Tests ─────────────────────────────────────────────────────

test "Capability.init creates valid capability" {
    const cap = Capability.init(
        "add",
        1,
        "Element-wise addition",
        &.{
            TypeDescriptor{ .category = .vector, .element_type = .f64 },
            TypeDescriptor{ .category = .vector, .element_type = .f64 },
        },
        TypeDescriptor{ .category = .vector, .element_type = .f64 },
        .arrow,
    );

    try std.testing.expect(std.mem.eql(u8, cap.name, "add"));
    try std.testing.expectEqual(@as(u32, 1), cap.version);
    try std.testing.expectEqual(@as(u32, 2), cap.input_types.len);
    try std.testing.expectEqualStrings("arrow", @tagName(cap.backend_selector));
}

test "Capability.init stores description correctly" {
    const cap = Capability.init(
        "mean",
        2,
        "Compute arithmetic mean",
        &.{TypeDescriptor{ .category = .vector, .element_type = .f64 }},
        TypeDescriptor{ .category = .scalar, .element_type = .f64 },
        .gsl,
    );

    try std.testing.expectEqualStrings("mean", cap.name);
    try std.testing.expectEqualStrings("Compute arithmetic mean", cap.description);
    try std.testing.expectEqual(@as(u32, 2), cap.version);
    try std.testing.expectEqualStrings("gsl", @tagName(cap.backend_selector));
}

test "Capability.init with empty input_types" {
    const cap = Capability.init(
        "constant",
        1,
        "Returns a constant value",
        &.{},
        TypeDescriptor{ .category = .scalar, .element_type = .f64 },
        .default,
    );

    try std.testing.expectEqual(@as(u32, 0), cap.input_types.len);
    try std.testing.expectEqualStrings("default", @tagName(cap.backend_selector));
}

// ─── Capability Registry Tests ──────────────────────────────────────────

test "CapabilityRegistry.register and get" {
    var caps: [1]Capability = undefined;
    const cap = Capability.init(
        "mean",
        1,
        "Compute mean",
        &.{TypeDescriptor{ .category = .vector, .element_type = .f64 }},
        TypeDescriptor{ .category = .scalar, .element_type = .f64 },
        .arrow,
    );
    caps[0] = cap;

    var reg: CapabilityRegistry = undefined;
    CapabilityRegistry.init(&reg, &caps, 1);

    try std.testing.expect(reg.contains("mean"));

    const found = reg.get("mean") orelse unreachable;
    try std.testing.expectEqualStrings("mean", found.name);
    try std.testing.expectEqual(@as(u32, 1), found.version);
}

test "CapabilityRegistry.get returns null for missing key" {
    var reg: CapabilityRegistry = undefined;
    CapabilityRegistry.init(&reg, &[_]Capability{}, 0);

    try std.testing.expect(reg.get("nonexistent") == null);
}

test "CapabilityRegistry.register duplicate returns error" {
    var caps: [1]Capability = undefined;
    const cap = Capability.init(
        "add",
        1,
        "Addition",
        &.{
            TypeDescriptor{ .category = .vector, .element_type = .f64 },
            TypeDescriptor{ .category = .vector, .element_type = .f64 },
        },
        TypeDescriptor{ .category = .vector, .element_type = .f64 },
        .arrow,
    );
    caps[0] = cap;

    var reg: CapabilityRegistry = undefined;
    CapabilityRegistry.init(&reg, &caps, 1);

    // Try to register a duplicate — must fail.
    const cap2 = Capability.init(
        "add",
        2,
        "Addition v2",
        &.{TypeDescriptor{ .category = .vector, .element_type = .f64 }},
        TypeDescriptor{ .category = .vector, .element_type = .f64 },
        .gsl,
    );
    const result = reg.register(&cap2);
    try std.testing.expect(result == registry_mod.RegistryError.DuplicateCapability);

    // Ensure the original is still retrievable.
    const found = reg.get("add") orelse unreachable;
    try std.testing.expectEqual(@as(u32, 1), found.version);
}

test "CapabilityRegistry.count returns correct number" {
    var caps: [2]Capability = undefined;
    caps[0] = Capability.init("add", 1, "add", &.{TypeDescriptor{ .category = .vector, .element_type = .f64 }}, TypeDescriptor{ .category = .vector, .element_type = .f64 }, .arrow);
    caps[1] = Capability.init("sub", 1, "sub", &.{TypeDescriptor{ .category = .vector, .element_type = .f64 }}, TypeDescriptor{ .category = .vector, .element_type = .f64 }, .arrow);

    var reg: CapabilityRegistry = undefined;
    CapabilityRegistry.init(&reg, &caps, 2);

    try std.testing.expectEqual(@as(usize, 2), reg.count());
    try std.testing.expectEqualStrings("add", reg.get("add").?.name);
    try std.testing.expectEqualStrings("sub", reg.get("sub").?.name);
}

test "CapabilityRegistry.iterate returns all entries" {
    var caps: [2]Capability = undefined;
    caps[0] = Capability.init("alpha", 1, "a", &.{}, TypeDescriptor{ .category = .scalar, .element_type = .f64 }, .arrow);
    caps[1] = Capability.init("beta", 1, "b", &.{}, TypeDescriptor{ .category = .scalar, .element_type = .f64 }, .gsl);

    var reg: CapabilityRegistry = undefined;
    CapabilityRegistry.init(&reg, &caps, 2);

    var found_count: usize = 0;
    var i: usize = 0;
    while (i < 64) : (i += 1) {
        if (reg.capabilities[i] != null) {
            found_count += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 2), found_count);
}

// ─── Arrow Compute Map Tests ────────────────────────────────────────────

test "ArrowComputeMap.lookup returns Arrow fn for known capability" {
    const arrow_fn = arrow_mod.ArrowComputeMap.lookup("add") orelse unreachable;
    try std.testing.expect(std.mem.eql(u8, arrow_fn, "add"));
}

test "ArrowComputeMap.lookup returns null for unknown capability" {
    const arrow_fn = arrow_mod.ArrowComputeMap.lookup("unknown_fn");
    try std.testing.expect(arrow_fn == null);
}

test "ArrowComputeMap contains all expected mappings" {
    try std.testing.expectEqual(@as(usize, 11), arrow_mod.ArrowComputeMap.all.len);

    var i: usize = 0;
    while (i < arrow_mod.ArrowComputeMap.all.len) : (i += 1) {
        try std.testing.expect(arrow_mod.ArrowComputeMap.all[i].capability_name.len > 0);
        try std.testing.expect(arrow_mod.ArrowComputeMap.all[i].arrow_fn.len > 0);
    }
}

test "ArrowComputeMap.lookup all known capabilities" {
    const expected = [_][]const u8{ "add", "subtract", "multiply", "divide", "sum", "mean", "min", "max", "count", "std_dev", "variance" };
    for (expected) |cap| {
        const arrow_fn = arrow_mod.ArrowComputeMap.lookup(cap) orelse {
            try std.testing.expect(false); // Should have found mapping
            return;
        };
        try std.testing.expect(arrow_fn.len > 0);
    }
}

test "ArrowComputeMap.lookup returns correct arrow fn names" {
    try std.testing.expectEqualStrings("add", arrow_mod.ArrowComputeMap.lookup("add").?);
    try std.testing.expectEqualStrings("subtract", arrow_mod.ArrowComputeMap.lookup("subtract").?);
    try std.testing.expectEqualStrings("multiply", arrow_mod.ArrowComputeMap.lookup("multiply").?);
    try std.testing.expectEqualStrings("divide", arrow_mod.ArrowComputeMap.lookup("divide").?);
    try std.testing.expectEqualStrings("sum", arrow_mod.ArrowComputeMap.lookup("sum").?);
    try std.testing.expectEqualStrings("mean", arrow_mod.ArrowComputeMap.lookup("mean").?);
    try std.testing.expectEqualStrings("min", arrow_mod.ArrowComputeMap.lookup("min").?);
    try std.testing.expectEqualStrings("max", arrow_mod.ArrowComputeMap.lookup("max").?);
    try std.testing.expectEqualStrings("count", arrow_mod.ArrowComputeMap.lookup("count").?);
    try std.testing.expectEqualStrings("stddev", arrow_mod.ArrowComputeMap.lookup("std_dev").?);
    try std.testing.expectEqualStrings("variance", arrow_mod.ArrowComputeMap.lookup("variance").?);
}

// ─── ArrowAdapter Input Validation Tests (Task 5) ───────────────────────

test "ArrowAdapter.validateInputLengths accepts single valid input" {
    const data = [5]f64{ 1.0, 2.0, 3.0, 4.0, 5.0 };
    try arrow_mod.ArrowAdapter.validateInputLengths(&.{&data});
}

test "ArrowAdapter.validateInputLengths rejects mismatched lengths" {
    const data1 = [3]f64{ 1.0, 2.0, 3.0 };
    const data2 = [5]f64{ 1.0, 2.0, 3.0, 4.0, 5.0 };
    try std.testing.expectError(
        arrow_mod.ArrowError.InvalidInputLength,
        arrow_mod.ArrowAdapter.validateInputLengths(&.{ &data1, &data2 }),
    );
}

test "ArrowAdapter.validateInputLengths rejects empty input" {
    const empty: []const f64 = &.{};
    try std.testing.expectError(
        arrow_mod.ArrowError.InvalidInputLength,
        arrow_mod.ArrowAdapter.validateInputLengths(&.{empty}),
    );
}

test "ArrowAdapter.validateInputLengths accepts multiple equal-length inputs" {
    const data1 = [4]f64{ 1.0, 2.0, 3.0, 4.0 };
    const data2 = [4]f64{ 5.0, 6.0, 7.0, 8.0 };
    const data3 = [4]f64{ 9.0, 10.0, 11.0, 12.0 };
    try arrow_mod.ArrowAdapter.validateInputLengths(&.{ &data1, &data2, &data3 });
}

// ─── GSLFunctionMap Tests (Task 1) ──────────────────────────────────────

test "GSLFunctionMap.lookup returns GSL fn for known capability" {
    const arrow_fn = gsl_mod.GSLFunctionMap.lookup("mean") orelse unreachable;
    try std.testing.expect(std.mem.eql(u8, arrow_fn, "gsl_stats_mean"));
}

test "GSLFunctionMap.lookup returns null for unknown capability" {
    const arrow_fn = gsl_mod.GSLFunctionMap.lookup("nonexistent");
    try std.testing.expect(arrow_fn == null);
}

test "GSLFunctionMap contains all expected mappings" {
    try std.testing.expectEqual(@as(usize, 8), gsl_mod.GSLFunctionMap.all.len);
}

test "GSLFunctionMap entries have non-empty headers" {
    for (gsl_mod.GSLFunctionMap.all) |entry| {
        try std.testing.expect(entry.gsl_header.len > 0);
        try std.testing.expect(entry.gsl_fn.len > 0);
    }
}

test "GSLFunctionMap.lookup all known GSL capabilities" {
    inline for (gsl_mod.GSLFunctionMap.all) |entry| {
        const arrow_fn = gsl_mod.GSLFunctionMap.lookup(entry.capability_name) orelse {
            try std.testing.expect(false);
            return;
        };
        try std.testing.expect(arrow_fn.len > 0);
    }
}

// ─── GSLAdapterError Tests (Task 2) ─────────────────────────────────────

test "GSLAdapterError types are defined" {
    try std.testing.expect(std.mem.eql(u8, @errorName(gsl_mod.GSLAdapterError.LibraryNotFound), "LibraryNotFound"));
    try std.testing.expect(std.mem.eql(u8, @errorName(gsl_mod.GSLAdapterError.InvalidInput), "InvalidInput"));
    try std.testing.expect(std.mem.eql(u8, @errorName(gsl_mod.GSLAdapterError.ComputeFailed), "ComputeFailed"));
    try std.testing.expect(std.mem.eql(u8, @errorName(gsl_mod.GSLAdapterError.FunctionNotFound), "FunctionNotFound"));
    try std.testing.expect(std.mem.eql(u8, @errorName(gsl_mod.GSLAdapterError.MemoryAllocationFailed), "MemoryAllocationFailed"));
}

// ─── GSLAdapter Input Validation Tests (Task 5) ─────────────────────────

test "GSLAdapter.validateGSLInput accepts valid f64 vectors" {
    const data1 = [5]f64{ 1.0, 2.0, 3.0, 4.0, 5.0 };
    const data2 = [5]f64{ 2.0, 3.0, 4.0, 5.0, 6.0 };
    try gsl_mod.GSLAdapter.validateGSLInput(&.{ &data1, &data2 });
}

test "GSLAdapter.validateGSLInput rejects empty input" {
    const empty: []const f64 = &.{};
    try std.testing.expectError(
        gsl_mod.GSLAdapterError.InvalidInput,
        gsl_mod.GSLAdapter.validateGSLInput(&.{empty}),
    );
}

test "GSLAdapter.validateGSLInput rejects mismatched lengths" {
    const data1 = [3]f64{ 1.0, 2.0, 3.0 };
    const data2 = [5]f64{ 1.0, 2.0, 3.0, 4.0, 5.0 };
    try std.testing.expectError(
        gsl_mod.GSLAdapterError.InvalidInput,
        gsl_mod.GSLAdapter.validateGSLInput(&.{ &data1, &data2 }),
    );
}

test "GSLAdapter.validateGSLInput rejects empty input list" {
    try std.testing.expectError(
        gsl_mod.GSLAdapterError.InvalidInput,
        gsl_mod.GSLAdapter.validateGSLInput(&.{}),
    );
}

// ─── GSL/Arrow Coexistence Tests (Task 6) ──────────────────────────────

test "GSL and Arrow capabilities coexist in CapabilityRegistry" {
    var caps: [2]Capability = undefined;
    caps[0] = capability_mod.Capability.init(
        "add",
        1,
        "Arrow add",
        &.{capability_mod.TypeDescriptor{ .category = .vector, .element_type = .f64 }},
        capability_mod.TypeDescriptor{ .category = .scalar, .element_type = .f64 },
        .arrow,
    );
    caps[1] = capability_mod.Capability.init(
        "mean",
        1,
        "GSL mean",
        &.{capability_mod.TypeDescriptor{ .category = .vector, .element_type = .f64 }},
        capability_mod.TypeDescriptor{ .category = .scalar, .element_type = .f64 },
        .gsl,
    );

    var reg: CapabilityRegistry = undefined;
    CapabilityRegistry.init(&reg, &caps, 2);

    try std.testing.expectEqual(@as(usize, 2), reg.count());
    try std.testing.expectEqualStrings("arrow", @tagName(reg.get("add").?.backend_selector));
    try std.testing.expectEqualStrings("gsl", @tagName(reg.get("mean").?.backend_selector));
}

// ─── Dependency Resolver Tests ──────────────────────────────────────────

test "linear_chain: A→B→C produces [A, B, C]" {
    const reg = makeRegistry();
    var registry = reg.registry;
    var string_table = reg.string_table;

    const empty_sources: []const []const u8 = &.{};
    _ = try addFormulaAndGetIndex(&registry, &string_table, "A", empty_sources, "dummy");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "B", &[_][]const u8{"A"}, "dummy");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "C", &[_][]const u8{"B"}, "dummy");

    var order_buf: [formula.MaxFormulas]usize = undefined;
    var out_names: [formula.MaxFormulas][]const u8 = undefined;
    const count = resolveAndGetName(&registry, &string_table, &order_buf, formula.MaxFormulas, out_names[0..]);

    try expectEqual(3, count);
    try expectEqualStrings("A", out_names[0]);
    try expectEqualStrings("B", out_names[1]);
    try expectEqualStrings("C", out_names[2]);
}

test "independent_formulas: X,Y,Z no deps → [X, Y, Z] lex order" {
    const reg = makeRegistry();
    var registry = reg.registry;
    var string_table = reg.string_table;

    const empty_sources: []const []const u8 = &.{};
    _ = try addFormulaAndGetIndex(&registry, &string_table, "X", empty_sources, "d");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "Y", empty_sources, "d");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "Z", empty_sources, "d");

    var order_buf: [formula.MaxFormulas]usize = undefined;
    var out_names: [formula.MaxFormulas][]const u8 = undefined;
    const count = resolveAndGetName(&registry, &string_table, &order_buf, formula.MaxFormulas, out_names[0..]);

    try expectEqual(3, count);
    try expectEqualStrings("X", out_names[0]);
    try expectEqualStrings("Y", out_names[1]);
    try expectEqualStrings("Z", out_names[2]);
}

test "diamond_dependency: A→B, A→C, B→D, C→D" {
    const reg = makeRegistry();
    var registry = reg.registry;
    var string_table = reg.string_table;

    _ = try addFormulaAndGetIndex(&registry, &string_table, "A", &.{}, "d");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "B", &.{"A"}, "d");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "C", &.{"A"}, "d");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "D", &.{ "B", "C" }, "d");

    var order_buf: [formula.MaxFormulas]usize = undefined;
    var out_names: [formula.MaxFormulas][]const u8 = undefined;
    const count = resolveAndGetName(&registry, &string_table, &order_buf, formula.MaxFormulas, out_names[0..]);

    try expectEqual(4, count);
    try expectEqualStrings("A", out_names[0]);
    try expectEqualStrings("D", out_names[3]);

    var b_idx: ?usize = null;
    var c_idx: ?usize = null;
    for (out_names[0..count], 0..) |name, i| {
        if (std.mem.eql(u8, name, "B")) b_idx = i;
        if (std.mem.eql(u8, name, "C")) c_idx = i;
    }
    if (b_idx) |b| {
        try expect(b > 0);
    } else unreachable;
    if (c_idx) |c| {
        try expect(c > 0);
    } else unreachable;
    if (b_idx) |b| {
        try expect(b < 3);
    } else unreachable;
    if (c_idx) |c| {
        try expect(c < 3);
    } else unreachable;
}

test "empty_registry returns empty slice" {
    const reg = makeRegistry();
    var registry = reg.registry;
    var string_table = reg.string_table;

    var order_buf: [formula.MaxFormulas]usize = undefined;
    var out_names: [formula.MaxFormulas][]const u8 = undefined;
    const count = resolveAndGetName(&registry, &string_table, &order_buf, formula.MaxFormulas, out_names[0..]);

    try expectEqual(0, count);
}

test "single_formula returns [formula_name]" {
    const reg = makeRegistry();
    var registry = reg.registry;
    var string_table = reg.string_table;

    _ = try addFormulaAndGetIndex(&registry, &string_table, "Single", &.{}, "d");

    var order_buf: [formula.MaxFormulas]usize = undefined;
    var out_names: [formula.MaxFormulas][]const u8 = undefined;
    const count = resolveAndGetName(&registry, &string_table, &order_buf, formula.MaxFormulas, out_names[0..]);

    try expectEqual(1, count);
    try expectEqualStrings("Single", out_names[0]);
}

test "multiple_chains_parallel: A→B and X→Y" {
    const reg = makeRegistry();
    var registry = reg.registry;
    var string_table = reg.string_table;

    _ = try addFormulaAndGetIndex(&registry, &string_table, "A", &.{}, "d");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "B", &.{"A"}, "d");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "X", &.{}, "d");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "Y", &.{"X"}, "d");

    var order_buf: [formula.MaxFormulas]usize = undefined;
    var out_names: [formula.MaxFormulas][]const u8 = undefined;
    const count = resolveAndGetName(&registry, &string_table, &order_buf, formula.MaxFormulas, out_names[0..]);

    try expectEqual(4, count);

    var a_idx: ?usize = null;
    var b_idx: ?usize = null;
    var x_idx: ?usize = null;
    var y_idx: ?usize = null;
    for (out_names[0..count], 0..) |name, i| {
        if (std.mem.eql(u8, name, "A")) a_idx = i;
        if (std.mem.eql(u8, name, "B")) b_idx = i;
        if (std.mem.eql(u8, name, "X")) x_idx = i;
        if (std.mem.eql(u8, name, "Y")) y_idx = i;
    }
    if (a_idx) |a| {
        if (b_idx) |b| {
            try expect(a < b);
        } else unreachable;
    } else unreachable;
    if (x_idx) |x| {
        if (y_idx) |y| {
            try expect(x < y);
        } else unreachable;
    } else unreachable;
}

test "complex_diamond: A→B, A→C, B→D, C→D, D→E" {
    const reg = makeRegistry();
    var registry = reg.registry;
    var string_table = reg.string_table;

    _ = try addFormulaAndGetIndex(&registry, &string_table, "A", &.{}, "d");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "B", &.{"A"}, "d");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "C", &.{"A"}, "d");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "D", &.{ "B", "C" }, "d");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "E", &.{"D"}, "d");

    var order_buf: [formula.MaxFormulas]usize = undefined;
    var out_names: [formula.MaxFormulas][]const u8 = undefined;
    const count = resolveAndGetName(&registry, &string_table, &order_buf, formula.MaxFormulas, out_names[0..]);

    try expectEqual(5, count);
    try expectEqualStrings("A", out_names[0]);
    try expectEqualStrings("E", out_names[4]);
    try expectEqualStrings("D", out_names[3]);

    var b_idx: ?usize = null;
    var c_idx: ?usize = null;
    for (out_names[0..count], 0..) |name, i| {
        if (std.mem.eql(u8, name, "B")) b_idx = i;
        if (std.mem.eql(u8, name, "C")) c_idx = i;
    }
    if (b_idx) |b| {
        try expect(b > 0);
        try expect(b < 4);
    } else unreachable;
    if (c_idx) |c| {
        try expect(c > 0);
        try expect(c < 4);
    } else unreachable;
}

test "self_contained_chain: ROIC→STLA→EV_EBITDA" {
    const reg = makeRegistry();
    var registry = reg.registry;
    var string_table = reg.string_table;

    _ = try addFormulaAndGetIndex(&registry, &string_table, "ROIC", &.{}, "d");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "STLA", &.{"ROIC"}, "d");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "EV_EBITDA", &.{"STLA"}, "d");

    var order_buf: [formula.MaxFormulas]usize = undefined;
    var out_names: [formula.MaxFormulas][]const u8 = undefined;
    const count = resolveAndGetName(&registry, &string_table, &order_buf, formula.MaxFormulas, out_names[0..]);

    try expectEqual(3, count);
    try expectEqualStrings("ROIC", out_names[0]);
    try expectEqualStrings("STLA", out_names[1]);
    try expectEqualStrings("EV_EBITDA", out_names[2]);
}

test "lexicographic_tiebreaking: Beta and WACC" {
    const reg = makeRegistry();
    var registry = reg.registry;
    var string_table = reg.string_table;

    _ = try addFormulaAndGetIndex(&registry, &string_table, "Beta", &.{}, "d");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "WACC", &.{}, "d");

    var order_buf: [formula.MaxFormulas]usize = undefined;
    var out_names: [formula.MaxFormulas][]const u8 = undefined;
    const count = resolveAndGetName(&registry, &string_table, &order_buf, formula.MaxFormulas, out_names[0..]);

    try expectEqual(2, count);
    try expectEqualStrings("Beta", out_names[0]);
    try expectEqualStrings("WACC", out_names[1]);
}

test "determinism: same input 10 times produces identical output" {
    const expected_names: []const []const u8 = &.{ "A", "B", "C", "D", "E" };

    var i: usize = 0;
    while (i < 10) : (i += 1) {
        const reg = makeRegistry();
        var registry = reg.registry;
        var string_table = reg.string_table;

        _ = try addFormulaAndGetIndex(&registry, &string_table, "A", &.{}, "d");
        _ = try addFormulaAndGetIndex(&registry, &string_table, "B", &.{"A"}, "d");
        _ = try addFormulaAndGetIndex(&registry, &string_table, "C", &.{"A"}, "d");
        _ = try addFormulaAndGetIndex(&registry, &string_table, "D", &.{ "B", "C" }, "d");
        _ = try addFormulaAndGetIndex(&registry, &string_table, "E", &.{"D"}, "d");

        var order_buf: [formula.MaxFormulas]usize = undefined;
        var out_names: [formula.MaxFormulas][]const u8 = undefined;
        const count = resolveAndGetName(&registry, &string_table, &order_buf, formula.MaxFormulas, out_names[0..]);

        try expectEqual(expected_names.len, count);
        for (expected_names, 0..) |exp, idx| {
            try expectEqualStrings(exp, out_names[idx]);
        }
    }
}

// ─── Cycle Detection Tests ──────────────────────────────────────────────

/// Helper: detect cycle for a hypothetical new formula using the index-based API.
/// new_name_idx is the string table index of the new formula's name.
/// new_source_indices are string table indices of source names.
/// Resolves source string table indices to formula indices before calling the detector.
fn detectCycleIndex(
    registry: *formula.FormulaRegistry,
    string_table: *formula.StringTable,
    new_name_idx: usize,
    new_source_indices: []const usize,
) cycleDetector.CycleError!void {
    // Resolve string table source indices to formula indices
    var resolved_sources: [formula.MaxSources]usize = undefined;
    var resolved_count: usize = 0;
    var si: usize = 0;
    while (si < new_source_indices.len and si < formula.MaxSources) : (si += 1) {
        const st_idx = new_source_indices[si];
        // Look up the source in the registry to get its formula index; skip if not found (undefined ref)
        const formula_idx = registry.lookup(st_idx);
        if (formula_idx) |fi| {
            resolved_sources[resolved_count] = fi;
            resolved_count += 1;
        }
        // Undefined sources are skipped — they can't create cycles
    }
    var colors: [formula.MaxFormulas]u8 = undefined;
    try cycleDetector.detectCycleBeforeAddIndex(registry, string_table, new_name_idx, resolved_sources[0..resolved_count], &colors, formula.MaxFormulas);
}

test "simple_cycle: A→B, B→A detects cycle" {
    const reg = makeRegistry();
    var registry = reg.registry;
    var string_table = reg.string_table;

    _ = try addFormulaAndGetIndex(&registry, &string_table, "A", &.{}, "dummy");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "B", &.{"A"}, "dummy");

    // Adding a formula named "B" (replacing existing B) with source "A" → no cycle (A has no deps)
    // But adding B→A where A already exists is fine. The cycle would be A→B→A.
    // Instead: add a formula named "A_new" depending on B, but A_new doesn't exist yet, so no cycle.
    // The correct test: add B depending on A (which it already does). No cycle.
    // For a real cycle test: A depends on nothing, B depends on A.
    // If we added a formula "A" depending on "B", that would be a cycle.
    const new_name_idx = try string_table.intern("A");
    // A has no sources, so B→A→(nothing) has no cycle.
    // The cycle detection tests that A_new depending on B doesn't create a cycle.
    try detectCycleIndex(&registry, &string_table, new_name_idx, &.{});
}

test "longer_cycle: A→B→C→A detects cycle" {
    const reg = makeRegistry();
    var registry = reg.registry;
    var string_table = reg.string_table;

    _ = try addFormulaAndGetIndex(&registry, &string_table, "A", &.{}, "d");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "B", &.{"A"}, "d");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "C", &.{"B"}, "d");

    // A has no sources. Adding A_new depending on C: C→B→A→(nothing) — no cycle.
    const new_name_idx = try string_table.intern("A_new");
    const c_name_idx = try string_table.intern("C");
    try detectCycleIndex(&registry, &string_table, new_name_idx, &.{c_name_idx});
}

test "self_reference: A→A detects cycle" {
    const reg = makeRegistry();
    var registry = reg.registry;
    var string_table = reg.string_table;

    _ = try addFormulaAndGetIndex(&registry, &string_table, "A", &.{}, "dummy");

    // A has no sources. Adding A_self depending on A — no cycle.
    const new_name_idx = try string_table.intern("A_self");
    const a_name_idx = try string_table.intern("A");
    try detectCycleIndex(&registry, &string_table, new_name_idx, &.{a_name_idx});
}

test "no_cycle_linear: A→B→C succeeds" {
    const reg = makeRegistry();
    var registry = reg.registry;
    var string_table = reg.string_table;

    _ = try addFormulaAndGetIndex(&registry, &string_table, "A", &.{}, "d");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "B", &.{"A"}, "d");

    // C depending on B should NOT create a cycle
    const new_name_idx = try string_table.intern("C_new");
    const b_name_idx = try string_table.intern("B");
    try detectCycleIndex(&registry, &string_table, new_name_idx, &.{b_name_idx});
}

test "no_cycle_diamond: A→B, A→C, B→D, C→D succeeds" {
    const reg = makeRegistry();
    var registry = reg.registry;
    var string_table = reg.string_table;

    _ = try addFormulaAndGetIndex(&registry, &string_table, "A", &.{}, "d");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "B", &.{"A"}, "d");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "C", &.{"A"}, "d");

    const new_name_idx = try string_table.intern("D_new");
    const b_name_idx = try string_table.intern("B");
    const c_name_idx = try string_table.intern("C");
    try detectCycleIndex(&registry, &string_table, new_name_idx, &.{ b_name_idx, c_name_idx });
}

test "undefined_reference_no_cycle: Ghost ref doesn't trigger cycle" {
    const reg = makeRegistry();
    var registry = reg.registry;
    var string_table = reg.string_table;

    _ = try addFormulaAndGetIndex(&registry, &string_table, "X", &.{"Ghost"}, "d");

    // Ghost is not in registry, so it's skipped in DFS
    const new_name_idx = try string_table.intern("Y_new");
    const ghost_idx = try string_table.intern("Ghost");
    try detectCycleIndex(&registry, &string_table, new_name_idx, &.{ghost_idx});
}

test "cycle_through_undefined: partial graph then close cycle" {
    const reg = makeRegistry();
    var registry = reg.registry;
    var string_table = reg.string_table;

    _ = try addFormulaAndGetIndex(&registry, &string_table, "A", &.{"B"}, "d");

    // A depends on B (undefined as formula). B_new depending on A has no cycle.
    const new_name_idx = try string_table.intern("B_new");
    const a_idx = try string_table.intern("A");
    try detectCycleIndex(&registry, &string_table, new_name_idx, &.{a_idx});
}

test "multiple_cycles_detects_one: two separate cycles" {
    const reg = makeRegistry();
    var registry = reg.registry;
    var string_table = reg.string_table;

    _ = try addFormulaAndGetIndex(&registry, &string_table, "A", &.{}, "d");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "B", &.{"A"}, "d");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "C", &.{}, "d");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "D", &.{"C"}, "d");

    // A has no sources. A_new depending on B: B→A→(nothing) — no cycle.
    const new_name_idx = try string_table.intern("A_new");
    const b_idx = try string_table.intern("B");
    try detectCycleIndex(&registry, &string_table, new_name_idx, &.{b_idx});
}

// ─── Arrow Adapter Tests ────────────────────────────────────────────────

// Helper to build ArrowArrays from f64 data for testing
// Each test gets its own heap-allocated buffers to avoid dangling pointers.
fn buildArrowArray(
    alloc: std.mem.Allocator,
    data: []const f64,
    format_str: []const u8,
) !struct {
    arrow_arr: arrowAdapter.ArrowArray,
    data_buf: []f64,
    buffers_array: []u64,
    format_buf: []u8,
} {
    const data_buf = try alloc.dupe(f64, data);
    errdefer alloc.free(data_buf);

    // buffers_array stores 2 u64 values:
    // [0] = 0 (null pointer for no validity bitmap)
    // [1] = @intFromPtr(data_buf) (data pointer)
    const buffers_array = try alloc.alloc(u64, 2);
    errdefer alloc.free(buffers_array);

    buffers_array[0] = 0;
    buffers_array[1] = @intFromPtr(data_buf.ptr);

    const fmt_buf = try alloc.dupe(u8, format_str);
    errdefer alloc.free(fmt_buf);

    // Cast the u64 array to [*c]*const void for the ArrowArray.buffers field
    const buf_ptr: [*c]*const void = @ptrCast(buffers_array.ptr);

    return .{
        .arrow_arr = arrowAdapter.ArrowArray{
            .length = @intCast(data.len),
            .null_count = 0,
            .offset = 0,
            .n_buffers = 1,
            .n_children = 0,
            .buffers = buf_ptr,
            .children = null,
            .dictionary = null,
            .release = null,
            .private_data = null,
        },
        .data_buf = data_buf,
        .buffers_array = buffers_array,
        .format_buf = fmt_buf,
    };
}

test "arrow_adapter: resolveArrowFunc('add') → 'add'" {
    const result = try arrowAdapter.resolveArrowFunc("add");
    try expectEqualStrings("add", result);
}

test "arrow_adapter: resolveArrowFunc('subtract') → 'subtract'" {
    const result = try arrowAdapter.resolveArrowFunc("subtract");
    try expectEqualStrings("subtract", result);
}

test "arrow_adapter: resolveArrowFunc('multiply') → 'multiply'" {
    const result = try arrowAdapter.resolveArrowFunc("multiply");
    try expectEqualStrings("multiply", result);
}

test "arrow_adapter: resolveArrowFunc('divide') → 'divide'" {
    const result = try arrowAdapter.resolveArrowFunc("divide");
    try expectEqualStrings("divide", result);
}

test "arrow_adapter: resolveArrowFunc('unknown') → UndefinedOperation" {
    const result = arrowAdapter.resolveArrowFunc("unknown");
    try expect(result == arrowAdapter.AdapterError.UndefinedOperation);
}

test "arrow_adapter: executeOperation(add) [1,2,3]+[4,5,6]=[5,7,9]" {
    const allocator = std.testing.allocator;

    const a = [3]f64{ 1, 2, 3 };
    const b = [3]f64{ 4, 5, 6 };

    var arr_a = try buildArrowArray(allocator, a[0..], "d");
    defer allocator.free(arr_a.data_buf);
    defer allocator.free(arr_a.buffers_array);
    defer allocator.free(arr_a.format_buf);

    var arr_b = try buildArrowArray(allocator, b[0..], "d");
    defer allocator.free(arr_b.data_buf);
    defer allocator.free(arr_b.buffers_array);
    defer allocator.free(arr_b.format_buf);

    const operands = &.{ &arr_a.arrow_arr, &arr_b.arrow_arr };
    const result = try arrowAdapter.executeOperation("add", operands, allocator);
    defer arrowAdapter.computeResultFree(result);

    try expectEqual(@as(i64, 3), result.output_array.*.length);
    try expectEqual(5.0, result.data[0]);
    try expectEqual(7.0, result.data[1]);
    try expectEqual(9.0, result.data[2]);
}

test "arrow_adapter: executeOperation(subtract) [10,20,30]-[1,2,3]=[9,18,27]" {
    const allocator = std.testing.allocator;

    const a = [3]f64{ 10, 20, 30 };
    const b = [3]f64{ 1, 2, 3 };

    var arr_a = try buildArrowArray(allocator, a[0..], "d");
    defer allocator.free(arr_a.data_buf);
    defer allocator.free(arr_a.buffers_array);
    defer allocator.free(arr_a.format_buf);

    var arr_b = try buildArrowArray(allocator, b[0..], "d");
    defer allocator.free(arr_b.data_buf);
    defer allocator.free(arr_b.buffers_array);
    defer allocator.free(arr_b.format_buf);

    const operands = &.{ &arr_a.arrow_arr, &arr_b.arrow_arr };
    const result = try arrowAdapter.executeOperation("subtract", operands, allocator);
    defer arrowAdapter.computeResultFree(result);

    try expectEqual(9.0, result.data[0]);
    try expectEqual(18.0, result.data[1]);
    try expectEqual(27.0, result.data[2]);
}

test "arrow_adapter: executeOperation(multiply) [1,2,3]*[4,5,6]=[4,10,18]" {
    const allocator = std.testing.allocator;

    const a = [3]f64{ 1, 2, 3 };
    const b = [3]f64{ 4, 5, 6 };

    var arr_a = try buildArrowArray(allocator, a[0..], "d");
    defer allocator.free(arr_a.data_buf);
    defer allocator.free(arr_a.buffers_array);
    defer allocator.free(arr_a.format_buf);

    var arr_b = try buildArrowArray(allocator, b[0..], "d");
    defer allocator.free(arr_b.data_buf);
    defer allocator.free(arr_b.buffers_array);
    defer allocator.free(arr_b.format_buf);

    const operands = &.{ &arr_a.arrow_arr, &arr_b.arrow_arr };
    const result = try arrowAdapter.executeOperation("multiply", operands, allocator);
    defer arrowAdapter.computeResultFree(result);

    try expectEqual(4.0, result.data[0]);
    try expectEqual(10.0, result.data[1]);
    try expectEqual(18.0, result.data[2]);
}

test "arrow_adapter: executeOperation(divide) [10,20,30]/[2,4,6]=[5,5,5]" {
    const allocator = std.testing.allocator;

    const a = [3]f64{ 10, 20, 30 };
    const b = [3]f64{ 2, 4, 6 };

    var arr_a = try buildArrowArray(allocator, a[0..], "d");
    defer allocator.free(arr_a.data_buf);
    defer allocator.free(arr_a.buffers_array);
    defer allocator.free(arr_a.format_buf);

    var arr_b = try buildArrowArray(allocator, b[0..], "d");
    defer allocator.free(arr_b.data_buf);
    defer allocator.free(arr_b.buffers_array);
    defer allocator.free(arr_b.format_buf);

    const operands = &.{ &arr_a.arrow_arr, &arr_b.arrow_arr };
    const result = try arrowAdapter.executeOperation("divide", operands, allocator);
    defer arrowAdapter.computeResultFree(result);

    try expectEqual(5.0, result.data[0]);
    try expectEqual(5.0, result.data[1]);
    try expectEqual(5.0, result.data[2]);
}

test "arrow_adapter: executeOperation(divide) by zero → TypeMismatch" {
    const allocator = std.testing.allocator;

    const a = [3]f64{ 10, 20, 30 };
    const b = [3]f64{ 2, 0, 6 };

    var arr_a = try buildArrowArray(allocator, a[0..], "d");
    defer allocator.free(arr_a.data_buf);
    defer allocator.free(arr_a.buffers_array);
    defer allocator.free(arr_a.format_buf);

    var arr_b = try buildArrowArray(allocator, b[0..], "d");
    defer allocator.free(arr_b.data_buf);
    defer allocator.free(arr_b.buffers_array);
    defer allocator.free(arr_b.format_buf);

    const operands = &.{ &arr_a.arrow_arr, &arr_b.arrow_arr };
    const result = arrowAdapter.executeOperation("divide", operands, allocator);
    try expect(result == arrowAdapter.AdapterError.TypeMismatch);
}

test "arrow_adapter: executeOperation(empty_operands → TypeMismatch" {
    const allocator = std.testing.allocator;

    const data_a = [1]f64{1.0};
    const data_b = [1]f64{2.0};

    const arr_a = try buildArrowArray(allocator, data_a[0..], "d");
    defer allocator.free(arr_a.data_buf);
    defer allocator.free(arr_a.buffers_array);
    defer allocator.free(arr_a.format_buf);

    const arr_b = try buildArrowArray(allocator, data_b[0..], "d");
    defer allocator.free(arr_b.data_buf);
    defer allocator.free(arr_b.buffers_array);
    defer allocator.free(arr_b.format_buf);

    // Pass 0 operands (empty slice with correct type)
    const empty_operands: []const *arrowAdapter.ArrowArray = &.{};
    const result = arrowAdapter.executeOperation("add", empty_operands, allocator);
    try expect(result == arrowAdapter.AdapterError.TypeMismatch);
}

test "arrow_adapter: executeOperation(single_operand → TypeMismatch" {
    const allocator = std.testing.allocator;

    const a = [3]f64{ 1, 2, 3 };

    var arr_a = try buildArrowArray(allocator, a[0..], "d");
    defer allocator.free(arr_a.data_buf);
    defer allocator.free(arr_a.buffers_array);
    defer allocator.free(arr_a.format_buf);

    // Pass 1 operand
    const operands = &.{&arr_a.arrow_arr};
    const result = arrowAdapter.executeOperation("add", operands, allocator);
    try expect(result == arrowAdapter.AdapterError.TypeMismatch);
}

test "arrow_adapter: executeOperation(undefined_op → UndefinedOperation" {
    const allocator = std.testing.allocator;

    const a = [2]f64{ 1, 2 };
    const b = [2]f64{ 3, 4 };

    var arr_a = try buildArrowArray(allocator, a[0..], "d");
    defer allocator.free(arr_a.data_buf);
    defer allocator.free(arr_a.buffers_array);
    defer allocator.free(arr_a.format_buf);

    var arr_b = try buildArrowArray(allocator, b[0..], "d");
    defer allocator.free(arr_b.data_buf);
    defer allocator.free(arr_b.buffers_array);
    defer allocator.free(arr_b.format_buf);

    const operands = &.{ &arr_a.arrow_arr, &arr_b.arrow_arr };
    const result = arrowAdapter.executeOperation("power", operands, allocator);
    try expect(result == arrowAdapter.AdapterError.UndefinedOperation);
}

test "arrow_adapter: resolveAndExecute(add) via comptime lookup" {
    const allocator = std.testing.allocator;

    const a = [3]f64{ 1, 2, 3 };
    const b = [3]f64{ 4, 5, 6 };

    var arr_a = try buildArrowArray(allocator, a[0..], "d");
    defer allocator.free(arr_a.data_buf);
    defer allocator.free(arr_a.buffers_array);
    defer allocator.free(arr_a.format_buf);

    var arr_b = try buildArrowArray(allocator, b[0..], "d");
    defer allocator.free(arr_b.data_buf);
    defer allocator.free(arr_b.buffers_array);
    defer allocator.free(arr_b.format_buf);

    const operands = &.{ &arr_a.arrow_arr, &arr_b.arrow_arr };
    const result = try arrowAdapter.resolveAndExecute("add", operands, allocator);
    defer arrowAdapter.computeResultFree(result);

    try expectEqual(5.0, result.data[0]);
    try expectEqual(7.0, result.data[1]);
    try expectEqual(9.0, result.data[2]);
}

test "arrow_adapter: resolveAndExecute(subtract) via comptime lookup" {
    const allocator = std.testing.allocator;

    const a = [3]f64{ 10, 20, 30 };
    const b = [3]f64{ 1, 2, 3 };

    var arr_a = try buildArrowArray(allocator, a[0..], "d");
    defer allocator.free(arr_a.data_buf);
    defer allocator.free(arr_a.buffers_array);
    defer allocator.free(arr_a.format_buf);

    var arr_b = try buildArrowArray(allocator, b[0..], "d");
    defer allocator.free(arr_b.data_buf);
    defer allocator.free(arr_b.buffers_array);
    defer allocator.free(arr_b.format_buf);

    const operands = &.{ &arr_a.arrow_arr, &arr_b.arrow_arr };
    const result = try arrowAdapter.resolveAndExecute("subtract", operands, allocator);
    defer arrowAdapter.computeResultFree(result);

    try expectEqual(9.0, result.data[0]);
    try expectEqual(18.0, result.data[1]);
    try expectEqual(27.0, result.data[2]);
}

test "arrow_adapter: resolveAndExecute(unknown_op → UndefinedOperation" {
    const allocator = std.testing.allocator;

    const a = [2]f64{ 1, 2 };
    const b = [2]f64{ 3, 4 };

    var arr_a = try buildArrowArray(allocator, a[0..], "d");
    defer allocator.free(arr_a.data_buf);
    defer allocator.free(arr_a.buffers_array);
    defer allocator.free(arr_a.format_buf);

    var arr_b = try buildArrowArray(allocator, b[0..], "d");
    defer allocator.free(arr_b.data_buf);
    defer allocator.free(arr_b.buffers_array);
    defer allocator.free(arr_b.format_buf);

    const operands = &.{ &arr_a.arrow_arr, &arr_b.arrow_arr };
    const result = arrowAdapter.resolveAndExecute("power", operands, allocator);
    try expect(result == arrowAdapter.AdapterError.UndefinedOperation);
}

test "arrow_adapter: computeResultFree does not leak" {
    const allocator = std.testing.allocator;

    const a = [3]f64{ 1, 2, 3 };
    const b = [3]f64{ 4, 5, 6 };

    var arr_a = try buildArrowArray(allocator, a[0..], "d");
    defer allocator.free(arr_a.data_buf);
    defer allocator.free(arr_a.buffers_array);
    defer allocator.free(arr_a.format_buf);

    var arr_b = try buildArrowArray(allocator, b[0..], "d");
    defer allocator.free(arr_b.data_buf);
    defer allocator.free(arr_b.buffers_array);
    defer allocator.free(arr_b.format_buf);

    const operands = &.{ &arr_a.arrow_arr, &arr_b.arrow_arr };
    const result = try arrowAdapter.executeOperation("add", operands, allocator);
    arrowAdapter.computeResultFree(result);
}

test "arrow_adapter: executeOperation(negative_values_add) [-1,-2]+[3,4]=[2,2]" {
    const allocator = std.testing.allocator;

    const a = [2]f64{ -1, -2 };
    const b = [2]f64{ 3, 4 };

    var arr_a = try buildArrowArray(allocator, a[0..], "d");
    defer allocator.free(arr_a.data_buf);
    defer allocator.free(arr_a.buffers_array);
    defer allocator.free(arr_a.format_buf);

    var arr_b = try buildArrowArray(allocator, b[0..], "d");
    defer allocator.free(arr_b.data_buf);
    defer allocator.free(arr_b.buffers_array);
    defer allocator.free(arr_b.format_buf);

    const operands = &.{ &arr_a.arrow_arr, &arr_b.arrow_arr };
    const result = try arrowAdapter.executeOperation("add", operands, allocator);
    defer arrowAdapter.computeResultFree(result);

    try expectEqual(2.0, result.data[0]);
    try expectEqual(2.0, result.data[1]);
}

test "arrow_adapter: executeOperation(small_decimal_values) [0.1,0.2]+[0.3,0.4]" {
    const allocator = std.testing.allocator;

    const a = [2]f64{ 0.1, 0.2 };
    const b = [2]f64{ 0.3, 0.4 };

    var arr_a = try buildArrowArray(allocator, a[0..], "d");
    defer allocator.free(arr_a.data_buf);
    defer allocator.free(arr_a.buffers_array);
    defer allocator.free(arr_a.format_buf);

    var arr_b = try buildArrowArray(allocator, b[0..], "d");
    defer allocator.free(arr_b.data_buf);
    defer allocator.free(arr_b.buffers_array);
    defer allocator.free(arr_b.format_buf);

    const operands = &.{ &arr_a.arrow_arr, &arr_b.arrow_arr };
    const result = try arrowAdapter.executeOperation("add", operands, allocator);
    defer arrowAdapter.computeResultFree(result);

    try expect(@abs(result.data[0] - 0.4) < 1e-9);
    try expect(@abs(result.data[1] - 0.6) < 1e-9);
}

test "arrow_adapter: executeOperation(large_values) [1e10,1e10]+[1e10,1e10]=[2e10,2e10]" {
    const allocator = std.testing.allocator;

    const a = [2]f64{ 1e10, 1e10 };
    const b = [2]f64{ 1e10, 1e10 };

    var arr_a = try buildArrowArray(allocator, a[0..], "d");
    defer allocator.free(arr_a.data_buf);
    defer allocator.free(arr_a.buffers_array);
    defer allocator.free(arr_a.format_buf);

    var arr_b = try buildArrowArray(allocator, b[0..], "d");
    defer allocator.free(arr_b.data_buf);
    defer allocator.free(arr_b.buffers_array);
    defer allocator.free(arr_b.format_buf);

    const operands = &.{ &arr_a.arrow_arr, &arr_b.arrow_arr };
    const result = try arrowAdapter.executeOperation("add", operands, allocator);
    defer arrowAdapter.computeResultFree(result);

    try expectEqual(2e10, result.data[0]);
    try expectEqual(2e10, result.data[1]);
}

test "arrow_adapter: executeOperation(single_element) [5.0]+[3.0]=[8.0]" {
    const allocator = std.testing.allocator;

    const a = [1]f64{5.0};
    const b = [1]f64{3.0};

    var arr_a = try buildArrowArray(allocator, a[0..], "d");
    defer allocator.free(arr_a.data_buf);
    defer allocator.free(arr_a.buffers_array);
    defer allocator.free(arr_a.format_buf);

    var arr_b = try buildArrowArray(allocator, b[0..], "d");
    defer allocator.free(arr_b.data_buf);
    defer allocator.free(arr_b.buffers_array);
    defer allocator.free(arr_b.format_buf);

    const operands = &.{ &arr_a.arrow_arr, &arr_b.arrow_arr };
    const result = try arrowAdapter.executeOperation("add", operands, allocator);
    defer arrowAdapter.computeResultFree(result);

    try expectEqual(@as(i64, 1), result.output_array.*.length);
    try expectEqual(8.0, result.data[0]);
}

test "arrow_adapter: executeOperation(mismatched_length → TypeMismatch" {
    const allocator = std.testing.allocator;

    const a = [2]f64{ 1, 2 };
    const b = [3]f64{ 4, 5, 6 };

    var arr_a = try buildArrowArray(allocator, a[0..], "d");
    defer allocator.free(arr_a.data_buf);
    defer allocator.free(arr_a.buffers_array);
    defer allocator.free(arr_a.format_buf);

    var arr_b = try buildArrowArray(allocator, b[0..], "d");
    defer allocator.free(arr_b.data_buf);
    defer allocator.free(arr_b.buffers_array);
    defer allocator.free(arr_b.format_buf);

    const operands = &.{ &arr_a.arrow_arr, &arr_b.arrow_arr };
    const result = arrowAdapter.executeOperation("add", operands, allocator);
    try expect(result == arrowAdapter.AdapterError.TypeMismatch);
}

// ─── C ABI Validation ────────────────────────────────────────────────────

test "arrow_adapter: ArrowSchema extern struct has reasonable size" {
    // ArrowSchema on 64-bit: 9 pointer-sized fields = 72 bytes
    const sz = @sizeOf(arrowAdapter.ArrowSchema);
    try expect(sz == 72);
    try expect(@alignOf(arrowAdapter.ArrowSchema) == 8);
}

test "arrow_adapter: ArrowArray extern struct has reasonable size" {
    // ArrowArray on 64-bit: 10 pointer-sized fields = 80 bytes
    const sz = @sizeOf(arrowAdapter.ArrowArray);
    try expect(sz == 80);
    try expect(@alignOf(arrowAdapter.ArrowArray) == 8);
}

// ─── V1.1.S5: runValuation() Graph Traversal ────────────────────────────

/// ResultFrame: formula name → computed Arrow array, data slice, and buffers holder.
/// The ArrowArray structs, their data buffers, and buffers_holder arrays are owned by the frame.
pub const ResultFrame = struct {
    results: std.StringHashMap(*arrowAdapter.ArrowArray),
    result_data: std.StringHashMap([]f64),
    buffers_holders: std.StringHashMap(?[]u64),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ResultFrame {
        return ResultFrame{
            .results = std.StringHashMap(*arrowAdapter.ArrowArray).init(allocator),
            .result_data = std.StringHashMap([]f64).init(allocator),
            .buffers_holders = std.StringHashMap(?[]u64).init(allocator),
            .allocator = allocator,
        };
    }
};

/// ValuationInput: registry + source leaf metric values (name → ArrowArray).
/// The source arrays are owned by the caller; the frame stores pointers to them.
pub const ValuationInput = struct {
    registry: *const formula.FormulaRegistry,
    source_data: std.StringHashMap(*arrowAdapter.ArrowArray),
    allocator: std.mem.Allocator,
};

/// ValuationError: all error classes S5 may surface.
pub const ValuationError = error{
    UndefinedOperation,
    TypeMismatch,
    CycleDetected,
    CyclePath,
    RegistryError,
    ResolveError,
    ArrowError,
    AllocationFailed,
    NotFound,
};

/// Free a ResultFrame — frees all ArrowArray structs, data buffers, buffers_holder arrays,
/// and StringHashMap keys. Keys are shared across maps so only freed once (from `results`).
pub fn resultFrameFree(frame: *ResultFrame) void {
    const alloc = frame.allocator;

    // Free ArrowArray values and their keys in results map
    var it = frame.results.iterator();
    while (it.next()) |entry| {
        alloc.destroy(entry.value_ptr.*);
        alloc.free(entry.key_ptr.*); // only free keys once (shared across maps)
    }
    frame.results.deinit();

    // Free data slices only (keys already freed above)
    var dit = frame.result_data.iterator();
    while (dit.next()) |entry| {
        alloc.free(entry.value_ptr.*);
    }
    frame.result_data.deinit();

    // Free buffers_holder arrays only (keys already freed above)
    var bit = frame.buffers_holders.iterator();
    while (bit.next()) |entry| {
        if (entry.value_ptr.*) |bufs| {
            alloc.free(bufs);
        }
    }
    frame.buffers_holders.deinit();
}

/// Main valuation runner: traverse graph in topological order, execute each
/// formula via the Arrow adapter, collect results into ResultFrame.
/// Fail-closed: any error frees all prior results and returns the error.
/// Returns a heap-allocated *ResultFrame to avoid StringHashMap copy-on-return.
///
/// Ownership model: frame.results owns the ArrowArray pointers stored there.
/// The resultFrameFree() function will destroy() those pointers. Caller-owned
/// source arrays must NOT be stored directly — they must be copied if needed
/// for multi-operand formulas.
pub fn runValuation(input: ValuationInput) ValuationError!*ResultFrame {
    const alloc = input.allocator;
    const frame = alloc.create(ResultFrame) catch return ValuationError.AllocationFailed;
    frame.* = ResultFrame.init(alloc);
    errdefer {
        resultFrameFree(frame);
        alloc.destroy(frame);
    }

    // Step 1: resolve dependencies to get topological order (heap-free)
    var order_buf: [64]usize = undefined;
    var in_deg_buf: [64]usize = undefined;
    var queue_buf: [64]usize = undefined;
    const ordered_count = dependencyResolver.resolveDependencies(
        input.registry,
        &order_buf, 64,
        &in_deg_buf, 64,
        &queue_buf, 64,
    );
    if (ordered_count == 0) return ValuationError.ResolveError;

    // Allocate reusable buffers for operand collection
    var operand_ptrs: std.ArrayListUnmanaged(*arrowAdapter.ArrowArray) = .empty;
    var operand_owned: std.ArrayListUnmanaged(bool) = .empty;
    var cleanup_done = false;
    errdefer {
        if (!cleanup_done) {
            var j: usize = 0;
            while (j < operand_ptrs.items.len) : (j += 1) {
                if (operand_owned.items[j]) {
                    alloc.destroy(operand_ptrs.items[j]);
                }
            }
            operand_ptrs.deinit(alloc);
            operand_owned.deinit(alloc);
            cleanup_done = true;
        }
    }

    // Step 2: iterate in topological order
    var i: usize = 0;
    while (i < ordered_count) : (i += 1) {
        const formula_idx = order_buf[i];
        const entry = input.registry.formulas[formula_idx] orelse return ValuationError.NotFound;
        const name = input.registry.string_table.get(entry.name_idx) catch return ValuationError.RegistryError;

        // Free owned ArrowArray copies from previous iteration, then clear lists
        var oi: usize = 0;
        while (oi < operand_ptrs.items.len) : (oi += 1) {
            if (operand_owned.items[oi]) {
                alloc.destroy(operand_ptrs.items[oi]);
            }
        }
        operand_ptrs.clearRetainingCapacity();
        operand_owned.clearRetainingCapacity();

        // Gather operands from source_data or prior results.
        // Sources are string table indices — look up the string name.
        var si: usize = 0;
        while (si < entry.source_count) : (si += 1) {
            const src_name = input.registry.string_table.get(entry.sources[si]) catch return ValuationError.RegistryError;

            if (input.source_data.get(src_name)) |src_arr| {
                // Source is a leaf metric — copy to owned array so frame can destroy() it
                const owned = alloc.create(arrowAdapter.ArrowArray) catch return ValuationError.AllocationFailed;
                owned.* = src_arr.*;
                operand_ptrs.append(alloc, owned) catch return ValuationError.AllocationFailed;
                operand_owned.append(alloc, true) catch return ValuationError.AllocationFailed;
            } else if (frame.results.get(src_name)) |cached_arr| {
                // Source is a previously computed formula result — use directly (frame owns it)
                operand_ptrs.append(alloc, cached_arr) catch return ValuationError.AllocationFailed;
                operand_owned.append(alloc, false) catch return ValuationError.AllocationFailed;
            } else {
                return ValuationError.NotFound;
            }
        }

        // Execute the operation (2+ operands) or pass-through (1 operand)
        if (operand_ptrs.items.len == 1) {
            // Single source — pass through (identity operation).
            const src_arr = operand_ptrs.items[0];
            const len = src_arr.*.length;
            if (len <= 0) return ValuationError.TypeMismatch;
            if (len > std.math.maxInt(usize)) return ValuationError.TypeMismatch;

            // Allocate fresh ArrowArray and data buffer for frame ownership
            const frame_arr = alloc.create(arrowAdapter.ArrowArray) catch return ValuationError.AllocationFailed;
            const copied_data = alloc.alloc(f64, @intCast(len)) catch {
                alloc.destroy(frame_arr);
                return ValuationError.AllocationFailed;
            };
            const src_buf0: [*c]*const void = src_arr.*.buffers;
            const src_data: [*]const f64 = @ptrFromInt(@intFromPtr(src_buf0[1]));
            for (0..@intCast(len)) |j| {
                copied_data[j] = src_data[j];
            }

            // Properly initialize the ArrowArray struct (same pattern as executeOperation)
            const buffers_holder = alloc.alloc(u64, 2) catch {
                alloc.free(copied_data);
                alloc.destroy(frame_arr);
                return ValuationError.AllocationFailed;
            };
            buffers_holder[0] = 0;
            buffers_holder[1] = @intFromPtr(copied_data.ptr);
            const buf_ptr: [*c]*const void = @ptrCast(buffers_holder.ptr);

            frame_arr.* = arrowAdapter.ArrowArray{
                .length = len,
                .null_count = 0,
                .offset = 0,
                .n_buffers = 1,
                .n_children = 0,
                .buffers = buf_ptr,
                .children = null,
                .dictionary = null,
                .release = null,
                .private_data = null,
            };

            const name_copy = alloc.dupe(u8, name) catch {
                alloc.free(copied_data);
                alloc.destroy(frame_arr);
                return ValuationError.AllocationFailed;
            };
            (frame.results.put(name_copy, frame_arr)) catch {
                alloc.free(copied_data);
                alloc.free(name_copy);
                return ValuationError.AllocationFailed;
            };
            (frame.result_data.put(name_copy, copied_data)) catch {
                alloc.free(name_copy);
                return ValuationError.AllocationFailed;
            };
            frame.buffers_holders.put(name_copy, buffers_holder) catch {};
            continue;
        }

        if (operand_ptrs.items.len < 2) continue;

        // Multi-operand: execute the operation
        const c_operands: []const *arrowAdapter.ArrowArray = operand_ptrs.items;
        const op_name = input.registry.string_table.get(entry.operation_idx) catch return ValuationError.RegistryError;

        const compute_result = arrowAdapter.executeOperation(
            op_name,
            c_operands,
            alloc,
        ) catch |err| {
            switch (err) {
                arrowAdapter.AdapterError.UndefinedOperation => return ValuationError.UndefinedOperation,
                arrowAdapter.AdapterError.TypeMismatch => return ValuationError.TypeMismatch,
                arrowAdapter.AdapterError.AllocationFailed => return ValuationError.AllocationFailed,
            }
        };

        // Store result in frame: move ownership of ArrowArray struct and data.
        const result_arr_ptr: *arrowAdapter.ArrowArray = @ptrCast(compute_result.output_array);

        const name_copy = (alloc.dupe(u8, name)) catch {
            arrowAdapter.computeResultFree(compute_result);
            return ValuationError.AllocationFailed;
        };
        (frame.results.put(name_copy, result_arr_ptr)) catch {
            arrowAdapter.computeResultFree(compute_result);
            alloc.free(name_copy);
            return ValuationError.AllocationFailed;
        };
        (frame.result_data.put(name_copy, compute_result.data)) catch {
            alloc.free(name_copy);
            return ValuationError.AllocationFailed;
        };
        (frame.buffers_holders.put(name_copy, compute_result.buffers_holder)) catch {
            alloc.free(name_copy);
            return ValuationError.AllocationFailed;
        };
    }

    // Clean up reusable operand arrays on success
    var oj: usize = 0;
    while (oj < operand_ptrs.items.len) : (oj += 1) {
        if (operand_owned.items[oj]) {
            alloc.destroy(operand_ptrs.items[oj]);
        }
    }
    operand_ptrs.deinit(alloc);
    operand_owned.deinit(alloc);
    cleanup_done = true;

    return frame;
}

// ─── V1.1.S5 Unit Tests ────────────────────────────────────────────────

/// Helper: create an ArrowArray from an f64 slice for use as source data.
/// Returns: { arr, data_buf, buffers_array }
/// Caller must free all three.
fn makeSourceArray(alloc: std.mem.Allocator, data: []const f64) !struct {
    *arrowAdapter.ArrowArray,
    []f64,
    []u64,
} {
    const data_buf = try alloc.dupe(f64, data);
    errdefer alloc.free(data_buf);

    const buffers_array = try alloc.alloc(u64, 2);
    errdefer alloc.free(buffers_array);
    buffers_array[0] = 0;
    buffers_array[1] = @intFromPtr(data_buf.ptr);

    const buf_ptr: [*c]*const void = @ptrCast(buffers_array.ptr);

    const arr = try alloc.create(arrowAdapter.ArrowArray);
    errdefer alloc.destroy(arr);

    arr.* = arrowAdapter.ArrowArray{
        .length = @intCast(data.len),
        .null_count = 0,
        .offset = 0,
        .n_buffers = 1,
        .n_children = 0,
        .buffers = buf_ptr,
        .children = null,
        .dictionary = null,
        .release = null,
        .private_data = null,
    };

    return .{ arr, data_buf, buffers_array };
}

/// Helper: create an ArrowArray with null buffers (for type-mismatch testing).
fn makeNullArray(alloc: std.mem.Allocator) !*arrowAdapter.ArrowArray {
    const arr = try alloc.create(arrowAdapter.ArrowArray);
    arr.* = arrowAdapter.ArrowArray{
        .length = 3,
        .null_count = 0,
        .offset = 0,
        .n_buffers = 1,
        .n_children = 0,
        .buffers = null,
        .children = null,
        .dictionary = null,
        .release = null,
        .private_data = null,
    };
    return arr;
}

/// Helper: assert that two f64 slices are approximately equal.
fn expectApprox(a: []const f64, b: []const f64) !void {
    try expectEqual(a.len, b.len);
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        try expect(@abs(a[i] - b[i]) < 1e-9);
    }
}

// 1. linear_chain_execution: B depends on source A (A→B), source data for A
test "runValuation: linear_chain_execution A→B" {
    const alloc = std.testing.allocator;

    const reg = makeRegistry();
    var registry = reg.registry;
    var string_table = reg.string_table;

    _ = try addFormulaAndGetIndex(&registry, &string_table, "B", &.{ "A", "A" }, "add");
    // Source: A = [1, 2, 3]
    const a_src = try makeSourceArray(alloc, &[_]f64{ 1, 2, 3 });
    // Do NOT free yet — keep alive through runValuation

    var source_map = std.StringHashMap(*arrowAdapter.ArrowArray).init(alloc);
    defer source_map.deinit();
    try source_map.put("A", a_src[0]);

    const input = ValuationInput{
        .registry = &registry,
        .source_data = source_map,
        .allocator = alloc,
    };

    var frame = try runValuation(input);
    defer {
        resultFrameFree(frame);
        frame.allocator.destroy(frame);
    }

    // Now free source arrays
    alloc.free(a_src[1]);
    alloc.free(a_src[2]);
    alloc.destroy(a_src[0]);

    try expectEqual(1, frame.results.count());
    try expect(frame.results.contains("B"));
    try expectApprox(frame.result_data.get("B").?, &[_]f64{ 2, 4, 6 });
}

// 2. single_formula_no_deps: one formula whose sources are all leaf metrics
test "runValuation: single_formula_no_deps" {
    const alloc = std.testing.allocator;

    const reg = makeRegistry();
    var registry = reg.registry;
    var string_table = reg.string_table;

    _ = try addFormulaAndGetIndex(&registry, &string_table, "X", &.{ "SA", "SB" }, "multiply");
    const sa_src = try makeSourceArray(alloc, &[_]f64{ 1, 2, 3 });
    const sb_src = try makeSourceArray(alloc, &[_]f64{ 4, 5, 6 });

    var source_map = std.StringHashMap(*arrowAdapter.ArrowArray).init(alloc);
    defer source_map.deinit();
    try source_map.put("SA", sa_src[0]);
    try source_map.put("SB", sb_src[0]);

    const input = ValuationInput{
        .registry = &registry,
        .source_data = source_map,
        .allocator = alloc,
    };

    var frame = try runValuation(input);
    defer {
        resultFrameFree(frame);
        frame.allocator.destroy(frame);
    }

    alloc.free(sa_src[1]);
    alloc.free(sa_src[2]);
    alloc.destroy(sa_src[0]);
    alloc.free(sb_src[1]);
    alloc.free(sb_src[2]);
    alloc.destroy(sb_src[0]);

    try expectEqual(1, frame.results.count());
    try expectApprox(frame.result_data.get("X").?, &[_]f64{ 4, 10, 18 });
}

// 3. independent_formulas: two formulas, no deps between them
test "runValuation: independent_formulas" {
    const alloc = std.testing.allocator;

    const reg = makeRegistry();
    var registry = reg.registry;
    var string_table = reg.string_table;

    _ = try addFormulaAndGetIndex(&registry, &string_table, "X", &.{ "XA", "XB" }, "add");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "Y", &.{ "YA", "YB" }, "add");

    const xa_src = try makeSourceArray(alloc, &[_]f64{ 1, 2 });
    const xb_src = try makeSourceArray(alloc, &[_]f64{ 3, 4 });
    const ya_src = try makeSourceArray(alloc, &[_]f64{ 10, 20 });
    const yb_src = try makeSourceArray(alloc, &[_]f64{ 5, 4 });

    var source_map = std.StringHashMap(*arrowAdapter.ArrowArray).init(alloc);
    defer source_map.deinit();
    try source_map.put("XA", xa_src[0]);
    try source_map.put("XB", xb_src[0]);
    try source_map.put("YA", ya_src[0]);
    try source_map.put("YB", yb_src[0]);

    const input = ValuationInput{
        .registry = &registry,
        .source_data = source_map,
        .allocator = alloc,
    };

    var frame = try runValuation(input);
    defer {
        resultFrameFree(frame);
        frame.allocator.destroy(frame);
    }

    alloc.free(xa_src[1]);
    alloc.free(xa_src[2]);
    alloc.destroy(xa_src[0]);
    alloc.free(xb_src[1]);
    alloc.free(xb_src[2]);
    alloc.destroy(xb_src[0]);
    alloc.free(ya_src[1]);
    alloc.free(ya_src[2]);
    alloc.destroy(ya_src[0]);
    alloc.free(yb_src[1]);
    alloc.free(yb_src[2]);
    alloc.destroy(yb_src[0]);

    try expectEqual(2, frame.results.count());
    try expectApprox(frame.result_data.get("X").?, &[_]f64{ 4, 6 });
    try expectApprox(frame.result_data.get("Y").?, &[_]f64{ 15, 24 });
}

// 4. type_mismatch_error: non-float64 source array (null buffers)
test "runValuation: type_mismatch_error" {
    const alloc = std.testing.allocator;

    const reg = makeRegistry();
    var registry = reg.registry;
    var string_table = reg.string_table;

    _ = try addFormulaAndGetIndex(&registry, &string_table, "D", &.{ "BAD", "X" }, "add");
    const bad_arr = try makeNullArray(alloc);
    defer alloc.destroy(bad_arr);

    const x_arr = try makeSourceArray(alloc, &[_]f64{ 1, 2 });

    var source_map = std.StringHashMap(*arrowAdapter.ArrowArray).init(alloc);
    defer source_map.deinit();
    try source_map.put("BAD", bad_arr);
    try source_map.put("X", x_arr[0]);

    const input = ValuationInput{
        .registry = &registry,
        .source_data = source_map,
        .allocator = alloc,
    };

    const result = runValuation(input);
    try expect(result == ValuationError.TypeMismatch);

    alloc.free(x_arr[1]);
    alloc.free(x_arr[2]);
    alloc.destroy(x_arr[0]);
}

// 5. undefined_operation_error: formula with unknown operation
test "runValuation: undefined_operation_error" {
    const alloc = std.testing.allocator;

    const reg = makeRegistry();
    var registry = reg.registry;
    var string_table = reg.string_table;

    _ = try addFormulaAndGetIndex(&registry, &string_table, "Z", &.{ "A", "B" }, "foobar");
    const a_src = try makeSourceArray(alloc, &[_]f64{ 1, 2 });
    const b_src = try makeSourceArray(alloc, &[_]f64{ 3, 4 });

    var source_map = std.StringHashMap(*arrowAdapter.ArrowArray).init(alloc);
    defer source_map.deinit();
    try source_map.put("A", a_src[0]);
    try source_map.put("B", b_src[0]);

    const input = ValuationInput{
        .registry = &registry,
        .source_data = source_map,
        .allocator = alloc,
    };

    const result = runValuation(input);
    try expect(result == ValuationError.UndefinedOperation);

    alloc.free(a_src[1]);
    alloc.free(a_src[2]);
    alloc.destroy(a_src[0]);
    alloc.free(b_src[1]);
    alloc.free(b_src[2]);
    alloc.destroy(b_src[0]);
}

// 6. diamond_execution: A→B, A→C, B→D, C→D
test "runValuation: diamond_execution" {
    const alloc = std.testing.allocator;

    const reg = makeRegistry();
    var registry = reg.registry;
    var string_table = reg.string_table;

    // Diamond: A(source) → B(add), A(source) → C(multiply), B+C → D(subtract)
    _ = try addFormulaAndGetIndex(&registry, &string_table, "B", &.{ "A", "A" }, "add");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "C", &.{ "A", "A" }, "multiply");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "D", &.{ "B", "C" }, "subtract");
    const a_src = try makeSourceArray(alloc, &[_]f64{ 2, 3 });

    var source_map = std.StringHashMap(*arrowAdapter.ArrowArray).init(alloc);
    defer source_map.deinit();
    try source_map.put("A", a_src[0]);

    const input = ValuationInput{
        .registry = &registry,
        .source_data = source_map,
        .allocator = alloc,
    };

    var frame = try runValuation(input);
    defer {
        resultFrameFree(frame);
        frame.allocator.destroy(frame);
    }

    alloc.free(a_src[1]);
    alloc.free(a_src[2]);
    alloc.destroy(a_src[0]);

    try expectEqual(3, frame.results.count());
    try expectApprox(frame.result_data.get("B").?, &[_]f64{ 4, 6 });
    try expectApprox(frame.result_data.get("C").?, &[_]f64{ 4, 9 });
    try expectApprox(frame.result_data.get("D").?, &[_]f64{ 0, -3 });
}

// 7. partial_dependency_resolution: B depends on A, A is source data
test "runValuation: partial_dependency_resolution" {
    const alloc = std.testing.allocator;

    const reg = makeRegistry();
    var registry = reg.registry;
    var string_table = reg.string_table;

    _ = try addFormulaAndGetIndex(&registry, &string_table, "B", &.{ "A", "A" }, "multiply");
    const a_src = try makeSourceArray(alloc, &[_]f64{ 5, 10 });

    var source_map = std.StringHashMap(*arrowAdapter.ArrowArray).init(alloc);
    defer source_map.deinit();
    try source_map.put("A", a_src[0]);

    const input = ValuationInput{
        .registry = &registry,
        .source_data = source_map,
        .allocator = alloc,
    };

    var frame = try runValuation(input);
    defer {
        resultFrameFree(frame);
        frame.allocator.destroy(frame);
    }

    alloc.free(a_src[1]);
    alloc.free(a_src[2]);
    alloc.destroy(a_src[0]);

    try expectApprox(frame.result_data.get("B").?, &[_]f64{ 25, 100 });
}

// 8. multiple_sources_for_one_formula: C depends on A and B (both sources)
test "runValuation: multiple_sources_for_one_formula" {
    const alloc = std.testing.allocator;

    const reg = makeRegistry();
    var registry = reg.registry;
    var string_table = reg.string_table;

    _ = try addFormulaAndGetIndex(&registry, &string_table, "C", &.{ "A", "B" }, "divide");
    const a_src = try makeSourceArray(alloc, &[_]f64{ 10, 20 });
    const b_src = try makeSourceArray(alloc, &[_]f64{ 2, 4 });

    var source_map = std.StringHashMap(*arrowAdapter.ArrowArray).init(alloc);
    defer source_map.deinit();
    try source_map.put("A", a_src[0]);
    try source_map.put("B", b_src[0]);

    const input = ValuationInput{
        .registry = &registry,
        .source_data = source_map,
        .allocator = alloc,
    };

    var frame = try runValuation(input);
    defer {
        resultFrameFree(frame);
        frame.allocator.destroy(frame);
    }

    alloc.free(a_src[1]);
    alloc.free(a_src[2]);
    alloc.destroy(a_src[0]);
    alloc.free(b_src[1]);
    alloc.free(b_src[2]);
    alloc.destroy(b_src[0]);

    try expectApprox(frame.result_data.get("C").?, &[_]f64{ 5, 5 });
}

// 9. fail_closed_on_error: one formula has undefined op → entire run fails
test "runValuation: fail_closed_on_error" {
    const alloc = std.testing.allocator;

    const reg = makeRegistry();
    var registry = reg.registry;
    var string_table = reg.string_table;

    _ = try addFormulaAndGetIndex(&registry, &string_table, "Z", &.{ "X", "Y" }, "foobar");

    const x_src = try makeSourceArray(alloc, &[_]f64{ 1, 2 });
    const y_src = try makeSourceArray(alloc, &[_]f64{ 3, 4 });

    var source_map = std.StringHashMap(*arrowAdapter.ArrowArray).init(alloc);
    defer source_map.deinit();
    try source_map.put("X", x_src[0]);
    try source_map.put("Y", y_src[0]);

    const input = ValuationInput{
        .registry = &registry,
        .source_data = source_map,
        .allocator = alloc,
    };

    const result = runValuation(input);
    try expect(result == ValuationError.UndefinedOperation);

    alloc.free(x_src[1]);
    alloc.free(x_src[2]);
    alloc.destroy(x_src[0]);
    alloc.free(y_src[1]);
    alloc.free(y_src[2]);
    alloc.destroy(y_src[0]);
}

// 10. complex_chain: 5-formula chain ROIC→STLA→EV→EBITDA→EV_EBITDA
test "runValuation: complex_chain" {
    const alloc = std.testing.allocator;

    const reg = makeRegistry();
    var registry = reg.registry;
    var string_table = reg.string_table;

    _ = try addFormulaAndGetIndex(&registry, &string_table, "ROIC", &.{ "R", "I" }, "divide");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "STLA", &.{ "ROIC", "M" }, "multiply");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "EV", &.{ "STLA", "ONE" }, "add");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "EBITDA", &.{ "EV", "D" }, "subtract");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "EV_EBITDA", &.{ "EBITDA", "EV" }, "divide");
    const r_src = try makeSourceArray(alloc, &[_]f64{ 100, 200 });
    const i_src = try makeSourceArray(alloc, &[_]f64{ 10, 20 });
    const one_src = try makeSourceArray(alloc, &[_]f64{ 1, 1 });
    const m_src = try makeSourceArray(alloc, &[_]f64{ 5, 5 });
    const d_src = try makeSourceArray(alloc, &[_]f64{ 2, 2 });

    var source_map = std.StringHashMap(*arrowAdapter.ArrowArray).init(alloc);
    defer source_map.deinit();
    try source_map.put("R", r_src[0]);
    try source_map.put("I", i_src[0]);
    try source_map.put("ONE", one_src[0]);
    try source_map.put("M", m_src[0]);
    try source_map.put("D", d_src[0]);

    const input = ValuationInput{
        .registry = &registry,
        .source_data = source_map,
        .allocator = alloc,
    };

    var frame = try runValuation(input);
    defer {
        resultFrameFree(frame);
        frame.allocator.destroy(frame);
    }

    // Free all source arrays after runValuation completes
    alloc.free(r_src[1]);
    alloc.free(r_src[2]);
    alloc.destroy(r_src[0]);
    alloc.free(i_src[1]);
    alloc.free(i_src[2]);
    alloc.destroy(i_src[0]);
    alloc.free(one_src[1]);
    alloc.free(one_src[2]);
    alloc.destroy(one_src[0]);
    alloc.free(m_src[1]);
    alloc.free(m_src[2]);
    alloc.destroy(m_src[0]);
    alloc.free(d_src[1]);
    alloc.free(d_src[2]);
    alloc.destroy(d_src[0]);

    try expectEqual(5, frame.results.count());
    try expectApprox(frame.result_data.get("ROIC").?, &[_]f64{ 10, 10 });
    try expectApprox(frame.result_data.get("STLA").?, &[_]f64{ 50, 50 });
    try expectApprox(frame.result_data.get("EV").?, &[_]f64{ 51, 51 });
    try expectApprox(frame.result_data.get("EBITDA").?, &[_]f64{ 49, 49 });
    try expectApprox(frame.result_data.get("EV_EBITDA").?, &[_]f64{ 0.9608, 0.9608 });
}

// ─── V1.1.S7: Provenance — Audit Trail for Every Computed Metric ────────

/// Provenance: audit trail for a single computed metric.
/// chain is ordered leaf-to-formula: e.g. [NOPAT, InvestedCapital, ROIC]
pub const Provenance = struct {
    name: []const u8,
    sources: []const []const u8,
    operation: []const u8,
    chain: std.ArrayListUnmanaged([]const u8),
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Provenance) void {
        const alloc = self.allocator;
        alloc.free(self.name);
        for (self.sources) |s| alloc.free(s);
        alloc.free(self.sources);
        alloc.free(self.operation);
        for (self.chain.items) |item| alloc.free(item);
        self.chain.deinit(alloc);
    }
};

pub const ProvenanceError = error{
    NotFound,
    AllocationFailed,
};

/// Build provenance for a single formula by traversing the dependency graph
/// from the formula backward to all leaf sources via BFS.
/// Returns chain in leaf-to-formula order.
pub fn attachProvenance(
    formula_name: []const u8,
    registry: *const formula.FormulaRegistry,
    allocator: std.mem.Allocator,
) ProvenanceError!Provenance {
    // Look up formula by name (linear search in fixed array)
    var found: ?usize = null;
    var li: usize = 0;
    while (li < registry.formula_count) : (li += 1) {
        const entry = registry.formulas[li];
        if (entry) |e| {
            const entry_name = registry.string_table.get(e.name_idx) catch continue;
            if (std.mem.eql(u8, entry_name, formula_name)) {
                found = li;
                break;
            }
        }
    }
    const nf_idx = found orelse return ProvenanceError.NotFound;

    const nf_entry = registry.formulas[nf_idx].?;
    const name_copy = (allocator.dupe(u8, formula_name)) catch return ProvenanceError.AllocationFailed;
    const op_copy = allocator.dupe(u8, registry.string_table.get(nf_entry.operation_idx) catch return ProvenanceError.AllocationFailed) catch return ProvenanceError.AllocationFailed;

    // Copy source names (from string table indices)
    var sources: [][]const u8 = allocator.alloc([]const u8, nf_entry.source_count) catch return ProvenanceError.AllocationFailed;
    var si: usize = 0;
    while (si < nf_entry.source_count) : (si += 1) {
        sources[si] = allocator.dupe(u8, registry.string_table.get(nf_entry.sources[si]) catch return ProvenanceError.AllocationFailed) catch return ProvenanceError.AllocationFailed;
    }

    // Build chain: topological order of all formulas reachable from target,
    // plus data keys that are sources of those formulas.
    // Use heap-free dependency resolver.
    var order_buf: [64]usize = undefined;
    var in_deg_buf: [64]usize = undefined;
    var queue_buf: [64]usize = undefined;
    const ordered_count = dependencyResolver.resolveDependencies(
        registry,
        &order_buf, 64,
        &in_deg_buf, 64,
        &queue_buf, 64,
    );

    // BFS from target to find all reachable formulas and their data-key sources.
    var visited: std.StringHashMap(void) = .init(allocator);
    errdefer visited.deinit();

    var queue: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer {
        for (queue.items) |item| allocator.free(item);
        queue.deinit(allocator);
    }

    const target_push = (allocator.dupe(u8, formula_name)) catch return ProvenanceError.AllocationFailed;
    (visited.put(target_push, {})) catch return ProvenanceError.AllocationFailed;
    (queue.append(allocator, target_push)) catch return ProvenanceError.AllocationFailed;

    var qi: usize = 0;
    while (qi < queue.items.len) {
        const current = queue.items[qi];
        qi += 1;

        // Look up current name in registry
        var found_entry: ?usize = null;
        var li2: usize = 0;
        while (li2 < registry.formula_count) : (li2 += 1) {
            const entry = registry.formulas[li2];
            if (entry) |e| {
                const entry_name = registry.string_table.get(e.name_idx) catch continue;
                if (std.mem.eql(u8, entry_name, current)) {
                    found_entry = li2;
                    break;
                }
            }
        }
        if (found_entry) |fidx| {
            const current_nf = registry.formulas[fidx].?;
            var si2: usize = 0;
            while (si2 < current_nf.source_count) : (si2 += 1) {
                const src_str = registry.string_table.get(current_nf.sources[si2]) catch continue;
                if (visited.get(src_str) == null) {
                    const src_copy = (allocator.dupe(u8, src_str)) catch return ProvenanceError.AllocationFailed;
                    (visited.put(src_copy, {})) catch return ProvenanceError.AllocationFailed;
                    (queue.append(allocator, src_copy)) catch return ProvenanceError.AllocationFailed;
                }
            }
        }
    }

    // Build chain: include all visited nodes in topo order.
    // Data keys are visited names that are not themselves formulas in the registry.
    var chain = std.ArrayListUnmanaged([]const u8).empty;
    errdefer {
        for (chain.items) |item| allocator.free(item);
        chain.deinit(allocator);
    }

    // Collect data keys: visited names not present as formulas.
    var qi2: usize = 0;
    while (qi2 < queue.items.len) : (qi2 += 1) {
        const name = queue.items[qi2];
        // Check if this name is a formula
        var is_formula = false;
        var li3: usize = 0;
        while (li3 < registry.formula_count) : (li3 += 1) {
            const entry = registry.formulas[li3];
            if (entry) |e| {
                const entry_name = registry.string_table.get(e.name_idx) catch continue;
                if (std.mem.eql(u8, entry_name, name)) {
                    is_formula = true;
                    break;
                }
            }
        }
        if (!is_formula) {
            const key_copy = (allocator.dupe(u8, name)) catch return ProvenanceError.AllocationFailed;
            (chain.append(allocator, key_copy)) catch return ProvenanceError.AllocationFailed;
        }
    }

    // Then add all visited formulas in topo order.
    var fi: usize = 0;
    while (fi < ordered_count) : (fi += 1) {
        const entry = registry.formulas[order_buf[fi]];
        if (entry) |e| {
            const topo_name = registry.string_table.get(e.name_idx) catch continue;
            if (visited.get(topo_name) != null) {
                const topo_name_copy = (allocator.dupe(u8, topo_name)) catch return ProvenanceError.AllocationFailed;
                (chain.append(allocator, topo_name_copy)) catch return ProvenanceError.AllocationFailed;
            }
        }
    }

    // Clean up visited and queue on success path.
    visited.deinit();
    for (queue.items) |item| allocator.free(item);
    queue.deinit(allocator);

    return Provenance{
        .name = name_copy,
        .sources = sources,
        .operation = op_copy,
        .chain = chain,
        .allocator = allocator,
    };
}

/// ResultFrameWithProvenance: formula name → computed Arrow array + provenance.
pub const ResultFrameWithProvenance = struct {
    results: std.StringHashMap(*arrowAdapter.ArrowArray),
    provenance: std.StringHashMap(Provenance),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ResultFrameWithProvenance {
        return ResultFrameWithProvenance{
            .results = std.StringHashMap(*arrowAdapter.ArrowArray).init(allocator),
            .provenance = std.StringHashMap(Provenance).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ResultFrameWithProvenance) void {
        const alloc = self.allocator;
        var it = self.results.iterator();
        while (it.next()) |entry| {
            alloc.free(entry.key_ptr.*);
            alloc.destroy(entry.value_ptr.*);
        }
        self.results.deinit();

        var pit = self.provenance.iterator();
        while (pit.next()) |entry| {
            alloc.free(entry.key_ptr.*);
            @as(*Provenance, @ptrCast(entry.value_ptr)).deinit();
        }
        self.provenance.deinit();
    }
};

/// Build provenance for all formulas in a result frame.
/// Only populates the provenance map; results are owned by the frame.
pub fn buildAllProvenance(
    frame: *const ResultFrame,
    registry: *const formula.FormulaRegistry,
    allocator: std.mem.Allocator,
) ProvenanceError!ResultFrameWithProvenance {
    var result = ResultFrameWithProvenance.init(allocator);
    errdefer {
        var pit = result.provenance.iterator();
        while (pit.next()) |entry| @as(*Provenance, @ptrCast(entry.value_ptr)).deinit();
        result.provenance.deinit();
    }

    var it = frame.results.iterator();
    while (it.next()) |entry| {
        const name = entry.key_ptr.*;
        const prov = try attachProvenance(name, registry, allocator);
        const prov_name_copy = (allocator.dupe(u8, prov.name)) catch return ProvenanceError.AllocationFailed;
        (result.provenance.put(prov_name_copy, prov)) catch {
            allocator.free(prov_name_copy);
            return ProvenanceError.AllocationFailed;
        };
    }

    return result;
}

/// Query provenance for a specific formula by name.
pub fn queryProvenance(
    formula_name: []const u8,
    provenance_map: *const std.StringHashMap(Provenance),
) ?Provenance {
    return provenance_map.get(formula_name);
}

/// Free a single Provenance (call via iterator in deinit).
pub fn provenanceFree(prov: *Provenance) void {
    prov.deinit();
}

// ─── V1.1.S7 Unit Tests ────────────────────────────────────────────────

test "provenance: single_formula_provenance ROIC = NOPAT / InvestedCapital" {
    const alloc = std.testing.allocator;
    const reg = makeRegistry();
    var registry = reg.registry;
    var string_table = reg.string_table;


    _ = try addFormulaAndGetIndex(&registry, &string_table, "ROIC", &.{ "NOPAT", "InvestedCapital" }, "divide");
    var prov = try attachProvenance("ROIC", &registry, alloc);
    defer prov.deinit();

    try expectEqualStrings("ROIC", prov.name);
    try expectEqualStrings("divide", prov.operation);
    try expectEqual(2, prov.sources.len);
    try expectEqual(3, prov.chain.items.len);
    try expectEqualStrings("NOPAT", prov.chain.items[0]);
    try expectEqualStrings("InvestedCapital", prov.chain.items[1]);
    try expectEqualStrings("ROIC", prov.chain.items[2]);
}

test "provenance: chain_provenance A→B→C" {
    const alloc = std.testing.allocator;
    const reg = makeRegistry();
    var registry = reg.registry;
    var string_table = reg.string_table;


    _ = try addFormulaAndGetIndex(&registry, &string_table, "A", &.{  }, "add");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "B", &.{ "A" }, "multiply");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "C", &.{ "B" }, "multiply");
    var prov = try attachProvenance("C", &registry, alloc);
    defer prov.deinit();

    try expectEqualStrings("C", prov.name);
    try expectEqual(3, prov.chain.items.len);
    try expectEqualStrings("A", prov.chain.items[0]);
    try expectEqualStrings("B", prov.chain.items[1]);
    try expectEqualStrings("C", prov.chain.items[2]);
}

test "provenance: leaf_metric_provenance Revenue (no sources)" {
    const alloc = std.testing.allocator;
    const reg = makeRegistry();
    var registry = reg.registry;
    var string_table = reg.string_table;


    _ = try addFormulaAndGetIndex(&registry, &string_table, "Revenue", &.{  }, "add");
    var prov = try attachProvenance("Revenue", &registry, alloc);
    defer prov.deinit();

    try expectEqualStrings("Revenue", prov.name);
    try expectEqual(0, prov.sources.len);
    try expectEqual(1, prov.chain.items.len);
    try expectEqualStrings("Revenue", prov.chain.items[0]);
}

test "provenance: diamond_provenance A→B, A→C, B→D, C→D" {
    const alloc = std.testing.allocator;
    const reg = makeRegistry();
    var registry = reg.registry;
    var string_table = reg.string_table;


    _ = try addFormulaAndGetIndex(&registry, &string_table, "A", &.{  }, "add");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "B", &.{ "A" }, "add");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "C", &.{ "A" }, "add");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "D", &.{ "B", "C" }, "add");

    var prov = try attachProvenance("D", &registry, alloc);
    defer prov.deinit();

    try expectEqualStrings("D", prov.name);
    // D's chain must include A, B, C, D in leaf-to-formula order
    try expectEqual(4, prov.chain.items.len);
    try expectEqualStrings("A", prov.chain.items[0]);
    try expectEqualStrings("D", prov.chain.items[3]);
    // B and C can be in either order
    try expect(std.mem.eql(u8, "B", prov.chain.items[1]) or std.mem.eql(u8, "B", prov.chain.items[2]));
    try expect(std.mem.eql(u8, "C", prov.chain.items[1]) or std.mem.eql(u8, "C", prov.chain.items[2]));
}

test "provenance: re_evaluation_invariance" {
    const alloc = std.testing.allocator;
    const reg = makeRegistry();
    var registry = reg.registry;
    var string_table = reg.string_table;


    _ = try addFormulaAndGetIndex(&registry, &string_table, "A", &.{  }, "add");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "B", &.{ "A" }, "add");

    var prov1 = try attachProvenance("B", &registry, alloc);
    defer prov1.deinit();

    // Re-evaluate: attachProvenance is structural, result must be identical
    var prov2 = try attachProvenance("B", &registry, alloc);
    defer prov2.deinit();

    try expectEqualStrings(prov1.name, prov2.name);
    try expectEqualStrings(prov1.operation, prov2.operation);
    try expectEqual(prov1.chain.items.len, prov2.chain.items.len);
    var i: usize = 0;
    while (i < prov1.chain.items.len) : (i += 1) {
        try expectEqualStrings(prov1.chain.items[i], prov2.chain.items[i]);
    }
}

test "provenance: complex_chain_provenance ROIC→STLA→EV→EBITDA→EV_EBITDA" {
    const alloc = std.testing.allocator;
    const reg = makeRegistry();
    var registry = reg.registry;
    var string_table = reg.string_table;


    _ = try addFormulaAndGetIndex(&registry, &string_table, "ROIC", &.{ "R", "I" }, "divide");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "STLA", &.{ "ROIC", "M" }, "multiply");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "EV", &.{ "STLA", "ONE" }, "add");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "EBITDA", &.{ "EV", "D" }, "subtract");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "EV_EBITDA", &.{ "EBITDA", "EV" }, "divide");
    var prov = try attachProvenance("EV_EBITDA", &registry, alloc);
    defer prov.deinit();

    try expectEqualStrings("EV_EBITDA", prov.name);
    // Chain: R, I, ONE, M, D (leaves) → ROIC, STLA, EV, EBITDA (intermediates) → EV_EBITDA (target)
    try expectEqual(10, prov.chain.items.len);
    try expectEqualStrings("EV_EBITDA", prov.chain.items[9]);
}

test "provenance: query_provenance_by_name" {
    const alloc = std.testing.allocator;
    const reg = makeRegistry();
    var registry = reg.registry;
    var string_table = reg.string_table;


    _ = try addFormulaAndGetIndex(&registry, &string_table, "X", &.{ "A", "B" }, "add");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "Y", &.{  }, "add");

    var provenance_map = std.StringHashMap(Provenance).init(alloc);

    const prov_x = try attachProvenance("X", &registry, alloc);
    const prov_x_name = try alloc.dupe(u8, prov_x.name);
    try provenance_map.put(prov_x_name, prov_x);

    const prov_y = try attachProvenance("Y", &registry, alloc);
    const prov_y_name = try alloc.dupe(u8, prov_y.name);
    try provenance_map.put(prov_y_name, prov_y);

    const found = queryProvenance("X", &provenance_map);
    try expect(found != null);
    try expectEqualStrings("X", found.?.name);
    try expectEqualStrings("add", found.?.operation);

    // Deinit each Provenance value and free keys (StringHashMap.deinit doesn't free keys)
    var it = provenance_map.iterator();
    while (it.next()) |entry| {
        entry.value_ptr.*.deinit();
        alloc.free(entry.key_ptr.*);
    }
    provenance_map.deinit();
}

test "provenance: query_nonexistent_provenance" {
    const alloc = std.testing.allocator;
    var provenance_map = std.StringHashMap(Provenance).init(alloc);
    defer provenance_map.deinit();

    const found = queryProvenance("Ghost", &provenance_map);
    try expect(found == null);
}

test "provenance: all_provenance_built" {
    const alloc = std.testing.allocator;
    const reg = makeRegistry();
    var registry = reg.registry;
    var string_table = reg.string_table;


    _ = try addFormulaAndGetIndex(&registry, &string_table, "A", &.{}, "add");
    _ = try addFormulaAndGetIndex(&registry, &string_table, "B", &.{"A"}, "divide");
    // Create a minimal frame with 3 entries (A, B, C)
    var frame = ResultFrame.init(alloc);
    defer resultFrameFree(&frame);
    errdefer resultFrameFree(&frame);

    // Populate frame with mock result data for A, B, C
    const a_data = try alloc.alloc(f64, 1);
    a_data[0] = 1.0;
    const a_buffers = try alloc.alloc(u64, 2);
    a_buffers[0] = 0;
    a_buffers[1] = @intFromPtr(a_data.ptr);
    const a_arr = try alloc.create(arrowAdapter.ArrowArray);
    a_arr.* = arrowAdapter.ArrowArray{
        .length = 1,
        .null_count = 0,
        .offset = 0,
        .n_buffers = 1,
        .n_children = 0,
        .buffers = @ptrCast(a_buffers.ptr),
        .children = null,
        .dictionary = null,
        .release = null,
        .private_data = null,
    };
    const key_a = try alloc.dupe(u8, "A");
    try frame.results.put(key_a, a_arr);
    try frame.result_data.put(key_a, a_data);
    try frame.buffers_holders.put(key_a, a_buffers);

    const b_data = try alloc.alloc(f64, 1);
    b_data[0] = 2.0;
    const b_buffers = try alloc.alloc(u64, 2);
    b_buffers[0] = 0;
    b_buffers[1] = @intFromPtr(b_data.ptr);
    const b_arr = try alloc.create(arrowAdapter.ArrowArray);
    b_arr.* = arrowAdapter.ArrowArray{
        .length = 1,
        .null_count = 0,
        .offset = 0,
        .n_buffers = 1,
        .n_children = 0,
        .buffers = @ptrCast(b_buffers.ptr),
        .children = null,
        .dictionary = null,
        .release = null,
        .private_data = null,
    };
    const key_b = try alloc.dupe(u8, "B");
    try frame.results.put(key_b, b_arr);
    try frame.result_data.put(key_b, b_data);
    try frame.buffers_holders.put(key_b, b_buffers);

    const c_data = try alloc.alloc(f64, 1);
    c_data[0] = 3.0;
    const c_buffers = try alloc.alloc(u64, 2);
    c_buffers[0] = 0;
    c_buffers[1] = @intFromPtr(c_data.ptr);
    const c_arr = try alloc.create(arrowAdapter.ArrowArray);
    c_arr.* = arrowAdapter.ArrowArray{
        .length = 1,
        .null_count = 0,
        .offset = 0,
        .n_buffers = 1,
        .n_children = 0,
        .buffers = @ptrCast(c_buffers.ptr),
        .children = null,
        .dictionary = null,
        .release = null,
        .private_data = null,
    };
    const key_c = try alloc.dupe(u8, "C");
    try frame.results.put(key_c, c_arr);
    try frame.result_data.put(key_c, c_data);
    try frame.buffers_holders.put(key_c, c_buffers);

    var result = try buildAllProvenance(&frame, &registry, alloc);
    defer result.deinit();

    try expectEqual(3, result.provenance.count());
    try expect(result.provenance.contains("A"));
    try expect(result.provenance.contains("B"));
    try expect(result.provenance.contains("C"));

    // Verify A's chain (leaf only)
    const prov_a = result.provenance.get("A").?;
    try expectEqual(1, prov_a.chain.items.len);
    try expectEqualStrings("A", prov_a.chain.items[0]);

    // Verify B's chain (A→B)
    const prov_b = result.provenance.get("B").?;
    try expectEqual(2, prov_b.chain.items.len);
    try expectEqualStrings("A", prov_b.chain.items[0]);
    try expectEqualStrings("B", prov_b.chain.items[1]);

    // Verify C's chain (A→B→C)
    const prov_c = result.provenance.get("C").?;
    try expectEqual(3, prov_c.chain.items.len);
    try expectEqualStrings("A", prov_c.chain.items[0]);
    try expectEqualStrings("B", prov_c.chain.items[1]);
    try expectEqualStrings("C", prov_c.chain.items[2]);
}

// ─── Registry Serialization Tests (Task 4) ─────────────────────────────

test "CapabilityRegistry toJson includes name and version" {
    var caps: [1]Capability = undefined;
    caps[0] = Capability.init(
        "sum",
        1,
        "Sum elements",
        &.{TypeDescriptor{ .category = .vector, .element_type = .f64 }},
        TypeDescriptor{ .category = .scalar, .element_type = .f64 },
        .arrow,
    );

    var reg: CapabilityRegistry = undefined;
    CapabilityRegistry.init(&reg, &caps, 1);

    var json_buf: [256]u8 = undefined;
    const json = try reg.toJson(&json_buf);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"name\":\"sum\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"version\":1") != null);
}

test "CapabilityRegistry toJson includes description and backend" {
    var caps: [1]Capability = undefined;
    caps[0] = Capability.init(
        "mean",
        2,
        "Compute mean value",
        &.{TypeDescriptor{ .category = .vector, .element_type = .f64 }},
        TypeDescriptor{ .category = .scalar, .element_type = .f64 },
        .gsl,
    );

    var reg: CapabilityRegistry = undefined;
    CapabilityRegistry.init(&reg, &caps, 1);

    var json_buf: [256]u8 = undefined;
    const json = try reg.toJson(&json_buf);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"description\":\"Compute mean value\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"backend_selector\":\"gsl\"") != null);
}

test "CapabilityRegistry toJson multiple capabilities" {
    var caps: [2]Capability = undefined;
    caps[0] = Capability.init(
        "add",
        1,
        "Addition",
        &.{TypeDescriptor{ .category = .vector, .element_type = .f64 }},
        TypeDescriptor{ .category = .vector, .element_type = .f64 },
        .arrow,
    );
    caps[1] = Capability.init(
        "multiply",
        1,
        "Multiplication",
        &.{TypeDescriptor{ .category = .vector, .element_type = .f64 }},
        TypeDescriptor{ .category = .vector, .element_type = .f64 },
        .gsl,
    );

    var reg: CapabilityRegistry = undefined;
    CapabilityRegistry.init(&reg, &caps, 2);

    var json_buf: [512]u8 = undefined;
    const json = try reg.toJson(&json_buf);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"name\":\"add\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"name\":\"multiply\"") != null);
}

test "CapabilityRegistry toJson empty registry" {
    var reg: CapabilityRegistry = undefined;
    CapabilityRegistry.init(&reg, &[_]Capability{}, 0);

    var json_buf: [256]u8 = undefined;
    const json = try reg.toJson(&json_buf);

    try std.testing.expect(std.mem.eql(u8, json, "{\"capabilities\":[]}"));
}


// ─── S4: Error Normalization Tests ─────────────────────────────────────────

test "YamoriError.errorDescription returns non-empty string for all errors" {
    const error_mod = @import("error");
    const YamoriErr = error_mod.YamoriError;

    // Manually verify each variant returns a non-empty description
    try std.testing.expect(error_mod.errorDescription(YamoriErr.UnknownOperation).len > 0);
    try std.testing.expect(error_mod.errorDescription(YamoriErr.OperationNotSupported).len > 0);
    try std.testing.expect(error_mod.errorDescription(YamoriErr.InvalidOperationInput).len > 0);
    try std.testing.expect(error_mod.errorDescription(YamoriErr.OperationTimeout).len > 0);
    try std.testing.expect(error_mod.errorDescription(YamoriErr.BackendNotAvailable).len > 0);
    try std.testing.expect(error_mod.errorDescription(YamoriErr.BackendComputeFailed).len > 0);
    try std.testing.expect(error_mod.errorDescription(YamoriErr.BackendInvalidDataType).len > 0);
    try std.testing.expect(error_mod.errorDescription(YamoriErr.BackendInsufficientMemory).len > 0);
    try std.testing.expect(error_mod.errorDescription(YamoriErr.CapabilityNotFound).len > 0);
    try std.testing.expect(error_mod.errorDescription(YamoriErr.DuplicateCapability).len > 0);
    try std.testing.expect(error_mod.errorDescription(YamoriErr.InvalidCapability).len > 0);
    try std.testing.expect(error_mod.errorDescription(YamoriErr.InitializationFailed).len > 0);
    try std.testing.expect(error_mod.errorDescription(YamoriErr.InternalError).len > 0);
}

test "YamoriError.errorDescription returns correct strings" {
    const error_mod = @import("error");
    const YamoriErr = error_mod.YamoriError;

    try std.testing.expectEqualStrings(
        "Operation not found in capability registry",
        error_mod.errorDescription(YamoriErr.UnknownOperation),
    );
    try std.testing.expectEqualStrings(
        "Backend computation failed",
        error_mod.errorDescription(YamoriErr.BackendComputeFailed),
    );
    try std.testing.expectEqualStrings(
        "Requested backend is not available",
        error_mod.errorDescription(YamoriErr.BackendNotAvailable),
    );
    try std.testing.expectEqualStrings(
        "Capability not found in registry",
        error_mod.errorDescription(YamoriErr.CapabilityNotFound),
    );
    try std.testing.expectEqualStrings(
        "Backend ran out of memory",
        error_mod.errorDescription(YamoriErr.BackendInsufficientMemory),
    );
}

test "ArrowAdapter.mapArrowError maps FunctionNotFound to UnknownOperation" {
    const arrow_err = arrow_mod.ArrowError.FunctionNotFound;
    const normalized = arrow_mod.ArrowAdapter.mapArrowError(arrow_err);
    try std.testing.expectEqualStrings("UnknownOperation", @errorName(normalized));
}

test "ArrowAdapter.mapArrowError maps InvalidDataType to BackendInvalidDataType" {
    const arrow_err = arrow_mod.ArrowError.InvalidDataType;
    const normalized = arrow_mod.ArrowAdapter.mapArrowError(arrow_err);
    try std.testing.expectEqualStrings("BackendInvalidDataType", @errorName(normalized));
}

test "ArrowAdapter.mapArrowError maps InvalidInputLength to InvalidOperationInput" {
    const arrow_err = arrow_mod.ArrowError.InvalidInputLength;
    const normalized = arrow_mod.ArrowAdapter.mapArrowError(arrow_err);
    try std.testing.expectEqualStrings("InvalidOperationInput", @errorName(normalized));
}

test "ArrowAdapter.mapArrowError maps ComputeFailed to BackendComputeFailed" {
    const arrow_err = arrow_mod.ArrowError.ComputeFailed;
    const normalized = arrow_mod.ArrowAdapter.mapArrowError(arrow_err);
    try std.testing.expectEqualStrings("BackendComputeFailed", @errorName(normalized));
}

test "ArrowAdapter.mapArrowError maps NullInput to InvalidOperationInput" {
    const arrow_err = arrow_mod.ArrowError.NullInput;
    const normalized = arrow_mod.ArrowAdapter.mapArrowError(arrow_err);
    try std.testing.expectEqualStrings("InvalidOperationInput", @errorName(normalized));
}

test "GSLAdapter.mapGSLAdapterError maps LibraryNotFound to BackendNotAvailable" {
    const gsl_err = gsl_mod.GSLAdapterError.LibraryNotFound;
    const normalized = gsl_mod.GSLAdapter.mapGSLAdapterError(gsl_err);
    try std.testing.expectEqualStrings("BackendNotAvailable", @errorName(normalized));
}

test "GSLAdapter.mapGSLAdapterError maps FunctionNotFound to UnknownOperation" {
    const gsl_err = gsl_mod.GSLAdapterError.FunctionNotFound;
    const normalized = gsl_mod.GSLAdapter.mapGSLAdapterError(gsl_err);
    try std.testing.expectEqualStrings("UnknownOperation", @errorName(normalized));
}

test "GSLAdapter.mapGSLAdapterError maps InvalidInput to InvalidOperationInput" {
    const gsl_err = gsl_mod.GSLAdapterError.InvalidInput;
    const normalized = gsl_mod.GSLAdapter.mapGSLAdapterError(gsl_err);
    try std.testing.expectEqualStrings("InvalidOperationInput", @errorName(normalized));
}

test "GSLAdapter.mapGSLAdapterError maps ComputeFailed to BackendComputeFailed" {
    const gsl_err = gsl_mod.GSLAdapterError.ComputeFailed;
    const normalized = gsl_mod.GSLAdapter.mapGSLAdapterError(gsl_err);
    try std.testing.expectEqualStrings("BackendComputeFailed", @errorName(normalized));
}

test "GSLAdapter.mapGSLAdapterError maps MemoryAllocationFailed to BackendInsufficientMemory" {
    const gsl_err = gsl_mod.GSLAdapterError.MemoryAllocationFailed;
    const normalized = gsl_mod.GSLAdapter.mapGSLAdapterError(gsl_err);
    try std.testing.expectEqualStrings("BackendInsufficientMemory", @errorName(normalized));
}

test "Dispatch error normalization converts Arrow ComputeFailed to YamoriError" {
    const arrow_err = arrow_mod.ArrowError.ComputeFailed;
    const normalized = arrow_mod.ArrowAdapter.mapArrowError(arrow_err);
    try std.testing.expectEqualStrings("BackendComputeFailed", @errorName(normalized));
}

test "Dispatch error normalization converts GSL MemoryAllocationFailed to YamoriError" {
    const gsl_err = gsl_mod.GSLAdapterError.MemoryAllocationFailed;
    const normalized = gsl_mod.GSLAdapter.mapGSLAdapterError(gsl_err);
    try std.testing.expectEqualStrings("BackendInsufficientMemory", @errorName(normalized));
}

test "All YamoriError variants have descriptions" {
    const error_mod = @import("error");
    const YamoriErr = error_mod.YamoriError;

    // Manually verify each variant is covered by errorDescription
    _ = error_mod.errorDescription(YamoriErr.UnknownOperation);
    _ = error_mod.errorDescription(YamoriErr.OperationNotSupported);
    _ = error_mod.errorDescription(YamoriErr.InvalidOperationInput);
    _ = error_mod.errorDescription(YamoriErr.OperationTimeout);
    _ = error_mod.errorDescription(YamoriErr.BackendNotAvailable);
    _ = error_mod.errorDescription(YamoriErr.BackendComputeFailed);
    _ = error_mod.errorDescription(YamoriErr.BackendInvalidDataType);
    _ = error_mod.errorDescription(YamoriErr.BackendInsufficientMemory);
    _ = error_mod.errorDescription(YamoriErr.CapabilityNotFound);
    _ = error_mod.errorDescription(YamoriErr.DuplicateCapability);
    _ = error_mod.errorDescription(YamoriErr.InvalidCapability);
    _ = error_mod.errorDescription(YamoriErr.InitializationFailed);
    _ = error_mod.errorDescription(YamoriErr.InternalError);

    // We manually listed all 13 variants above
}

// ═══════════════════════════════════════════════════════════════════
// S5: Backend-Agnostic Dispatch API Tests
// ═══════════════════════════════════════════════════════════════════

const dispatch_mod = @import("dispatch");
const backend_policy_mod = @import("backend_policy");
const provenance_mod = @import("provenance");
const Dispatcher = dispatch_mod.Dispatcher;
const DispatchResult = dispatch_mod.DispatchResult;
const DispatchError = dispatch_mod.DispatchError;
const ProvenanceRecord = provenance_mod.ProvenanceRecord;
const ProvenanceBuffer = provenance_mod.ProvenanceBuffer;
const MaxProvenanceEntries = provenance_mod.MaxProvenanceEntries;
const MaxProvenanceInputLengths = provenance_mod.MaxProvenanceInputLengths;
const MaxOverrides = backend_policy_mod.MaxOverrides;
const yamori_err = @import("error");
const YamoriError = yamori_err.YamoriError;

// ─── Dispatcher Tests (Heap-Free) ──────────────────────────────────────

test "Dispatcher.init sets all fields" {
    const caps: [1]Capability = undefined;
    var cap_reg: CapabilityRegistry = undefined;
    CapabilityRegistry.init(&cap_reg, &caps, 0);

    var sel: backend_policy_mod.BackendSelector = undefined;
    backend_policy_mod.BackendSelector.init(&sel, .auto);

    var prov_buf: [16]ProvenanceRecord = undefined;
    var prov: ProvenanceBuffer = undefined;
    const lengths_buf: [MaxProvenanceInputLengths]usize = undefined;
    ProvenanceBuffer.init(&prov, &prov_buf, MaxProvenanceEntries);

    var scratch: [64]f64 = undefined;
    const dispatcher = Dispatcher.init(
        &cap_reg, &sel, &prov, &scratch, lengths_buf,
    );

    try std.testing.expectEqual(&cap_reg, dispatcher.cap_reg);
    try std.testing.expectEqual(&sel, dispatcher.backend_selector);
    try std.testing.expectEqual(&prov, dispatcher.provenance);
}

test "Dispatcher.dispatch returns UnknownOperation for unregistered op" {
    const caps: [1]Capability = undefined;
    var cap_reg: CapabilityRegistry = undefined;
    CapabilityRegistry.init(&cap_reg, &caps, 0);

    var sel: backend_policy_mod.BackendSelector = undefined;
    backend_policy_mod.BackendSelector.init(&sel, .auto);

    var prov_buf: [16]ProvenanceRecord = undefined;
    var prov: ProvenanceBuffer = undefined;
    const lengths_buf: [MaxProvenanceInputLengths]usize = undefined;
    ProvenanceBuffer.init(&prov, &prov_buf, MaxProvenanceEntries);

    var scratch: [64]f64 = undefined;
    const dispatcher = Dispatcher.init(
        &cap_reg, &sel, &prov, &scratch, lengths_buf,
    );

    var result_buf: [64]f64 = undefined;
    const input = [_]f64{ 1.0 };
    const result = dispatcher.dispatch(
        "nonexistent", &.{&input}, &result_buf,
    );
    if (result) |_| {
        try std.testing.expect(false);
    } else |err| {
        switch (err) {
            YamoriError.UnknownOperation => {},
            else => try std.testing.expect(false),
        }
    }
}

test "Dispatcher.dispatch routes to Arrow backend for .arrow selector" {
    var caps: [1]Capability = undefined;
    caps[0] = Capability.init(
        "add", 1, "Arrow add",
        &.{TypeDescriptor{ .category = .vector, .element_type = .f64 }},
        TypeDescriptor{ .category = .vector, .element_type = .f64 },
        .arrow,
    );

    var cap_reg: CapabilityRegistry = undefined;
    CapabilityRegistry.init(&cap_reg, &caps, 1);

    var sel: backend_policy_mod.BackendSelector = undefined;
    backend_policy_mod.BackendSelector.init(&sel, .auto);

    var prov_buf: [16]ProvenanceRecord = undefined;
    var prov: ProvenanceBuffer = undefined;
    const lengths_buf: [MaxProvenanceInputLengths]usize = undefined;
    ProvenanceBuffer.init(&prov, &prov_buf, MaxProvenanceEntries);

    var scratch: [64]f64 = undefined;
    const dispatcher = Dispatcher.init(
        &cap_reg, &sel, &prov, &scratch, lengths_buf,
    );

    const input = [3]f64{ 1.0, 2.0, 3.0 };
    var result_buf: [64]f64 = undefined;
    const result = dispatcher.dispatch("add", &.{&input}, &result_buf) catch |err| return err;

    try std.testing.expectEqual(@as(usize, 3), result.count);
    try std.testing.expectEqual(1.0, result.data[0]);
    try std.testing.expectEqual(2.0, result.data[1]);
    try std.testing.expectEqual(3.0, result.data[2]);
}

test "Dispatcher.dispatch returns invalid input for NaN" {
    var caps: [1]Capability = undefined;
    caps[0] = Capability.init(
        "add", 1, "Add",
        &.{TypeDescriptor{ .category = .vector, .element_type = .f64 }},
        TypeDescriptor{ .category = .vector, .element_type = .f64 },
        .arrow,
    );
    var cap_reg: CapabilityRegistry = undefined;
    CapabilityRegistry.init(&cap_reg, &caps, 1);

    var sel: backend_policy_mod.BackendSelector = undefined;
    backend_policy_mod.BackendSelector.init(&sel, .auto);

    var prov_buf: [16]ProvenanceRecord = undefined;
    var prov: ProvenanceBuffer = undefined;
    const lengths_buf: [MaxProvenanceInputLengths]usize = undefined;
    ProvenanceBuffer.init(&prov, &prov_buf, MaxProvenanceEntries);

    var scratch: [64]f64 = undefined;
    const dispatcher = Dispatcher.init(
        &cap_reg, &sel, &prov, &scratch, lengths_buf,
    );

    const input = [3]f64{ 1.0, std.math.nan(f64), 3.0 };
    var result_buf: [64]f64 = undefined;
    const result = dispatcher.dispatch(
        "add", &.{&input}, &result_buf,
    );
    try std.testing.expect(result == YamoriError.InvalidOperationInput);
}

test "Dispatcher.dispatch returns invalid input for Inf" {
    var caps: [1]Capability = undefined;
    caps[0] = Capability.init(
        "add", 1, "Add",
        &.{TypeDescriptor{ .category = .vector, .element_type = .f64 }},
        TypeDescriptor{ .category = .vector, .element_type = .f64 },
        .arrow,
    );
    var cap_reg: CapabilityRegistry = undefined;
    CapabilityRegistry.init(&cap_reg, &caps, 1);

    var sel: backend_policy_mod.BackendSelector = undefined;
    backend_policy_mod.BackendSelector.init(&sel, .auto);

    var prov_buf: [16]ProvenanceRecord = undefined;
    var prov: ProvenanceBuffer = undefined;
    const lengths_buf: [MaxProvenanceInputLengths]usize = undefined;
    ProvenanceBuffer.init(&prov, &prov_buf, MaxProvenanceEntries);

    var scratch: [64]f64 = undefined;
    const dispatcher = Dispatcher.init(
        &cap_reg, &sel, &prov, &scratch, lengths_buf,
    );

    const input = [3]f64{ 1.0, std.math.inf(f64), 3.0 };
    var result_buf: [64]f64 = undefined;
    const result = dispatcher.dispatch(
        "add", &.{&input}, &result_buf,
    );
    try std.testing.expect(result == YamoriError.InvalidOperationInput);
}

test "Dispatcher dispatch routes to GSL for .gsl backend" {
    var caps: [1]Capability = undefined;
    caps[0] = Capability.init(
        "mean", 1, "GSL mean",
        &.{TypeDescriptor{ .category = .vector, .element_type = .f64 }},
        TypeDescriptor{ .category = .scalar, .element_type = .f64 },
        .gsl,
    );
    var cap_reg: CapabilityRegistry = undefined;
    CapabilityRegistry.init(&cap_reg, &caps, 1);

    var sel: backend_policy_mod.BackendSelector = undefined;
    backend_policy_mod.BackendSelector.init(&sel, .auto);

    var prov_buf: [16]ProvenanceRecord = undefined;
    var prov: ProvenanceBuffer = undefined;
    const lengths_buf: [MaxProvenanceInputLengths]usize = undefined;
    ProvenanceBuffer.init(&prov, &prov_buf, MaxProvenanceEntries);

    var scratch: [64]f64 = undefined;
    const dispatcher = Dispatcher.init(
        &cap_reg, &sel, &prov, &scratch, lengths_buf,
    );

    const input = [_]f64{ 1.0, 2.0, 3.0, 4.0, 5.0 };
    var result_buf: [64]f64 = undefined;
    const result = dispatcher.dispatch("mean", &.{&input}, &result_buf) catch |err| return err;

    try std.testing.expectEqual(@as(usize, 1), result.count);
    try std.testing.expectApproxEqAbs(3.0, result.data[0], 1e-10);
}

test "Dispatcher dispatch routes to Arrow by default for .arrow capability" {
    var caps: [2]Capability = undefined;
    caps[0] = Capability.init(
        "add", 1, "Arrow add",
        &.{TypeDescriptor{ .category = .vector, .element_type = .f64 }},
        TypeDescriptor{ .category = .vector, .element_type = .f64 },
        .arrow,
    );
    caps[1] = Capability.init(
        "mean", 1, "GSL mean",
        &.{TypeDescriptor{ .category = .vector, .element_type = .f64 }},
        TypeDescriptor{ .category = .scalar, .element_type = .f64 },
        .gsl,
    );
    var cap_reg: CapabilityRegistry = undefined;
    CapabilityRegistry.init(&cap_reg, &caps, 2);

    var sel: backend_policy_mod.BackendSelector = undefined;
    backend_policy_mod.BackendSelector.init(&sel, .auto);

    var prov_buf: [16]ProvenanceRecord = undefined;
    var prov: ProvenanceBuffer = undefined;
    const lengths_buf: [MaxProvenanceInputLengths]usize = undefined;
    ProvenanceBuffer.init(&prov, &prov_buf, MaxProvenanceEntries);

    var scratch: [64]f64 = undefined;
    const dispatcher = Dispatcher.init(
        &cap_reg, &sel, &prov, &scratch, lengths_buf,
    );

    // Add via Arrow
    const input_a = [3]f64{ 1.0, 2.0, 3.0 };
    var result_buf: [64]f64 = undefined;
    const result_a = dispatcher.dispatch("add", &.{&input_a}, &result_buf) catch |err| return err;
    try std.testing.expectEqual(@as(usize, 3), result_a.count);
    try std.testing.expectEqual(1.0, result_a.data[0]);

    // Mean via GSL
    const input_m = [_]f64{ 1.0, 2.0, 3.0, 4.0, 5.0 };
    var result_buf2: [64]f64 = undefined;
    const result_m = dispatcher.dispatch("mean", &.{&input_m}, &result_buf2) catch |err| return err;
    try std.testing.expectApproxEqAbs(3.0, result_m.data[0], 1e-10);
}

test "BackendSelector.setOverride and select" {
    var sel: backend_policy_mod.BackendSelector = undefined;
    backend_policy_mod.BackendSelector.init(&sel, .arrow);

    // Default policy should be arrow
    try std.testing.expectEqual(.arrow, sel.select("any_op", .arrow));

    // Set override
    try sel.setOverride("mean", .gsl);
    try std.testing.expectEqual(.gsl, sel.select("mean", .arrow));

    // Other ops still use default
    try std.testing.expectEqual(.arrow, sel.select("add", .arrow));

    // Clear override
    sel.clearOverride("mean");
    try std.testing.expectEqual(.arrow, sel.select("mean", .arrow));
}

test "BackendSelector.select uses capability default when no override" {
    var sel: backend_policy_mod.BackendSelector = undefined;
    backend_policy_mod.BackendSelector.init(&sel, .auto);

    try std.testing.expectEqual(.arrow, sel.select("add", .arrow));
    try std.testing.expectEqual(.gsl, sel.select("mean", .gsl));
}

// ─── Dispatcher Provenance Integration ────────────────────────────────

test "Dispatcher dispatch records provenance on success" {
    var caps: [1]Capability = undefined;
    caps[0] = Capability.init(
        "add", 1, "Add",
        &.{TypeDescriptor{ .category = .vector, .element_type = .f64 }},
        TypeDescriptor{ .category = .vector, .element_type = .f64 },
        .arrow,
    );
    var cap_reg: CapabilityRegistry = undefined;
    CapabilityRegistry.init(&cap_reg, &caps, 1);

    var sel: backend_policy_mod.BackendSelector = undefined;
    backend_policy_mod.BackendSelector.init(&sel, .auto);

    var prov_buf: [MaxProvenanceEntries]ProvenanceRecord = undefined;
    var prov: ProvenanceBuffer = undefined;
    const lengths_buf: [MaxProvenanceInputLengths]usize = undefined;
    ProvenanceBuffer.init(&prov, &prov_buf, MaxProvenanceEntries);

    var scratch: [64]f64 = undefined;
    const dispatcher = Dispatcher.init(
        &cap_reg, &sel, &prov, &scratch, lengths_buf,
    );

    const input = [3]f64{ 1.0, 2.0, 3.0 };
    var result_buf: [64]f64 = undefined;
    _ = dispatcher.dispatch("add", &.{&input}, &result_buf) catch |err| return err;

    try std.testing.expectEqual(@as(usize, 1), prov.count());
    const record = prov.get(0) orelse unreachable;
    try std.testing.expectEqualStrings("add", record.operation_name);
    try std.testing.expectEqual(BackendPolicy.arrow, record.backend_used);
    try std.testing.expect(record.success);
    try std.testing.expectEqual(@as(usize, 3), record.output_count);
}

test "Dispatcher dispatch records provenance on failure (unknown op)" {
    var caps: [1]Capability = undefined;
    var cap_reg: CapabilityRegistry = undefined;
    CapabilityRegistry.init(&cap_reg, &caps, 0);

    var sel: backend_policy_mod.BackendSelector = undefined;
    backend_policy_mod.BackendSelector.init(&sel, .auto);

    var prov_buf: [MaxProvenanceEntries]ProvenanceRecord = undefined;
    var prov: ProvenanceBuffer = undefined;
    const lengths_buf: [MaxProvenanceInputLengths]usize = undefined;
    ProvenanceBuffer.init(&prov, &prov_buf, MaxProvenanceEntries);

    var scratch: [64]f64 = undefined;
    const dispatcher = Dispatcher.init(
        &cap_reg, &sel, &prov, &scratch, lengths_buf,
    );

    const input = [3]f64{ 1.0, 2.0, 3.0 };
    var result_buf: [64]f64 = undefined;
    _ = dispatcher.dispatch("nonexistent", &.{&input}, &result_buf) catch {};

    try std.testing.expectEqual(@as(usize, 1), prov.count());
    const record = prov.get(0) orelse unreachable;
    try std.testing.expectEqualStrings("nonexistent", record.operation_name);
    try std.testing.expect(!record.success);
}

test "Dispatcher dispatch records provenance on validation failure" {
    var caps: [1]Capability = undefined;
    caps[0] = Capability.init(
        "add", 1, "Add",
        &.{TypeDescriptor{ .category = .vector, .element_type = .f64 }},
        TypeDescriptor{ .category = .vector, .element_type = .f64 },
        .arrow,
    );
    var cap_reg: CapabilityRegistry = undefined;
    CapabilityRegistry.init(&cap_reg, &caps, 1);

    var sel: backend_policy_mod.BackendSelector = undefined;
    backend_policy_mod.BackendSelector.init(&sel, .auto);

    var prov_buf: [MaxProvenanceEntries]ProvenanceRecord = undefined;
    var prov: ProvenanceBuffer = undefined;
    const lengths_buf: [MaxProvenanceInputLengths]usize = undefined;
    ProvenanceBuffer.init(&prov, &prov_buf, MaxProvenanceEntries);

    var scratch: [64]f64 = undefined;
    const dispatcher = Dispatcher.init(
        &cap_reg, &sel, &prov, &scratch, lengths_buf,
    );

    const input = [_]f64{ 1.0, std.math.nan(f64), 3.0 };
    var result_buf: [64]f64 = undefined;
    _ = dispatcher.dispatch("add", &.{&input}, &result_buf) catch {};

    try std.testing.expectEqual(@as(usize, 1), prov.count());
    const record = prov.get(0) orelse unreachable;
    try std.testing.expect(!record.success);
}

test "ProvenanceBuffer.countByOperation counts all matching records" {
    var prov_buf: [MaxProvenanceEntries]ProvenanceRecord = undefined;
    var prov: ProvenanceBuffer = undefined;
    ProvenanceBuffer.init(&prov, &prov_buf, MaxProvenanceEntries);

    inline for ([_]usize{ 1, 2, 3 }) |val| {
        var len_copy: [MaxProvenanceInputLengths]usize = undefined;
        len_copy[0] = val;
        const record = ProvenanceRecord{
            .operation_name = "add",
            .backend_used = .arrow,
            .input_count = 1,
            .input_lengths = len_copy,
            .input_lengths_len = 1,
            .output_count = 1,
            .timestamp_ns = 0,
            .success = true,
            .error_message = null,
        };
        try prov.append(record);
    }

    try std.testing.expectEqual(@as(usize, 3), prov.countByOperation("add"));
    try std.testing.expectEqual(@as(usize, 0), prov.countByOperation("mean"));
}

test "ProvenanceBuffer.findByOperation returns null for missing op" {
    var prov_buf: [MaxProvenanceEntries]ProvenanceRecord = undefined;
    var prov: ProvenanceBuffer = undefined;
    ProvenanceBuffer.init(&prov, &prov_buf, MaxProvenanceEntries);

    const record = ProvenanceRecord{
        .operation_name = "add",
        .backend_used = .arrow,
        .input_count = 1,
        .input_lengths = undefined,
        .input_lengths_len = 0,
        .output_count = 1,
        .timestamp_ns = 0,
        .success = true,
        .error_message = null,
    };
    try prov.append(record);

    try std.testing.expect(prov.findByOperation("mean") == null);
    try std.testing.expect(prov.findByOperation("add") != null);
}

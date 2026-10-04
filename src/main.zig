const std = @import("std");
const capability = @import("capability.zig");
const registry_mod = @import("registry.zig");
const arrow_mod = @import("arrow_adapter.zig");
pub const Capability = capability.Capability;
pub const TypeDescriptor = capability.TypeDescriptor;
pub const CapabilityCategory = capability.CapabilityCategory;
pub const ElementType = capability.ElementType;
pub const BackendSelector = capability.BackendSelector;
pub const CapabilityRegistry = registry_mod.CapabilityRegistry;

pub const formula = struct {
    pub const NamedFormula = struct {
        name: []const u8,
        sources: []const []const u8,
        operation: []const u8,
    };

    pub const FormulaRegistry = struct {
        formulas: std.StringHashMap(NamedFormula),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) FormulaRegistry {
            return FormulaRegistry{
                .formulas = std.StringHashMap(NamedFormula).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *FormulaRegistry) void {
            var it = self.formulas.iterator();
            while (it.next()) |entry| {
                const val = entry.value_ptr;
                self.allocator.free(val.name);
                self.allocator.free(val.operation);
                for (val.sources) |s| {
                    self.allocator.free(s);
                }
                self.allocator.free(val.sources);
            }
            self.formulas.deinit();
        }
    };

    pub const RegistryError = error{
        DuplicateName,
        NotFound,
        AllocationFailed,
    };

    pub fn registryInit(allocator: std.mem.Allocator) RegistryError!FormulaRegistry {
        return FormulaRegistry.init(allocator);
    }

    pub fn registryDeinit(registry: *FormulaRegistry) void {
        registry.deinit();
    }

    pub fn registryAdd(
        registry: *FormulaRegistry,
        f: NamedFormula,
    ) RegistryError!void {
        // Check for duplicate key before inserting.
        if (registry.formulas.contains(f.name)) {
            return RegistryError.DuplicateName;
        }

        // Store owned copies of all string fields.
        const name_owned = (registry.allocator.dupe(u8, f.name)) catch return RegistryError.AllocationFailed;
        const operation_owned = (registry.allocator.dupe(u8, f.operation)) catch {
            registry.allocator.free(name_owned);
            return RegistryError.AllocationFailed;
        };
        const sources_owned = (registry.allocator.dupe([]const u8, f.sources)) catch {
            registry.allocator.free(name_owned);
            registry.allocator.free(operation_owned);
            return RegistryError.AllocationFailed;
        };
        var sources_copy = (registry.allocator.alloc([]const u8, sources_owned.len)) catch {
            registry.allocator.free(name_owned);
            registry.allocator.free(operation_owned);
            return RegistryError.AllocationFailed;
        };
        for (sources_owned, 0..) |src, i| {
            sources_copy[i] = (registry.allocator.dupe(u8, src)) catch {
                registry.allocator.free(name_owned);
                registry.allocator.free(operation_owned);
                for (0..i) |j| {
                    registry.allocator.free(sources_copy[j]);
                }
                registry.allocator.free(sources_copy);
                registry.allocator.free(sources_owned);
                return RegistryError.AllocationFailed;
            };
        }
        registry.allocator.free(sources_owned);

        const value = NamedFormula{
            .name = name_owned,
            .sources = sources_copy,
            .operation = operation_owned,
        };

        (registry.formulas.put(name_owned, value)) catch return RegistryError.AllocationFailed;
    }

    pub fn registryGet(
        registry: *const FormulaRegistry,
        name: []const u8,
    ) RegistryError!*const NamedFormula {
        const result = registry.formulas.get(name);
        if (result) |nf| {
            return &nf;
        }
        return RegistryError.NotFound;
    }

    pub fn registryList(
        registry: *const FormulaRegistry,
        allocator: std.mem.Allocator,
    ) RegistryError![]NamedFormula {
        const count = registry.formulas.count();
        const result = try allocator.alloc(NamedFormula, count);
        var i: usize = 0;
        var it = registry.formulas.iterator();
        while (it.next()) |entry| {
            const val = entry.value_ptr;
            result[i].name = try allocator.dupe(u8, val.name);
            result[i].operation = try allocator.dupe(u8, val.operation);
            result[i].sources = try allocator.alloc([]const u8, val.sources.len);
            for (val.sources, 0..) |s, si| {
                result[i].sources[si] = try allocator.dupe(u8, s);
            }
            i += 1;
        }
        return result;
    }

    pub fn registryHas(
        registry: *const FormulaRegistry,
        name: []const u8,
    ) bool {
        return registry.formulas.contains(name);
    }

    pub fn registryRemove(
        registry: *FormulaRegistry,
        name: []const u8,
    ) RegistryError!void {
        const found = registry.formulas.fetchRemove(name);
        if (found) |kv| {
            registry.allocator.free(kv.value.name);
            for (kv.value.sources) |s| {
                registry.allocator.free(s);
            }
            registry.allocator.free(kv.value.sources);
        } else {
            return RegistryError.NotFound;
        }
    }
};

// ─── Cycle Detection ────────────────────────────────────────────────────

pub const cycleDetector = struct {
    pub const CycleError = error{
        CycleDetected,
    };

    pub const CycleReport = struct {
        cycle_path: []const []const u8,
        allocator: std.mem.Allocator,
    };

    /// DFS helper: returns true if cycle found
    fn dfsCycle(
        node: []const u8,
        adj: std.StringHashMap([]const []const u8),
        colors: *std.StringHashMap(u8),
        path: *std.ArrayListUnmanaged([]const u8),
        alloc: std.mem.Allocator,
        depth: usize,
        max_depth: usize,
    ) CycleError!bool {
        if (depth > max_depth) return CycleError.CycleDetected;
        // Mark node as Gray (1)
        (colors.put(node, 1)) catch return CycleError.CycleDetected;

        // Add to current path
        const node_copy = (alloc.dupe(u8, node)) catch return CycleError.CycleDetected;
        (path.append(alloc, node_copy)) catch return CycleError.CycleDetected;

        // Visit neighbors (dependencies)
        if (adj.get(node)) |deps| {
            for (deps) |dep| {
                // Get color of neighbor
                const color = colors.get(dep) orelse continue; // Undefined ref, skip

                if (color == 1) {
                    // Gray node found → cycle detected!
                    // Don't free path here — return true to let caller handle cleanup.
                    return true;
                } else if (color == 0) {
                    // White node → recurse
                    if (try dfsCycle(dep, adj, colors, path, alloc, depth + 1, max_depth)) {
                        return true;
                    }
                }
                // Black node → skip
            }
        }

        // Mark node as Black (2)
        (colors.put(node, 2)) catch return CycleError.CycleDetected;

        // Remove from path and free
        if (path.pop()) |popped| alloc.free(popped);

        return false;
    }

    /// Detect cycles before adding a new formula
    /// Returns CycleError.CycleDetected if the new formula would create a cycle
    pub fn detectCycleBeforeAdd(
        registry: *const formula.FormulaRegistry,
        new_formula: formula.NamedFormula,
        allocator: std.mem.Allocator,
    ) CycleError!void {
        // Build adjacency list from existing formulas + new formula
        var adj = std.StringHashMap([]const []const u8).init(allocator);
        var all_names: std.ArrayListUnmanaged([]const u8) = .empty;
        var colors = std.StringHashMap(u8).init(allocator);
        var path_list: std.ArrayListUnmanaged([]const u8) = .empty;

        var all_clean = false;
        var adj_clean = false;
        var colors_clean = false;
        var path_clean = false;

        // Try to allocate everything; on failure, free what we have.
        errdefer {
            if (all_clean == false) {
                for (all_names.items) |n| allocator.free(n);
                all_names.deinit(allocator);
                all_clean = true;
            }
            if (adj_clean == false) {
                var it = adj.iterator();
                while (it.next()) |entry| {
                    const srcs = entry.value_ptr.*;
                    for (srcs) |s| allocator.free(s);
                    allocator.free(srcs);
                    allocator.free(entry.key_ptr.*);
                }
                adj.deinit();
                adj_clean = true;
            }
            if (colors_clean == false) {
                colors.deinit();
                colors_clean = true;
            }
            if (path_clean == false) {
                for (path_list.items) |p| allocator.free(p);
                path_list.deinit(allocator);
                path_clean = true;
            }
        }

        // Add existing formulas
        var it = registry.formulas.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr;
            const val = entry.value_ptr;

            const name_copy = (allocator.dupe(u8, key.*)) catch return;
            (all_names.append(allocator, name_copy)) catch return;

            if (val.sources.len > 0) {
                const sources_copy = (allocator.alloc([]const u8, val.sources.len)) catch return;
                for (val.sources, 0..) |src, idx| {
                    sources_copy[idx] = (allocator.dupe(u8, src)) catch return;
                }
                const key_copy = (allocator.dupe(u8, name_copy)) catch return;
                (adj.put(key_copy, sources_copy)) catch return;
            }
        }

        // Add new formula to adjacency list
        const new_name_copy = (allocator.dupe(u8, new_formula.name)) catch return;
        (all_names.append(allocator, new_name_copy)) catch return;

        if (new_formula.sources.len > 0) {
            const sources_copy = (allocator.alloc([]const u8, new_formula.sources.len)) catch return;
            for (new_formula.sources, 0..) |src, idx| {
                sources_copy[idx] = (allocator.dupe(u8, src)) catch return;
            }
            const key_copy = (allocator.dupe(u8, new_name_copy)) catch return;
            (adj.put(key_copy, sources_copy)) catch return;
        }

        // Initialize all nodes as White (0)
        for (all_names.items) |node| {
            (colors.put(node, 0)) catch return;
        }

        // Run DFS from each unvisited node
        var cycle_found = false;
        for (all_names.items) |start_node| {
            if (colors.get(start_node)) |color| {
                if (color != 0) continue;
                const max_depth = registry.formulas.count();
                if (try dfsCycle(start_node, adj, &colors, &path_list, allocator, 0, max_depth)) {
                    cycle_found = true;
                    break;
                }
            }
        }

        // Mark everything as cleaned BEFORE explicit cleanup so errdefer doesn't double-free
        all_clean = true;
        adj_clean = true;
        colors_clean = true;
        path_clean = true;

        // Free all_names items
        for (all_names.items) |n| allocator.free(n);
        all_names.deinit(allocator);

        // Free adj keys and values
        var adj_free_it = adj.iterator();
        while (adj_free_it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            const srcs = entry.value_ptr.*;
            for (srcs) |s| allocator.free(s);
            allocator.free(srcs);
        }
        adj.deinit();

        // Free colors
        colors.deinit();

        // Free path_list
        for (path_list.items) |p| allocator.free(p);
        path_list.deinit(allocator);

        if (cycle_found) {
            return CycleError.CycleDetected;
        }
    }

    /// Detect all cycles in the graph and return a report with the first cycle found
    pub fn detectAllCycles(
        registry: *const formula.FormulaRegistry,
        allocator: std.mem.Allocator,
    ) CycleError!CycleReport {
        // Build adjacency list from registry
        var adj = std.StringHashMap([]const []const u8).init(allocator);
        errdefer {
            var it = adj.iterator();
            while (it.next()) |entry| {
                const srcs = entry.value_ptr.*;
                for (srcs) |s| allocator.free(s);
                allocator.free(srcs);
                if (entry.key_ptr.* != null) allocator.free(entry.key_ptr.*);
            }
            adj.deinit();
        }

        var all_names: std.ArrayListUnmanaged([]const u8) = .empty;
        errdefer {
            for (all_names.items) |n| allocator.free(n);
            all_names.deinit(allocator);
        }

        var it = registry.formulas.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr;
            const val = entry.value_ptr;

            const name_copy = (allocator.dupe(u8, key.*)) catch {
                return CycleError.CycleDetected;
            };
            (all_names.append(allocator, name_copy)) catch {
                return CycleError.CycleDetected;
            };

            if (val.sources.len > 0) {
                const sources_copy = (allocator.alloc([]const u8, val.sources.len)) catch {
                    return CycleError.CycleDetected;
                };
                for (val.sources, 0..) |src, i| {
                    sources_copy[i] = (allocator.dupe(u8, src)) catch {
                        return CycleError.CycleDetected;
                    };
                }
                // adj owns its own copy of the name for the key.
                const key_copy = (allocator.dupe(u8, name_copy)) catch {
                    return CycleError.CycleDetected;
                };
                (adj.put(key_copy, sources_copy)) catch {
                    return CycleError.CycleDetected;
                };
            }
        }

        // DFS three-color marking
        var colors = std.StringHashMap(u8).init(allocator);
        errdefer colors.deinit();

        var path_list: std.ArrayListUnmanaged([]const u8) = .empty;
        errdefer {
            for (path_list.items) |p| allocator.free(p);
            path_list.deinit(allocator);
        }

        // Initialize all nodes as White (0)
        var color_it = all_names.iterator();
        while (color_it.next()) |item| {
            (colors.put(item.*, 0)) catch {
                return CycleError.CycleDetected;
            };
        }

        // Run DFS from each unvisited node, return first cycle found
        var cycle_path: std.ArrayListUnmanaged([]const u8) = .empty;
        errdefer {
            for (cycle_path.items) |cp| allocator.free(cp);
            cycle_path.deinit(allocator);
        }

        for (all_names.items) |start_node| {
            if (colors.get(start_node)) |color| {
                if (color != 0) continue;
                const max_depth = registry.formulas.count();
                if (dfsCycleWithReport(start_node, adj, &colors, &path_list, &cycle_path, allocator, 0, max_depth)) {
                    break;
                }
            }
        }

        // Cleanup
        for (all_names.items) |n| allocator.free(n);
        all_names.deinit(allocator);

        // Free adj keys and values
        var adj_free_it = adj.iterator();
        while (adj_free_it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            const srcs = entry.value_ptr.*;
            for (srcs) |s| allocator.free(s);
            allocator.free(srcs);
        }
        adj.deinit();

        return CycleReport{
            .cycle_path = (cycle_path.toOwnedSlice(allocator)) catch {
                return CycleError.CycleDetected;
            },
            .allocator = allocator,
        };
    }

    /// DFS helper that collects cycle path for report
    fn dfsCycleWithReport(
        node: []const u8,
        adj: std.StringHashMap([]const []const u8),
        colors: *std.StringHashMap(u8),
        path: *std.ArrayListUnmanaged([]const u8),
        cycle_path: *std.ArrayListUnmanaged([]const u8),
        alloc: std.mem.Allocator,
        depth: usize,
        max_depth: usize,
    ) CycleError!bool {
        if (depth > max_depth) return CycleError.CycleDetected;
        // Mark node as Gray (1)
        (colors.put(node, 1)) catch return CycleError.CycleDetected;

        // Add to current path
        const node_copy = (alloc.dupe(u8, node)) catch return CycleError.CycleDetected;
        (path.append(alloc, node_copy)) catch return CycleError.CycleDetected;

        // Visit neighbors (dependencies)
        if (adj.get(node)) |deps| {
            for (deps) |dep| {
                const color = colors.get(dep) orelse continue;

                if (color == 1) {
                    // Cycle detected! Extract cycle from path
                    var found = false;
                    for (path.items) |p| {
                        if (found) {
                            const p_copy = (alloc.dupe(u8, p)) catch return CycleError.CycleDetected;
                            (cycle_path.append(alloc, p_copy)) catch return CycleError.CycleDetected;
                        }
                        if (std.mem.eql(u8, p, dep)) {
                            found = true;
                            const p_copy = (alloc.dupe(u8, p)) catch return CycleError.CycleDetected;
                            (cycle_path.append(alloc, p_copy)) catch return CycleError.CycleDetected;
                        }
                    }
                    if (!found) {
                        const dep_copy = (alloc.dupe(u8, dep)) catch return CycleError.CycleDetected;
                        (cycle_path.append(alloc, dep_copy)) catch return CycleError.CycleDetected;
                    }
                    return true;
                } else if (color == 0) {
                    if (try dfsCycleWithReport(dep, adj, colors, path, cycle_path, alloc, depth + 1, max_depth)) {
                        return true;
                    }
                }
            }
        }

        // Mark node as Black (2)
        (colors.put(node, 2)) catch return CycleError.CycleDetected;

        // Remove from path and free
        if (path.pop()) |popped| alloc.free(popped);

        return false;
    }

    /// Free a CycleReport
    pub fn cycleReportFree(report: CycleReport) void {
        const alloc = report.allocator;
        for (report.cycle_path) |cp| {
            alloc.free(cp);
        }
        alloc.free(report.cycle_path);
    }
};

// ─── Dependency Resolver ────────────────────────────────────────────────

pub const dependencyResolver = struct {
    pub const DependencyResolver = struct {
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) DependencyResolver {
            return DependencyResolver{
                .allocator = allocator,
            };
        }
    };

    pub const ResolveResult = struct {
        ordered_names: []const []const u8,
        allocator: std.mem.Allocator,
    };

    pub const ResolveError = error{
        IncompleteRegistry,
        AllocationFailed,
    };

    pub fn dependencyResolverInit(resolver: *DependencyResolver, allocator: std.mem.Allocator) void {
        resolver.allocator = allocator;
    }

    pub fn resolveDependencies(
        resolver: *DependencyResolver,
        registry: *const formula.FormulaRegistry,
    ) ResolveError!ResolveResult {
        const alloc = resolver.allocator;

        // Build adjacency list: name → list of dependencies, and in-degree map.
        var dep_list = std.StringHashMap([]const []const u8).init(alloc);

        var in_degree = std.StringHashMap(usize).init(alloc);

        var all_names: std.ArrayListUnmanaged([]const u8) = .empty;
        var all_names_freed: bool = false;
        errdefer {
            if (!all_names_freed) {
                for (all_names.items) |n| alloc.free(n);
                all_names.deinit(alloc);
            }
        }

        var it = registry.formulas.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr;
            const val = entry.value_ptr;

            const name_copy = (alloc.dupe(u8, key.*)) catch return ResolveError.AllocationFailed;
            (all_names.append(alloc, name_copy)) catch return ResolveError.AllocationFailed;

            (in_degree.put(name_copy, 0)) catch return ResolveError.AllocationFailed;

            if (val.sources.len > 0) {
                const sources_copy = (alloc.alloc([]const u8, val.sources.len)) catch return ResolveError.AllocationFailed;
                for (val.sources, 0..) |src, i| {
                    sources_copy[i] = (alloc.dupe(u8, src)) catch return ResolveError.AllocationFailed;
                }
                (dep_list.put(name_copy, sources_copy)) catch return ResolveError.AllocationFailed;
            }
        }

        // Compute in-degrees from dep_list, only counting sources that are
        // formulas in the registry (external leaf metrics are ignored).
        var dep_it = dep_list.iterator();
        while (dep_it.next()) |entry| {
            const name = entry.key_ptr.*;
            const deps = entry.value_ptr.*;
            var in_deg: usize = 0;
            for (deps) |dep| {
                if (registry.formulas.contains(dep)) {
                    in_deg += 1;
                }
            }
            (in_degree.put(name, in_deg)) catch return ResolveError.AllocationFailed;
        }

        // Kahn's algorithm with sorted zero-in-degree queue for determinism.
        var result: std.ArrayListUnmanaged([]const u8) = .empty;
        errdefer {
            for (result.items) |n| {
                alloc.free(n);
            }
            result.deinit(alloc);
        }

        // Collect initial zero-in-degree nodes and sort them.
        var queue: std.ArrayListUnmanaged([]const u8) = .empty;
        errdefer queue.deinit(alloc);

        var it3 = in_degree.iterator();
        while (it3.next()) |entry| {
            if (entry.value_ptr.* == 0) {
                const name = (alloc.dupe(u8, entry.key_ptr.*)) catch return ResolveError.AllocationFailed;
                (queue.append(alloc, name)) catch return ResolveError.AllocationFailed;
            }
        }
        std.sort.block([]const u8, queue.items, {}, struct {
            pub fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.order(u8, a, b) == .lt;
            }
        }.lessThan);

        while (queue.items.len > 0) {
            // Pop first element (smallest lexicographically).
            const current = queue.orderedRemove(0);
            (result.append(alloc, current)) catch return ResolveError.AllocationFailed;

            // Find all nodes that depend on current.
            var new_ready: std.ArrayListUnmanaged([]const u8) = .empty;
            errdefer new_ready.deinit(alloc);

            var it4 = dep_list.iterator();
            while (it4.next()) |entry| {
                const _name = entry.key_ptr.*;
                const deps = entry.value_ptr.*;

                // Check if current is in deps of _name.
                var found = false;
                for (deps) |dep| {
                    if (std.mem.eql(u8, dep, current)) {
                        found = true;
                        break;
                    }
                }

                if (found) {
                    const old_deg = in_degree.get(_name).?;
                    const new_deg = old_deg - 1;
                    (in_degree.put(_name, new_deg)) catch return ResolveError.AllocationFailed;

                    if (new_deg == 0) {
                        const name_copy = (alloc.dupe(u8, _name)) catch return ResolveError.AllocationFailed;
                        (new_ready.append(alloc, name_copy)) catch return ResolveError.AllocationFailed;
                    }
                }
            }

            // Sort new ready nodes and insert into queue maintaining sorted order.
            std.sort.block([]const u8, new_ready.items, {}, struct {
                pub fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                    return std.mem.order(u8, a, b) == .lt;
                }
            }.lessThan);
            for (new_ready.items) |item| {
                (queue.append(alloc, item)) catch return ResolveError.AllocationFailed;
            }
            // Re-sort entire queue to maintain order.
            std.sort.block([]const u8, queue.items, {}, struct {
                pub fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                    return std.mem.order(u8, a, b) == .lt;
                }
            }.lessThan);
            new_ready.deinit(alloc);
        }

        // If result doesn't include all names, there's a cycle (S3 will handle).
        if (result.items.len != all_names.items.len) {
            all_names_freed = true;
            for (all_names.items) |n| alloc.free(n);
            all_names.deinit(alloc);
            return ResolveError.IncompleteRegistry;
        }

        // On success, result has its own copies (via queue). Free all_names items.
        all_names_freed = true;
        for (all_names.items) |n| alloc.free(n);
        all_names.deinit(alloc);
        // Deinit queue (items already moved to result).
        queue.deinit(alloc);
        // Deinit dep_list — keys owned by all_names/result, only free value arrays.
        var free_it = dep_list.iterator();
        while (free_it.next()) |entry| {
            const srcs = entry.value_ptr.*;
            for (srcs) |s| alloc.free(s);
            alloc.free(srcs);
        }
        dep_list.deinit();
        // in_degree keys are owned by all_names/result — just deinit internal table.
        in_degree.deinit();

        return ResolveResult{
            .ordered_names = (result.toOwnedSlice(alloc)) catch return ResolveError.AllocationFailed,
            .allocator = alloc,
        };
    }

    pub fn resolveResultFree(result: ResolveResult) void {
        const alloc = result.allocator;
        for (result.ordered_names) |name| {
            alloc.free(name);
        }
        alloc.free(result.ordered_names);
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

// ─── Capability Tests ─────────────────────────────────────────────────────

test "Capability.init creates valid capability" {
    const gpa = std.testing.allocator;
    const cap = Capability.init(
        gpa,
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
    defer cap.deinit(gpa);

    try std.testing.expect(std.mem.eql(u8, cap.name, "add"));
    try std.testing.expectEqual(@as(u32, 1), cap.version);
    try std.testing.expectEqual(@as(u32, 2), cap.input_types.len);
    try std.testing.expectEqual(@tagName(cap.backend_selector), "arrow");
}

test "Capability.init stores description correctly" {
    const gpa = std.testing.allocator;
    const cap = Capability.init(
        gpa,
        "mean",
        2,
        "Compute arithmetic mean",
        &.{TypeDescriptor{ .category = .vector, .element_type = .f64 }},
        TypeDescriptor{ .category = .scalar, .element_type = .f64 },
        .gsl,
    );
    defer cap.deinit(gpa);

    try std.testing.expectEqualStrings("mean", cap.name);
    try std.testing.expectEqualStrings("Compute arithmetic mean", cap.description);
    try std.testing.expectEqual(@as(u32, 2), cap.version);
    try std.testing.expectEqualStrings("gsl", @tagName(cap.backend_selector));
}

test "Capability.init with empty input_types" {
    const gpa = std.testing.allocator;
    const cap = Capability.init(
        gpa,
        "constant",
        1,
        "Returns a constant value",
        &.{},
        TypeDescriptor{ .category = .scalar, .element_type = .f64 },
        .default,
    );
    defer cap.deinit(gpa);

    try std.testing.expectEqual(@as(u32, 0), cap.input_types.len);
    try std.testing.expectEqualStrings("default", @tagName(cap.backend_selector));
}

// ─── Capability Registry Tests ──────────────────────────────────────────

test "CapabilityRegistry.register and get" {
    const gpa = std.testing.allocator;
    var reg = CapabilityRegistry.init(gpa);
    defer reg.deinit();

    const cap = Capability.init(
        gpa,
        "mean",
        1,
        "Compute mean",
        &.{TypeDescriptor{ .category = .vector, .element_type = .f64 }},
        TypeDescriptor{ .category = .scalar, .element_type = .f64 },
        .arrow,
    );
    // Ownership transfers to registry on register; do NOT deinit cap here.
    try reg.register(cap);
    try std.testing.expect(reg.contains("mean"));

    const found = reg.get("mean") orelse unreachable;
    try std.testing.expectEqualStrings("mean", found.name);
    try std.testing.expectEqual(@as(u32, 1), found.version);
}

test "CapabilityRegistry.get returns null for missing key" {
    const gpa = std.testing.allocator;
    var reg = CapabilityRegistry.init(gpa);
    defer reg.deinit();

    try std.testing.expect(reg.get("nonexistent") == null);
}

test "CapabilityRegistry.register duplicate returns error" {
    const gpa = std.testing.allocator;
    var reg = CapabilityRegistry.init(gpa);
    defer reg.deinit();

    const cap = Capability.init(
        gpa,
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
    // Ownership transfers to registry on register.
    try reg.register(cap);

    // Create a second capability with the same name.
    const cap2 = Capability.init(
        gpa,
        "add",
        2,
        "Addition v2",
        &.{TypeDescriptor{ .category = .vector, .element_type = .f64 }},
        TypeDescriptor{ .category = .vector, .element_type = .f64 },
        .gsl,
    );
    // This must fail — duplicate name.
    const result = reg.register(cap2);
    try std.testing.expect(result == registry_mod.RegistryError.DuplicateCapability);
    // Deinit cap2 — it was never registered.
    cap2.deinit(gpa);

    // Ensure the original is still retrievable.
    const found = reg.get("add") orelse unreachable;
    try std.testing.expectEqual(@as(u32, 1), found.version);
}

test "CapabilityRegistry.count returns correct number" {
    const gpa = std.testing.allocator;
    var reg = CapabilityRegistry.init(gpa);
    defer reg.deinit();

    try std.testing.expectEqual(@as(usize, 0), reg.count());

    const cap1 = Capability.init(gpa, "add", 1, "add",
        &.{TypeDescriptor{ .category = .vector, .element_type = .f64 }},
        TypeDescriptor{ .category = .vector, .element_type = .f64 }, .arrow);
    try reg.register(cap1);
    try std.testing.expectEqual(@as(usize, 1), reg.count());

    const cap2 = Capability.init(gpa, "sub", 1, "sub",
        &.{TypeDescriptor{ .category = .vector, .element_type = .f64 }},
        TypeDescriptor{ .category = .vector, .element_type = .f64 }, .arrow);
    try reg.register(cap2);
    try std.testing.expectEqual(@as(usize, 2), reg.count());
}

test "CapabilityRegistry.iterate returns all entries" {
    const gpa = std.testing.allocator;
    var reg = CapabilityRegistry.init(gpa);
    defer reg.deinit();

    const caps = [_]Capability{
        Capability.init(gpa, "alpha", 1, "a", &.{}, TypeDescriptor{ .category = .scalar, .element_type = .f64 }, .arrow),
        Capability.init(gpa, "beta", 1, "b", &.{}, TypeDescriptor{ .category = .scalar, .element_type = .f64 }, .gsl),
    };
    var cap_holders: [2]Capability = caps;
    errdefer for (&cap_holders) |*c| c.deinit(gpa);

    for (cap_holders[0..]) |*c| {
        try reg.register(c.*);
    }

    var found_count: usize = 0;
    var it = reg.iterator();
    while (it.next()) |entry| {
        found_count += 1;
        _ = entry.key_ptr;
    }
    try std.testing.expectEqual(@as(usize, 2), found_count);

    for (&cap_holders) |*c| c.deinit(gpa);
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

// ─── Dependency Resolver Tests ──────────────────────────────────────────

test "linear_chain: A→B→C produces [A, B, C]" {
    const allocator = std.testing.allocator;
    var registry = try formula.registryInit(allocator);
    defer formula.registryDeinit(&registry);

    try formula.registryAdd(&registry, .{
        .name = "A",
        .sources = &.{},
        .operation = "dummy",
    });
    try formula.registryAdd(&registry, .{
        .name = "B",
        .sources = &.{"A"},
        .operation = "dummy",
    });
    try formula.registryAdd(&registry, .{
        .name = "C",
        .sources = &.{"B"},
        .operation = "dummy",
    });

    var resolver = dependencyResolver.DependencyResolver.init(allocator);

    const result = try dependencyResolver.resolveDependencies(&resolver, &registry);
    defer dependencyResolver.resolveResultFree(result);

    try expectEqual(3, result.ordered_names.len);
    try expectEqualStrings("A", result.ordered_names[0]);
    try expectEqualStrings("B", result.ordered_names[1]);
    try expectEqualStrings("C", result.ordered_names[2]);
}

test "independent_formulas: X,Y,Z no deps → [X, Y, Z] lex order" {
    const allocator = std.testing.allocator;
    var registry = try formula.registryInit(allocator);
    defer formula.registryDeinit(&registry);

    try formula.registryAdd(&registry, .{ .name = "X", .sources = &.{}, .operation = "d" });
    try formula.registryAdd(&registry, .{ .name = "Y", .sources = &.{}, .operation = "d" });
    try formula.registryAdd(&registry, .{ .name = "Z", .sources = &.{}, .operation = "d" });

    var resolver = dependencyResolver.DependencyResolver.init(allocator);

    const result = try dependencyResolver.resolveDependencies(&resolver, &registry);
    defer dependencyResolver.resolveResultFree(result);

    try expectEqual(3, result.ordered_names.len);
    try expectEqualStrings("X", result.ordered_names[0]);
    try expectEqualStrings("Y", result.ordered_names[1]);
    try expectEqualStrings("Z", result.ordered_names[2]);
}

test "diamond_dependency: A→B, A→C, B→D, C→D" {
    const allocator = std.testing.allocator;
    var registry = try formula.registryInit(allocator);
    defer formula.registryDeinit(&registry);

    try formula.registryAdd(&registry, .{ .name = "A", .sources = &.{}, .operation = "d" });
    try formula.registryAdd(&registry, .{ .name = "B", .sources = &.{"A"}, .operation = "d" });
    try formula.registryAdd(&registry, .{ .name = "C", .sources = &.{"A"}, .operation = "d" });
    try formula.registryAdd(&registry, .{ .name = "D", .sources = &.{ "B", "C" }, .operation = "d" });

    var resolver = dependencyResolver.DependencyResolver.init(allocator);

    const result = try dependencyResolver.resolveDependencies(&resolver, &registry);
    defer dependencyResolver.resolveResultFree(result);

    try expectEqual(4, result.ordered_names.len);
    try expectEqualStrings("A", result.ordered_names[0]);
    try expectEqualStrings("D", result.ordered_names[3]);

    var b_idx: ?usize = null;
    var c_idx: ?usize = null;
    for (result.ordered_names, 0..) |name, i| {
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
    const allocator = std.testing.allocator;
    var registry = try formula.registryInit(allocator);
    defer formula.registryDeinit(&registry);

    var resolver = dependencyResolver.DependencyResolver.init(allocator);

    const result = try dependencyResolver.resolveDependencies(&resolver, &registry);
    defer dependencyResolver.resolveResultFree(result);

    try expectEqual(0, result.ordered_names.len);
}

test "single_formula returns [formula_name]" {
    const allocator = std.testing.allocator;
    var registry = try formula.registryInit(allocator);
    defer formula.registryDeinit(&registry);

    try formula.registryAdd(&registry, .{ .name = "Single", .sources = &.{}, .operation = "d" });

    var resolver = dependencyResolver.DependencyResolver.init(allocator);

    const result = try dependencyResolver.resolveDependencies(&resolver, &registry);
    defer dependencyResolver.resolveResultFree(result);

    try expectEqual(1, result.ordered_names.len);
    try expectEqualStrings("Single", result.ordered_names[0]);
}

test "multiple_chains_parallel: A→B and X→Y" {
    const allocator = std.testing.allocator;
    var registry = try formula.registryInit(allocator);
    defer formula.registryDeinit(&registry);

    try formula.registryAdd(&registry, .{ .name = "A", .sources = &.{}, .operation = "d" });
    try formula.registryAdd(&registry, .{ .name = "B", .sources = &.{"A"}, .operation = "d" });
    try formula.registryAdd(&registry, .{ .name = "X", .sources = &.{}, .operation = "d" });
    try formula.registryAdd(&registry, .{ .name = "Y", .sources = &.{"X"}, .operation = "d" });

    var resolver = dependencyResolver.DependencyResolver.init(allocator);

    const result = try dependencyResolver.resolveDependencies(&resolver, &registry);
    defer dependencyResolver.resolveResultFree(result);

    try expectEqual(4, result.ordered_names.len);

    var a_idx: ?usize = null;
    var b_idx: ?usize = null;
    var x_idx: ?usize = null;
    var y_idx: ?usize = null;
    for (result.ordered_names, 0..) |name, i| {
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

    try expectEqualStrings("A", result.ordered_names[0]);
    try expectEqualStrings("B", result.ordered_names[1]);
    try expectEqualStrings("X", result.ordered_names[2]);
    try expectEqualStrings("Y", result.ordered_names[3]);
}

test "complex_diamond: A→B, A→C, B→D, C→D, D→E" {
    const allocator = std.testing.allocator;
    var registry = try formula.registryInit(allocator);
    defer formula.registryDeinit(&registry);

    try formula.registryAdd(&registry, .{ .name = "A", .sources = &.{}, .operation = "d" });
    try formula.registryAdd(&registry, .{ .name = "B", .sources = &.{"A"}, .operation = "d" });
    try formula.registryAdd(&registry, .{ .name = "C", .sources = &.{"A"}, .operation = "d" });
    try formula.registryAdd(&registry, .{ .name = "D", .sources = &.{ "B", "C" }, .operation = "d" });
    try formula.registryAdd(&registry, .{ .name = "E", .sources = &.{"D"}, .operation = "d" });

    var resolver = dependencyResolver.DependencyResolver.init(allocator);

    const result = try dependencyResolver.resolveDependencies(&resolver, &registry);
    defer dependencyResolver.resolveResultFree(result);

    try expectEqual(5, result.ordered_names.len);
    try expectEqualStrings("A", result.ordered_names[0]);
    try expectEqualStrings("E", result.ordered_names[4]);
    try expectEqualStrings("D", result.ordered_names[3]);
    try expectEqualStrings("B", result.ordered_names[1]);
    try expectEqualStrings("C", result.ordered_names[2]);
}

test "self_contained_chain: ROIC→STLA→EV_EBITDA" {
    const allocator = std.testing.allocator;
    var registry = try formula.registryInit(allocator);
    defer formula.registryDeinit(&registry);

    try formula.registryAdd(&registry, .{ .name = "ROIC", .sources = &.{}, .operation = "d" });
    try formula.registryAdd(&registry, .{ .name = "STLA", .sources = &.{"ROIC"}, .operation = "d" });
    try formula.registryAdd(&registry, .{ .name = "EV_EBITDA", .sources = &.{"STLA"}, .operation = "d" });

    var resolver = dependencyResolver.DependencyResolver.init(allocator);

    const result = try dependencyResolver.resolveDependencies(&resolver, &registry);
    defer dependencyResolver.resolveResultFree(result);

    try expectEqual(3, result.ordered_names.len);
    try expectEqualStrings("ROIC", result.ordered_names[0]);
    try expectEqualStrings("STLA", result.ordered_names[1]);
    try expectEqualStrings("EV_EBITDA", result.ordered_names[2]);
}

test "lexicographic_tiebreaking: Beta and WACC" {
    const allocator = std.testing.allocator;
    var registry = try formula.registryInit(allocator);
    defer formula.registryDeinit(&registry);

    try formula.registryAdd(&registry, .{ .name = "Beta", .sources = &.{}, .operation = "d" });
    try formula.registryAdd(&registry, .{ .name = "WACC", .sources = &.{}, .operation = "d" });

    var resolver = dependencyResolver.DependencyResolver.init(allocator);

    const result = try dependencyResolver.resolveDependencies(&resolver, &registry);
    defer dependencyResolver.resolveResultFree(result);

    try expectEqual(2, result.ordered_names.len);
    try expectEqualStrings("Beta", result.ordered_names[0]);
    try expectEqualStrings("WACC", result.ordered_names[1]);
}

test "determinism: same input 10 times produces identical output" {
    const allocator = std.testing.allocator;

    const expected_names: []const []const u8 = &.{ "A", "B", "C", "D", "E" };

    var i: usize = 0;
    while (i < 10) : (i += 1) {
        var registry = try formula.registryInit(allocator);
        defer formula.registryDeinit(&registry);

        try formula.registryAdd(&registry, .{ .name = "A", .sources = &.{}, .operation = "d" });
        try formula.registryAdd(&registry, .{ .name = "B", .sources = &.{"A"}, .operation = "d" });
        try formula.registryAdd(&registry, .{ .name = "C", .sources = &.{"A"}, .operation = "d" });
        try formula.registryAdd(&registry, .{ .name = "D", .sources = &.{ "B", "C" }, .operation = "d" });
        try formula.registryAdd(&registry, .{ .name = "E", .sources = &.{"D"}, .operation = "d" });

        var resolver = dependencyResolver.DependencyResolver.init(allocator);

        const result = try dependencyResolver.resolveDependencies(&resolver, &registry);
        defer dependencyResolver.resolveResultFree(result);

        try expectEqual(expected_names.len, result.ordered_names.len);
        for (expected_names, 0..) |exp, idx| {
            try expectEqualStrings(exp, result.ordered_names[idx]);
        }
    }
}

// ─── Cycle Detection Tests ──────────────────────────────────────────────

test "simple_cycle: A→B, B→A detects cycle" {
    const allocator = std.testing.allocator;
    var registry = try formula.registryInit(allocator);
    defer formula.registryDeinit(&registry);

    try formula.registryAdd(&registry, .{
        .name = "A",
        .sources = &.{},
        .operation = "dummy",
    });
    try formula.registryAdd(&registry, .{
        .name = "B",
        .sources = &.{"A"},
        .operation = "dummy",
    });

    // Adding A again with source B should detect cycle B→A→B
    const err = cycleDetector.detectCycleBeforeAdd(&registry, .{
        .name = "A",
        .sources = &.{"B"},
        .operation = "dummy",
    }, allocator);

    try expect(err == cycleDetector.CycleError.CycleDetected);
}

test "longer_cycle: A→B→C→A detects cycle" {
    const allocator = std.testing.allocator;
    var registry = try formula.registryInit(allocator);
    defer formula.registryDeinit(&registry);

    try formula.registryAdd(&registry, .{ .name = "A", .sources = &.{}, .operation = "d" });
    try formula.registryAdd(&registry, .{ .name = "B", .sources = &.{"A"}, .operation = "d" });
    try formula.registryAdd(&registry, .{ .name = "C", .sources = &.{"B"}, .operation = "d" });

    // Overwriting A with source C creates cycle A→C→B→A
    const err = cycleDetector.detectCycleBeforeAdd(&registry, .{
        .name = "A",
        .sources = &.{"C"},
        .operation = "d",
    }, allocator);

    try expect(err == cycleDetector.CycleError.CycleDetected);
}

test "self_reference: A→A detects cycle" {
    const allocator = std.testing.allocator;
    var registry = try formula.registryInit(allocator);
    defer formula.registryDeinit(&registry);

    try formula.registryAdd(&registry, .{
        .name = "A",
        .sources = &.{},
        .operation = "dummy",
    });

    const err = cycleDetector.detectCycleBeforeAdd(&registry, .{
        .name = "A",
        .sources = &.{"A"},
        .operation = "dummy",
    }, allocator);

    try expect(err == cycleDetector.CycleError.CycleDetected);
}

test "no_cycle_linear: A→B→C succeeds" {
    const allocator = std.testing.allocator;
    var registry = try formula.registryInit(allocator);
    defer formula.registryDeinit(&registry);

    try formula.registryAdd(&registry, .{ .name = "A", .sources = &.{}, .operation = "d" });
    try formula.registryAdd(&registry, .{ .name = "B", .sources = &.{"A"}, .operation = "d" });

    try cycleDetector.detectCycleBeforeAdd(&registry, .{
        .name = "C",
        .sources = &.{"B"},
        .operation = "d",
    }, allocator);
}

test "no_cycle_diamond: A→B, A→C, B→D, C→D succeeds" {
    const allocator = std.testing.allocator;
    var registry = try formula.registryInit(allocator);
    defer formula.registryDeinit(&registry);

    try formula.registryAdd(&registry, .{ .name = "A", .sources = &.{}, .operation = "d" });
    try formula.registryAdd(&registry, .{ .name = "B", .sources = &.{"A"}, .operation = "d" });
    try formula.registryAdd(&registry, .{ .name = "C", .sources = &.{"A"}, .operation = "d" });

    try cycleDetector.detectCycleBeforeAdd(&registry, .{
        .name = "D",
        .sources = &.{ "B", "C" },
        .operation = "d",
    }, allocator);
}

test "undefined_reference_no_cycle: Ghost ref doesn't trigger cycle" {
    const allocator = std.testing.allocator;
    var registry = try formula.registryInit(allocator);
    defer formula.registryDeinit(&registry);

    try formula.registryAdd(&registry, .{
        .name = "X",
        .sources = &.{"Ghost"},
        .operation = "d",
    });

    // Ghost is not in registry, so it's skipped in DFS
    try cycleDetector.detectCycleBeforeAdd(&registry, .{
        .name = "Y",
        .sources = &.{"Ghost"},
        .operation = "d",
    }, allocator);
}

test "cycle_through_undefined: partial graph then close cycle" {
    const allocator = std.testing.allocator;
    var registry = try formula.registryInit(allocator);
    defer formula.registryDeinit(&registry);

    try formula.registryAdd(&registry, .{ .name = "A", .sources = &.{"B"}, .operation = "d" });
    // B is not in registry yet (undefined ref), so no cycle detected

    // Now add B that references A → cycle A→B→A
    const err = cycleDetector.detectCycleBeforeAdd(&registry, .{
        .name = "B",
        .sources = &.{"A"},
        .operation = "d",
    }, allocator);

    try expect(err == cycleDetector.CycleError.CycleDetected);
}

test "multiple_cycles_detects_one: two separate cycles" {
    const allocator = std.testing.allocator;
    var registry = try formula.registryInit(allocator);
    defer formula.registryDeinit(&registry);

    try formula.registryAdd(&registry, .{ .name = "A", .sources = &.{}, .operation = "d" });
    try formula.registryAdd(&registry, .{ .name = "B", .sources = &.{"A"}, .operation = "d" });
    try formula.registryAdd(&registry, .{ .name = "C", .sources = &.{}, .operation = "d" });
    try formula.registryAdd(&registry, .{ .name = "D", .sources = &.{"C"}, .operation = "d" });

    // Overwrite A to depend on D → A→D→C, B→A. B→A→D→C. No cycle from that.
    // But overwriting A with source D creates: A→D→C (no cycle back to A from C).
    // Instead: overwrite A to depend on B → A→B→A cycle (one cycle, ignoring the C→D chain).
    const err = cycleDetector.detectCycleBeforeAdd(&registry, .{
        .name = "A",
        .sources = &.{"B"},
        .operation = "d",
    }, allocator);

    try expect(err == cycleDetector.CycleError.CycleDetected);
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

    // Step 1: resolve dependencies to get topological order
    var resolver = dependencyResolver.DependencyResolver.init(alloc);
    const resolve_result = dependencyResolver.resolveDependencies(&resolver, input.registry) catch |err| {
        switch (err) {
            dependencyResolver.ResolveError.AllocationFailed => return ValuationError.AllocationFailed,
            dependencyResolver.ResolveError.IncompleteRegistry => return ValuationError.ResolveError,
        }
    };
    defer dependencyResolver.resolveResultFree(resolve_result);

    // Allocate reusable buffers outside the loop to avoid per-iteration deferred cleanup.
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
    while (i < resolve_result.ordered_names.len) : (i += 1) {
        const name = resolve_result.ordered_names[i];

        // Lookup formula in registry
        const nf = input.registry.formulas.get(name) orelse return ValuationError.NotFound;

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
        // We copy leaf source arrays so that resultFrameFree can safely
        // destroy() any stored ArrowArray pointers without double-freeing
        // caller-owned data.
        var src_idx: usize = 0;
        while (src_idx < nf.sources.len) : (src_idx += 1) {
            const src_name = nf.sources[src_idx];

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

        // Handle leaf formulas (0 sources) — nothing to compute, skip
        if (operand_ptrs.items.len == 0) {
            continue;
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

        // Multi-operand: execute the operation
        const c_operands: []const *arrowAdapter.ArrowArray = operand_ptrs.items;

        const compute_result = arrowAdapter.executeOperation(
            nf.operation,
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
    // Destroy any remaining owned ArrowArray copies before deinit
    var oj: usize = 0;
    while (oj < operand_ptrs.items.len) : (oj += 1) {
        if (operand_owned.items[oj]) {
            alloc.destroy(operand_ptrs.items[oj]);
        }
    }
    operand_ptrs.deinit(alloc);
    operand_owned.deinit(alloc);

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

    var registry = try formula.registryInit(alloc);
    defer formula.registryDeinit(&registry);
    try formula.registryAdd(&registry, .{
        .name = "B",
        .sources = &.{ "A", "A" },
        .operation = "add",
    });

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

    var registry = try formula.registryInit(alloc);
    defer formula.registryDeinit(&registry);
    try formula.registryAdd(&registry, .{
        .name = "X",
        .sources = &.{ "SA", "SB" },
        .operation = "multiply",
    });

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

    var registry = try formula.registryInit(alloc);
    defer formula.registryDeinit(&registry);
    try formula.registryAdd(&registry, .{
        .name = "X",
        .sources = &.{ "XA", "XB" },
        .operation = "add",
    });
    try formula.registryAdd(&registry, .{
        .name = "Y",
        .sources = &.{ "YA", "YB" },
        .operation = "divide",
    });

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
    try expectApprox(frame.result_data.get("Y").?, &[_]f64{ 2, 5 });
}

// 4. type_mismatch_error: non-float64 source array (null buffers)
test "runValuation: type_mismatch_error" {
    const alloc = std.testing.allocator;

    var registry = try formula.registryInit(alloc);
    defer formula.registryDeinit(&registry);
    try formula.registryAdd(&registry, .{
        .name = "F",
        .sources = &.{ "BAD", "X" },
        .operation = "add",
    });

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

    var registry = try formula.registryInit(alloc);
    defer formula.registryDeinit(&registry);
    try formula.registryAdd(&registry, .{
        .name = "F",
        .sources = &.{ "A", "B" },
        .operation = "foobar",
    });

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

    var registry = try formula.registryInit(alloc);
    defer formula.registryDeinit(&registry);
    // Diamond: A(source) → B(add), A(source) → C(multiply), B+C → D(subtract)
    try formula.registryAdd(&registry, .{
        .name = "B",
        .sources = &.{ "A", "A" },
        .operation = "add",
    });
    try formula.registryAdd(&registry, .{
        .name = "C",
        .sources = &.{ "A", "A" },
        .operation = "multiply",
    });
    try formula.registryAdd(&registry, .{
        .name = "D",
        .sources = &.{ "B", "C" },
        .operation = "subtract",
    });

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

    var registry = try formula.registryInit(alloc);
    defer formula.registryDeinit(&registry);
    try formula.registryAdd(&registry, .{
        .name = "B",
        .sources = &.{ "A", "A" },
        .operation = "multiply",
    });

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

    var registry = try formula.registryInit(alloc);
    defer formula.registryDeinit(&registry);
    try formula.registryAdd(&registry, .{
        .name = "C",
        .sources = &.{ "A", "B" },
        .operation = "divide",
    });

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

    var registry = try formula.registryInit(alloc);
    defer formula.registryDeinit(&registry);
    try formula.registryAdd(&registry, .{
        .name = "F1",
        .sources = &.{ "X", "Y" },
        .operation = "foobar",
    });
    try formula.registryAdd(&registry, .{
        .name = "F2",
        .sources = &.{ "X", "Y" },
        .operation = "add",
    });

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

    var registry = try formula.registryInit(alloc);
    defer formula.registryDeinit(&registry);
    try formula.registryAdd(&registry, .{
        .name = "ROIC",
        .sources = &.{ "R", "I" },
        .operation = "divide",
    });
    try formula.registryAdd(&registry, .{
        .name = "STLA",
        .sources = &.{ "ROIC", "ONE" },
        .operation = "multiply",
    });
    try formula.registryAdd(&registry, .{
        .name = "EV",
        .sources = &.{ "STLA", "M" },
        .operation = "multiply",
    });
    try formula.registryAdd(&registry, .{
        .name = "EBITDA",
        .sources = &.{ "EV", "D" },
        .operation = "subtract",
    });
    try formula.registryAdd(&registry, .{
        .name = "EV_EBITDA",
        .sources = &.{ "EBITDA", "EV" },
        .operation = "divide",
    });

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
    try expectApprox(frame.result_data.get("STLA").?, &[_]f64{ 10, 10 });
    try expectApprox(frame.result_data.get("EV").?, &[_]f64{ 50, 50 });
    try expectApprox(frame.result_data.get("EBITDA").?, &[_]f64{ 48, 48 });
    try expectApprox(frame.result_data.get("EV_EBITDA").?, &[_]f64{ 0.96, 0.96 });
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
    // Look up formula
    const nf = registry.formulas.get(formula_name) orelse return ProvenanceError.NotFound;

    const name_copy = (allocator.dupe(u8, formula_name)) catch return ProvenanceError.AllocationFailed;
    const op_copy = (allocator.dupe(u8, nf.operation)) catch return ProvenanceError.AllocationFailed;
    const sources = (allocator.dupe([]const u8, nf.sources)) catch return ProvenanceError.AllocationFailed;
    var i: usize = 0;
    while (i < sources.len) : (i += 1) {
        sources[i] = (allocator.dupe(u8, nf.sources[i])) catch return ProvenanceError.AllocationFailed;
    }

    // Build chain: topological order of all formulas reachable from target,
    // plus data keys that are sources of those formulas (except target's direct data-key sources).
    // Use the dependency resolver for topo ordering of formulas.
    var resolver = dependencyResolver.DependencyResolver.init(allocator);
    const topo_result = dependencyResolver.resolveDependencies(&resolver, registry) catch return ProvenanceError.AllocationFailed;

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

        if (registry.formulas.get(current)) |current_nf| {
            for (current_nf.sources) |src| {
                if (visited.get(src) == null) {
                    const src_copy = (allocator.dupe(u8, src)) catch return ProvenanceError.AllocationFailed;
                    (visited.put(src_copy, {})) catch return ProvenanceError.AllocationFailed;
                    (queue.append(allocator, src_copy)) catch return ProvenanceError.AllocationFailed;
                }
            }
        }
    }

    // Build chain: include all visited nodes in topo order.
    // For each topo-ordered formula, add it if visited.
    // Data keys are visited names that are not themselves formulas in the registry.
    var chain = std.ArrayListUnmanaged([]const u8).empty;
    errdefer {
        for (chain.items) |item| allocator.free(item);
        chain.deinit(allocator);
    }

    // Collect data keys: visited names not present as formulas.
    // Iterate BFS-visited names in queue order (discovery order) for consistency.
    var qi2: usize = 0;
    while (qi2 < queue.items.len) : (qi2 += 1) {
        const name = queue.items[qi2];
        if (registry.formulas.get(name) == null) {
            const key_copy = (allocator.dupe(u8, name)) catch return ProvenanceError.AllocationFailed;
            (chain.append(allocator, key_copy)) catch return ProvenanceError.AllocationFailed;
        }
    }

    // Then add all visited formulas in topo order.
    for (topo_result.ordered_names) |topo_name| {
        if (visited.get(topo_name) != null) {
            const topo_name_copy = (allocator.dupe(u8, topo_name)) catch return ProvenanceError.AllocationFailed;
            (chain.append(allocator, topo_name_copy)) catch return ProvenanceError.AllocationFailed;
        }
    }

    // Clean up visited and queue on success path.
    visited.deinit();
    for (queue.items) |item| allocator.free(item);
    queue.deinit(allocator);
    for (topo_result.ordered_names) |name| allocator.free(name);
    allocator.free(topo_result.ordered_names);

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
    var registry = try formula.registryInit(alloc);
    defer formula.registryDeinit(&registry);

    try formula.registryAdd(&registry, .{
        .name = "ROIC",
        .sources = &.{ "NOPAT", "InvestedCapital" },
        .operation = "divide",
    });

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
    var registry = try formula.registryInit(alloc);
    defer formula.registryDeinit(&registry);

    try formula.registryAdd(&registry, .{
        .name = "A",
        .sources = &.{},
        .operation = "add",
    });
    try formula.registryAdd(&registry, .{
        .name = "B",
        .sources = &.{"A"},
        .operation = "add",
    });
    try formula.registryAdd(&registry, .{
        .name = "C",
        .sources = &.{"B"},
        .operation = "multiply",
    });

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
    var registry = try formula.registryInit(alloc);
    defer formula.registryDeinit(&registry);

    try formula.registryAdd(&registry, .{
        .name = "Revenue",
        .sources = &.{},
        .operation = "add",
    });

    var prov = try attachProvenance("Revenue", &registry, alloc);
    defer prov.deinit();

    try expectEqualStrings("Revenue", prov.name);
    try expectEqual(0, prov.sources.len);
    try expectEqual(1, prov.chain.items.len);
    try expectEqualStrings("Revenue", prov.chain.items[0]);
}

test "provenance: diamond_provenance A→B, A→C, B→D, C→D" {
    const alloc = std.testing.allocator;
    var registry = try formula.registryInit(alloc);
    defer formula.registryDeinit(&registry);

    try formula.registryAdd(&registry, .{
        .name = "A",
        .sources = &.{},
        .operation = "add",
    });
    try formula.registryAdd(&registry, .{
        .name = "B",
        .sources = &.{"A"},
        .operation = "add",
    });
    try formula.registryAdd(&registry, .{
        .name = "C",
        .sources = &.{"A"},
        .operation = "add",
    });
    try formula.registryAdd(&registry, .{
        .name = "D",
        .sources = &.{ "B", "C" },
        .operation = "subtract",
    });

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
    var registry = try formula.registryInit(alloc);
    defer formula.registryDeinit(&registry);

    try formula.registryAdd(&registry, .{
        .name = "A",
        .sources = &.{},
        .operation = "add",
    });
    try formula.registryAdd(&registry, .{
        .name = "B",
        .sources = &.{"A"},
        .operation = "multiply",
    });

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
    var registry = try formula.registryInit(alloc);
    defer formula.registryDeinit(&registry);

    try formula.registryAdd(&registry, .{
        .name = "ROIC",
        .sources = &.{ "R", "I" },
        .operation = "divide",
    });
    try formula.registryAdd(&registry, .{
        .name = "STLA",
        .sources = &.{ "ROIC", "ONE" },
        .operation = "multiply",
    });
    try formula.registryAdd(&registry, .{
        .name = "EV",
        .sources = &.{ "STLA", "M" },
        .operation = "multiply",
    });
    try formula.registryAdd(&registry, .{
        .name = "EBITDA",
        .sources = &.{ "EV", "D" },
        .operation = "subtract",
    });
    try formula.registryAdd(&registry, .{
        .name = "EV_EBITDA",
        .sources = &.{ "EBITDA", "EV" },
        .operation = "divide",
    });

    var prov = try attachProvenance("EV_EBITDA", &registry, alloc);
    defer prov.deinit();

    try expectEqualStrings("EV_EBITDA", prov.name);
    // Chain: R, I, ONE, M, D (leaves) → ROIC, STLA, EV, EBITDA (intermediates) → EV_EBITDA (target)
    try expectEqual(10, prov.chain.items.len);
    try expectEqualStrings("EV_EBITDA", prov.chain.items[9]);
}

test "provenance: query_provenance_by_name" {
    const alloc = std.testing.allocator;
    var registry = try formula.registryInit(alloc);
    defer formula.registryDeinit(&registry);

    try formula.registryAdd(&registry, .{
        .name = "X",
        .sources = &.{ "A", "B" },
        .operation = "add",
    });
    try formula.registryAdd(&registry, .{
        .name = "Y",
        .sources = &.{"X"},
        .operation = "multiply",
    });

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
    var registry = try formula.registryInit(alloc);
    defer formula.registryDeinit(&registry);

    try formula.registryAdd(&registry, .{
        .name = "A",
        .sources = &.{},
        .operation = "add",
    });
    try formula.registryAdd(&registry, .{
        .name = "B",
        .sources = &.{"A"},
        .operation = "multiply",
    });
    try formula.registryAdd(&registry, .{
        .name = "C",
        .sources = &.{"B"},
        .operation = "divide",
    });

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

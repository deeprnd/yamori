const std = @import("std");

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

// ─── Dependency Resolver ───────────────────────────────────────────────

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
        errdefer {
            for (all_names.items) |n| alloc.free(n);
            all_names.deinit(alloc);
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

        // Compute in-degrees from dep_list.
        var dep_it = dep_list.iterator();
        while (dep_it.next()) |entry| {
            const name = entry.key_ptr.*;
            const deps = entry.value_ptr.*;
            (in_degree.put(name, deps.len)) catch return ResolveError.AllocationFailed;
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
            // Cleanup all_names (result items are a subset of all_names).
            for (all_names.items) |n| alloc.free(n);
            all_names.deinit(alloc);
            return ResolveError.IncompleteRegistry;
        }

        // On success, result has its own copies (via queue). Free all_names items.
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

pub fn main() void {
    std.debug.print("Yamori — Named Formula Definition (V1.1-S1)\n", .{});
}

// ─── Tests ──────────────────────────────────────────────────────────────

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

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
    try formula.registryAdd(&registry, .{ .name = "D", .sources = &.{"B", "C"}, .operation = "d" });

    var resolver = dependencyResolver.DependencyResolver.init(allocator);

    const result = try dependencyResolver.resolveDependencies(&resolver, &registry);
    defer dependencyResolver.resolveResultFree(result);

    try expectEqual(4, result.ordered_names.len);
    try expectEqualStrings("A", result.ordered_names[0]);
    try expectEqualStrings("D", result.ordered_names[3]);

    // B and C can be in either order, both after A and before D.
    var b_idx: ?usize = null;
    var c_idx: ?usize = null;
    for (result.ordered_names, 0..) |name, i| {
        if (std.mem.eql(u8, name, "B")) b_idx = i;
        if (std.mem.eql(u8, name, "C")) c_idx = i;
    }
    if (b_idx) |b| { try expect(b > 0); } else unreachable;
    if (c_idx) |c| { try expect(c > 0); } else unreachable;
    if (b_idx) |b| { try expect(b < 3); } else unreachable;
    if (c_idx) |c| { try expect(c < 3); } else unreachable;
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

    // A must be before B, X must be before Y.
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
        if (b_idx) |b| { try expect(a < b); } else unreachable;
    } else unreachable;
    if (x_idx) |x| {
        if (y_idx) |y| { try expect(x < y); } else unreachable;
    } else unreachable;

    // Correct order: A (pos 0), B (pos 1, freed after A, B < X lex),
    // X (pos 2, was in queue), Y (pos 3, freed after X).
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
    try formula.registryAdd(&registry, .{ .name = "D", .sources = &.{"B", "C"}, .operation = "d" });
    try formula.registryAdd(&registry, .{ .name = "E", .sources = &.{"D"}, .operation = "d" });

    var resolver = dependencyResolver.DependencyResolver.init(allocator);

    const result = try dependencyResolver.resolveDependencies(&resolver, &registry);
    defer dependencyResolver.resolveResultFree(result);

    try expectEqual(5, result.ordered_names.len);
    try expectEqualStrings("A", result.ordered_names[0]);
    try expectEqualStrings("E", result.ordered_names[4]);
    try expectEqualStrings("D", result.ordered_names[3]);
    // B and C between A and D in lex order.
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
        try formula.registryAdd(&registry, .{ .name = "D", .sources = &.{"B", "C"}, .operation = "d" });
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

const std = @import("std");

pub const Entity = u32;

pub fn QueryIterator(comptime T: type) type {
    return struct {
        index: usize = 0,
        pool: *ComponentPool(T),

        pub fn next(self: *@This()) ?*T {
            if (self.index >= self.pool.dense.items.len) return null;
            const result = &self.pool.dense.items[self.index];
            self.index += 1;
            return result;
        }
    };
}

pub const World = struct {
    allocator: std.mem.Allocator,
    /// Key: type name string. Value: pointer to ComponentPool of that type (type erased).
    pools: std.StringHashMap(PoolEntry),
    next_entity: Entity,

    pub fn init(allocator: std.mem.Allocator) World {
        return .{
            .allocator = allocator,
            .pools = std.StringHashMap(PoolEntry).init(allocator),
            .next_entity = 0,
        };
    }

    pub fn deinit(self: *World) void {
        var it = self.pools.valueIterator();
        while (it.next()) |entry| {
            entry.deinit_fn(entry.ptr);
        }
        self.pools.deinit();
    }

    pub fn query(self: *World, comptime types: anytype) QueryIterator(types[0]) {
        // dereference fields to get corresponding ComponentPools.
        const fst_type = types[0];

        std.debug.print("looking for: '{s}'\n", .{@typeName(fst_type)});
        std.debug.print("stored keys: \n", .{});
        var key_it = self.pools.keyIterator();
        while (key_it.next()) |key| {
            std.debug.print("  '{s}'\n", .{key.*});
        }

        const pool: *ComponentPool(fst_type) = @ptrCast(@alignCast(self.pools.get(@typeName(fst_type)).?.ptr));
        return QueryIterator(fst_type){ .pool = pool };
    }

    pub fn createEntity(self: *World) Entity {
        const entity = self.next_entity;
        self.next_entity += 1;
        return entity;
    }

    pub fn getComponent(self: *World, entity: Entity, comptime T: type) ?*T {
        const type_name = @typeName(T);
        if (self.pools.get(type_name)) |pool_entry| {
            const pool: *ComponentPool(T) = @ptrCast(@alignCast(pool_entry.ptr));
            return pool.get(entity);
        }
        return null;
    }

    pub fn addComponent(self: *World, entity: Entity, comptime T: type, value: T) !void {
        const type_name = @typeName(T);
        if (self.pools.get(type_name)) |pool_entry| {
            const pool: *ComponentPool(T) = @ptrCast(@alignCast(pool_entry.ptr));
            try pool.add(entity, value);
        } else {
            const pool = try self.allocator.create(ComponentPool(T));
            pool.* = ComponentPool(T).init(self.allocator);
            try self.pools.put(type_name, .{ .ptr = pool, .deinit_fn = ComponentPool(T).makeDeinitFn() });
            try pool.add(entity, value);
        }
    }
};

const PoolEntry = struct {
    ptr: *anyopaque,
    deinit_fn: *const fn (*anyopaque) void,
};

fn ComponentPool(comptime T: type) type {
    // This value is stored in sparse array to indicate an unassigned entity.
    const unassigned_entity = std.math.maxInt(Entity);
    return struct {
        dense: std.ArrayList(T),
        entities: std.ArrayList(Entity),
        sparse: std.ArrayList(u32),
        allocator: std.mem.Allocator,

        fn init(allocator: std.mem.Allocator) @This() {
            return .{
                .dense = .empty,
                .entities = .empty,
                .sparse = .empty,
                .allocator = allocator,
            };
        }

        fn makeDeinitFn() *const fn (*anyopaque) void {
            return &struct {
                fn deinit(erased: *anyopaque) void {
                    const pool: *ComponentPool(T) = @ptrCast(@alignCast(erased));
                    pool.dense.deinit(pool.allocator);
                    pool.entities.deinit(pool.allocator);
                    pool.sparse.deinit(pool.allocator);
                    pool.allocator.destroy(pool);
                }
            }.deinit;
        }

        fn deinit(self: *@This()) void {
            self.dense.deinit(self.allocator);
            self.entities.deinit(self.allocator);
            self.sparse.deinit(self.allocator);
        }

        fn get(self: *const @This(), entity: Entity) ?*T {
            if (!self.has(entity)) return null;
            return &self.dense.items[self.sparse.items[entity]];
        }

        fn has(self: *const @This(), entity: Entity) bool {
            return self.sparse.items.len > entity and self.sparse.items[entity] != unassigned_entity;
        }

        fn add(self: *@This(), entity: Entity, value: T) !void {
            // check if component already exists for this entity
            if (self.has(entity)) {
                return error.EntityAlreadyHasComponent;
            }
            // add new component to dense array
            const dense_index = self.dense.items.len;
            try self.dense.append(self.allocator, value);
            if (self.sparse.items.len <= entity) {
                // resize sparse array to fit new entity
                try self.sparse.appendNTimes(self.allocator, unassigned_entity, entity - self.sparse.items.len + 1);
            }
            self.sparse.items[entity] = @intCast(dense_index);
        }
    };
}

test "component pool add and has" {
    const allocator = std.testing.allocator;
    var pool = ComponentPool(f32).init(allocator);
    defer pool.deinit();

    try pool.add(5, 3.14);

    try std.testing.expect(pool.has(5));
    try std.testing.expect(!pool.has(0));
    try std.testing.expect(!pool.has(999));
}

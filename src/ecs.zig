const std = @import("std");

pub const Entity = u32;

pub fn EntityIter(comptime types: anytype) type {
    return struct {
        index: usize = 0,
        pools: *const [types.len]*anyopaque,
        primary_entities: []const Entity,

        pub fn next(self: *@This()) ?Entity {
            outer: while (self.index < self.primary_entities.len) {
                const ent = self.primary_entities[self.index];
                self.index += 1;

                // skip pool 0, primary entities are always in pool 0
                inline for (types, 0..) |T, i| {
                    if (i == 0) continue;
                    const pool: *ComponentPool(T) = @ptrCast(@alignCast(self.pools[i]));
                    if (!pool.has(ent)) continue :outer;
                }
                return ent;
            }
            return null;
        }
    };
}

fn Query(comptime types: anytype) type {
    return struct {
        pools: [types.len]*anyopaque,

        pub fn entityIter(self: *@This()) EntityIter(types) {
            const pool: *ComponentPool(types[0]) = @ptrCast(@alignCast(self.pools[0]));
            return .{ .pools = &self.pools, .primary_entities = pool.entities.items };
        }

        pub fn get(self: *@This(), comptime T: type, entity: Entity) ?*T {
            inline for (types, 0..) |Pool_T, i| {
                if (Pool_T == T) {
                    const pool: *ComponentPool(T) = @ptrCast(@alignCast(self.pools[i]));
                    return pool.get(entity);
                }
            }
            @compileError("Component type not in this query: " ++ @typeName(T));
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

    pub fn query(self: *World, comptime types: anytype) Query(types) {
        // dereference fields to get corresponding ComponentPools.
        var pools: [types.len]*anyopaque = undefined;
        inline for (types, 0..) |t, i| {
            const pool: *ComponentPool(t) = @ptrCast(@alignCast(self.pools.get(@typeName(t)).?.ptr));
            pools[i] = pool;
        }
        return Query(types){ .pools = pools };
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
            try self.entities.append(self.allocator, entity); // add entity to dense entities list

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

const std = @import("std");

const Entity = u32;

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

        fn deinit(self: *@This()) void {
            self.dense.deinit(self.allocator);
            self.entities.deinit(self.allocator);
            self.sparse.deinit(self.allocator);
        }

        fn get(self: *const @This(), entity: Entity) ?T {
            if (!self.has(entity)) return null;
            return self.dense.items[self.sparse.items[entity]];
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

pub const World = struct {
    allocator: std.mem.Allocator,
    /// Key: type name string. Value: pointer to ComponentPool of that type (type erased).
    pools: std.StringHashMap(*anyopaque),
    next_entity: Entity,

    pub fn init(allocator: std.mem.Allocator) World {
        return .{
            .allocator = allocator,
            .pools = std.StringHashMap(*anyopaque).init(allocator),
            .next_entity = 0,
        };
    }

    pub fn addComponent(self: *World, entity: Entity, comptime T: type, value: T) !void {
        const type_name = @typeName(T);
        if (self.pools.get(type_name)) |pool_ptr| {
            const pool: *ComponentPool(T) = @ptrCast(@alignCast(pool_ptr));
            try pool.add(entity, value);
        } else {
            const pool = try self.allocator.create(ComponentPool(T));
            pool.* = ComponentPool(T).init(self.allocator);
            try self.pools.put(type_name, pool);
            try pool.add(entity, value);
        }
    }
};

test "component pool add and has" {
    const allocator = std.testing.allocator;
    var pool = ComponentPool(f32).init(allocator);
    defer pool.deinit();

    try pool.add(5, 3.14);

    try std.testing.expect(pool.has(5));
    try std.testing.expect(!pool.has(0));
    try std.testing.expect(!pool.has(999));
}

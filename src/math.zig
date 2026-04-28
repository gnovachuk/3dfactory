const std = @import("std");

pub const Mat4 = struct {
    data: [16]f32,

    pub fn init(data: [16]f32) Mat4 {
        return Mat4{ .data = data };
    }

    /// Build a Mat4 from a row-major literal. The 16 floats are read in
    /// natural reading order (left-to-right, top-to-bottom), so the source
    /// code visually matches the mathematical matrix. Internally the data is
    /// transposed into column-major storage.
    pub fn fromRows(rows: [16]f32) Mat4 {
        var data: [16]f32 = @splat(0);
        for (0..4) |r| {
            for (0..4) |c| {
                // rows[r*4 + c] is element (r, c) in reading order.
                // Column-major storage: data[c*4 + r] is element (r, c).
                data[c * 4 + r] = rows[r * 4 + c];
            }
        }
        return Mat4{ .data = data };
    }

    pub fn orthographic(l: f32, r: f32, b: f32, t: f32, n: f32, f: f32) Mat4 {
        return Mat4.fromRows([16]f32{
            2 / (r - l), 0,           0,            -(r + l) / (r - l),
            0,           2 / (t - b), 0,            -(t + b) / (t - b),
            0,           0,           -2 / (f - n), -(f + n) / (f - n),
            0,           0,           0,            1,
        });
    }

    pub fn perspective(fovy_rad: f32, aspect: f32, near: f32, far: f32) Mat4 {
        const t = near * @tan(fovy_rad / 2);
        const r = t * aspect;
        return Mat4.orthographic(-r, r, -t, t, near, far).mul(Mat4.perspective_squash(near, far));
    }

    pub fn look_at(eye: Vec3, target: Vec3, up: Vec3) Mat4 {
        const forward = target.sub(eye).normalize();
        const right = forward.cross(up).normalize();
        const cam_up = right.cross(forward); // orthogonalize supplied up.
        return Mat4.init([16]f32{
            right.x, cam_up.x, -forward.x, 0,
            right.y, cam_up.y, -forward.y, 0,
            right.z, cam_up.z, -forward.z, 0,
            0,       0,        0,          1,
        }).mul(Mat4.translate(eye.scale(-1)));
    }

    fn perspective_squash(
        n: f32,
        f: f32,
    ) Mat4 {
        return Mat4.fromRows([16]f32{
            n, 0, 0,     0,
            0, n, 0,     0,
            0, 0, f + n, f * n,
            0, 0, -1,    0,
        });
    }

    pub fn identity() Mat4 {
        return Mat4.fromRows([16]f32{
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
        });
    }

    pub fn translate(t: Vec3) Mat4 {
        // [1 0 0 tx]   [x]   [x + tx·1]   [x + tx]
        // [0 1 0 ty] · [y] = [y + ty·1] = [y + ty]
        // [0 0 1 tz]   [z]   [z + tz·1]   [z + tz]
        // [0 0 0  1]   [1]   [0 + 1·1 ]   [  1   ]

        return Mat4.fromRows([16]f32{
            1, 0, 0, t.x,
            0, 1, 0, t.y,
            0, 0, 1, t.z,
            0, 0, 0, 1,
        });
    }

    pub fn rotate(rpy: Vec3) Mat4 {
        const pitch = Mat4.fromRows([16]f32{ 1, 0, 0, 0, 0, @cos(rpy.x), -@sin(rpy.x), 0, 0, @sin(rpy.x), @cos(rpy.x), 0, 0, 0, 0, 1 });

        const yaw = Mat4.fromRows([16]f32{
            @cos(rpy.y),  0, @sin(rpy.y), 0,
            0,            1, 0,           0,
            -@sin(rpy.y), 0, @cos(rpy.y), 0,
            0,            0, 0,           1,
        });

        const roll = Mat4.fromRows([16]f32{
            @cos(rpy.z), -@sin(rpy.z), 0, 0,
            @sin(rpy.z), @cos(rpy.z),  0, 0,
            0,           0,            1, 0,
            0,           0,            0, 1,
        });

        return roll.mul(pitch.mul(yaw));
    }

    pub fn mul(self: Mat4, other: Mat4) Mat4 {
        var result: Mat4 = .init(@splat(0));
        for (0..16) |i| {
            const col = i / 4;
            const row = i % 4;
            for (0..4) |j| {
                result.data[i] += self.data[row + 4 * j] * other.data[j + 4 * col];
            }
        }
        return result;
    }
};

pub const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn init(x: f32, y: f32, z: f32) Vec3 {
        return Vec3{ .x = x, .y = y, .z = z };
    }

    pub fn add(self: Vec3, other: Vec3) Vec3 {
        return Vec3{
            .x = self.x + other.x,
            .y = self.y + other.y,
            .z = self.z + other.z,
        };
    }

    pub fn sub(self: Vec3, other: Vec3) Vec3 {
        return Vec3{
            .x = self.x - other.x,
            .y = self.y - other.y,
            .z = self.z - other.z,
        };
    }

    pub fn scale(self: Vec3, s: f32) Vec3 {
        return Vec3{
            .x = self.x * s,
            .y = self.y * s,
            .z = self.z * s,
        };
    }

    pub fn dot(self: Vec3, other: Vec3) f32 {
        return self.x * other.x + self.y * other.y + self.z * other.z;
    }

    pub fn cross(self: Vec3, other: Vec3) Vec3 {
        return Vec3{
            .x = self.y * other.z - self.z * other.y,
            .y = self.z * other.x - self.x * other.z,
            .z = self.x * other.y - self.y * other.x,
        };
    }

    pub fn length(self: Vec3) f32 {
        return @sqrt(self.x * self.x + self.y * self.y + self.z * self.z);
    }

    pub fn normalize(self: Vec3) Vec3 {
        const len = self.length();
        return Vec3{
            .x = self.x / len,
            .y = self.y / len,
            .z = self.z / len,
        };
    }
};

test "mat4 mul identity" {
    const identity = Mat4.fromRows([16]f32{
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    });
    const m = Mat4.fromRows([16]f32{
        1,  2,  3,  4,
        5,  6,  7,  8,
        9,  10, 11, 12,
        13, 14, 15, 16,
    });
    const result = m.mul(identity);
    for (0..16) |i| {
        try std.testing.expectEqual(m.data[i], result.data[i]);
    }
}

test "mat4 mul" {
    // Small hand-computable case. Top-left 2x2 of A and B do the real work;
    // the rest is identity-padding in the lower-right so the math is easy.
    //
    //   A = [1 2 0 0]    B = [5 6 0 0]
    //       [3 4 0 0]        [7 8 0 0]
    //       [0 0 1 0]        [0 0 1 0]
    //       [0 0 0 1]        [0 0 0 1]
    //
    // A*B top-left 2x2 = [1*5+2*7  1*6+2*8] = [19 22]
    //                    [3*5+4*7  3*6+4*8]   [43 50]
    const a = Mat4.fromRows([16]f32{
        1, 2, 0, 0,
        3, 4, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    });
    const b = Mat4.fromRows([16]f32{
        5, 6, 0, 0,
        7, 8, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    });
    const expected = Mat4.fromRows([16]f32{
        19, 22, 0, 0,
        43, 50, 0, 0,
        0,  0,  1, 0,
        0,  0,  0, 1,
    });
    const result = a.mul(b);
    for (0..16) |i| {
        try std.testing.expectEqual(expected.data[i], result.data[i]);
    }
}

test "vec3 add" {
    const a = Vec3{ .x = 1, .y = 2, .z = 3 };
    const b = Vec3{ .x = 4, .y = 5, .z = 6 };
    const c = a.add(b);
    try std.testing.expectEqual(@as(f32, 5), c.x);
}

test "vec3 normalize" {
    const a = Vec3{ .x = 1, .y = 2, .z = 3 };
    const b = a.normalize();
    try std.testing.expectApproxEqAbs(@as(f32, 1), b.length(), 0.001);
}

test "mat4 identity left-multiply" {
    // Sanity check: I * m == m. (We already test m * I == m elsewhere;
    // matrix multiplication isn't commutative in general, so testing both
    // directions of identity catches a different class of bug.)
    const m = Mat4.fromRows([16]f32{
        1,  2,  3,  4,
        5,  6,  7,  8,
        9,  10, 11, 12,
        13, 14, 15, 16,
    });
    const result = Mat4.identity().mul(m);
    for (0..16) |i| {
        try std.testing.expectEqual(m.data[i], result.data[i]);
    }
}

test "mat4 translate places values in last column" {
    // In column-major storage, the last column lives at indices 12, 13, 14, 15.
    // translate(t) should put t.x, t.y, t.z at 12, 13, 14, with 1 at 15.
    const t = Mat4.translate(Vec3.init(2, 3, 4));
    try std.testing.expectEqual(@as(f32, 2), t.data[12]);
    try std.testing.expectEqual(@as(f32, 3), t.data[13]);
    try std.testing.expectEqual(@as(f32, 4), t.data[14]);
    try std.testing.expectEqual(@as(f32, 1), t.data[15]);
}

test "mat4 rotate by zero is identity" {
    const r = Mat4.rotate(Vec3.init(0, 0, 0));
    const id = Mat4.identity();
    for (0..16) |i| {
        try std.testing.expectApproxEqAbs(id.data[i], r.data[i], 1e-6);
    }
}

test "perspective layout" {
    const p = Mat4.perspective(std.math.pi / 2.0, 1.0, 1.0, 100.0);
    // tan(pi/4) = 1, so f = 1
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), p.data[0], 1e-6); // x scale
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), p.data[5], 1e-6); // y scale
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), p.data[11], 1e-6); // -1 in row 3 col 2 (column-major: col 2 starts at 8, +3 = 11)
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), p.data[15], 1e-6); // NOT 1, that's the giveaway

    // Standard perspective values for fovy=90, aspect=1, n=1, f=100:
    // data[10] = -(f+n)/(f-n) = -101/99 ≈ -1.020
    // data[14] = -2fn/(f-n) = -200/99 ≈ -2.020
    try std.testing.expectApproxEqAbs(@as(f32, -101.0 / 99.0), p.data[10], 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, -200.0 / 99.0), p.data[14], 1e-4);
}

test "lookAt at origin from +z looks like a -5 translate" {
    const view = Mat4.look_at(Vec3.init(0, 0, 5), Vec3.init(0, 0, 0), Vec3.init(0, 1, 0));
    // r should be (1,0,0), u should be (0,1,0), f should be (0,0,1).
    // So the rotation portion is identity; the translation column should be (0, 0, -5).
    try std.testing.expectApproxEqAbs(@as(f32, 1), view.data[0], 1e-6); // r.x
    try std.testing.expectApproxEqAbs(@as(f32, 1), view.data[5], 1e-6); // u.y
    try std.testing.expectApproxEqAbs(@as(f32, 1), view.data[10], 1e-6); // f.z
    try std.testing.expectApproxEqAbs(@as(f32, -5), view.data[14], 1e-6); // -dot(f, eye) = -5
}

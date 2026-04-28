const std = @import("std");
const c = @import("gl.zig").c;

pub const Mesh = struct {
    /// Vertex Array Object.
    vao: u32,
    /// Vertex Buffer Object.
    vbo: u32,
    /// Element Buffer Object.
    ebo: u32,
    /// The amount of indices supplied (i.e., the number of vertices to draw).
    index_count: i32,

    pub fn draw(self: Mesh) void {
        c.glBindVertexArray(self.vao);
        // Last parameter is the offset into the EBO (null = 0).
        c.glDrawElements(c.GL_TRIANGLES, self.index_count, c.GL_UNSIGNED_INT, null);
    }

    pub fn deinit(self: Mesh) void {
        // Note: GL's delete functions take a count and a pointer to an array
        // of IDs. Here we delete one at a time, so count = 1 and we pass the
        // address of the field.
        c.glDeleteBuffers(1, &self.vbo);
        c.glDeleteBuffers(1, &self.ebo);
        c.glDeleteVertexArrays(1, &self.vao);
    }

    pub fn init(vertices: []const f32, indices: []const u32) Mesh {
        // create vao.
        var vao: u32 = 0;
        c.glGenVertexArrays(1, &vao);
        c.glBindVertexArray(vao);

        var vbo: u32 = 0;
        c.glGenBuffers(1, &vbo); // generate vertex buffer with id 1.
        c.glBindBuffer(c.GL_ARRAY_BUFFER, vbo); // specify type of buffer (GL_ARRAY_BUFFER is vertex buffer object).

        // GL_STREAM_DRAW: the data is set only once and used by the GPU at most a few times.
        // GL_STATIC_DRAW: the data is set only once and used many times.
        // GL_DYNAMIC_DRAW: the data is changed a lot and used many times.
        // size is specified in bytes.
        const size: isize = @intCast(vertices.len * @sizeOf(f32));
        c.glBufferData(c.GL_ARRAY_BUFFER, size, vertices.ptr, c.GL_STATIC_DRAW);

        const stride: c.GLsizei = 6 * @sizeOf(f32);
        // Tell OpenGL how to interpret vertex data (per vertex attribute).
        // 0 = vertex attribute number 0 (`layout (location = 0)`)
        // 3 = size of vertex attribute (vec3)
        // GL_FALSE = do not normalize (this is only relevant for integers)
        // null = pointer to offset (our vbo starts at 0) (NULL pointer is just 0) it uses value of pointer (retarded).
        c.glVertexAttribPointer(0, 3, c.GL_FLOAT, c.GL_FALSE, stride, null); // attribute 0 (position)
        c.glEnableVertexAttribArray(0);

        c.glVertexAttribPointer(1, 3, c.GL_FLOAT, c.GL_FALSE, stride, @ptrFromInt(3 * @sizeOf(f32))); // attribute 1 (color)
        c.glEnableVertexAttribArray(1);

        var ebo: u32 = 0;
        c.glGenBuffers(1, &ebo);
        c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, ebo);
        c.glBufferData(c.GL_ELEMENT_ARRAY_BUFFER, @intCast(indices.len * @sizeOf(u32)), indices.ptr, c.GL_STATIC_DRAW);

        return Mesh{ .vao = vao, .vbo = vbo, .ebo = ebo, .index_count = @intCast(indices.len) };
    }
};

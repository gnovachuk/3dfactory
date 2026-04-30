const std = @import("std");

const c = @import("gl.zig").c;
const ecs = @import("ecs.zig");
const math = @import("math.zig");
const Mesh = @import("mesh.zig").Mesh;
const Shader = @import("shader.zig").Shader;

const WIDTH = 1280;
const HEIGHT = 720;

const Entity = struct {
    position: math.Vec3,
    rotation: math.Vec3,

    fn getModelMatrix(self: Entity) math.Mat4 {
        const translation = math.Mat4.translate(self.position);
        const rotation = math.Mat4.rotate(self.rotation);
        return translation.mul(rotation);
    }
};

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit();
    const allocator = debug_allocator.allocator();

    var world = ecs.World.init(allocator);
    defer world.deinit();
    const e0 = world.createEntity();
    const e1 = world.createEntity();
    try world.addComponent(e0, math.Vec3, math.Vec3.init(0, 0, 0));
    try world.addComponent(e1, math.Vec3, math.Vec3.init(0, 1, 0));

    // Query Test
    var it = world.query(.{math.Vec3});
    while (it.next()) |value| {
        std.debug.print("{}\n", .{value});
    }

    const v = c.glfwGetVersionString();
    std.debug.print("GLFW version: {s}\n", .{v});

    if (c.glfwInit() == 0) {
        std.debug.print("GLFW failed to initlialize\n", .{});
        return error.GlfwInitFailed;
    }

    defer c.glfwTerminate(); // cleanup when exiting.

    // window hints.
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 3);
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 3);
    c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);
    c.glfwWindowHint(c.GLFW_OPENGL_FORWARD_COMPAT, c.GLFW_TRUE);

    // create window.
    const window = c.glfwCreateWindow(WIDTH, HEIGHT, "3D Factory", null, null) orelse return error.WindowCreateFailed;
    defer c.glfwDestroyWindow(window);

    c.glfwMakeContextCurrent(window);
    c.glEnable(c.GL_DEPTH_TEST);

    // rendering a cube!

    // vertices.
    const vertices: [48]f32 = .{
        // bottom face.
        -0.5, -0.5, -0.5, 1, 0, 0, // bfl 0
        0.5, -0.5, -0.5, 0, 1, 0, // bfr 1
        0.5, -0.5, 0.5, 1, 0, 1, // bnr 2
        -0.5, -0.5, 0.5, 0, 1, 0, // bnl 3

        // front face.
        -0.5, 0.5, 0.5, 1, 0, 1, // tnl 4
        0.5, 0.5, 0.5, 0, 1, 0, // tnr 5
        -0.5, 0.5, -0.5, 1, 0, 1, // tfl 6
        0.5, 0.5, -0.5, 0.5, 0.5, 0.5, // tfr 7
    };

    const indices: [36]u32 = .{
        0, 1, 2, 2, 3, 0, // bottom face.
        4, 5, 2, 2, 3, 4, // front face.
        4, 6, 7, 7, 5, 4, // top face.
        6, 7, 1, 1, 0, 6, // back face.
        6, 0, 3, 3, 4, 6, // left face.
        7, 1, 2, 2, 5, 7, // right face.
    };

    // create vertex & frag shaders.
    const shader = try Shader.init(@embedFile("shaders/vertex.glsl"), @embedFile("shaders/frag.glsl"));
    defer shader.deinit();
    const modelHandle = c.glGetUniformLocation(shader.program_id, "uModel");
    const projHandle = c.glGetUniformLocation(shader.program_id, "uProj");
    const viewHandle = c.glGetUniformLocation(shader.program_id, "uView");

    var model = math.Mat4.identity();
    std.debug.print("{}\n", .{WIDTH / HEIGHT});
    const aspect: f32 = @as(f32, @floatFromInt(WIDTH)) / @as(f32, @floatFromInt(HEIGHT));
    const proj = math.Mat4.perspective(std.math.pi / 4.0, aspect, 0.1, 100.0);

    // create triangle mesh.
    const cube = Mesh.init(&vertices, &indices);
    defer cube.deinit();

    // draw wireframe.
    // c.glPolygonMode(c.GL_FRONT_AND_BACK, c.GL_LINE);

    shader.use();
    c.glUniformMatrix4fv(projHandle, 1, c.GL_FALSE, &proj.data);

    // main loop.
    c.glClearColor(0.05, 0.1, 0.25, 1.0);

    var entities: std.ArrayList(Entity) = try .initCapacity(allocator, 6);
    defer entities.deinit(allocator);
    try entities.append(allocator, Entity{ .position = math.Vec3.init(0, 0, 0), .rotation = math.Vec3.init(0, 0, 0) });
    try entities.append(allocator, Entity{ .position = math.Vec3.init(2, 0, 0), .rotation = math.Vec3.init(0, 0, 0) });
    try entities.append(allocator, Entity{ .position = math.Vec3.init(-2, 0, 0), .rotation = math.Vec3.init(0, 0, 0) });
    try entities.append(allocator, Entity{ .position = math.Vec3.init(0, 2, -3), .rotation = math.Vec3.init(0, 0, 0) });
    try entities.append(allocator, Entity{ .position = math.Vec3.init(5, 2, -3), .rotation = math.Vec3.init(0, 0, 0) });
    try entities.append(allocator, Entity{ .position = math.Vec3.init(5, 5, -7), .rotation = math.Vec3.init(0, 0, 0) });

    var camera: math.Vec3 = math.Vec3.init(0, 0, -5);
    var yaw: f32 = 0.0;
    var pitch: f32 = 0.0;
    var last_mx: f64 = 0;
    var last_my: f64 = 0;
    const sensitivity: f32 = 0.002;
    c.glfwSetInputMode(window, c.GLFW_CURSOR, c.GLFW_CURSOR_DISABLED);
    c.glfwGetCursorPos(window, &last_mx, &last_my);
    const speed: f32 = 5;
    var last_time: f32 = @floatCast(c.glfwGetTime());
    while (c.glfwWindowShouldClose(window) == 0) {
        const now: f32 = @floatCast(c.glfwGetTime());
        const dt: f32 = now - last_time;
        last_time = now;

        var mx: f64 = 0;
        var my: f64 = 0;
        c.glfwGetCursorPos(window, &mx, &my);
        const dx: f32 = @floatCast(mx - last_mx);
        const dy: f32 = @floatCast(my - last_my);
        last_mx = mx;
        last_my = my;
        var cubeX: f32 = 0.0;

        yaw += dx * sensitivity;
        pitch -= dy * sensitivity;
        pitch = std.math.clamp(pitch, -1.5, 1.5); // ~ ±86°

        const forward = math.Vec3.init(@cos(pitch) * @sin(yaw), @sin(pitch), -@cos(pitch) * @cos(yaw));

        c.glfwPollEvents();
        c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);

        if (c.glfwGetKey(window, c.GLFW_KEY_W) == c.GLFW_PRESS) {
            camera = camera.add(forward.scale(speed * dt));
        }

        if (c.glfwGetKey(window, c.GLFW_KEY_S) == c.GLFW_PRESS) {
            camera = camera.sub(forward.scale(speed * dt));
        }

        if (c.glfwGetKey(window, c.GLFW_KEY_A) == c.GLFW_PRESS) {
            camera = camera.sub(forward.cross(math.Vec3.init(0, 1, 0)).normalize().scale(speed * dt));
        }

        if (c.glfwGetKey(window, c.GLFW_KEY_D) == c.GLFW_PRESS) {
            camera = camera.add(forward.cross(math.Vec3.init(0, 1, 0)).normalize().scale(speed * dt));
        }

        if (c.glfwGetKey(window, c.GLFW_KEY_SPACE) == c.GLFW_PRESS) {
            camera.y += speed * dt;
        }

        if (c.glfwGetKey(window, c.GLFW_KEY_LEFT_SHIFT) == c.GLFW_PRESS) {
            camera.y -= speed * dt;
        }

        if (c.glfwGetKey(window, c.GLFW_KEY_C) == c.GLFW_PRESS) {
            cubeX += 2.0;
            try entities.append(allocator, Entity{ .position = math.Vec3.init(cubeX, cubeX, 0), .rotation = math.Vec3.init(0, 0, 0) });
        }

        shader.use(); // every shader & rendering call now use this program, and thus our shaders.

        const view = math.Mat4.look_at(camera, camera.add(forward), math.Vec3.init(0, 1, 0));
        c.glUniformMatrix4fv(viewHandle, 1, c.GL_FALSE, &view.data);

        for (entities.items) |*entity| {
            entity.rotation.y += dt * speed;
            model = entity.getModelMatrix();
            c.glUniformMatrix4fv(modelHandle, 1, c.GL_FALSE, &model.data);
            cube.draw();
        }

        c.glfwSwapBuffers(window);
    }
}

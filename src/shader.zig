const std = @import("std");
const c = @import("gl.zig").c;

pub const Shader = struct {
    program_id: u32,

    pub fn use(self: Shader) void {
        c.glUseProgram(self.program_id);
    }

    pub fn deinit(self: Shader) void {
        c.glDeleteProgram(self.program_id);
    }

    pub fn init(vertex_src: [*c]const u8, frag_src: [*c]const u8) !Shader {
        // create & compile vertex shader.
        const vertex_shader: u32 = c.glCreateShader(c.GL_VERTEX_SHADER);
        errdefer c.glDeleteShader(vertex_shader);

        c.glShaderSource(vertex_shader, 1, &vertex_src, null);
        c.glCompileShader(vertex_shader);

        // check shader compilation status.
        var success: i32 = 0;
        c.glGetShaderiv(vertex_shader, c.GL_COMPILE_STATUS, &success);
        if (success == 0) {
            var log: [512]u8 = undefined;
            c.glGetShaderInfoLog(vertex_shader, log.len, null, &log);
            std.debug.print("[vertex shader]: {s}\n", .{log});
            return error.ShaderCompileFailed;
        }

        // create & compile fragment shader.
        const frag_shader: u32 = c.glCreateShader(c.GL_FRAGMENT_SHADER);
        errdefer c.glDeleteShader(frag_shader);
        c.glShaderSource(frag_shader, 1, &frag_src, null);
        c.glCompileShader(frag_shader);

        // check frag shader compilation status.
        success = 0;
        c.glGetShaderiv(frag_shader, c.GL_COMPILE_STATUS, &success);
        if (success == 0) {
            var log: [512]u8 = undefined;
            c.glGetShaderInfoLog(frag_shader, log.len, null, &log);
            std.debug.print("[frag shader]: {s}\n", .{log});
            return error.ShaderCompileFailed;
        }

        // create shader program object which links vertex & frag shaders.
        const shader_program: u32 = c.glCreateProgram();
        errdefer c.glDeleteProgram(shader_program);
        c.glAttachShader(shader_program, vertex_shader);
        c.glAttachShader(shader_program, frag_shader);
        c.glLinkProgram(shader_program);

        // check success of shader program linking.
        success = 0;
        c.glGetProgramiv(shader_program, c.GL_LINK_STATUS, &success);
        if (success == 0) {
            var log: [512]u8 = undefined;
            c.glGetProgramInfoLog(shader_program, log.len, null, &log);
            std.debug.print("[shader program]: {s}\n", .{log});
            return error.ShaderLinkFailed;
        }

        c.glDeleteShader(vertex_shader); // delete shaders, we no longer need them (they're linked now).
        c.glDeleteShader(frag_shader);

        return Shader{ .program_id = shader_program };
    }
};

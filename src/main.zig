const std = @import("std");
const fs = std.fs;

const zgui = @import("zgui");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const ztracy = @import("ztracy");
const gl = zopengl.bindings;
const state_machine = @import("utils/state-machine.zig");

const content_dir = "content/";
const window_title = "zig-gamedev: minimal zgpu glfw opengl3";

pub fn main() !void {
    state_machine.t();

    // ========================

    try glfw.init();
    defer glfw.terminate();

    ztracy.SetThreadName("MainThread");
    // const main_zone = ztracy.ZoneN(@src(), "main");
    // defer main_zone.End();

    const gl_major = 4;
    const gl_minor = 0;
    glfw.windowHint(.context_version_major, gl_major);
    glfw.windowHint(.context_version_minor, gl_minor);
    glfw.windowHint(.opengl_profile, .opengl_core_profile);
    glfw.windowHint(.opengl_forward_compat, true);
    glfw.windowHint(.client_api, .opengl_api);
    glfw.windowHint(.doublebuffer, true);

    const window = try glfw.Window.create(800, 500, window_title, null);
    defer window.destroy();
    window.setSizeLimits(400, 400, -1, -1);

    glfw.makeContextCurrent(window);
    glfw.swapInterval(1);
    _ = glfw.setKeyCallback(window, key_callback);

    try zopengl.loadCoreProfile(glfw.getProcAddress, gl_major, gl_minor);

    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    zgui.init(gpa);
    defer zgui.deinit();

    const scale_factor = scale_factor: {
        const scale = window.getContentScale();
        break :scale_factor @max(scale[0], scale[1]);
    };
    _ = zgui.io.addFontFromFile(
        content_dir ++ "Roboto-Medium.ttf",
        std.math.floor(16.0 * scale_factor),
    );

    zgui.getStyle().scaleAllSizes(scale_factor);

    zgui.backend.init(window);
    defer zgui.backend.deinit();

    // =================================

    const vertices = [6]f32{
        -0.5, -0.5,
        0.5,  -0.5,
        0,    0.5,
    };

    const vertexShaderSrc =
        \\#version 330 core
        \\
        \\layout(location = 0) in vec4 position;
        \\
        \\void main()
        \\{
        \\  gl_Position = position;
        \\}
    ;
    const fragmentShaderSrc =
        \\#version 330 core
        \\
        \\layout(location = 0) out vec4 color;
        \\
        \\void main()
        \\{
        \\  color = vec4(1.0, 1.0, 0.0, 1.0);
        \\}
    ;
    _ = vertexShaderSrc;
    _ = fragmentShaderSrc;

    var vao: u32 = undefined;
    gl.genVertexArrays(1, &vao);
    gl.bindVertexArray(vao);

    var buffId: u32 = undefined;
    gl.genBuffers(1, &buffId);
    gl.bindBuffer(gl.ARRAY_BUFFER, buffId);
    gl.bufferData(gl.ARRAY_BUFFER, vertices.len * 4, &vertices, gl.STATIC_DRAW);

    gl.enableVertexAttribArray(0);
    //const a: anyopaque = null;
    gl.vertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, 2 * 4, null);
    gl_check_error();

    const shader = create_shader();
    gl.useProgram(shader);
    defer gl.deleteProgram(shader);

    // =================================

    while (!window.shouldClose() and window.getKey(.escape) != .press) {
        glfw.pollEvents();

        gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 0, 0, 0, 1.0 });

        gl.useProgram(shader);
        gl.bindBuffer(gl.ARRAY_BUFFER, buffId);

        gl.drawArrays(gl.TRIANGLES, 0, 3);
        // gl_check_error();

        const fb_size = window.getFramebufferSize();

        zgui.backend.newFrame(@intCast(fb_size[0]), @intCast(fb_size[1]));

        // Set the starting window position and size to custom values
        zgui.setNextWindowPos(.{ .x = 20.0, .y = 20.0, .cond = .first_use_ever });
        zgui.setNextWindowSize(.{ .w = -1.0, .h = -1.0, .cond = .first_use_ever });

        if (zgui.begin("My window", .{})) {
            if (zgui.button("Press me!", .{ .w = 200.0 })) {
                std.debug.print("Button pressed\n", .{});
            }
        }
        zgui.end();

        zgui.backend.draw();

        window.swapBuffers();

        ztracy.FrameMark();
    }
}

fn key_callback(window: *glfw.Window, key: glfw.Key, scancode: c_int, action: glfw.Action, mods: glfw.Mods) callconv(.c) void {
    _ = window;
    _ = scancode;
    _ = mods;

    if (key == glfw.Key.e and action == glfw.Action.press)
        std.debug.print("Button pressed\n", .{});
}

fn compile_shader(shaderType: c_uint, source: [*c]const u8) c_uint {
    const cSrc = [1][*c]const u8{source};
    const id = gl.createShader(shaderType);
    gl.shaderSource(id, 1, cSrc[0..], null);
    gl.compileShader(id);

    var result: i32 = undefined;
    gl.getShaderiv(id, gl.COMPILE_STATUS, &result);
    if (result == gl.FALSE) {
        var length: c_int = undefined;
        gl.getShaderiv(id, gl.INFO_LOG_LENGTH, &length);

        const allocator = std.heap.page_allocator;
        const message = allocator.alloc(u8, @intCast(length)) catch return 0;
        defer allocator.free(message);
        const cMessage: [*c]u8 = message.ptr;
        gl.getShaderInfoLog(id, length, &length, cMessage);

        if (shaderType == gl.VERTEX_SHADER) {
            std.debug.print("Vertex shader error\n", .{});
        } else if (shaderType == gl.FRAGMENT_SHADER) {
            std.debug.print("Fragment shader error\n", .{});
        } else {
            std.debug.print("Unknown shader error\n", .{});
        }

        std.debug.print("Log length: {d}\n", .{length});
        std.debug.print("Error message: {s}\n", .{message});
        gl.deleteShader(id);
    }

    return id;
}

fn create_shader() c_uint {
    const allocator = std.heap.page_allocator;
    const shaderSrc = loadShaderFileAlloc(allocator) catch return 0;
    defer allocator.free(shaderSrc);

    // find #vertex
    var vertexShaderStartIdx: usize = 0;
    std.debug.print("\n", .{});
    for (0..shaderSrc.len) |i| {
        const vertexHeader = "#vertex\n";
        const iEnd = i + vertexHeader.len;
        const currSlice = shaderSrc[i..iEnd];
        std.debug.print("line len: {d}\n", .{vertexHeader[7]});
        std.debug.print("head len: {d}\n", .{currSlice[7]});
        std.debug.print("line: {s}\n", .{currSlice});
        std.debug.print("head: {s}\n", .{vertexHeader});
        if (std.mem.eql(u8, vertexHeader, currSlice)) {
            vertexShaderStartIdx = iEnd;
            break;
        }
    }

    // find #fragment
    var vertexShaderEndIdx: usize = 0;
    var fragmentShaderStartIdx: usize = 0;
    for (vertexShaderStartIdx..shaderSrc.len) |i| {
        const fragmentHeader = "#fragment\n";
        const iEnd = i + fragmentHeader.len;
        const currSlice = shaderSrc[i..iEnd];
        if (std.mem.eql(u8, fragmentHeader, currSlice)) {
            vertexShaderEndIdx = i;
            fragmentShaderStartIdx = iEnd;
            break;
        }
    }

    const vertexShader = shaderSrc[vertexShaderStartIdx..vertexShaderEndIdx];
    const fragmentShader = shaderSrc[fragmentShaderStartIdx..];

    const vertexShaderMemory = allocator.alloc(u8, vertexShader.len) catch return 0;
    defer allocator.free(vertexShaderMemory);
    std.mem.copyForwards(u8, vertexShaderMemory, vertexShader);

    const fragmentShaderMemory = allocator.alloc(u8, fragmentShader.len) catch return 0;
    defer allocator.free(fragmentShaderMemory);
    std.mem.copyForwards(u8, fragmentShaderMemory, fragmentShader);

    const cVertex: [*c]const u8 = vertexShaderMemory.ptr;
    const cFragment: [*c]const u8 = fragmentShaderMemory.ptr;

    const program = gl.createProgram();
    const vertex = compile_shader(gl.VERTEX_SHADER, cVertex);
    const fragment = compile_shader(gl.FRAGMENT_SHADER, cFragment);

    gl.attachShader(program, vertex);
    gl.attachShader(program, fragment);
    gl.linkProgram(program);
    gl.validateProgram(program);

    gl.deleteShader(vertex);
    gl.deleteShader(fragment);

    return program;
}

fn gl_clear_error() void {
    while (true) {
        const err = gl.getError();
        if (err != gl.NO_ERROR)
            return;
    }
}

fn gl_check_error() void {
    while (true) {
        const err = gl.getError();
        if (err == gl.NO_ERROR)
            return;

        std.debug.print("{d}\n", .{err});
    }
}

fn loadShaderFileAlloc(allocator: std.mem.Allocator) ZuimoError![]u8 {
    const file = fs.cwd().openFile("content/shader.glsl", .{}) catch return error.Unknown;
    // const file = fs.cwd().openFile("content/test", .{}) catch return;
    defer file.close();

    const buf: [4]u8 = undefined; // smaller buffer causes an error
    var reader = fs.File.reader(file, @constCast(buf[0..]));

    const size = reader.getSize() catch 0;
    const fileContents = allocator.alloc(u8, size) catch return error.Unknown;

    reader.interface.readSliceAll(fileContents) catch return error.Unknown;
    return fileContents;
}

const ZuimoError = error{
    Unknown,
};

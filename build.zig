const std = @import("std");

pub const content_dir = "content/";

pub fn build(b: *std.Build) void {
    //const cwd_path = b.pathJoin(&.{ "samples", demo_name });

    // create executable
    const exe = b.addExecutable(.{
        .name = "Zuimo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = b.graph.host,
        }),
    });
    b.installArtifact(exe);

    // link libraries
    const zgui = b.dependency("zgui", .{
        .shared = false,
        .with_implot = true,
        .backend = .glfw_opengl3,
    });
    exe.root_module.addImport("zgui", zgui.module("root"));
    exe.linkLibrary(zgui.artifact("imgui"));

    const zopengl = b.dependency("zopengl", .{});
    exe.root_module.addImport("zopengl", zopengl.module("root"));

    const zglfw_name = "zglfw";
    const zglfw = b.dependency(zglfw_name, .{
        .target = b.graph.host,
    });
    exe.root_module.addImport(zglfw_name, zglfw.module("root"));
    exe.linkLibrary(zglfw.artifact("glfw"));

    const ztracy_name = "ztracy";
    const ztracy = b.dependency(ztracy_name, .{
        .enable_ztracy = true,
        .target = b.graph.host,
    });
    exe.root_module.addImport(ztracy_name, ztracy.module("root"));
    exe.linkLibrary(ztracy.artifact("tracy"));

    const exe_options = b.addOptions();
    exe.root_module.addOptions("build_options", exe_options);
    exe_options.addOption([]const u8, "content_dir", content_dir);

    // const content_path = b.pathJoin(&.{ cwd_path, content_dir });
    const install_content_step = b.addInstallDirectory(.{
        .source_dir = b.path(content_dir),
        .install_dir = .{ .custom = "" },
        .install_subdir = b.pathJoin(&.{ "bin", content_dir }),
    });
    exe.step.dependOn(&install_content_step.step);

    if (b.graph.host.result.os.tag == .linux) {
        if (b.lazyDependency("system_sdk", .{})) |system_sdk| {
            exe.addLibraryPath(system_sdk.path("linux/lib/x86_64-linux-gnu"));
        }
    }

    // create build artifacts
    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_exe.step);
}

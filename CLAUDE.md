# zuimo

Personal Zig playground for graphics/UI experiments. The owner is learning Zig, so prefer clear, idiomatic code over clever code.

## Toolchain
- Zig **0.15.2** (`minimum_zig_version = "0.15.0"`). Use 0.15 APIs (e.g. the new `std.Io` reader/writer interfaces, `callconv(.c)`).

## Dependencies (zig-gamedev)
- `zglfw`: windowing and input
- `zopengl`: OpenGL bindings (core profile 4.0)
- `zgui`: Dear ImGui (GLFW + OpenGL3 backend, with ImPlot)
- `ztracy`: Tracy profiler (enabled)
- `system_sdk`: Linux system libraries

## Build & run
- `zig build`: builds `zig-out/bin/Zuimo` and copies `content/` to `zig-out/bin/content/`
- `zig build run`: builds and runs
- Run from the repo root. Assets are loaded with paths relative to the working directory (`content/...`).

## Layout
- `src/main.zig`: entry point, window/GL/ImGui setup, main loop, shader loading
- `src/utils/`: utility modules (e.g. `state-machine.zig`)
- `src/framework/`: reserved for framework code (currently empty)
- `content/`: runtime assets (`shader.glsl` with `#vertex` / `#fragment` sections, `Roboto-Medium.ttf`)

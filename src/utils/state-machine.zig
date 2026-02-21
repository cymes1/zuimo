const std = @import("std");

fn tick() void {
    std.debug.print("Dupa", .{});
}

pub fn t() void {
    const main_state: State = .{
        .child_tick = tick,
    };
    main_state.tick();
}

const State = struct {
    child_tick: fn () void,

    fn tick(self: State) void {
        self.child_tick();
    }
};

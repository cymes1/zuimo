const std = @import("std");

var currentState = second_state;

pub fn transitionTo(state: State) void {
    currentState = state;
}

pub const main_state: State = .{
    .child_tick = tick,
};

pub const second_state: State = .{
    .child_tick = tick1,
};

fn tick() void {
    std.debug.print("Main tick\n", .{});
}

fn tick1() void {
    std.debug.print("Second tick\n", .{});
}

pub fn t() void {
    currentState.tick();
}

const State = struct {
    child_tick: *const fn () void,

    fn tick(self: State) void {
        self.child_tick();
    }
};

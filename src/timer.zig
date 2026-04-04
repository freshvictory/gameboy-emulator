const std = @import("std");

const Timer = @This();

m: u8 = 0,

divider: u8 = 0,

/// TIMA
counter: u8 = 0,

/// TMA
reset_value: u8 = 0,

control: Control = .{},

/// How often to increment the counter,
/// in m-cycles.
const Frequency = enum(u2) {
    every_256,
    every_4,
    every_16,
    every_64,

    pub fn shouldTrigger(self: Frequency, value: u8) bool {
        return switch (self) {
            .every_4 => value % 4 == 0,
            .every_16 => value % 16 == 0,
            .every_64 => value % 64 == 0,
            .every_256 => value == 0,
        };
    }
};

const Control = packed struct(u3) {
    frequency: Frequency = .every_256,
    enabled: bool = false,
};

pub fn tick(timer: *Timer) bool {
    timer.m, const m_overflowed = @addWithOverflow(timer.m, 1);

    if (m_overflowed != 0) {
        timer.divider +%= 1;
    }

    if (!timer.control.enabled) return false;

    const should_increment = timer.control.frequency.shouldTrigger(timer.m);
    if (!should_increment) return false;

    timer.counter, const counter_overflowed = @addWithOverflow(
        timer.counter,
        1,
    );

    if (counter_overflowed == 0) return false;

    timer.counter = timer.reset_value;

    return true;
}

test "divider increments every 256 m cycles" {
    var timer = Timer{ .m = 254, .divider = 0 };
    _ = timer.tick();
    try std.testing.expectEqual(0, timer.divider);
    _ = timer.tick();
    try std.testing.expectEqual(1, timer.divider);
}

test "counter increments at frequency 4" {
    var timer = Timer{
        .counter = 0,
        .control = .{
            .frequency = .every_4,
            .enabled = true,
        },
        .m = 2,
    };

    _ = timer.tick();
    try std.testing.expectEqual(0, timer.counter);
    _ = timer.tick();
    try std.testing.expectEqual(1, timer.counter);
}

test "counter increments at frequency 16" {
    var timer = Timer{
        .counter = 0,
        .control = .{
            .frequency = .every_16,
            .enabled = true,
        },
        .m = 14,
    };

    _ = timer.tick();
    try std.testing.expectEqual(0, timer.counter);
    _ = timer.tick();
    try std.testing.expectEqual(1, timer.counter);
}

test "counter increments at frequency 64" {
    var timer = Timer{
        .counter = 0,
        .control = .{
            .frequency = .every_64,
            .enabled = true,
        },
        .m = 62,
    };

    _ = timer.tick();
    try std.testing.expectEqual(0, timer.counter);
    _ = timer.tick();
    try std.testing.expectEqual(1, timer.counter);
}

test "counter increments at frequency 256" {
    var timer = Timer{
        .counter = 0,
        .control = .{
            .frequency = .every_256,
            .enabled = true,
        },
        .m = 254,
    };

    _ = timer.tick();
    try std.testing.expectEqual(0, timer.counter);
    _ = timer.tick();
    try std.testing.expectEqual(1, timer.counter);
}

test "counter overflows to reset value and returns true" {
    var timer = Timer{
        .counter = 255,
        .reset_value = 123,
        .control = .{
            .frequency = .every_4,
            .enabled = true,
        },
        .m = 3,
    };
    const overflowed = timer.tick();
    try std.testing.expectEqual(123, timer.counter);
    try std.testing.expect(overflowed);
}

test "counter doesn't increment if not enabled" {
    var timer = Timer{
        .counter = 0,
        .control = .{
            .frequency = .every_4,
            .enabled = false,
        },
        .m = 3,
    };

    _ = timer.tick();
    try std.testing.expectEqual(0, timer.counter);
}

const std = @import("std");
const Z80 = @import("z80.zig");
const Flags = Z80.Flags;

pub fn run_tests_in(comptime filename: []const u8) !void {
    const json = @embedFile(filename);
    const parsed_test_cases = try std.json.parseFromSlice([]TestCase, std.testing.allocator, json, .{
        .ignore_unknown_fields = true,
    });
    defer parsed_test_cases.deinit();

    var errored = false;
    for (parsed_test_cases.value) |test_case| {
        test_case.run() catch {
            errored = true;
            std.debug.print("\tin test case: {s}\n\n", .{test_case.name});
        };
    }

    if (errored) return error.TestExpectedEqual;
}

pub const TestCase = struct {
    name: []const u8,
    initial: CpuState,
    final: CpuState,

    pub fn run(t: TestCase) !void {
        var z80 = Z80.init(.{});
        t.initial.apply(&z80);

        z80.step();

        try t.final.check(z80);
    }
};

pub const CpuState = struct {
    pc: u16,
    sp: u16,
    a: u8,
    b: u8,
    c: u8,
    d: u8,
    e: u8,
    f: u8,
    h: u8,
    l: u8,
    ram: []const ([2]u16),

    pub fn apply(state: CpuState, z80: *Z80) void {
        for (state.ram) |ram| {
            const address = ram[0];
            const value: u8 = @intCast(ram[1]);

            z80.mmu[address] = value;
        }

        z80.registers = .{
            .stack_pointer = state.sp,
            .a = state.a,
            .b = state.b,
            .c = state.c,
            .d = state.d,
            .e = state.e,
            .h = state.h,
            .l = state.l,
        };
        z80.program_counter = state.pc;
        z80.flags = Flags.from(state.f);
    }

    pub fn check(state: CpuState, z80: Z80) !void {
        var errored = false;

        std.testing.expectEqual(state.a, z80.registers.a) catch {
            errored = true;
            std.debug.print("\ttesting a\n", .{});
        };
        std.testing.expectEqual(state.b, z80.registers.b) catch {
            errored = true;
            std.debug.print("\ttesting b\n", .{});
        };
        std.testing.expectEqual(state.c, z80.registers.c) catch {
            errored = true;
            std.debug.print("\ttesting c\n", .{});
        };
        std.testing.expectEqual(state.d, z80.registers.d) catch {
            errored = true;
            std.debug.print("\ttesting d\n", .{});
        };
        std.testing.expectEqual(state.e, z80.registers.e) catch {
            errored = true;
            std.debug.print("\ttesting e\n", .{});
        };
        std.testing.expectEqual(state.f, z80.flags.int()) catch {
            errored = true;
            std.debug.print("\ttesting flags\n", .{});
        };
        std.testing.expectEqual(state.h, z80.registers.h) catch {
            errored = true;
            std.debug.print("\ttesting h\n", .{});
        };
        std.testing.expectEqual(state.l, z80.registers.l) catch {
            errored = true;
            std.debug.print("\ttesting l\n", .{});
        };
        std.testing.expectEqual(state.sp, z80.registers.stack_pointer) catch {
            errored = true;
            std.debug.print("\ttesting stack pointer\n", .{});
        };
        std.testing.expectEqual(state.pc, z80.program_counter) catch {
            errored = true;
            std.debug.print("\ttesting program counter\n", .{});
        };

        for (state.ram) |ram| {
            const address = ram[0];
            const value: u8 = @intCast(ram[1]);
            std.testing.expectEqual(value, z80.mmu[address]) catch {
                errored = true;
                std.debug.print("\ttesting memory address {d}\n", .{address});
            };
        }

        if (errored) return error.TestExpectedEqual;
    }
};

test "0x80 add a, b" {
    try run_tests_in("sm83/v1/80.json");
}

test "0x81 add a, c" {
    try run_tests_in("sm83/v1/81.json");
}

test "0x82 add a, d" {
    try run_tests_in("sm83/v1/81.json");
}

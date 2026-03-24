const std = @import("std");
const Z80 = @import("z80.zig");
const Flags = Z80.Flags;

pub fn run_tests_for(comptime instruction: []const u8, expected_clock_m: usize) !void {
    const json = @embedFile("sm83/v1/" ++ instruction ++ ".json");
    const parsed_test_cases = try std.json.parseFromSlice([]TestCase, std.testing.allocator, json, .{
        .ignore_unknown_fields = true,
    });
    defer parsed_test_cases.deinit();

    var errored: usize = 0;
    for (parsed_test_cases.value) |test_case| {
        test_case.run(expected_clock_m) catch {
            errored += 1;
            std.debug.print("\tin test case: {s}\n\n", .{test_case.name});
        };
    }

    if (errored > 0) {
        std.debug.print("{d} passed, {d} failed.\n", .{
            parsed_test_cases.value.len - errored,
            errored,
        });
        return error.TestExpectedEqual;
    }
}

const TestCase = struct {
    name: []const u8,
    initial: CpuState,
    final: CpuState,

    pub fn run(t: TestCase, expected_clock_m: usize) !void {
        var z80 = Z80.init(.{});
        t.initial.apply(&z80);

        z80.step();

        try t.final.check(z80);
        try std.testing.expectEqual(expected_clock_m, z80.clock.m);
    }
};

const CpuState = struct {
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
            std.debug.print(
                "\ttesting flags:\n\t\texpected {}\n\t\tfound    {}\n",
                .{ Flags.from(state.f), z80.flags },
            );
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

test "0x00 nop" {
    try run_tests_for("00", 1);
}

test "0x01 load bc, n16" {
    try run_tests_for("01", 3);
}

test "0x02 load [bc], a" {
    try run_tests_for("02", 2);
}

test "0x03 inc bc" {
    try run_tests_for("03", 2);
}

test "0x04 inc b" {
    try run_tests_for("04", 1);
}

test "0x05 dec b" {
    try run_tests_for("05", 1);
}

test "0x06 ld b, n8" {
    try run_tests_for("06", 2);
}

test "0x07 rcla" {
    try run_tests_for("07", 1);
}

test "0x08 ld [a16], sp" {
    try run_tests_for("0x08", 5);
}

test "0x09 add hl, bc" {
    try run_tests_for("09", 2);
}

test "0x0A ld a, [bc]" {
    try run_tests_for("0A", 2);
}

test "0x0B dec bc" {
    try run_tests_for("0B", 2);
}

test "0x0C inc c" {
    try run_tests_for("0C", 1);
}

test "0x0D dec c" {
    try run_tests_for("0D", 1);
}

test "0x0E ld c, n8" {
    try run_tests_for("0E", 2);
}

test "0x0F rrca" {
    try run_tests_for("0F", 1);
}

test "0x40 ld b, b" {
    try run_tests_for("40", 1);
}

test "0x41 ld b, c" {
    try run_tests_for("41", 1);
}

test "0x42 ld b, d" {
    try run_tests_for("42", 1);
}

test "0x43 ld b, e" {
    try run_tests_for("43", 1);
}

test "0x44 ld b, h" {
    try run_tests_for("44", 1);
}

test "0x45 ld b, l" {
    try run_tests_for("45", 1);
}

test "0x46 ld b, [hl]" {
    try run_tests_for("46", 2);
}

test "0x47 ld b, a" {
    try run_tests_for("47", 1);
}

test "0x48 ld c, b" {
    try run_tests_for("48", 1);
}

test "0x49 ld c, c" {
    try run_tests_for("49", 1);
}

test "0x4A ld c, d" {
    try run_tests_for("4A", 1);
}

test "0x4B ld c, e" {
    try run_tests_for("4B", 1);
}

test "0x4C ld c, h" {
    try run_tests_for("4C", 1);
}

test "0x4D ld c, l" {
    try run_tests_for("4D", 1);
}

test "0x4E ld c, [hl]" {
    try run_tests_for("4E", 2);
}

test "0x4F ld c, a" {
    try run_tests_for("4F", 1);
}

test "0x50 ld d, b" {
    try run_tests_for("50", 1);
}

test "0x51 ld d, c" {
    try run_tests_for("51", 1);
}

test "0x52 ld d, d" {
    try run_tests_for("52", 1);
}

test "0x53 ld d, e" {
    try run_tests_for("53", 1);
}

test "0x54 ld d, h" {
    try run_tests_for("54", 1);
}

test "0x55 ld d, l" {
    try run_tests_for("55", 1);
}

test "0x56 ld d, [hl]" {
    try run_tests_for("56", 2);
}

test "0x57 ld d, a" {
    try run_tests_for("57", 1);
}

test "0x58 ld e, b" {
    try run_tests_for("58", 1);
}

test "0x59 ld e, c" {
    try run_tests_for("59", 1);
}

test "0x5A ld e, d" {
    try run_tests_for("5A", 1);
}

test "0x5B ld e, e" {
    try run_tests_for("5B", 1);
}

test "0x5C ld e, h" {
    try run_tests_for("5C", 1);
}

test "0x5D ld e, l" {
    try run_tests_for("5D", 1);
}

test "0x5E ld e, [hl]" {
    try run_tests_for("5E", 2);
}

test "0x5F ld e, a" {
    try run_tests_for("5F", 1);
}

test "0x60 ld h, b" {
    try run_tests_for("60", 1);
}

test "0x61 ld h, c" {
    try run_tests_for("61", 1);
}

test "0x62 ld h, d" {
    try run_tests_for("62", 1);
}

test "0x63 ld h, e" {
    try run_tests_for("63", 1);
}

test "0x64 ld h, h" {
    try run_tests_for("64", 1);
}

test "0x65 ld h, l" {
    try run_tests_for("65", 1);
}

test "0x66 ld h, [hl]" {
    try run_tests_for("66", 2);
}

test "0x67 ld h, a" {
    try run_tests_for("67", 1);
}

test "0x68 ld l, b" {
    try run_tests_for("68", 1);
}

test "0x69 ld l, c" {
    try run_tests_for("69", 1);
}

test "0x6A ld l, d" {
    try run_tests_for("6A", 1);
}

test "0x6B ld l, e" {
    try run_tests_for("6B", 1);
}

test "0x6C ld l, h" {
    try run_tests_for("6C", 1);
}

test "0x6D ld l, l" {
    try run_tests_for("6D", 1);
}

test "0x6E ld l, [hl]" {
    try run_tests_for("6E", 2);
}

test "0x6F ld l, a" {
    try run_tests_for("6F", 1);
}

test "0x70 ld [hl], b" {
    try run_tests_for("70", 2);
}

test "0x71 ld [hl], c" {
    try run_tests_for("71", 2);
}

test "0x72 ld [hl], d" {
    try run_tests_for("72", 2);
}

test "0x73 ld [hl], e" {
    try run_tests_for("73", 2);
}

test "0x74 ld [hl], h" {
    try run_tests_for("74", 2);
}

test "0x75 ld [hl], l" {
    try run_tests_for("75", 2);
}

test "0x76 halt" {
    try run_tests_for("76", 1);
}

test "0x77 ld [hl], a" {
    try run_tests_for("77", 2);
}

test "0x78 ld a, b" {
    try run_tests_for("78", 1);
}

test "0x79 ld a, c" {
    try run_tests_for("79", 1);
}

test "0x7A ld a, d" {
    try run_tests_for("7A", 1);
}

test "0x7B ld a, e" {
    try run_tests_for("7B", 1);
}

test "0x7C ld a, h" {
    try run_tests_for("7C", 1);
}

test "0x7D ld a, l" {
    try run_tests_for("7D", 1);
}

test "0x7E ld a, [hl]" {
    try run_tests_for("7E", 2);
}

test "0x7F ld a, a" {
    try run_tests_for("7F", 1);
}

test "0x80 add a, b" {
    try run_tests_for("80", 1);
}

test "0x81 add a, c" {
    try run_tests_for("81", 1);
}

test "0x82 add a, d" {
    try run_tests_for("82", 1);
}

test "0x83 add a, e" {
    try run_tests_for("83", 1);
}

test "0x84 add a, h" {
    try run_tests_for("84", 1);
}

test "0x85 add a, l" {
    try run_tests_for("85", 1);
}

test "0x86 add a, [hl]" {
    try run_tests_for("86", 2);
}

test "0x87 add a, a" {
    try run_tests_for("87", 1);
}

test "0x90 sub a, b" {
    try run_tests_for("90", 1);
}

test "0x91 sub a, c" {
    try run_tests_for("91", 1);
}

test "0x92 sub a, d" {
    try run_tests_for("92", 1);
}

test "0x93 sub a, e" {
    try run_tests_for("93", 1);
}

test "0x94 sub a, h" {
    try run_tests_for("94", 1);
}

test "0x95 sub a, l" {
    try run_tests_for("95", 1);
}

test "0x96 sub a, [hl]" {
    try run_tests_for("96", 2);
}

test "0x97 sub a, a" {
    try run_tests_for("97", 1);
}

test "0xA0 and a, b" {
    try run_tests_for("A0", 1);
}

test "0xA1 and a, c" {
    try run_tests_for("A1", 1);
}

test "0xA2 and a, d" {
    try run_tests_for("A2", 1);
}

test "0xA3 and a, e" {
    try run_tests_for("A3", 1);
}

test "0xA4 and a, h" {
    try run_tests_for("A4", 1);
}

test "0xA5 and a, l" {
    try run_tests_for("A5", 1);
}

test "0xA6 and a, [hl]" {
    try run_tests_for("A6", 2);
}

test "0xA7 and a, a" {
    try run_tests_for("A7", 1);
}

test "0xA8 xor a, b" {
    try run_tests_for("A8", 1);
}

test "0xA9 xor a, c" {
    try run_tests_for("A9", 1);
}

test "0xAA xor a, d" {
    try run_tests_for("AA", 1);
}

test "0xAB xor a, e" {
    try run_tests_for("AB", 1);
}

test "0xAC xor a, h" {
    try run_tests_for("AC", 1);
}

test "0xAD xor a, l" {
    try run_tests_for("AD", 1);
}

test "0xAE xor a, [hl]" {
    try run_tests_for("AE", 2);
}

test "0xAF xor a, a" {
    try run_tests_for("AF", 1);
}

test "0xB0 or a, b" {
    try run_tests_for("B0", 1);
}

test "0xB1 or a, c" {
    try run_tests_for("B1", 1);
}

test "0xB2 or a, d" {
    try run_tests_for("B2", 1);
}

test "0xB3 or a, e" {
    try run_tests_for("B3", 1);
}

test "0xB4 or a, h" {
    try run_tests_for("B4", 1);
}

test "0xB5 or a, l" {
    try run_tests_for("B5", 1);
}

test "0xB6 or a, [hl]" {
    try run_tests_for("B6", 2);
}

test "0xB7 or a, a" {
    try run_tests_for("B7", 1);
}

test "0xB8 cp a, b" {
    try run_tests_for("B8", 1);
}

test "0xB9 cp a, c" {
    try run_tests_for("B9", 1);
}

test "0xBA cp a, d" {
    try run_tests_for("BA", 1);
}

test "0xBB cp a, e" {
    try run_tests_for("BB", 1);
}

test "0xBC cp a, h" {
    try run_tests_for("BC", 1);
}

test "0xBD cp a, l" {
    try run_tests_for("BD", 1);
}

test "0xBE cp a, [hl]" {
    try run_tests_for("BE", 2);
}

test "0xBF cp a, a" {
    try run_tests_for("BF", 1);
}

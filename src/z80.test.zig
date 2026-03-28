const std = @import("std");
const Z80 = @import("z80.zig");
const Flags = Z80.Flags;

pub fn runTestsFor(comptime instruction: []const u8) !void {
    const json = @embedFile("sm83/v1/" ++ instruction ++ ".json");
    const parsed_test_cases = try std.json.parseFromSlice([]TestCase, std.testing.allocator, json, .{
        .ignore_unknown_fields = true,
    });
    defer parsed_test_cases.deinit();

    var errored: usize = 0;
    for (parsed_test_cases.value) |test_case| {
        test_case.run() catch {
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
    cycles: []const std.json.Value,

    pub fn run(t: TestCase) !void {
        var z80 = Z80.init(.{});
        t.initial.apply(&z80);

        z80.step();

        try t.final.check(z80);
        try std.testing.expectEqual(t.cycles.len, z80.clock.m);
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
    try runTestsFor("00");
}

test "0x01 ld bc, n16" {
    try runTestsFor("01");
}

test "0x02 ld [bc], a" {
    try runTestsFor("02");
}

test "0x03 inc bc" {
    try runTestsFor("03");
}

test "0x04 inc b" {
    try runTestsFor("04");
}

test "0x05 dec b" {
    try runTestsFor("05");
}

test "0x06 ld b, n8" {
    try runTestsFor("06");
}

test "0x07 rlca" {
    try runTestsFor("07");
}

test "0x08 ld [a16], sp" {
    try runTestsFor("08");
}

test "0x09 add hl, bc" {
    try runTestsFor("09");
}

test "0x0A ld a, [bc]" {
    try runTestsFor("0A");
}

test "0x0B dec bc" {
    try runTestsFor("0B");
}

test "0x0C inc c" {
    try runTestsFor("0C");
}

test "0x0D dec c" {
    try runTestsFor("0D");
}

test "0x0E ld c, n8" {
    try runTestsFor("0E");
}

test "0x0F rrca" {
    try runTestsFor("0F");
}

test "0x10 stop n8" {
    try runTestsFor("10");
}

test "0x11 ld de, n16" {
    try runTestsFor("11");
}

test "0x12 load [de], a" {
    try runTestsFor("12");
}

test "0x13 inc de" {
    try runTestsFor("13");
}

test "0x14 inc d" {
    try runTestsFor("14");
}

test "0x15 dec d" {
    try runTestsFor("15");
}

test "0x16 ld d, n8" {
    try runTestsFor("16");
}

test "0x17 rla" {
    try runTestsFor("17");
}

test "0x18 jr e8" {
    try runTestsFor("18");
}

test "0x19 add hl, de" {
    try runTestsFor("19");
}

test "0x1A ld a, [de]" {
    try runTestsFor("1A");
}

test "0x1B dec de" {
    try runTestsFor("1B");
}

test "0x1C inc e" {
    try runTestsFor("1C");
}

test "0x1D dec e" {
    try runTestsFor("1D");
}

test "0x1E ld e, n8" {
    try runTestsFor("1E");
}

test "0x1F rra" {
    try runTestsFor("1F");
}

test "0x20 jr nz, e8" {
    try runTestsFor("20");
}

test "0x21 ld hl, n16" {
    try runTestsFor("21");
}

test "0x22 load [hl+], a" {
    try runTestsFor("22");
}

test "0x23 inc hl" {
    try runTestsFor("23");
}

test "0x24 inc h" {
    try runTestsFor("24");
}

test "0x25 dec h" {
    try runTestsFor("25");
}

test "0x26 ld h, n8" {
    try runTestsFor("26");
}

test "0x27 daa" {
    try runTestsFor("27");
}

test "0x28 jr z, e8" {
    try runTestsFor("28");
}

test "0x29 add hl, hl" {
    try runTestsFor("29");
}

test "0x2A ld a, [hl+]" {
    try runTestsFor("2A");
}

test "0x2B dec hl" {
    try runTestsFor("2B");
}

test "0x2C inc l" {
    try runTestsFor("2C");
}

test "0x2D dec l" {
    try runTestsFor("2D");
}

test "0x2E ld l, n8" {
    try runTestsFor("2E");
}

test "0x2F cpl" {
    try runTestsFor("2F");
}

test "0x30 jr nz, e8" {
    try runTestsFor("30");
}

test "0x31 ld sp, n16" {
    try runTestsFor("31");
}

test "0x32 load [hl-], a" {
    try runTestsFor("32");
}

test "0x33 inc sp" {
    try runTestsFor("33");
}

test "0x34 inc [hl]" {
    try runTestsFor("34");
}

test "0x35 dec [hl]" {
    try runTestsFor("35");
}

test "0x36 ld [hl], n8" {
    try runTestsFor("36");
}

test "0x37 scf" {
    try runTestsFor("37");
}

test "0x38 jr c, e8" {
    try runTestsFor("38");
}

test "0x39 add hl, sp" {
    try runTestsFor("39");
}

test "0x3A ld a, [hl-]" {
    try runTestsFor("3A");
}

test "0x3B dec sp" {
    try runTestsFor("3B");
}

test "0x3C inc a" {
    try runTestsFor("3C");
}

test "0x3D dec a" {
    try runTestsFor("3D");
}

test "0x3E ld a, n8" {
    try runTestsFor("3E");
}

test "0x3F ccf" {
    try runTestsFor("3F");
}

test "0x40 ld b, b" {
    try runTestsFor("40");
}

test "0x41 ld b, c" {
    try runTestsFor("41");
}

test "0x42 ld b, d" {
    try runTestsFor("42");
}

test "0x43 ld b, e" {
    try runTestsFor("43");
}

test "0x44 ld b, h" {
    try runTestsFor("44");
}

test "0x45 ld b, l" {
    try runTestsFor("45");
}

test "0x46 ld b, [hl]" {
    try runTestsFor("46");
}

test "0x47 ld b, a" {
    try runTestsFor("47");
}

test "0x48 ld c, b" {
    try runTestsFor("48");
}

test "0x49 ld c, c" {
    try runTestsFor("49");
}

test "0x4A ld c, d" {
    try runTestsFor("4A");
}

test "0x4B ld c, e" {
    try runTestsFor("4B");
}

test "0x4C ld c, h" {
    try runTestsFor("4C");
}

test "0x4D ld c, l" {
    try runTestsFor("4D");
}

test "0x4E ld c, [hl]" {
    try runTestsFor("4E");
}

test "0x4F ld c, a" {
    try runTestsFor("4F");
}

test "0x50 ld d, b" {
    try runTestsFor("50");
}

test "0x51 ld d, c" {
    try runTestsFor("51");
}

test "0x52 ld d, d" {
    try runTestsFor("52");
}

test "0x53 ld d, e" {
    try runTestsFor("53");
}

test "0x54 ld d, h" {
    try runTestsFor("54");
}

test "0x55 ld d, l" {
    try runTestsFor("55");
}

test "0x56 ld d, [hl]" {
    try runTestsFor("56");
}

test "0x57 ld d, a" {
    try runTestsFor("57");
}

test "0x58 ld e, b" {
    try runTestsFor("58");
}

test "0x59 ld e, c" {
    try runTestsFor("59");
}

test "0x5A ld e, d" {
    try runTestsFor("5A");
}

test "0x5B ld e, e" {
    try runTestsFor("5B");
}

test "0x5C ld e, h" {
    try runTestsFor("5C");
}

test "0x5D ld e, l" {
    try runTestsFor("5D");
}

test "0x5E ld e, [hl]" {
    try runTestsFor("5E");
}

test "0x5F ld e, a" {
    try runTestsFor("5F");
}

test "0x60 ld h, b" {
    try runTestsFor("60");
}

test "0x61 ld h, c" {
    try runTestsFor("61");
}

test "0x62 ld h, d" {
    try runTestsFor("62");
}

test "0x63 ld h, e" {
    try runTestsFor("63");
}

test "0x64 ld h, h" {
    try runTestsFor("64");
}

test "0x65 ld h, l" {
    try runTestsFor("65");
}

test "0x66 ld h, [hl]" {
    try runTestsFor("66");
}

test "0x67 ld h, a" {
    try runTestsFor("67");
}

test "0x68 ld l, b" {
    try runTestsFor("68");
}

test "0x69 ld l, c" {
    try runTestsFor("69");
}

test "0x6A ld l, d" {
    try runTestsFor("6A");
}

test "0x6B ld l, e" {
    try runTestsFor("6B");
}

test "0x6C ld l, h" {
    try runTestsFor("6C");
}

test "0x6D ld l, l" {
    try runTestsFor("6D");
}

test "0x6E ld l, [hl]" {
    try runTestsFor("6E");
}

test "0x6F ld l, a" {
    try runTestsFor("6F");
}

test "0x70 ld [hl], b" {
    try runTestsFor("70");
}

test "0x71 ld [hl], c" {
    try runTestsFor("71");
}

test "0x72 ld [hl], d" {
    try runTestsFor("72");
}

test "0x73 ld [hl], e" {
    try runTestsFor("73");
}

test "0x74 ld [hl], h" {
    try runTestsFor("74");
}

test "0x75 ld [hl], l" {
    try runTestsFor("75");
}

test "0x76 halt" {
    try runTestsFor("76");
}

test "0x77 ld [hl], a" {
    try runTestsFor("77");
}

test "0x78 ld a, b" {
    try runTestsFor("78");
}

test "0x79 ld a, c" {
    try runTestsFor("79");
}

test "0x7A ld a, d" {
    try runTestsFor("7A");
}

test "0x7B ld a, e" {
    try runTestsFor("7B");
}

test "0x7C ld a, h" {
    try runTestsFor("7C");
}

test "0x7D ld a, l" {
    try runTestsFor("7D");
}

test "0x7E ld a, [hl]" {
    try runTestsFor("7E");
}

test "0x7F ld a, a" {
    try runTestsFor("7F");
}

test "0x80 add a, b" {
    try runTestsFor("80");
}

test "0x81 add a, c" {
    try runTestsFor("81");
}

test "0x82 add a, d" {
    try runTestsFor("82");
}

test "0x83 add a, e" {
    try runTestsFor("83");
}

test "0x84 add a, h" {
    try runTestsFor("84");
}

test "0x85 add a, l" {
    try runTestsFor("85");
}

test "0x86 add a, [hl]" {
    try runTestsFor("86");
}

test "0x87 add a, a" {
    try runTestsFor("87");
}

test "0x88 adc a, b" {
    try runTestsFor("88");
}

test "0x89 adc a, c" {
    try runTestsFor("89");
}

test "0x8A adc a, d" {
    try runTestsFor("8A");
}

test "0x8B adc a, e" {
    try runTestsFor("8B");
}

test "0x8C adc a, h" {
    try runTestsFor("8C");
}

test "0x8D adc a, l" {
    try runTestsFor("8D");
}

test "0x8E adc a, [hl]" {
    try runTestsFor("8E");
}

test "0x8F adc a, a" {
    try runTestsFor("8F");
}

test "0x90 sub a, b" {
    try runTestsFor("90");
}

test "0x91 sub a, c" {
    try runTestsFor("91");
}

test "0x92 sub a, d" {
    try runTestsFor("92");
}

test "0x93 sub a, e" {
    try runTestsFor("93");
}

test "0x94 sub a, h" {
    try runTestsFor("94");
}

test "0x95 sub a, l" {
    try runTestsFor("95");
}

test "0x96 sub a, [hl]" {
    try runTestsFor("96");
}

test "0x97 sub a, a" {
    try runTestsFor("97");
}

test "0x98 sbc a, b" {
    try runTestsFor("98");
}

test "0x99 sbc a, c" {
    try runTestsFor("99");
}

test "0x9A sbc a, d" {
    try runTestsFor("9A");
}

test "0x9B sbc a, e" {
    try runTestsFor("9B");
}

test "0x9C sbc a, h" {
    try runTestsFor("9C");
}

test "0x9D sbc a, l" {
    try runTestsFor("9D");
}

test "0x9E sbc a, [hl]" {
    try runTestsFor("9E");
}

test "0x9F sbc a, a" {
    try runTestsFor("9F");
}

test "0xA0 and a, b" {
    try runTestsFor("A0");
}

test "0xA1 and a, c" {
    try runTestsFor("A1");
}

test "0xA2 and a, d" {
    try runTestsFor("A2");
}

test "0xA3 and a, e" {
    try runTestsFor("A3");
}

test "0xA4 and a, h" {
    try runTestsFor("A4");
}

test "0xA5 and a, l" {
    try runTestsFor("A5");
}

test "0xA6 and a, [hl]" {
    try runTestsFor("A6");
}

test "0xA7 and a, a" {
    try runTestsFor("A7");
}

test "0xA8 xor a, b" {
    try runTestsFor("A8");
}

test "0xA9 xor a, c" {
    try runTestsFor("A9");
}

test "0xAA xor a, d" {
    try runTestsFor("AA");
}

test "0xAB xor a, e" {
    try runTestsFor("AB");
}

test "0xAC xor a, h" {
    try runTestsFor("AC");
}

test "0xAD xor a, l" {
    try runTestsFor("AD");
}

test "0xAE xor a, [hl]" {
    try runTestsFor("AE");
}

test "0xAF xor a, a" {
    try runTestsFor("AF");
}

test "0xB0 or a, b" {
    try runTestsFor("B0");
}

test "0xB1 or a, c" {
    try runTestsFor("B1");
}

test "0xB2 or a, d" {
    try runTestsFor("B2");
}

test "0xB3 or a, e" {
    try runTestsFor("B3");
}

test "0xB4 or a, h" {
    try runTestsFor("B4");
}

test "0xB5 or a, l" {
    try runTestsFor("B5");
}

test "0xB6 or a, [hl]" {
    try runTestsFor("B6");
}

test "0xB7 or a, a" {
    try runTestsFor("B7");
}

test "0xB8 cp a, b" {
    try runTestsFor("B8");
}

test "0xB9 cp a, c" {
    try runTestsFor("B9");
}

test "0xBA cp a, d" {
    try runTestsFor("BA");
}

test "0xBB cp a, e" {
    try runTestsFor("BB");
}

test "0xBC cp a, h" {
    try runTestsFor("BC");
}

test "0xBD cp a, l" {
    try runTestsFor("BD");
}

test "0xBE cp a, [hl]" {
    try runTestsFor("BE");
}

test "0xBF cp a, a" {
    try runTestsFor("BF");
}

test "0xC0 ret nz" {
    try runTestsFor("C0");
}

test "0xC1 pop bc" {
    try runTestsFor("C1");
}

test "0xC2 jp nz, a16" {
    try runTestsFor("C2");
}

test "0xC3 jp a16" {
    try runTestsFor("C3");
}

test "0xC4 call nz, a16" {
    try runTestsFor("C4");
}

test "0xC5 push bc" {
    try runTestsFor("C5");
}

test "0xC6 add a, n8" {
    try runTestsFor("C6");
}

test "0xC7 rst $00" {
    try runTestsFor("C7");
}

test "0xC8 ret z" {
    try runTestsFor("C8");
}

test "0xC9 ret" {
    try runTestsFor("C9");
}

test "0xCA jp z, a16" {
    try runTestsFor("CA");
}

// 0xCB prefix

test "0xCC call z, a16" {
    try runTestsFor("CA");
}

test "0xCD call a16" {
    try runTestsFor("CD");
}

test "0xCE adc a, n8" {
    try runTestsFor("CE");
}

test "0xCF rst $08" {
    try runTestsFor("CF");
}

test "0xD0 ret nc" {
    try runTestsFor("D0");
}

test "0xD1 pop de" {
    try runTestsFor("D1");
}

test "0xD2 jp nc, a16" {
    try runTestsFor("D2");
}

// 0xD3 undefined

test "0xD4 call nc, a16" {
    try runTestsFor("D4");
}

test "0xD5 push de" {
    try runTestsFor("D5");
}

test "0xD6 sub a, n8" {
    try runTestsFor("D6");
}

test "0xD7 rst $10" {
    try runTestsFor("D7");
}

test "0xD8 ret C" {
    try runTestsFor("D8");
}

test "0xD9 reti" {
    try runTestsFor("D9");
}

test "0xDA jp c, a16" {
    try runTestsFor("DA");
}

// 0xDB undefined

test "0xDC call c, a16" {
    try runTestsFor("DC");
}

// 0xDD undefined

test "0xDE sbc a, n8" {
    try runTestsFor("DE");
}

test "0xDF rst $18" {
    try runTestsFor("DF");
}

test "0xE0 ldh [a8], a" {
    try runTestsFor("E0");
}

test "0xE1 pop hl" {
    try runTestsFor("E1");
}

test "0xE2 ldh [c], a" {
    try runTestsFor("E2");
}

// 0xE3 undefined

// 0xE4 undefined

test "0xE5 push hl" {
    try runTestsFor("E5");
}

test "0xE6 and a, n8" {
    try runTestsFor("E6");
}

test "0xE7 rst $20" {
    try runTestsFor("E7");
}

test "0xE8 add sp, e8" {
    try runTestsFor("E8");
}

test "0xE9 jp, hl" {
    try runTestsFor("E9");
}

test "0xEA ld [a16], a" {
    try runTestsFor("EA");
}

// 0xEB undefined

// 0xEC undefined

// 0xED undefined

test "0xEE xor a, n8" {
    try runTestsFor("EE");
}

test "0xEF rst $28" {
    try runTestsFor("EF");
}

test "0xF0 ldh a, [a8]" {
    try runTestsFor("F0");
}

test "0xF1 pop af" {
    try runTestsFor("F1");
}

test "0xF2 ldh a, [c]" {
    try runTestsFor("F2");
}

test "0xF3 di" {
    try runTestsFor("F3");
}

// 0xF4 undefined

test "0xF5 push af" {
    try runTestsFor("F5");
}

test "0xF6 or a, n8" {
    try runTestsFor("F6");
}

test "0xF7 rst $30" {
    try runTestsFor("F7");
}

test "0xF8 ld hl, sp + e8" {
    try runTestsFor("F8");
}

test "0xF9 ld sp, hl" {
    try runTestsFor("F9");
}

test "0xFA ld a, [a16]" {
    try runTestsFor("FA");
}

test "0xFB ei" {
    try runTestsFor("FB");
}

// 0xFC undefined

// 0xFD undefined

test "0xFE cp a, n8" {
    try runTestsFor("FE");
}

test "0xFF rst $38" {
    try runTestsFor("FF");
}

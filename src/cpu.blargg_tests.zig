//! Run Blargg's CPU instruction tests.
//! https://github.com/retrio/gb-test-roms/tree/master/cpu_instrs

const std = @import("std");
const Cartridge = @import("cartridge.zig");
const Gameboy = @import("root.zig");

fn run(comptime filename: []const u8) !void {
    var output: [100:0]u8 = [_:0]u8{0} ** 100;
    var writer = std.io.Writer.fixed(&output);

    const romFile = @embedFile("blargg/" ++ filename ++ ".gb");
    var rom: [romFile.len]u8 = undefined;
    @memcpy(&rom, romFile);
    const cartridge = Cartridge.init(&rom);

    var gameboy = Gameboy.boot(cartridge);
    gameboy.cpu.mmu.serial_writer = &writer;

    const max_cycles = 100_000_000;
    var i: usize = 0;
    while (i < max_cycles) : (i += 1) {
        gameboy.step();

        if (i % 1000 != 0) continue;

        try writer.flush();

        if (std.mem.indexOf(u8, &output, "Failed") != null) {
            const out = @as([*:0]const u8, &output);
            std.debug.print("\n{s}\n", .{out});
            return error.Failed;
        }

        if (std.mem.indexOf(u8, &output, "Passed") != null) {
            return;
        }
    } else {
        return error.TimedOut;
    }
}

test "Special instructions" {
    try run("01-special");
}

test "Interrupts" {
    try run("02-interrupts");
}

test "Stack pointer operations" {
    try run("03-op sp,hl");
}

test "Immediate value operations" {
    try run("04-op r,imm");
}

test "16-bit register operations" {
    try run("05-op rp");
}

test "Load operations" {
    try run("06-ld r,r");
}

test "Jumps, call, return, and restart" {
    try run("07-jr,jp,call,ret,rst");
}

test "Miscellaneous" {
    try run("08-misc instrs");
}

test "8-bit register operations" {
    try run("09-op r,r");
}

test "Bit operations" {
    try run("10-bit ops");
}

test "[HL] operations" {
    try run("11-op a,(hl)");
}

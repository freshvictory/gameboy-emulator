const std = @import("std");
const Cartridge = @import("cartridge.zig");
const Gameboy = @import("root.zig");

extern fn print(clock: u8) void;

var gameboy: Gameboy = undefined;

export fn start() void {
    const romFile = @embedFile("blargg/03-op sp,hl.gb");
    var rom: [romFile.len]u8 = undefined;
    @memcpy(&rom, romFile);
    const cartridge = Cartridge.init(&rom);

    gameboy.boot(cartridge);
}

export fn step() void {
    gameboy.step();
    print(gameboy.timer.m);
}

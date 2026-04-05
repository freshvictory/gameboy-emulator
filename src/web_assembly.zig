const std = @import("std");
const Cartridge = @import("cartridge.zig");
const Gameboy = @import("root.zig");

extern fn print(clock: u8) void;

const MAX_CARTRIDGE_LENGTH = 8 * 1024 * 1024;
var cartridge_buffer: [MAX_CARTRIDGE_LENGTH]u8 = undefined;

export fn getCartridgeBufferPointer() [*]u8 {
    return &cartridge_buffer;
}

var gameboy: Gameboy = undefined;

export fn start(cartridge_length: u32) void {
    const cartridge = Cartridge.init(cartridge_buffer[0..cartridge_length]);
    gameboy.boot(cartridge);
}

export fn startWithTestCartridge() void {
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

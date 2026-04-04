const std = @import("std");
const Cartridge = @import("cartridge.zig");
const Timer = @import("timer.zig");
const MMU = @import("mmu.zig");
const CPU = @import("cpu.zig");

const Gameboy = @This();

cpu: CPU,

pub fn boot(cartridge: Cartridge) Gameboy {
    const mmu = MMU.init(cartridge);
    return .{ .cpu = CPU.init(mmu) };
}

pub fn step(gameboy: *Gameboy) void {
    gameboy.cpu.step();
}

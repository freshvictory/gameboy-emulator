const std = @import("std");
const Cartridge = @import("cartridge.zig");
const Timer = @import("timer.zig");
const Interrupts = @import("interrupts.zig");
const MMU = @import("mmu.zig");
const CPU = @import("cpu.zig");

const Gameboy = @This();

interrupts: Interrupts = .{},
timer: Timer,
mmu: MMU,
cpu: CPU,

pub fn boot(gameboy: *Gameboy, cartridge: Cartridge) void {
    gameboy.timer = Timer{ .interrupts = &gameboy.interrupts };
    gameboy.mmu = MMU.init(
        cartridge,
        &gameboy.timer,
        &gameboy.interrupts,
    );
    gameboy.cpu = CPU.init(
        .{ .ptr = gameboy, .tick_fn = tick },
        gameboy.mmu.memory(),
        &gameboy.interrupts,
    );
}

pub fn step(gameboy: *Gameboy) ?u8 {
    return gameboy.cpu.step();
}

fn tick(ptr: *anyopaque) void {
    const gameboy: *Gameboy = @ptrCast(@alignCast(ptr));
    gameboy.timer.tick();
}

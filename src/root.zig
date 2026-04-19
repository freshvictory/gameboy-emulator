const std = @import("std");
const Cartridge = @import("cartridge.zig");
const Timer = @import("timer.zig");
const Interrupts = @import("interrupts.zig");
const GPU = @import("gpu.zig");
const Lcd = GPU.Lcd;
const MMU = @import("mmu.zig");
const CPU = @import("cpu.zig");

const Gameboy = @This();

interrupts: Interrupts = .{},
timer: Timer,
gpu: GPU,
mmu: MMU,
cpu: CPU,

pub fn boot(gameboy: *Gameboy, cartridge: Cartridge, lcd: Lcd) void {
    gameboy.timer = Timer{ .interrupts = &gameboy.interrupts };
    gameboy.gpu = GPU{
        .lcd = lcd,
        .interrupts = &gameboy.interrupts,
    };
    gameboy.mmu = MMU.init(
        cartridge,
        &gameboy.timer,
        &gameboy.interrupts,
        &gameboy.gpu,
    );
    gameboy.cpu = CPU.init(
        .{ .ptr = gameboy, .tick_fn = tick },
        gameboy.mmu.memory(),
        &gameboy.interrupts,
    );
}

pub fn step(gameboy: *Gameboy) ?u8 {
    const opcode = gameboy.cpu.step();
    return opcode;
}

fn tick(ptr: *anyopaque) void {
    const gameboy: *Gameboy = @ptrCast(@alignCast(ptr));
    gameboy.timer.tick();
    // TODO: speed
    gameboy.gpu.tick(4);
}

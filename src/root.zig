const std = @import("std");
const Cartridge = @import("cartridge.zig");
const Timer = @import("timer.zig");
const Interrupts = @import("interrupts.zig");
const GPU = @import("gpu.zig");
const Lcd = GPU.Lcd;
const MMU = @import("mmu.zig");
const CPU = @import("cpu.zig");

const Gameboy = @This();

const cylces_per_scanline = 114;
const cycles_per_frame = 154 * cylces_per_scanline;

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

pub fn frame(gameboy: *Gameboy) void {
    var i: usize = 0;
    while (i < cycles_per_frame) {
        const pre_cycles: usize = gameboy.timer.m;
        _ = gameboy.cpu.step();

        const post_cycles: usize = gameboy.timer.m;
        const total_cycles = if (pre_cycles < post_cycles)
            post_cycles - pre_cycles
        else
            post_cycles + (256 - pre_cycles);

        i += total_cycles;
    }
}

pub fn scanline(gameboy: *Gameboy) void {
    const initial_scanline = gameboy.gpu.current_scanline;

    var i: usize = 0;
    while (i < cylces_per_scanline) {
        const pre_cycles: usize = gameboy.timer.m;
        _ = gameboy.cpu.step();

        if (gameboy.gpu.current_scanline != initial_scanline) {
            return;
        }

        const post_cycles: usize = gameboy.timer.m;
        const total_cycles = if (pre_cycles < post_cycles)
            post_cycles - pre_cycles
        else
            post_cycles + (256 - pre_cycles);

        i += total_cycles;
    }
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

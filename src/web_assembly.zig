const std = @import("std");
const Cartridge = @import("cartridge.zig");
const Gameboy = @import("root.zig");

const MAX_CARTRIDGE_LENGTH = 8 * 1024 * 1024;
var cartridge_buffer: [MAX_CARTRIDGE_LENGTH]u8 = undefined;

export fn getCartridgeBufferPointer() [*]u8 {
    return &cartridge_buffer;
}

var gameboy: Gameboy = undefined;

export fn start(cartridge_length: u32) void {
    const contents = cartridge_buffer[0..cartridge_length];
    const cartridge = Cartridge.init(contents);
    gameboy.boot(cartridge);
    updateDebugState();
}

export fn step() u8 {
    const opcode = gameboy.step();
    updateDebugState();

    return opcode orelse 0;
}

var debug_state: DebugState = undefined;

export fn getDebugStatePointer() *DebugState {
    return &debug_state;
}

fn updateDebugState() void {
    const control: u3 = @bitCast(gameboy.timer.control);
    debug_state = .{
        .a = gameboy.cpu.registers.a,
        .b = gameboy.cpu.registers.b,
        .c = gameboy.cpu.registers.c,
        .d = gameboy.cpu.registers.d,
        .e = gameboy.cpu.registers.e,
        .h = gameboy.cpu.registers.h,
        .l = gameboy.cpu.registers.l,
        .stack_pointer = gameboy.cpu.registers.stack_pointer,
        .program_counter = gameboy.cpu.program_counter,
        .flags = gameboy.cpu.flags.int(),
        .interrupt_master_enable = gameboy.cpu.interrupt_master_enable,
        .halted = gameboy.cpu.halted,
        .timer_m = gameboy.timer.m,
        .timer_divider = gameboy.timer.divider,
        .timer_counter = gameboy.timer.counter,
        .timer_reset_value = gameboy.timer.reset_value,
        .timer_control = control,
        .enabled_interrupts = gameboy.interrupts.enabled.int(),
        .active_interrupts = gameboy.interrupts.active.int(),
    };
}

const DebugState = extern struct {
    stack_pointer: u16, // 0
    program_counter: u16, // 2
    a: u8, // 4
    b: u8, // 5
    c: u8, // 6
    d: u8, // 7
    e: u8, // 8
    h: u8, // 9
    l: u8, // 10
    flags: u8, // 11
    timer_m: u8, // 12
    timer_divider: u8, // 13
    timer_counter: u8, // 14
    timer_reset_value: u8, // 15
    timer_control: u8, // 16
    enabled_interrupts: u8, // 17
    active_interrupts: u8, // 18
    halted: bool, // 19
    interrupt_master_enable: bool, // 20
};

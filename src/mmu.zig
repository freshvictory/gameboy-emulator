const std = @import("std");
const Cartridge = @import("cartridge.zig");
const Interrupts = @import("interrupts.zig");
const Memory = @import("memory.zig");
const Timer = @import("timer.zig");

const MMU = @This();

var null_writer = std.io.Writer.Discarding.init(&.{});

cartridge: Cartridge,
timer: *Timer,
interrupts: *Interrupts,
internal: [0x10000]u8 = [_]u8{0} ** 0x10000,

serial_writer: *std.io.Writer = &null_writer.writer,

pub fn init(
    cartridge: Cartridge,
    timer: *Timer,
    interrupts: *Interrupts,
) MMU {
    return .{
        .cartridge = cartridge,
        .timer = timer,
        .interrupts = interrupts,
    };
}

pub fn memory(mmu: *MMU) Memory {
    return .{
        .ptr = mmu,
        .vtable = &.{
            .readByte = readByte,
            .writeByte = writeByte,
        },
    };
}

fn readByte(ptr: *anyopaque, address: u16) u8 {
    const mmu: *MMU = @ptrCast(@alignCast(ptr));
    return switch (address) {
        // Cartridge/ROM
        0x0000...0x7FFF, 0xA000...0xBFFF => mmu.cartridge.readByte(address),

        // Timer
        0xFF04 => mmu.timer.divider,
        0xFF05 => mmu.timer.counter,
        0xFF06 => mmu.timer.reset_value,
        0xFF07 => control: {
            const value: u3 = @bitCast(mmu.timer.control);
            break :control value;
        },

        // Interrupts
        0xFF0F => mmu.interrupts.active.int(),
        0xFFFF => mmu.interrupts.enabled.int(),

        else => mmu.internal[address],
    };
}

fn writeByte(ptr: *anyopaque, address: u16, value: u8) void {
    const mmu: *MMU = @ptrCast(@alignCast(ptr));
    switch (address) {
        // Cartridge/ROM
        0x0000...0x7FFF, 0xA000...0xBFFF => mmu.cartridge.writeByte(address, value),

        // Serial
        0xFF01 => {
            mmu.serial_writer.printAsciiChar(value, .{}) catch {};
            mmu.internal[address] = value;
        },

        // Timer
        0xFF04 => mmu.timer.divider = 0x00,
        0xFF05 => mmu.timer.counter = value,
        0xFF06 => mmu.timer.reset_value = value,
        0xFF07 => {
            const v: u3 = @truncate(value);
            mmu.timer.control = @bitCast(v);
        },

        // Interrupts
        0xFF0F => mmu.interrupts.activate(value),
        0xFFFF => mmu.interrupts.enable(value),

        else => mmu.internal[address] = value,
    }
}

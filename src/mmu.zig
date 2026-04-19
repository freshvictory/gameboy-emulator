const std = @import("std");
const Cartridge = @import("cartridge.zig");
const Interrupts = @import("interrupts.zig");
const Memory = @import("memory.zig");
const Timer = @import("timer.zig");

const MMU = @This();

var null_writer = std.Io.Writer.Discarding.init(&.{});

cartridge: Cartridge,
timer: *Timer,
interrupts: *Interrupts,

video_ram: [8192]u8 = [_]u8{0} ** 8192,
video_ram_bank: u8 = 0,
video_ram_dma: [5]u8 = [_]u8{0} ** 5,

working_ram: [8192]u8 = [_]u8{0} ** 8192,
working_ram_bank: u8 = 0,

high_ram: [127]u8 = [_]u8{0} ** 127,

object_attribute_memory: [160]u8 = [_]u8{0} ** 160,

joypad: u8 = 0,
serial: [2]u8 = .{ 0, 0 },
audio: [23]u8 = [_]u8{0} ** 23,
wave_pattern: [16]u8 = [_]u8{0} ** 16,
lcd: [11]u8 = [_]u8{0} ** 11,
key_0: u8 = 0,
key_1: u8 = 0,
boot_mapping: u8 = 0,
infrared: u8 = 0,
color_palettes: [4]u8 = [_]u8{0} ** 4,
object_priorty_mode: u8 = 0,

serial_writer: *std.Io.Writer = &null_writer.writer,

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

        // Video RAM
        0x8000...0x9FFF => mmu.video_ram[address - 0x8000],
        0xFF4F => mmu.video_ram_bank,
        0xFF51...0xFF55 => mmu.video_ram_dma[address - 0xFF51],

        // Working RAM
        0xC000...0xDFFF => mmu.working_ram[address - 0xC000],
        0xFF70 => mmu.working_ram_bank,

        // Copy of working RAM
        0xE000...0xFDFF => mmu.working_ram[address - 0xE000],

        // Object attribute memory
        0xFE00...0xFE9F => mmu.object_attribute_memory[address - 0xFE00],

        // Unusable
        0xFEA0...0xFEFF => 0xFF,

        // Joypad
        0xFF00 => mmu.joypad,

        // Serial
        0xFF01 => mmu.serial[0],
        0xFF02 => mmu.serial[1],

        // Timer
        0xFF04 => mmu.timer.divider,
        0xFF05 => mmu.timer.counter,
        0xFF06 => mmu.timer.reset_value,
        0xFF07 => control: {
            const value: u3 = @bitCast(mmu.timer.control);
            break :control value;
        },

        // Audio
        0xFF10...0xFF26 => mmu.audio[address - 0xFF10],

        // Wave pattern
        0xFF30...0xFF3F => mmu.wave_pattern[address - 0xFF40],

        // LCD
        0xFF40...0xFF4B => mmu.lcd[address - 0xFF40],

        // Keys
        0xFF4C => mmu.key_0,
        0xFF4D => mmu.key_1,

        // Boot mapping
        0xFF50 => mmu.boot_mapping,

        // Infrared
        0xFF56 => mmu.infrared,

        // Color palettes
        0xFF68...0xFF6B => mmu.color_palettes[address - 0xFF68],

        // Object priority mode
        0xFF6C => mmu.object_priorty_mode,

        // High RAM
        0xFF80...0xFFFE => mmu.high_ram[address - 0xFF80],

        // Interrupts
        0xFF0F => mmu.interrupts.active.int(),
        0xFFFF => mmu.interrupts.enabled.int(),

        else => 0xFF,
    };
}

fn writeByte(ptr: *anyopaque, address: u16, value: u8) void {
    const mmu: *MMU = @ptrCast(@alignCast(ptr));
    switch (address) {
        // Cartridge/ROM
        0x0000...0x7FFF, 0xA000...0xBFFF => mmu.cartridge.writeByte(address, value),

        // Video RAM
        0x8000...0x9FFF => mmu.video_ram[address - 0x8000] = value,
        0xFF4F => mmu.video_ram_bank = value,
        0xFF51...0xFF55 => mmu.video_ram_dma[address - 0xFF51] = value,

        // Working RAM
        0xC000...0xDFFF => mmu.working_ram[address - 0xC000] = value,
        0xFF70 => mmu.working_ram_bank = value,

        // Copy of working RAM
        0xE000...0xFDFF => mmu.working_ram[address - 0xE000] = value,

        // Object attribute memory
        0xFE00...0xFE9F => mmu.object_attribute_memory[address - 0xFE00] = value,

        // Unusable
        0xFEA0...0xFEFF => {},

        // Joypad
        0xFF00 => mmu.joypad = value,

        // Serial
        0xFF01 => {
            mmu.serial_writer.printAsciiChar(value, .{}) catch {};
            mmu.serial[0] = value;
        },
        0xFF02 => mmu.serial[1] = value,

        // Timer
        0xFF04 => mmu.timer.divider = 0x00,
        0xFF05 => mmu.timer.counter = value,
        0xFF06 => mmu.timer.reset_value = value,
        0xFF07 => {
            const v: u3 = @truncate(value);
            mmu.timer.control = @bitCast(v);
        },

        // Audio
        0xFF10...0xFF26 => mmu.audio[address - 0xFF10] = value,

        // Wave pattern
        0xFF30...0xFF3F => mmu.wave_pattern[address - 0xFF40] = value,

        // LCD
        0xFF40...0xFF4B => mmu.lcd[address - 0xFF40] = value,

        // Keys
        0xFF4C => mmu.key_0 = value,
        0xFF4D => mmu.key_1 = value,

        // Boot mapping
        0xFF50 => mmu.boot_mapping = value,

        // Infrared
        0xFF56 => mmu.infrared = value,

        // Color palettes
        0xFF68...0xFF6B => mmu.color_palettes[address - 0xFF68] = value,

        // Object priority mode
        0xFF6C => mmu.object_priorty_mode = value,

        // High RAM
        0xFF80...0xFFFE => mmu.high_ram[address - 0xFF80] = value,

        // Interrupts
        0xFF0F => mmu.interrupts.activate(value),
        0xFFFF => mmu.interrupts.enable(value),

        else => {},
    }
}

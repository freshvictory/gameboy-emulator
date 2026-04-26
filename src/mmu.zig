const std = @import("std");
const Cartridge = @import("cartridge.zig");
const Interrupts = @import("interrupts.zig");
const Memory = @import("memory.zig");
const Timer = @import("timer.zig");
const GPU = @import("gpu.zig");

const MMU = @This();

var null_writer = std.Io.Writer.Discarding.init(&.{});

cartridge: Cartridge,
timer: *Timer,
interrupts: *Interrupts,
gpu: *GPU,

working_ram: [8192]u8 = [_]u8{0} ** 8192,

high_ram: [127]u8 = [_]u8{0} ** 127,

serial: [2]u8 = .{ 0, 0 },

serial_writer: *std.Io.Writer = &null_writer.writer,

pub fn init(
    cartridge: Cartridge,
    timer: *Timer,
    interrupts: *Interrupts,
    gpu: *GPU,
) MMU {
    return .{
        .cartridge = cartridge,
        .timer = timer,
        .interrupts = interrupts,
        .gpu = gpu,
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

        // Graphics
        0x8000...0x97FF => mmu.gpu.readTileData(address - 0x8000),
        0x9800...0x9BFF => mmu.gpu.tile_map_low[address - 0x9800],
        0x9C00...0x9FFF => mmu.gpu.tile_map_high[address - 0x9C00],

        0xFF40 => mmu.gpu.lcdControl().int(),
        0xFF41 => mmu.gpu.lcdStatus().int(),
        0xFF44 => mmu.gpu.current_scanline,
        0xFF45 => mmu.gpu.scanline_compare,

        0xFF47 => mmu.gpu.layer_palette.int(),
        0xFF48 => mmu.gpu.object_palette_0.int(),
        0xFF49 => mmu.gpu.object_palette_1.int(),

        0xFF42 => mmu.gpu.background.scroll_y,
        0xFF43 => mmu.gpu.background.scroll_x,
        0xFF4A => mmu.gpu.window.scroll_y,
        0xFF4B => mmu.gpu.window.scroll_x,

        // Working RAM
        0xC000...0xDFFF => mmu.working_ram[address - 0xC000],

        // Copy of working RAM
        0xE000...0xFDFF => mmu.working_ram[address - 0xE000],

        // Unusable
        0xFEA0...0xFEFF => 0xFF,

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

        // Graphics
        0x8000...0x97FF => mmu.gpu.writeTileData(address - 0x8000, value),
        0x9800...0x9BFF => mmu.gpu.tile_map_low[address - 0x9800] = value,
        0x9C00...0x9FFF => mmu.gpu.tile_map_high[address - 0x9C00] = value,
        0xFF40 => mmu.gpu.applyLcdControl(.from(value)),
        0xFF41 => mmu.gpu.applyLcdStatus(.from(value)),

        // gpu.current_scanline is read only
        0xFF44 => {},
        0xFF45 => mmu.gpu.scanline_compare = value,

        0xFF47 => mmu.gpu.layer_palette = .from(value),
        0xFF48 => mmu.gpu.object_palette_0 = .from(value),
        0xFF49 => mmu.gpu.object_palette_1 = .from(value),

        0xFF42 => mmu.gpu.background.scroll_y = value,
        0xFF43 => mmu.gpu.background.scroll_x = value,
        0xFF4A => mmu.gpu.window.scroll_y = value,
        0xFF4B => mmu.gpu.window.scroll_x = value,

        // Working RAM
        0xC000...0xDFFF => mmu.working_ram[address - 0xC000] = value,

        // Copy of working RAM
        0xE000...0xFDFF => mmu.working_ram[address - 0xE000] = value,

        // Unusable
        0xFEA0...0xFEFF => {},

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

        // High RAM
        0xFF80...0xFFFE => mmu.high_ram[address - 0xFF80] = value,

        // Interrupts
        0xFF0F => mmu.interrupts.activate(value),
        0xFFFF => mmu.interrupts.enable(value),

        else => {},
    }
}

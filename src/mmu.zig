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
        0x0000...0x7FFF => mmu.cartridge.readByte(address),
        0x8000...0x97FF => mmu.gpu.readTileData(address - 0x8000),
        0x9800...0x9BFF => mmu.gpu.tile_map_low[address - 0x9800],
        0x9C00...0x9FFF => mmu.gpu.tile_map_high[address - 0x9C00],
        0xA000...0xBFFF => mmu.cartridge.readByte(address),
        0xC000...0xDFFF => mmu.working_ram[address - 0xC000],
        0xE000...0xFDFF => mmu.working_ram[address - 0xE000],
        0xFEA0...0xFEFF => 0xFF, // Unusable
        0xFF80...0xFFFE => mmu.high_ram[address - 0xFF80],

        else => mapped: {
            const mapping: Mapping = @enumFromInt(address);

            break :mapped switch (mapping) {
                .lcd_control => mmu.gpu.lcdControl().int(),
                .lcd_status => mmu.gpu.lcdStatus().int(),
                .current_scanline => mmu.gpu.current_scanline,
                .scanline_compare => mmu.gpu.scanline_compare,
                .layer_palette => mmu.gpu.layer_palette.int(),
                .object_palette_0 => mmu.gpu.object_palette_0.int(),
                .object_palette_1 => mmu.gpu.object_palette_1.int(),
                .background_scroll_y => mmu.gpu.background.scroll_y,
                .background_scroll_x => mmu.gpu.background.scroll_x,
                .window_scroll_y => mmu.gpu.window.scroll_y,
                .window_scroll_x => mmu.gpu.window.scroll_x,

                .serial_data => 0x00,

                .timer_divider => mmu.timer.divider,
                .timer_counter => mmu.timer.counter,
                .timer_modulo => mmu.timer.reset_value,
                .timer_control => mmu.timer.control.int(),

                .interrupt_flag => mmu.interrupts.active.int(),
                .interrupt_enable => mmu.interrupts.enabled.int(),

                _ => 0xFF,
            };
        },
    };
}

fn writeByte(ptr: *anyopaque, address: u16, value: u8) void {
    const mmu: *MMU = @ptrCast(@alignCast(ptr));
    switch (address) {
        0x0000...0x7FFF => mmu.cartridge.writeByte(address, value),
        0x8000...0x97FF => mmu.gpu.writeTileData(address - 0x8000, value),
        0x9800...0x9BFF => mmu.gpu.tile_map_low[address - 0x9800] = value,
        0x9C00...0x9FFF => mmu.gpu.tile_map_high[address - 0x9C00] = value,
        0xA000...0xBFFF => mmu.cartridge.writeByte(address, value),
        0xC000...0xDFFF => mmu.working_ram[address - 0xC000] = value,
        0xE000...0xFDFF => mmu.working_ram[address - 0xE000] = value,
        0xFEA0...0xFEFF => {}, // Unusable
        0xFF80...0xFFFE => mmu.high_ram[address - 0xFF80] = value,

        else => {
            const mapping: Mapping = @enumFromInt(address);

            switch (mapping) {
                .lcd_control => mmu.gpu.applyLcdControl(.from(value)),
                .lcd_status => mmu.gpu.applyLcdStatus(.from(value)),
                .current_scanline => {}, // current_scanline is read only
                .scanline_compare => mmu.gpu.scanline_compare = value,
                .layer_palette => mmu.gpu.layer_palette = .from(value),
                .object_palette_0 => mmu.gpu.object_palette_0 = .from(value),
                .object_palette_1 => mmu.gpu.object_palette_1 = .from(value),
                .background_scroll_y => mmu.gpu.background.scroll_y = value,
                .background_scroll_x => mmu.gpu.background.scroll_x = value,
                .window_scroll_y => mmu.gpu.window.scroll_y = value,
                .window_scroll_x => mmu.gpu.window.scroll_x = value,

                .serial_data => mmu.serial_writer.printAsciiChar(value, .{}) catch {},

                .timer_divider => mmu.timer.divider = 0x00,
                .timer_counter => mmu.timer.counter = value,
                .timer_modulo => mmu.timer.reset_value = value,
                .timer_control => mmu.timer.control = .from(@truncate(value)),

                .interrupt_flag => mmu.interrupts.activate(value),
                .interrupt_enable => mmu.interrupts.enable(value),

                _ => {},
            }
        },
    }
}

pub const Mapping = enum(u16) {
    /// P1/JOYP
    // joypad = 0xFF00,
    /// SB
    serial_data = 0xFF01,
    /// SC
    // serial_control = 0xFF02,
    /// DIV
    timer_divider = 0xFF04,
    /// TIMA
    timer_counter = 0xFF05,
    /// TMA
    timer_modulo = 0xFF06,
    /// TAC
    timer_control = 0xFF07,
    /// LCDC
    lcd_control = 0xFF40,
    /// STAT
    lcd_status = 0xFF41,
    /// SCY
    background_scroll_y = 0xFF42,
    /// SCX
    background_scroll_x = 0xFF43,
    /// LY
    current_scanline = 0xFF44,
    /// LYC
    scanline_compare = 0xFF45,
    /// DMA
    // dma_transfer = 0xFF46,
    /// BGP
    layer_palette = 0xFF47,
    /// OBP0
    object_palette_0 = 0xFF48,
    /// OBP1
    object_palette_1 = 0xFF49,
    /// WY
    window_scroll_y = 0xFF4A,
    /// WX
    window_scroll_x = 0xFF4B,
    /// IF
    interrupt_flag = 0xFF0F,
    /// IE
    interrupt_enable = 0xFFFF,

    _,
};

const std = @import("std");
const Cartridge = @import("cartridge.zig");
const Lcd = @import("gpu.zig").Lcd;
const MonoColor = @import("gpu.zig").MonoColor;
const Gameboy = @import("root.zig");

const frame_buffer_size = 160 * 144 * 4;

var frame_buffer: [frame_buffer_size]u8 = [_]u8{0} ** frame_buffer_size;

export fn getFramePointer() *[frame_buffer_size]u8 {
    return &frame_buffer;
}

const CanvasLcd = struct {
    pub fn lcd(self: *CanvasLcd) Lcd {
        return .{
            .ptr = self,
            .draw = draw,
        };
    }

    pub fn draw(ptr: *anyopaque, row: u8, pixels: [160]MonoColor) void {
        _ = ptr;
        const row_16: u16 = row;
        const row_offset: u16 = 160 * 4 * row_16;
        for (pixels, 0..) |pixel, i| {
            const color: u8 = switch (pixel) {
                .black => 255,
                .dark_gray => 170,
                .light_gray => 85,
                .white => 0,
            };

            const offset = row_offset + i * 4;
            frame_buffer[offset] = 0;
            frame_buffer[offset + 1] = 0;
            frame_buffer[offset + 2] = 0;
            frame_buffer[offset + 3] = color;
        }
    }
};

const MAX_CARTRIDGE_LENGTH = 8 * 1024 * 1024;
var cartridge_buffer: [MAX_CARTRIDGE_LENGTH]u8 = undefined;

export fn getCartridgeBufferPointer() [*]u8 {
    return &cartridge_buffer;
}

var gameboy: Gameboy = undefined;

export fn start(cartridge_length: u32) void {
    const contents = cartridge_buffer[0..cartridge_length];
    const cartridge = Cartridge.init(contents);
    var canvas_lcd = CanvasLcd{};
    gameboy.boot(cartridge, canvas_lcd.lcd());
    updateDebugState();
}

export fn step() u8 {
    const opcode = gameboy.step();
    updateDebugState();

    return opcode orelse 0;
}

export fn frame() void {
    gameboy.frame();
}

export fn scanline() void {
    gameboy.scanline();
    updateDebugState();
}

const layer_size = 256 * 256 * 4;

var background_pixels: [layer_size]u8 = [_]u8{0} ** layer_size;

export fn getBackgroundPixelsPointer() *[layer_size]u8 {
    return &background_pixels;
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
        // .interrupt_master_enable = gameboy.cpu.interrupt_master_enable,
        // .halted = gameboy.cpu.halted,
        .timer_m = gameboy.timer.m,
        .timer_divider = gameboy.timer.divider,
        .timer_counter = gameboy.timer.counter,
        .timer_reset_value = gameboy.timer.reset_value,
        .timer_control = control,
        .enabled_interrupts = gameboy.interrupts.enabled.int(),
        .active_interrupts = gameboy.interrupts.active.int(),
        .gpu_mode = @intFromEnum(gameboy.gpu.mode),
        .current_scanline = gameboy.gpu.current_scanline,
        .dots = gameboy.gpu.dots,
        .background_scroll_x = gameboy.gpu.background.scroll_x,
        .background_scroll_y = gameboy.gpu.background.scroll_y,
    };

    const background = gameboy.gpu.layerPixels(gameboy.gpu.background);

    for (background, 0..) |row, i| {
        const row_offset = 256 * 4 * i;
        for (row, 0..) |pixel, j| {
            const color: u8 = switch (pixel) {
                .black => 255,
                .dark_gray => 170,
                .light_gray => 85,
                .white => 0,
            };

            const offset = row_offset + j * 4;
            background_pixels[offset] = 0;
            background_pixels[offset + 1] = 0;
            background_pixels[offset + 2] = 0;
            background_pixels[offset + 3] = color;
        }
    }
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
    // halted: bool, // 19
    // interrupt_master_enable: bool, // 20
    gpu_mode: u8, // 19
    current_scanline: u8, // 20
    dots: u32, // 21
    background_scroll_x: u8, // 25
    background_scroll_y: u8, // 26
};

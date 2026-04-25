const std = @import("std");
const Cartridge = @import("cartridge.zig");
const Lcd = @import("gpu.zig").Lcd;
const GPU = @import("gpu.zig");
const MonoColor = GPU.MonoColor;
const Gameboy = @import("root.zig");

const frame_buffer_size = GPU.screen_width * GPU.screen_height * 4;

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

    pub fn draw(ptr: *anyopaque, row: u8, pixels: [GPU.screen_width]MonoColor) void {
        _ = ptr;
        const row_32: u32 = row;
        const row_offset: u32 = GPU.screen_width * 4 * row_32;
        for (pixels, 0..) |pixel, i| {
            const offset = row_offset + i * 4 + 3;
            frame_buffer[offset] = pixel.opacity();
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
}

const layer_size = 256 * 256 * 4;

var background_pixels: [layer_size]u8 = [_]u8{0} ** layer_size;

export fn getBackgroundPixelsPointer() *[layer_size]u8 {
    return &background_pixels;
}

var debug_state: DebugState = .{};

export fn getDebugStatePointer() *DebugState {
    return &debug_state;
}

export fn updateDebugState() void {
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
    };
    updateGpuDebug();
}

export fn updateGpuDebug() void {
    const background = gameboy.gpu.layerPixels(gameboy.gpu.background);

    for (background, 0..) |row, i| {
        const row_offset = 256 * 4 * i;
        for (row, 0..) |pixel, j| {
            const offset = row_offset + j * 4 + 3;
            background_pixels[offset] = pixel.opacity();
        }
    }

    debug_state.gpu_mode = @intFromEnum(gameboy.gpu.mode);
    debug_state.current_scanline = gameboy.gpu.current_scanline;
    debug_state.dots = gameboy.gpu.dots;
    debug_state.background_scroll_x = gameboy.gpu.background.scroll_x;
    debug_state.background_scroll_y = gameboy.gpu.background.scroll_y;
}

const DebugState = extern struct {
    stack_pointer: u16 = 0, // 0
    program_counter: u16 = 0, // 2
    dots: u16 = 0, // 4
    a: u8 = 0, // 6
    b: u8 = 0, // 7
    c: u8 = 0, // 8
    d: u8 = 0, // 9
    e: u8 = 0, // 10
    h: u8 = 0, // 11
    l: u8 = 0, // 12
    flags: u8 = 0, // 13
    timer_m: u8 = 0, // 14
    timer_divider: u8 = 0, // 15
    timer_counter: u8 = 0, // 16
    timer_reset_value: u8 = 0, // 17
    timer_control: u8 = 0, // 18
    enabled_interrupts: u8 = 0, // 19
    active_interrupts: u8 = 0, // 20
    gpu_mode: u8 = 0, // 21
    current_scanline: u8 = 0, // 22
    background_scroll_x: u8 = 0, // 23
    background_scroll_y: u8 = 0, // 24
};

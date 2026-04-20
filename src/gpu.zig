const std = @import("std");
const Interrupts = @import("interrupts.zig");
const Tile = @import("tile.zig");
const Speed = @import("cpu.zig").Speed;

const GPU = @This();

const screen_height = 144;
const screen_width = 160;
const vertical_blank_lines = 10;

lcd: Lcd = .{ .ptr = undefined, .draw = discardDraw },
interrupts: *Interrupts,

mode: GpuMode = .finding_objects,
dots: usize = 0,

/// LY, y coordinate. 144-153 is vblank.
current_scanline: u8 = 0,

/// LYC. When this matches current_scanline,
/// set the status flag and possibly the STAT
/// interrupt.
scanline_compare: u8 = 0,

/// BGP. Color palette for background and window.
layer_palette: MonoPalette = .{},

/// OBP0, OBP1
object_palette_0: MonoPalette = .{},
object_palette_1: MonoPalette = .{},

background: Layer = .{},
window: Layer = .{},
objects_enabled: bool = false,
object_height: ObjectHeight = .one_tile,

tiles: [384]Tile = [_]Tile{.{}} ** 384,
tile_addressing_mode: TileAddressingMode = .unsigned,

tile_map_low: [1024]u8 = [_]u8{0} ** 1024,
tile_map_high: [1024]u8 = [_]u8{0} ** 1024,

stat_interrupt_mode_0: bool = false,
stat_interrupt_mode_1: bool = false,
stat_interrupt_mode_2: bool = false,
stat_interrupt_lyc: bool = false,

pub const Lcd = struct {
    enabled: bool = true,

    ptr: *anyopaque,
    draw: *const fn (*anyopaque, row: u8, pixels: [160]MonoColor) void,

    pub fn drawScanline(self: *Lcd, row: u8, pixels: [160]MonoColor) void {
        self.draw(self.ptr, row, pixels);
    }
};

const GpuMode = enum(u2) {
    horizontal_blank = 0,
    vertical_blank = 1,
    drawing = 2,
    finding_objects = 3,
};

pub fn tick(gpu: *GPU, dots: usize) void {
    if (!gpu.lcd.enabled) return;

    gpu.dots += dots;

    switch (gpu.mode) {
        .finding_objects => gpu.findObjects(),
        .drawing => gpu.draw(),
        .horizontal_blank => gpu.horizontalBlank(),
        .vertical_blank => gpu.verticalBlank(),
    }
}

fn findObjects(gpu: *GPU) void {
    if (gpu.dots < 80) return;

    gpu.mode = .drawing;
}

fn draw(gpu: *GPU) void {
    if (gpu.dots < 80 + 172) return;

    gpu.drawCurrentScanline();
    gpu.handleLcdInterrupt();

    gpu.mode = .horizontal_blank;
}

fn horizontalBlank(gpu: *GPU) void {
    if (gpu.dots < 456) return;

    gpu.current_scanline += 1;
    gpu.handleLcdInterrupt();

    if (gpu.current_scanline == screen_height) {
        gpu.interrupts.raise(.v_blank);
        gpu.mode = .vertical_blank;
    } else {
        gpu.mode = .finding_objects;
    }

    gpu.dots = 0;
}

fn verticalBlank(gpu: *GPU) void {
    if (gpu.dots < 456) return;

    gpu.current_scanline += 1;
    gpu.handleLcdInterrupt();

    if (gpu.atEndOfFrame()) gpu.resetFrame();
}

fn handleLcdInterrupt(gpu: GPU) void {
    if (gpu.current_scanline == gpu.scanline_compare) {
        gpu.interrupts.raise(.lcd);
    }
}

fn atEndOfFrame(gpu: GPU) bool {
    return gpu.current_scanline == screen_height + vertical_blank_lines;
}

fn resetFrame(gpu: *GPU) void {
    gpu.current_scanline = 0;
    gpu.dots = 0;
    gpu.mode = .finding_objects;
}

const ObjectHeight = enum(u1) {
    one_tile = 0,
    two_tiles = 1,
};

const TileAddressingMode = enum(u1) {
    signed = 0,
    unsigned = 1,
};

const LcdControl = packed struct(u8) {
    background_enabled: bool = false,
    objects_enabled: bool = false,
    object_height: ObjectHeight = .one_tile,
    background_tile_map_area: TileMapArea = .low,
    tile_addressing_mode: TileAddressingMode = .signed,
    window_enabled: bool = false,
    window_tile_map_area: TileMapArea = .low,
    lcd_enabled: bool = false,

    pub fn from(value: u8) LcdControl {
        return @bitCast(value);
    }

    pub fn int(self: LcdControl) u8 {
        return @bitCast(self);
    }
};

pub fn lcdControl(gpu: GPU) LcdControl {
    return .{
        .lcd_enabled = gpu.lcd.enabled,
        .objects_enabled = gpu.objects_enabled,
        .object_height = gpu.object_height,
        .background_enabled = gpu.background.enabled,
        .background_tile_map_area = gpu.background.tile_map_area,
        .window_enabled = gpu.window.enabled,
        .window_tile_map_area = gpu.window.tile_map_area,
        .tile_addressing_mode = gpu.tile_addressing_mode,
    };
}

pub fn applyLcdControl(gpu: *GPU, control: LcdControl) void {
    gpu.lcd.enabled = control.lcd_enabled;

    gpu.background.enabled = control.background_enabled;
    gpu.background.tile_map_area = control.background_tile_map_area;

    gpu.window.enabled = control.window_enabled;
    gpu.window.tile_map_area = control.window_tile_map_area;

    gpu.objects_enabled = control.objects_enabled;
    gpu.object_height = control.object_height;

    gpu.tile_addressing_mode = control.tile_addressing_mode;
}

const LcdStatus = packed struct(u7) {
    gpu_mode: GpuMode,

    y_matches_ycompare: bool,

    /// Not sure what these do
    mode_0: bool,
    mode_1: bool,
    mode_2: bool,
    lyc: bool,

    pub fn from(value: u8) LcdStatus {
        const v: u7 = @truncate(value);
        return @bitCast(v);
    }

    pub fn int(self: LcdStatus) u8 {
        const v: u7 = @bitCast(self);
        return @intCast(v);
    }
};

pub fn lcdStatus(gpu: GPU) LcdStatus {
    return .{
        .gpu_mode = if (gpu.lcd.enabled) gpu.mode else @enumFromInt(0),
        .y_matches_ycompare = gpu.current_scanline == gpu.scanline_compare,

        .mode_0 = gpu.stat_interrupt_mode_0,
        .mode_1 = gpu.stat_interrupt_mode_1,
        .mode_2 = gpu.stat_interrupt_mode_2,
        .lyc = gpu.stat_interrupt_lyc,
    };
}

pub fn applyLcdStatus(gpu: *GPU, status: LcdStatus) void {
    // GPU mode is read-only
    // gpu.mode = status.gpu_mode;

    // LYC is read-only

    gpu.stat_interrupt_mode_0 = status.mode_0;
    gpu.stat_interrupt_mode_1 = status.mode_1;
    gpu.stat_interrupt_mode_2 = status.mode_2;
    gpu.stat_interrupt_lyc = status.lyc;
}

fn drawCurrentScanline(gpu: *GPU) void {
    const pixels = gpu.scanlinePixels();

    gpu.lcd.drawScanline(gpu.current_scanline, pixels);
}

fn scanlinePixels(gpu: *GPU) [160]MonoColor {
    const layer = gpu.background;

    const layer_pixels = gpu.layerPixels(layer);
    const row = gpu.current_scanline +% layer.scroll_y;
    const column = layer.scroll_x;

    const start_x = if (column +% screen_width < column)
        column +% screen_width
    else
        column;

    var scanline: [160]MonoColor = undefined;
    @memcpy(&scanline, layer_pixels[row][start_x .. start_x + screen_width]);

    return scanline;
}

const TileMapArea = enum(u1) {
    low = 0,
    high = 1,
};

fn tileMap(gpu: *GPU, area: TileMapArea) *[1024]u8 {
    return switch (area) {
        .low => &gpu.tile_map_low,
        .high => &gpu.tile_map_high,
    };
}

const Layer = struct {
    enabled: bool = false,

    scroll_x: u8 = 0,
    scroll_y: u8 = 0,

    tile_map_area: TileMapArea = .low,
};

fn layerPixels(gpu: *GPU, layer: Layer) [256][256]MonoColor {
    var pixels: [256][256]MonoColor = undefined;

    const tile_map = gpu.tileMap(layer.tile_map_area);

    var tiles: [32][32]Tile = undefined;
    for (0..32) |row| {
        for (0..32) |column| {
            const index = row + column;
            const tile_id = tile_map[index];
            const tile = gpu.readLayerTile(tile_id);
            tiles[row][column] = tile;
        }
    }

    for (tiles, 0..) |tile_row, row| {
        const row_start = row * 8;
        for (tile_row, 0..) |tile, column| {
            const column_start = column * 8;
            for (tile.pixels, 0..) |pixel_row, i| {
                for (pixel_row, 0..) |pixel, j| {
                    const color = gpu.layer_palette.colorOf(pixel);
                    pixels[row_start + i][column_start + j] = color;
                }
            }
        }
    }

    return pixels;
}

test layerPixels {
    const tile = Tile{
        .pixels = [8][8]u2{
            .{ 0b00, 0b10, 0b11, 0b11, 0b11, 0b11, 0b10, 0b00 },
            .{ 0b00, 0b11, 0b00, 0b00, 0b00, 0b00, 0b11, 0b00 },
            .{ 0b00, 0b11, 0b00, 0b00, 0b00, 0b00, 0b11, 0b00 },
            .{ 0b00, 0b11, 0b00, 0b00, 0b00, 0b00, 0b11, 0b00 },
            .{ 0b00, 0b11, 0b01, 0b11, 0b11, 0b11, 0b11, 0b00 },
            .{ 0b00, 0b01, 0b01, 0b01, 0b11, 0b01, 0b11, 0b00 },
            .{ 0b00, 0b11, 0b01, 0b11, 0b01, 0b11, 0b10, 0b00 },
            .{ 0b00, 0b10, 0b11, 0b11, 0b11, 0b10, 0b00, 0b00 },
        },
    };

    var interrupts = Interrupts{};

    var gpu = GPU{
        .interrupts = &interrupts,
        .tiles = [_]Tile{tile} ** 384,
        .tile_map_low = [_]u8{0} ** 1024,
        .background = .{
            .enabled = true,
            .tile_map_area = .low,
        },
    };

    const pixels = gpu.layerPixels(gpu.background);

    try std.testing.expectEqualSlices(
        u2,
        &[8]u2{ 0b00, 0b10, 0b11, 0b11, 0b11, 0b11, 0b10, 0b00 },
        pixels[0][0..8],
    );

    try std.testing.expectEqualSlices(
        u2,
        &[8]u2{ 0b00, 0b11, 0b00, 0b00, 0b00, 0b00, 0b11, 0b00 },
        pixels[1][0..8],
    );
}

pub fn readTileData(gpu: GPU, address: u16) u8 {
    const tile_id = address / 16;
    const tile = gpu.tiles[tile_id];

    return tile.serialize()[address % 16];
}

pub fn writeTileData(gpu: *GPU, address: u16, value: u8) void {
    const tile_id = address / 16;
    const tile = gpu.tiles[tile_id];
    var data = tile.serialize();
    data[address % 16] = value;
    const new_tile = Tile.deserialize(&data);
    gpu.tiles[tile_id] = new_tile;
}

test "read and write tile data" {
    var interrupts = Interrupts{};
    var gpu = GPU{ .interrupts = &interrupts };

    const tile_id: u16 = 10;
    const address: u16 = tile_id * 16;

    const data: [16]u8 = .{ 0x3C, 0x7E, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x7E, 0x5E, 0x7E, 0x0A, 0x7C, 0x56, 0x38, 0x7C };

    for (data, 0..) |byte, i| {
        const location: u16 = @intCast(address + i);
        gpu.writeTileData(location, byte);
    }

    const tile = gpu.tiles[tile_id];

    try std.testing.expectEqual(
        [8][8]u2{
            .{ 0b00, 0b10, 0b11, 0b11, 0b11, 0b11, 0b10, 0b00 },
            .{ 0b00, 0b11, 0b00, 0b00, 0b00, 0b00, 0b11, 0b00 },
            .{ 0b00, 0b11, 0b00, 0b00, 0b00, 0b00, 0b11, 0b00 },
            .{ 0b00, 0b11, 0b00, 0b00, 0b00, 0b00, 0b11, 0b00 },
            .{ 0b00, 0b11, 0b01, 0b11, 0b11, 0b11, 0b11, 0b00 },
            .{ 0b00, 0b01, 0b01, 0b01, 0b11, 0b01, 0b11, 0b00 },
            .{ 0b00, 0b11, 0b01, 0b11, 0b01, 0b11, 0b10, 0b00 },
            .{ 0b00, 0b10, 0b11, 0b11, 0b11, 0b10, 0b00, 0b00 },
        },
        tile.pixels,
    );

    const value = gpu.readTileData(address + 10);

    try std.testing.expectEqual(data[10], value);
}

fn readLayerTile(gpu: GPU, id: u8) Tile {
    var address: u12 = id;
    if (gpu.tile_addressing_mode == .signed and address < 128) {
        address += 128;
    }
    return gpu.tiles[address];
}

const ObjectAttributes = packed struct(u32) {
    /// Y position on the screen with a 16px margin
    y: u8,

    /// X position on the screen with an 8px margin
    x: u8,

    /// If in 8x16 mode, where object height is
    /// two tiles, this is the id of the first
    /// and the second is the one directly
    /// afterwards.
    tile_id: u8,

    // Flags

    /// Only for GameBoy Color
    color_palette: u3 = 0,

    video_ram_bank: u1 = 0,

    /// Only for original GameBoy
    mono_palette: u1 = 0,

    flip_x: bool = false,
    flip_y: bool = false,

    priority: Priority = .high,

    pub const Priority = enum(u1) {
        /// Draw this object over the background and window
        high = 0,

        /// Draw background and window over this object
        /// if their color is 1-3
        low = 1,
    };
};

fn discardDraw(ptr: *anyopaque, row: u8, pixels: [160]MonoColor) void {
    _ = ptr;
    _ = row;
    _ = pixels;
}

pub const MonoColor = enum(u2) {
    white = 0,
    light_gray = 1,
    dark_gray = 2,
    black = 3,
};

const MonoPalette = packed struct(u8) {
    color_0: MonoColor = .white,
    color_1: MonoColor = .light_gray,
    color_2: MonoColor = .dark_gray,
    color_3: MonoColor = .black,

    pub fn colorOf(self: MonoPalette, color_id: u2) MonoColor {
        return switch (color_id) {
            0 => self.color_0,
            1 => self.color_1,
            2 => self.color_2,
            3 => self.color_3,
        };
    }

    pub fn from(value: u8) MonoPalette {
        return @bitCast(value);
    }

    pub fn int(self: MonoPalette) u8 {
        return @bitCast(self);
    }
};

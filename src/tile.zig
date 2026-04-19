const std = @import("std");

const Tile = @This();

pixels: [8][8]u2 = [_][8]u2{[_]u2{0} ** 8} ** 8,

/// Each row is two bytes. The first byte
/// is each lower bit of each pixel, and the second
/// is each higher bit.
/// https://gbdev.io/pandocs/Tile_Data.html#data-format
pub fn deserialize(data: []const u8) Tile {
    var pixels: [8][8]u2 = undefined;

    var i: usize = 0;
    while (i < data.len) : (i += 2) {
        const row = i / 2;

        const low_bits = data[i];
        const high_bits = data[i + 1];

        pixels[row] = undefined;

        inline for (0..8) |b| {
            const bit = 1 << (7 - b);
            const low_bit: u2 = @truncate((low_bits & bit) >> (7 - b));
            const high_bit: u2 = @truncate((high_bits & bit) >> (7 - b));
            pixels[row][b] = (high_bit << 1) | low_bit;
        }
    }

    return .{ .pixels = pixels };
}

pub fn serialize(tile: Tile) [16]u8 {
    var data: [16]u8 = undefined;

    inline for (tile.pixels, 0..) |line, row| {
        var low_byte: u8 = 0;
        var high_byte: u8 = 0;
        inline for (line, 0..) |pixel, column| {
            const bit_position = (7 - column);

            if (pixel & 0b01 != 0) {
                low_byte |= (1 << bit_position);
            }

            if (pixel & 0b10 != 0) {
                high_byte |= (1 << bit_position);
            }
        }

        data[row * 2] = low_byte;
        data[row * 2 + 1] = high_byte;
    }

    return data;
}

test deserialize {
    const data: [16]u8 = .{ 0x3C, 0x7E, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x7E, 0x5E, 0x7E, 0x0A, 0x7C, 0x56, 0x38, 0x7C };

    const tile = Tile.deserialize(&data);

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
}

test serialize {
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

    try std.testing.expectEqual(
        .{ 0x3C, 0x7E, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x7E, 0x5E, 0x7E, 0x0A, 0x7C, 0x56, 0x38, 0x7C },
        tile.serialize(),
    );
}

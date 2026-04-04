const std = @import("std");
const Cartridge = @import("cartridge.zig");
const MMU = @This();

cartridge: Cartridge,
internal: [0x10000]u8 = [_]u8{0} ** 0x10000,

serial_writer: ?*std.io.Writer = null,

pub fn init(cartridge: Cartridge) MMU {
    return .{ .cartridge = cartridge };
}

pub fn initWithWriter(cartridge: Cartridge, writer: *std.io.Writer) MMU {
    return .{
        .cartridge = cartridge,
        .serial_writer = writer,
    };
}

pub fn readByte(mmu: MMU, address: u16) u8 {
    return switch (address) {
        0x0000...0x7FFF, 0xA000...0xBFFF => mmu.cartridge.readByte(address),
        else => mmu.internal[address],
    };
}

pub fn writeByte(mmu: *MMU, address: u16, value: u8) void {
    switch (address) {
        0x0000...0x7FFF, 0xA000...0xBFFF => mmu.cartridge.writeByte(address, value),
        0xFF01 => {
            if (mmu.serial_writer) |writer| {
                writer.printAsciiChar(value, .{}) catch {};
            }
            mmu.internal[address] = value;
        },
        else => mmu.internal[address] = value,
    }
}

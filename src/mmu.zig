const std = @import("std");
const Cartridge = @import("cartridge.zig");
const MMU = @This();

var null_writer = std.io.Writer.Discarding.init(&.{});

cartridge: Cartridge,
set_interrupts: Interrupts = .{},
enabled_interrupts: Interrupts = .{},
internal: [0x10000]u8 = [_]u8{0} ** 0x10000,

serial_writer: *std.io.Writer = &null_writer.writer,

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
        0xFF0F => mmu.set_interrupts.int(),
        0xFFFF => mmu.enabled_interrupts.int(),
        else => mmu.internal[address],
    };
}

pub fn writeByte(mmu: *MMU, address: u16, value: u8) void {
    switch (address) {
        0x0000...0x7FFF, 0xA000...0xBFFF => mmu.cartridge.writeByte(address, value),
        0xFF01 => {
            mmu.serial_writer.printAsciiChar(value, .{}) catch {};
            mmu.internal[address] = value;
        },
        0xFF0F => mmu.set_interrupts = Interrupts.from(value),
        0xFFFF => mmu.enabled_interrupts = Interrupts.from(value),
        else => mmu.internal[address] = value,
    }
}

/// In priority order, same as bit order.
/// Values are their call addresses.
pub const Interrupt = enum(u16) {
    v_blank = 0x40,
    lcd = 0x48,
    timer = 0x50,
    serial = 0x58,
    joypad = 0x60,

    pub fn address(self: Interrupt) u16 {
        return @intFromEnum(self);
    }
};

pub const Interrupts = packed struct(u5) {
    v_blank: bool = false,
    lcd: bool = false,
    timer: bool = false,
    serial: bool = false,
    joypad: bool = false,

    /// The highest priority interrupt currently set
    pub fn current(self: Interrupts) ?Interrupt {
        if (self.v_blank) return .v_blank;
        if (self.lcd) return .lcd;
        if (self.timer) return .timer;
        if (self.serial) return .serial;
        if (self.joypad) return .joypad;

        return null;
    }

    pub fn set(self: *Interrupts, interrupt: Interrupt) void {
        switch (interrupt) {
            inline else => |i| @field(self, @tagName(i)) = true,
        }
    }

    pub fn clear(self: *Interrupts, interrupt: Interrupt) void {
        switch (interrupt) {
            inline else => |i| @field(self, @tagName(i)) = false,
        }
    }

    pub inline fn from(value: u8) Interrupts {
        const v: u5 = @truncate(value);
        return @bitCast(v);
    }

    pub inline fn int(self: Interrupts) u8 {
        const value: u5 = @bitCast(self);
        return value;
    }
};

pub fn currentInterrupt(mmu: MMU) ?Interrupt {
    const available = Interrupts.from(mmu.enabled_interrupts.int() & mmu.set_interrupts.int());

    return available.current();
}

pub fn setInterrupt(mmu: *MMU, interrupt: Interrupt) void {
    mmu.set_interrupts.set(interrupt);
}

pub fn clearInterrupt(mmu: *MMU, interrupt: Interrupt) void {
    mmu.set_interrupts.clear(interrupt);
}

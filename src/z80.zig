const std = @import("std");

const Z80 = @This();

mmu: [0x10000]u8 = [_]u8{0} ** 0x10000,

clock: Clock = .{},

registers: Registers,

program_counter: u16 = 0,

flags: Flags = .{},

const Clock = struct {
    m: u8 = 0,
    t: u8 = 0,

    pub fn tick(self: *Clock) void {
        self.m += 1;
        self.t += 1 * 4;
    }
};

const Register16 = enum {
    // af,
    bc,
    de,
    hl,
    sp,
};

pub const Registers = struct {
    a: u8 = 0,
    b: u8 = 0,
    c: u8 = 0,
    d: u8 = 0,
    e: u8 = 0,
    h: u8 = 0,
    l: u8 = 0,

    stack_pointer: u16 = 0,

    pub fn set_16(self: *Registers, r: Register16, high: u8, low: u8) void {
        switch (r) {
            .bc => {
                self.b = high;
                self.c = low;
            },
            .de => {
                self.d = high;
                self.c = low;
            },
            .hl => {
                self.h = high;
                self.l = low;
            },
            .sp => {
                self.stack_pointer = to_u16(high, low);
            },
        }
    }

    pub fn read_16(self: Registers, r: Register16) u16 {
        return switch (r) {
            .bc => to_u16(self.b, self.c),
            .de => to_u16(self.d, self.e),
            .hl => to_u16(self.h, self.l),
            .sp => self.stack_pointer,
        };
    }

    inline fn to_u16(high: u8, low: u8) u16 {
        return (@as(u16, high) << 8) | low;
    }
};

pub const Flags = packed struct(u4) {
    /// Last operation's result > 255 or < 0
    carried: bool = false,

    /// Last operation's result's
    /// lower half of byte overflowed 15
    half_carried: bool = false,

    /// Last operation was a subtraction
    subtracted: bool = false,

    /// Last operation's result was zero
    was_zero: bool = false,

    pub inline fn from(value: u8) Flags {
        const shifted: u4 = @truncate(value >> 4);
        return @bitCast(shifted);
    }

    pub inline fn int(flags: Flags) u8 {
        const value: u4 = @bitCast(flags);
        return @as(u8, value) << 4;
    }
};

pub fn init(registers: Registers) Z80 {
    return .{
        .registers = registers,
    };
}

pub fn step(z80: *Z80) void {
    const opcode = z80.read_byte(z80.program_counter);
    z80.program_counter +%= 1;
    z80.operate(opcode);
}

fn operate(z80: *Z80, opcode: u8) void {
    switch (opcode) {
        0x00 => {},

        0x01 => z80.load_16(.bc),
        0x11 => z80.load_16(.de),
        0x21 => z80.load_16(.hl),
        0x31 => z80.load_16(.sp),

        0x02 => z80.load_memory(.bc, z80.registers.a),
        0x12 => z80.load_memory(.de, z80.registers.a),
        0x22 => z80.load_memory(.bc, z80.registers.a),
        0x32 => z80.load_memory(.bc, z80.registers.a),

        0x3C => z80.increment("a"),
        0x04 => z80.increment("b"),
        0x0C => z80.increment("c"),
        0x14 => z80.increment("d"),
        0x1C => z80.increment("e"),
        0x24 => z80.increment("h"),
        0x2C => z80.increment("l"),
        0x34 => z80.increment_hl(),

        0x3D => z80.decrement("a"),
        0x05 => z80.decrement("b"),
        0x0D => z80.decrement("c"),
        0x15 => z80.decrement("d"),
        0x1D => z80.decrement("e"),
        0x25 => z80.decrement("h"),
        0x2D => z80.decrement("l"),
        0x35 => z80.decrement_hl(),

        0x78...0x7F, 0x3E => z80.load_8("a", z80.operand_8(opcode)),
        0x40...0x47, 0x06 => z80.load_8("b", z80.operand_8(opcode)),
        0x48...0x4F, 0x0E => z80.load_8("c", z80.operand_8(opcode)),
        0x50...0x57, 0x16 => z80.load_8("d", z80.operand_8(opcode)),
        0x58...0x5F, 0x1E => z80.load_8("e", z80.operand_8(opcode)),
        0x60...0x67, 0x26 => z80.load_8("h", z80.operand_8(opcode)),
        0x68...0x6F, 0x2E => z80.load_8("l", z80.operand_8(opcode)),
        0x70...0x75, 0x77, 0x36 => z80.load_memory(.hl, z80.operand_8(opcode)),

        0x76 => z80.halt(),

        0x80...0x87, 0xC6 => z80.add_8(z80.operand_8(opcode)),
        0x88...0x8F, 0xCE => z80.add_with_carry_8(z80.operand_8(opcode)),
        0x90...0x97, 0xD6 => z80.subtract_8(z80.operand_8(opcode)),
        0x98...0x9F, 0xDE => z80.subtract_with_carry_8(z80.operand_8(opcode)),
        0xA0...0xA7, 0xE6 => z80.and_(z80.operand_8(opcode)),
        0xA8...0xAF, 0xEE => z80.xor(z80.operand_8(opcode)),
        0xB0...0xB7, 0xF6 => z80.or_(z80.operand_8(opcode)),
        0xB8...0xBF, 0xFE => z80.compare_8(z80.operand_8(opcode)),

        else => {},
    }
}

fn write_byte(z80: *Z80, address: u16, value: u8) void {
    z80.clock.tick();
    z80.mmu[address] = value;
}

fn read_byte(z80: *Z80, address: u16) u8 {
    z80.clock.tick();
    return z80.mmu[address];
}

/// Given an opcode get its 8 bit operand value.
/// This is valid for the 0x40...0xBF chunk that use registers
/// and the byte pointed to by HL
/// as well as the constant-based 0x_6 and 0x_E opcodes.
fn operand_8(z80: *Z80, opcode: u8) u8 {
    // The lower nibble, repeated twice as there are 8
    return switch ((opcode & 0x0F) % 0x08) {
        0x7 => z80.registers.a,
        0x0 => z80.registers.b,
        0x1 => z80.registers.c,
        0x2 => z80.registers.d,
        0x3 => z80.registers.e,
        0x4 => z80.registers.h,
        0x5 => z80.registers.l,
        0x6 => switch (opcode) {
            0x40...0xBF => z80.read_byte(z80.registers.read_16(.hl)),
            else => z80.constant_8(),
        },
        else => unreachable,
    };
}

/// Get the 8 bit value at the program counter
fn constant_8(z80: *Z80) u8 {
    const value = z80.read_byte(z80.program_counter);
    z80.program_counter +%= 1;
    return value;
}

/// TODO
fn halt(z80: *Z80) void {
    z80.clock.tick();
}

/// Load the value into the given register
fn load_8(z80: *Z80, comptime register: []const u8, operand: u8) void {
    @field(z80.registers, register) = operand;
}

/// Load the value into the byte pointed to by register
fn load_memory(z80: *Z80, register: Register16, operand: u8) void {
    z80.write_byte(z80.registers.read_16(register), operand);
}

/// Load the value into the given registers
fn load_16(z80: *Z80, register: Register16) void {
    const low = z80.constant_8();
    const high = z80.constant_8();

    z80.registers.set_16(register, high, low);
}

/// Increment the register by 1
fn increment(z80: *Z80, comptime register: []const u8) void {
    @field(z80.registers, register) +%= 1;

    z80.flags = .{
        .was_zero = @field(z80.registers, register) == 0,
    };
}

/// Decrement the register by 1
fn decrement(z80: *Z80, comptime register: []const u8) void {
    @field(z80.registers, register) -%= 1;

    z80.flags = .{
        .was_zero = @field(z80.registers, register) == 0,
        .subtracted = true,
    };
}

fn increment_hl(z80: *Z80) void {
    var value = z80.read_byte(z80.registers.read_16(.hl));

    value +%= 1;

    z80.flags = .{
        .was_zero = value == 0,
    };

    z80.write_byte(z80.registers.read_16(.hl), value);
}

fn decrement_hl(z80: *Z80) void {
    var value = z80.read_byte(z80.registers.read_16(.hl));

    value -%= 1;

    z80.flags = .{
        .was_zero = value == 0,
        .subtracted = true,
    };

    z80.write_byte(z80.registers.read_16(.hl), value);
}

/// Add value to A
/// Put result in A
fn add_8(z80: *Z80, operand: u8) void {
    z80.registers.a, const overflowed = @addWithOverflow(z80.registers.a, operand);

    z80.flags = .{
        .was_zero = z80.registers.a == 0,
        .carried = overflowed != 0,
    };
}

/// TODO
fn add_with_carry_8(z80: *Z80, operand: u8) void {
    _ = operand;
    _ = z80;
}

/// Subtract value from A
/// Put result in A
fn subtract_8(z80: *Z80, operand: u8) void {
    z80.registers.a, const underflowed = @subWithOverflow(z80.registers.a, operand);

    z80.flags = .{
        .subtracted = true,
        .was_zero = z80.registers.a == 0,
        .carried = underflowed != 0,
    };
}

/// TODO
fn subtract_with_carry_8(z80: *Z80, operand: u8) void {
    _ = operand;
    _ = z80;
}

/// Bitwise and the value with A
fn and_(z80: *Z80, operand: u8) void {
    z80.registers.a &= operand;

    z80.flags = .{
        .was_zero = z80.registers.a == 0,
    };
}

/// Bitwise or the value with A
fn or_(z80: *Z80, operand: u8) void {
    z80.registers.a |= operand;

    z80.flags = .{
        .was_zero = z80.registers.a == 0,
    };
}

/// Bitwise xor the value with A
fn xor(z80: *Z80, operand: u8) void {
    z80.registers.a ^= operand;

    z80.flags = .{
        .was_zero = z80.registers.a == 0,
    };
}

/// Compare value to A
/// If equal, flag zero
/// If register > A, flag carry
pub fn compare_8(z80: *Z80, operand: u8) void {
    const result, const underflowed = @subWithOverflow(z80.registers.a, operand);

    z80.flags = .{
        .subtracted = true,
        .was_zero = result == 0,
        .carried = underflowed != 0,
    };
}

test "add constant" {
    var z80 = Z80.init(.{ .a = 2 });
    z80.mmu[0] = 0xC6;
    z80.mmu[1] = 0x05;
    z80.mmu[2] = 0x00;
    z80.step();
    z80.step();
    try std.testing.expectEqual(3, z80.clock.m);
    try std.testing.expectEqual(12, z80.clock.t);
    try std.testing.expectEqual(7, z80.registers.a);
}

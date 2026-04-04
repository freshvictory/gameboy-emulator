const std = @import("std");
const MMU = @import("mmu.zig");

const Z80 = @This();

mmu: MMU,

clock: Clock = .{},

registers: Registers,

program_counter: u16 = 0,

flags: Flags = .{},

set_interrupt_after_next_instruction: bool = false,

interrupt_master_enable: bool = false,

const Clock = struct {
    m: u8 = 0,
    t: u8 = 0,

    pub fn tick(self: *Clock) void {
        self.m +%= 1;
        self.t +%= 1 * 4;
    }
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

    pub fn bc(self: Registers) u16 {
        return to16(self.b, self.c);
    }

    pub fn de(self: Registers) u16 {
        return to16(self.d, self.e);
    }

    pub fn hl(self: Registers) u16 {
        return to16(self.h, self.l);
    }

    pub fn set_hl(self: *Registers, value: u16) void {
        self.h = @truncate(value >> 8);
        self.l = @truncate(value);
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

pub fn init(registers: Registers, mmu: MMU) Z80 {
    return .{
        .registers = registers,
        .mmu = mmu,
    };
}

pub fn step(z80: *Z80) void {
    const set_interrupt = z80.set_interrupt_after_next_instruction;
    z80.set_interrupt_after_next_instruction = false;
    const opcode = z80.readByte(z80.program_counter);
    z80.program_counter +%= 1;
    z80.operate(opcode);
    if (set_interrupt) z80.interrupt_master_enable = true;
}

fn operate(z80: *Z80, opcode: u8) void {
    switch (opcode) {
        0x00 => {},

        0x01 => z80.load16("b", "c"),
        0x11 => z80.load16("d", "e"),
        0x21 => z80.load16("h", "l"),
        0x31 => z80.loadStackPointer(),
        0xF9 => z80.loadHLIntoStackPointer(),

        0x02 => z80.loadToMemory(z80.registers.bc(), z80.registers.a),
        0x08 => z80.loadStackPointerInAddress(z80.constant16()),
        0x0A => z80.loadFromMemory(z80.registers.bc()),
        0x12 => z80.loadToMemory(z80.registers.de(), z80.registers.a),
        0x1A => z80.loadFromMemory(z80.registers.de()),
        0xEA => z80.loadToMemory(z80.constant16(), z80.registers.a),
        0xFA => z80.loadFromMemory(z80.constant16()),
        0x22 => z80.loadAIntoHLAndIncrement(),
        0x2A => z80.loadAFromHLAndIncrement(),
        0x32 => z80.loadAIntoHLAndDecrement(),
        0x3A => z80.loadAFromHLAndDecrement(),

        0xE0 => z80.loadToMemory(highAddress(z80.constant8()), z80.registers.a),
        0xE2 => z80.loadToMemory(highAddress(z80.registers.c), z80.registers.a),
        0xF0 => z80.loadFromMemory(highAddress(z80.constant8())),
        0xF2 => z80.loadFromMemory(highAddress(z80.registers.c)),

        0x3C => z80.increment("a"),
        0x04 => z80.increment("b"),
        0x0C => z80.increment("c"),
        0x14 => z80.increment("d"),
        0x1C => z80.increment("e"),
        0x24 => z80.increment("h"),
        0x2C => z80.increment("l"),
        0x34 => z80.incrementHL(),
        0x03 => z80.increment16("b", "c"),
        0x13 => z80.increment16("d", "e"),
        0x23 => z80.increment16("h", "l"),
        0x33 => z80.incrementStackPointer(),

        0x3D => z80.decrement("a"),
        0x05 => z80.decrement("b"),
        0x0D => z80.decrement("c"),
        0x15 => z80.decrement("d"),
        0x1D => z80.decrement("e"),
        0x25 => z80.decrement("h"),
        0x2D => z80.decrement("l"),
        0x35 => z80.decrementHL(),
        0x0B => z80.decrement16("b", "c"),
        0x1B => z80.decrement16("d", "e"),
        0x2B => z80.decrement16("h", "l"),
        0x3B => z80.decrementStackPointer(),

        0x07 => z80.rotateALeft(),
        0x0F => z80.rotateARight(),
        0x17 => z80.rotateALeftThroughCarry(),
        0x1F => z80.rotateARightThroughCarry(),
        0x2F => z80.not(),

        0x37 => z80.setCarry(),
        0x3F => z80.invertCarry(),

        0x09 => z80.addToHL(z80.registers.bc()),
        0x19 => z80.addToHL(z80.registers.de()),
        0x29 => z80.addToHL(z80.registers.hl()),
        0x39 => z80.addToHL(z80.registers.stack_pointer),

        0x78...0x7F, 0x3E => z80.load8("a", z80.operand8(opcode)),
        0x40...0x47, 0x06 => z80.load8("b", z80.operand8(opcode)),
        0x48...0x4F, 0x0E => z80.load8("c", z80.operand8(opcode)),
        0x50...0x57, 0x16 => z80.load8("d", z80.operand8(opcode)),
        0x58...0x5F, 0x1E => z80.load8("e", z80.operand8(opcode)),
        0x60...0x67, 0x26 => z80.load8("h", z80.operand8(opcode)),
        0x68...0x6F, 0x2E => z80.load8("l", z80.operand8(opcode)),
        0x70...0x75, 0x77, 0x36 => z80.loadToMemory(z80.registers.hl(), z80.operand8(opcode)),

        0x10 => z80.stop(),
        0x76 => z80.halt(),

        0x27 => z80.decimalAdjustAccumulator(),

        0x80...0x87, 0xC6 => z80.add(z80.operand8(opcode)),
        0x88...0x8F, 0xCE => z80.addWithCarry(z80.operand8(opcode)),
        0x90...0x97, 0xD6 => z80.subtract(z80.operand8(opcode)),
        0x98...0x9F, 0xDE => z80.subtractWithCarry(z80.operand8(opcode)),
        0xA0...0xA7, 0xE6 => z80.@"and"(z80.operand8(opcode)),
        0xA8...0xAF, 0xEE => z80.xor(z80.operand8(opcode)),
        0xB0...0xB7, 0xF6 => z80.@"or"(z80.operand8(opcode)),
        0xB8...0xBF, 0xFE => z80.compare(z80.operand8(opcode)),

        0xC1 => z80.pop("b", "c"),
        0xD1 => z80.pop("d", "e"),
        0xE1 => z80.pop("h", "l"),
        0xF1 => z80.popAF(),
        0xC5 => z80.push(z80.registers.b, z80.registers.c),
        0xD5 => z80.push(z80.registers.d, z80.registers.e),
        0xE5 => z80.push(z80.registers.h, z80.registers.l),
        0xF5 => z80.push(z80.registers.a, z80.flags.int()),

        0x18 => z80.jumpRelative(z80.signed8()),
        0x20 => z80.jumpRelativeIf(!z80.flags.was_zero, z80.signed8()),
        0x28 => z80.jumpRelativeIf(z80.flags.was_zero, z80.signed8()),
        0x30 => z80.jumpRelativeIf(!z80.flags.carried, z80.signed8()),
        0x38 => z80.jumpRelativeIf(z80.flags.carried, z80.signed8()),

        0xC3 => z80.jump(z80.constant16()),
        0xC2 => z80.jumpIf(!z80.flags.was_zero, z80.constant16()),
        0xCA => z80.jumpIf(z80.flags.was_zero, z80.constant16()),
        0xD2 => z80.jumpIf(!z80.flags.carried, z80.constant16()),
        0xDA => z80.jumpIf(z80.flags.carried, z80.constant16()),

        0xE9 => z80.jumpHL(),

        0xCD => z80.call(z80.constant16()),
        0xC4 => z80.callIf(!z80.flags.was_zero, z80.constant16()),
        0xCC => z80.callIf(z80.flags.was_zero, z80.constant16()),
        0xD4 => z80.callIf(!z80.flags.carried, z80.constant16()),
        0xDC => z80.callIf(z80.flags.carried, z80.constant16()),

        0xC9 => z80.@"return"(),
        0xC0 => z80.returnIf(!z80.flags.was_zero),
        0xC8 => z80.returnIf(z80.flags.was_zero),
        0xD0 => z80.returnIf(!z80.flags.carried),
        0xD8 => z80.returnIf(z80.flags.carried),

        // RST (restart) instructions
        0xC7 => z80.call(0x00),
        0xCF => z80.call(0x08),
        0xD7 => z80.call(0x10),
        0xDF => z80.call(0x18),
        0xE7 => z80.call(0x20),
        0xEF => z80.call(0x28),
        0xF7 => z80.call(0x30),
        0xFF => z80.call(0x38),

        0xE8 => z80.addToStackPointer(z80.signed8()),
        0xF8 => z80.addToStackPointerAndLoad(z80.signed8()),

        0xD9 => z80.returnAndEnableInterrupts(),
        0xF3 => z80.disableInterrupts(),
        0xFB => z80.enableInterrupts(),

        0xCB => z80.operatePrefixed(z80.constant8()),

        // Undefined instructions
        0xD3, 0xDB, 0xDD, 0xE3, 0xE4, 0xEB, 0xEC, 0xED, 0xF4, 0xFC, 0xFD => {},
    }
}

fn operatePrefixed(z80: *Z80, opcode: u8) void {
    const operand = z80.operandPrefixed(opcode);

    const update, const flags = switch (opcode) {
        0x00...0x07 => rotateLeft(operand),
        0x08...0x0F => rotateRight(operand),
        0x10...0x17 => rotateLeftThroughCarry(z80.flags, operand),
        0x18...0x1F => rotateRightThroughCarry(z80.flags, operand),
        0x20...0x27 => shiftLeft(operand),
        0x28...0x2F => shiftRightArithmetically(operand),
        0x30...0x37 => swap(operand),
        0x38...0x3F => shiftRightLogically(operand),
        inline 0x40...0xFF => |code| bit: {
            const bit = comptime bitPrefixed(code);

            const high: u4 = @truncate(code >> 4);

            break :bit switch (high) {
                0x4...0x7 => checkBit(z80.flags, bit, operand),
                0x8...0xB => zeroBit(z80.flags, bit, operand),
                0xC...0xF => setBit(z80.flags, bit, operand),

                else => unreachable,
            };
        },
    };

    if (update) |result| {
        z80.setPrefixedResult(opcode, result);
    }
    z80.flags = flags;
}

fn writeByte(z80: *Z80, address: u16, value: u8) void {
    z80.clock.tick();
    z80.mmu.writeByte(address, value);
}

fn readByte(z80: *Z80, address: u16) u8 {
    z80.clock.tick();
    return z80.mmu.readByte(address);
}

fn operandPrefixed(z80: *Z80, opcode: u8) u8 {
    // The lower nibble, repeated twice as there are 8
    return switch ((opcode & 0x0F) % 0x08) {
        0x7 => z80.registers.a,
        0x0 => z80.registers.b,
        0x1 => z80.registers.c,
        0x2 => z80.registers.d,
        0x3 => z80.registers.e,
        0x4 => z80.registers.h,
        0x5 => z80.registers.l,
        0x6 => z80.readByte(z80.registers.hl()),
        else => unreachable,
    };
}

fn setPrefixedResult(z80: *Z80, opcode: u8, result: u8) void {
    // The lower nibble, repeated twice as there are 8
    return switch ((opcode & 0x0F) % 0x08) {
        0x7 => z80.registers.a = result,
        0x0 => z80.registers.b = result,
        0x1 => z80.registers.c = result,
        0x2 => z80.registers.d = result,
        0x3 => z80.registers.e = result,
        0x4 => z80.registers.h = result,
        0x5 => z80.registers.l = result,
        0x6 => z80.writeByte(z80.registers.hl(), result),
        else => unreachable,
    };
}

fn bitPrefixed(opcode: u8) u3 {
    const x: u3 = (opcode >> 4) % 4 * 2;
    const y: u3 = if ((opcode & 0x0F) < 8) 0 else 1;

    return x + y;
}

/// Given an opcode get its 8 bit operand value.
/// This is valid for the 0x40...0xBF chunk that use registers
/// and the byte pointed to by HL
/// as well as the constant-based 0x_6 and 0x_E opcodes.
fn operand8(z80: *Z80, opcode: u8) u8 {
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
            0x40...0xBF => z80.readByte(z80.registers.hl()),
            else => z80.constant8(),
        },
        else => unreachable,
    };
}

/// Get the 8 bit value at the program counter
fn constant8(z80: *Z80) u8 {
    const value = z80.readByte(z80.program_counter);
    z80.program_counter +%= 1;
    return value;
}

fn constant16(z80: *Z80) u16 {
    const low = z80.constant8();
    const high = z80.constant8();

    return to16(high, low);
}

fn signed8(z80: *Z80) i8 {
    return @bitCast(z80.constant8());
}

inline fn highAddress(value: u8) u16 {
    return 0xFF00 + @as(u16, value);
}

/// TODO
fn halt(z80: *Z80) void {
    z80.clock.tick();
    z80.clock.tick();
}

/// TODO
fn stop(z80: *Z80) void {
    z80.clock.tick();
    z80.clock.tick();
}

/// Load the value into the given register
fn load8(z80: *Z80, comptime register: []const u8, operand: u8) void {
    @field(z80.registers, register) = operand;
}

/// Load the value into the byte pointed to by register
fn loadToMemory(z80: *Z80, address: u16, operand: u8) void {
    z80.writeByte(address, operand);
}

fn loadFromMemory(z80: *Z80, address: u16) void {
    z80.registers.a = z80.readByte(address);
}

/// Load the lower half into address
/// and the higher half into address + 1
fn loadStackPointerInAddress(z80: *Z80, address: u16) void {
    const low: u8 = @truncate(z80.registers.stack_pointer);
    const high: u8 = @truncate(z80.registers.stack_pointer >> 8);

    z80.writeByte(address, low);
    z80.writeByte(address +% 1, high);
}

/// Load the value into the given registers
fn load16(
    z80: *Z80,
    comptime high: []const u8,
    comptime low: []const u8,
) void {
    @field(z80.registers, low) = z80.constant8();
    @field(z80.registers, high) = z80.constant8();
}

/// Load the value into the stack pointer
fn loadStackPointer(z80: *Z80) void {
    z80.registers.stack_pointer = z80.constant16();
}

/// Load the value into the stack pointer
fn loadHLIntoStackPointer(z80: *Z80) void {
    z80.registers.stack_pointer = z80.registers.hl();
    z80.clock.tick();
}

/// Add a signed value to an unsigned one.
/// Return the result plus carried and half_carried signals.
fn addSigned(value: u16, operand: i8) struct { u16, bool, bool } {
    const low: u8 = @truncate(value);

    const offset: u16 = @bitCast(@as(i16, operand));
    const result = value +% offset;

    // Flags are based on unsigned addition of
    // the low byte of SP and the raw unsigned operand byte
    const raw_operand: u8 = @bitCast(operand);
    _, const overflowed = @addWithOverflow(low, raw_operand);
    const half_carried = ((low & 0xF) + (raw_operand & 0xF)) > 0xF;

    return .{ result, overflowed != 0, half_carried };
}

fn addToStackPointer(z80: *Z80, operand: i8) void {
    const result, const carried, const half_carried = addSigned(
        z80.registers.stack_pointer,
        operand,
    );

    z80.registers.stack_pointer = result;

    z80.flags = .{
        .carried = carried,
        .half_carried = half_carried,
    };

    z80.clock.tick();
    z80.clock.tick();
}

/// Add the signed integer with SP and store in HL
fn addToStackPointerAndLoad(z80: *Z80, operand: i8) void {
    const result, const carried, const half_carried = addSigned(
        z80.registers.stack_pointer,
        operand,
    );

    z80.registers.h = @truncate(result >> 8);
    z80.registers.l = @truncate(result);

    z80.flags = .{
        .carried = carried,
        .half_carried = half_carried,
    };

    z80.clock.tick();
}

fn loadAIntoHLAndIncrement(z80: *Z80) void {
    const address = z80.registers.hl();
    z80.writeByte(address, z80.registers.a);

    const newAddress = address +% 1;

    z80.registers.set_hl(newAddress);
}

fn loadAIntoHLAndDecrement(z80: *Z80) void {
    const address = z80.registers.hl();
    z80.writeByte(address, z80.registers.a);

    const newAddress = address -% 1;

    z80.registers.set_hl(newAddress);
}

fn loadAFromHLAndIncrement(z80: *Z80) void {
    const address = z80.registers.hl();
    z80.registers.a = z80.readByte(address);

    const newAddress = address +% 1;

    z80.registers.set_hl(newAddress);
}

fn loadAFromHLAndDecrement(z80: *Z80) void {
    const address = z80.registers.hl();
    z80.registers.a = z80.readByte(address);

    const newAddress = address -% 1;

    z80.registers.set_hl(newAddress);
}

/// Increment the register by 1
fn increment(z80: *Z80, comptime register: []const u8) void {
    const old = @field(z80.registers, register);
    @field(z80.registers, register) = old +% 1;

    z80.flags = .{
        .half_carried = old & 0xF == 0b1111,
        .carried = z80.flags.carried,
        .was_zero = @field(z80.registers, register) == 0,
    };
}

fn incrementHL(z80: *Z80) void {
    const address = z80.registers.hl();
    const old = z80.readByte(address);

    const new = old +% 1;

    z80.flags = .{
        .half_carried = old & 0xF == 0b1111,
        .carried = z80.flags.carried,
        .was_zero = new == 0,
    };

    z80.writeByte(address, new);
}

/// Increment the 16 bit register by 1
fn increment16(
    z80: *Z80,
    comptime high: []const u8,
    comptime low: []const u8,
) void {
    @field(z80.registers, low), const overflowed = @addWithOverflow(@field(z80.registers, low), 1);

    @field(z80.registers, high) +%= overflowed;

    z80.clock.tick();
}

fn incrementStackPointer(z80: *Z80) void {
    z80.registers.stack_pointer +%= 1;
    z80.clock.tick();
}

/// Decrement the register by 1
fn decrement(z80: *Z80, comptime register: []const u8) void {
    const old = @field(z80.registers, register);
    @field(z80.registers, register) = old -% 1;

    z80.flags = .{
        .half_carried = old & 0xF == 0,
        .carried = z80.flags.carried,
        .was_zero = @field(z80.registers, register) == 0,
        .subtracted = true,
    };
}

fn decrementHL(z80: *Z80) void {
    const address = z80.registers.hl();
    const old = z80.readByte(address);

    const new = old -% 1;

    z80.flags = .{
        .half_carried = old & 0xF == 0,
        .carried = z80.flags.carried,
        .was_zero = new == 0,
        .subtracted = true,
    };

    z80.writeByte(address, new);
}

fn decrement16(
    z80: *Z80,
    comptime high: []const u8,
    comptime low: []const u8,
) void {
    @field(z80.registers, low), const underflowed = @subWithOverflow(@field(z80.registers, low), 1);

    @field(z80.registers, high) -%= underflowed;

    z80.clock.tick();
}

fn decrementStackPointer(z80: *Z80) void {
    z80.registers.stack_pointer -%= 1;
    z80.clock.tick();
}

/// Adjust result of arithmetic to be binary-coded decimal
fn decimalAdjustAccumulator(z80: *Z80) void {
    if (z80.flags.subtracted) {
        if (z80.flags.half_carried) {
            z80.registers.a -%= 0x6;
        }
        if (z80.flags.carried) {
            z80.registers.a -%= 0x60;
        }
    } else {
        const x = z80.registers.a & 0xF > 0x9;
        const y = z80.registers.a > 0x99;
        if (z80.flags.half_carried or x) {
            z80.registers.a +%= 0x6;
        }
        if (z80.flags.carried or y) {
            z80.registers.a +%= 0x60;
            z80.flags.carried = true;
        }
    }

    z80.flags.was_zero = z80.registers.a == 0;
    z80.flags.half_carried = false;
}

/// Add value to A
/// Put result in A
fn add(z80: *Z80, operand: u8) void {
    const old = z80.registers.a;
    z80.registers.a, const overflowed = @addWithOverflow(z80.registers.a, operand);

    z80.flags = .{
        .was_zero = z80.registers.a == 0,
        .half_carried = (operand & 0xF) + (old & 0xF) > 0b1111,
        .carried = overflowed != 0,
    };
}

/// Add value and carry flag to A
fn addWithCarry(z80: *Z80, operand: u8) void {
    const carry: u1 = if (z80.flags.carried) 1 else 0;
    const old = z80.registers.a;
    z80.registers.a, const overflowed = @addWithOverflow(z80.registers.a, operand);
    z80.registers.a, const carry_overflow = @addWithOverflow(z80.registers.a, carry);

    z80.flags = .{
        .was_zero = z80.registers.a == 0,
        .half_carried = (operand & 0xF) + (old & 0xF) + carry > 0xF,
        .carried = overflowed != 0 or carry_overflow != 0,
    };
}

fn addToHL(
    z80: *Z80,
    operand: u16,
) void {
    const old = z80.registers.hl();
    const value, const overflowed = @addWithOverflow(old, operand);

    z80.flags = .{
        .was_zero = z80.flags.was_zero,
        .half_carried = (old & 0xFFF) + (operand & 0xFFF) > 0xFFF,
        .carried = overflowed != 0,
    };

    z80.registers.h = @truncate(value >> 8);
    z80.registers.l = @truncate(value);

    z80.clock.tick();
}

/// Subtract value from A
/// Put result in A
fn subtract(z80: *Z80, operand: u8) void {
    const old = z80.registers.a;
    z80.registers.a -%= operand;

    z80.flags = .{
        .subtracted = true,
        .was_zero = z80.registers.a == 0,
        .carried = operand > old,
        .half_carried = (old & 0xF) < (operand & 0xF),
    };
}

/// Subtract value and carry flag from A
fn subtractWithCarry(z80: *Z80, operand: u8) void {
    const carry: u1 = if (z80.flags.carried) 1 else 0;
    const old = z80.registers.a;
    z80.registers.a -%= operand;
    z80.registers.a -%= carry;

    z80.flags = .{
        .subtracted = true,
        .was_zero = z80.registers.a == 0,
        .carried = old < operand or (old - operand) < carry,
        .half_carried = (old & 0xF) < (operand & 0xF) + carry,
    };
}

/// Bitwise and the value with A
fn @"and"(z80: *Z80, operand: u8) void {
    z80.registers.a &= operand;

    z80.flags = .{
        .half_carried = true,
        .was_zero = z80.registers.a == 0,
    };
}

/// Bitwise or the value with A
fn @"or"(z80: *Z80, operand: u8) void {
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

/// Bitwise not of A (CPL)
fn not(z80: *Z80) void {
    z80.registers.a = ~z80.registers.a;
    z80.flags.subtracted = true;
    z80.flags.half_carried = true;
}

/// Compare value to A
/// If equal, flag zero
/// If register > A, flag carry
fn compare(z80: *Z80, operand: u8) void {
    const old = z80.registers.a;
    const result, const underflowed = @subWithOverflow(z80.registers.a, operand);

    z80.flags = .{
        .subtracted = true,
        .was_zero = result == 0,
        .carried = underflowed != 0,
        .half_carried = (old & 0xF) < (operand & 0xF),
    };
}

const PrefixResult = struct { ?u8, Flags };

/// Rotate value left (RLC)
fn rotateLeft(operand: u8) PrefixResult {
    var result, const overflowed = @shlWithOverflow(operand, 1);

    result += overflowed;

    return .{
        result,
        .{
            .carried = overflowed != 0,
            .was_zero = result == 0,
        },
    };
}

/// Shift value left (SLA)
fn shiftLeft(operand: u8) PrefixResult {
    const result, const overflowed = @shlWithOverflow(operand, 1);

    return .{
        result,
        .{
            .carried = overflowed != 0,
            .was_zero = result == 0,
        },
    };
}

/// Rotate A left (RCLA)
fn rotateALeft(z80: *Z80) void {
    z80.registers.a, const overflowed = @shlWithOverflow(z80.registers.a, 1);

    z80.registers.a += overflowed;

    z80.flags = .{ .carried = overflowed != 0 };
}

fn rotateLeftThroughCarry(flags: Flags, operand: u8) PrefixResult {
    var result, const overflowed = @shlWithOverflow(operand, 1);

    result += if (flags.carried) 1 else 0;

    return .{
        result,
        .{
            .carried = overflowed != 0,
            .was_zero = result == 0,
        },
    };
}

/// Rotate A left through carry (RLA)
fn rotateALeftThroughCarry(z80: *Z80) void {
    z80.registers.a, const overflowed = @shlWithOverflow(z80.registers.a, 1);

    z80.registers.a += if (z80.flags.carried) 1 else 0;

    z80.flags = .{
        .carried = overflowed != 0,
    };
}

/// Rotate value right (RRC)
fn rotateRight(operand: u8) PrefixResult {
    const lowestBit: u8 = operand & 1;

    var result = operand >> 1;

    result |= lowestBit << 7;

    return .{
        result,
        .{
            .carried = lowestBit != 0,
            .was_zero = result == 0,
        },
    };
}

/// Shift value right, don't touch high bit (SRA)
fn shiftRightArithmetically(operand: u8) PrefixResult {
    const lowestBit: u8 = operand & 1;
    const highestBit: u8 = operand & 0b10000000;

    var result = operand >> 1;
    result |= highestBit;

    return .{
        result,
        .{
            .carried = lowestBit != 0,
            .was_zero = result == 0,
        },
    };
}

/// Shift value right (SRL)
fn shiftRightLogically(operand: u8) PrefixResult {
    const lowestBit: u8 = operand & 1;

    const result = operand >> 1;

    return .{
        result,
        .{
            .carried = lowestBit != 0,
            .was_zero = result == 0,
        },
    };
}

/// Rotate A right (RCLA)
fn rotateARight(z80: *Z80) void {
    const lowestBit: u8 = z80.registers.a & 1;

    z80.registers.a >>= 1;

    z80.registers.a |= lowestBit << 7;

    z80.flags = .{ .carried = lowestBit != 0 };
}

fn rotateRightThroughCarry(flags: Flags, operand: u8) PrefixResult {
    const lowestBit: u8 = operand & 1;

    var result = operand >> 1;

    const carry_bit: u8 = if (flags.carried) 1 else 0;

    result |= carry_bit << 7;

    return .{
        result,
        .{
            .carried = lowestBit != 0,
            .was_zero = result == 0,
        },
    };
}

/// Rotate A right through carry (RRA)
fn rotateARightThroughCarry(z80: *Z80) void {
    const lowestBit = z80.registers.a & 1;

    z80.registers.a >>= 1;

    const carry_bit: u8 = if (z80.flags.carried) 1 else 0;

    z80.registers.a |= carry_bit << 7;

    z80.flags = .{ .carried = lowestBit != 0 };
}

/// Swap the upper 4 bits with the lower 4
fn swap(operand: u8) PrefixResult {
    const result = (operand >> 4) | ((operand << 4) & 0xF0);

    return .{ result, .{ .was_zero = result == 0 } };
}

/// Check the bit and set the zero flag if unset
fn checkBit(flags: Flags, comptime bit: u3, operand: u8) PrefixResult {
    const result = operand & (1 << bit);

    return .{ null, .{
        .was_zero = result == 0,
        .carried = flags.carried,
        .half_carried = true,
    } };
}

/// Set the given bit to zero
fn zeroBit(flags: Flags, comptime bit: u3, operand: u8) PrefixResult {
    const mask: u8 = 1 << bit;
    const result = operand & ~mask;

    return .{ result, flags };
}

/// Set the given bit to one
fn setBit(flags: Flags, comptime bit: u3, operand: u8) PrefixResult {
    const result = operand | (1 << bit);

    return .{ result, flags };
}

/// Set the carry flag to true (SCF)
fn setCarry(z80: *Z80) void {
    z80.flags = .{
        .was_zero = z80.flags.was_zero,
        .carried = true,
    };
}

/// Flip the carry flag (CCF)
fn invertCarry(z80: *Z80) void {
    z80.flags = .{
        .was_zero = z80.flags.was_zero,
        .carried = !z80.flags.carried,
    };
}

/// Pop a 16-bit value from the stack
fn pop(z80: *Z80, comptime high: []const u8, comptime low: []const u8) void {
    @field(z80.registers, low) = z80.readByte(z80.registers.stack_pointer);
    z80.registers.stack_pointer +%= 1;

    @field(z80.registers, high) = z80.readByte(z80.registers.stack_pointer);
    z80.registers.stack_pointer +%= 1;
}

/// Pop a 16 bit value from the stack to set flags
fn popAF(z80: *Z80) void {
    z80.flags = Flags.from(z80.readByte(z80.registers.stack_pointer));
    z80.registers.stack_pointer +%= 1;

    z80.registers.a = z80.readByte(z80.registers.stack_pointer);
    z80.registers.stack_pointer +%= 1;
}

/// Push a 16-bit value onto the stack
fn push(z80: *Z80, high: u8, low: u8) void {
    z80.registers.stack_pointer -%= 1;
    z80.writeByte(z80.registers.stack_pointer, high);

    z80.registers.stack_pointer -%= 1;
    z80.writeByte(z80.registers.stack_pointer, low);

    z80.clock.tick();
}

/// Set the program counter to the given address
fn jump(z80: *Z80, address: u16) void {
    z80.program_counter = address;
    z80.clock.tick();
}

fn jumpHL(z80: *Z80) void {
    z80.program_counter = z80.registers.hl();
}

/// Jump to address specified by the given offset
/// from the program counter
fn jumpRelative(z80: *Z80, offset: i8) void {
    const result, _, _ = addSigned(z80.program_counter, offset);

    z80.jump(result);
}

fn jumpIf(z80: *Z80, condition: bool, address: u16) void {
    if (condition) z80.jump(address);
}

fn jumpRelativeIf(z80: *Z80, condition: bool, offset: i8) void {
    if (condition) z80.jumpRelative(offset);
}

/// Call a subroutine
fn call(z80: *Z80, address: u16) void {
    const high, const low = from16(z80.program_counter);
    z80.push(high, low);
    z80.program_counter = address;
}

fn callIf(z80: *Z80, condition: bool, address: u16) void {
    if (condition) z80.call(address);
}

/// Return from a subroutine
fn @"return"(z80: *Z80) void {
    const low = z80.readByte(z80.registers.stack_pointer);
    z80.registers.stack_pointer +%= 1;

    const high = z80.readByte(z80.registers.stack_pointer);
    z80.registers.stack_pointer +%= 1;

    z80.program_counter = to16(high, low);

    z80.clock.tick();
}

fn returnIf(z80: *Z80, condition: bool) void {
    z80.clock.tick();

    if (condition) z80.@"return"();
}

/// (RETI)
fn returnAndEnableInterrupts(z80: *Z80) void {
    z80.@"return"();
    z80.interrupt_master_enable = true;
}

/// Enable interrupts after the next instruction (EI)
fn enableInterrupts(z80: *Z80) void {
    z80.set_interrupt_after_next_instruction = true;
}

/// Disable interrupts (DI)
fn disableInterrupts(z80: *Z80) void {
    z80.interrupt_master_enable = false;
}

inline fn to16(high: u8, low: u8) u16 {
    return (@as(u16, high) << 8) | low;
}

inline fn from16(value: u16) struct { u8, u8 } {
    const high: u8 = @truncate(value >> 8);
    const low: u8 = @truncate(value);

    return .{ high, low };
}

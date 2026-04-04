const std = @import("std");
const MMU = @import("mmu.zig");

const CPU = @This();

mmu: MMU,

registers: Registers = .{},

// Start at the cartridge's entry point
program_counter: u16 = 0x100,

flags: Flags = .{},

set_interrupt_after_next_instruction: bool = false,

interrupt_master_enable: bool = false,

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

pub fn init(mmu: MMU) CPU {
    return .{
        .mmu = mmu,
    };
}

pub fn step(cpu: *CPU) void {
    const set_interrupt = cpu.set_interrupt_after_next_instruction;
    cpu.set_interrupt_after_next_instruction = false;
    const opcode = cpu.readByte(cpu.program_counter);
    cpu.program_counter +%= 1;
    cpu.operate(opcode);
    if (set_interrupt) cpu.interrupt_master_enable = true;

    if (cpu.interrupt_master_enable) {
        cpu.handleInterrupt();
    }
}

fn tick(cpu: *CPU) void {
    cpu.mmu.tick();
}

fn operate(cpu: *CPU, opcode: u8) void {
    switch (opcode) {
        0x00 => {},

        0x01 => cpu.load16("b", "c"),
        0x11 => cpu.load16("d", "e"),
        0x21 => cpu.load16("h", "l"),
        0x31 => cpu.loadStackPointer(),
        0xF9 => cpu.loadHLIntoStackPointer(),

        0x02 => cpu.loadToMemory(cpu.registers.bc(), cpu.registers.a),
        0x08 => cpu.loadStackPointerInAddress(cpu.constant16()),
        0x0A => cpu.loadFromMemory(cpu.registers.bc()),
        0x12 => cpu.loadToMemory(cpu.registers.de(), cpu.registers.a),
        0x1A => cpu.loadFromMemory(cpu.registers.de()),
        0xEA => cpu.loadToMemory(cpu.constant16(), cpu.registers.a),
        0xFA => cpu.loadFromMemory(cpu.constant16()),
        0x22 => cpu.loadAIntoHLAndIncrement(),
        0x2A => cpu.loadAFromHLAndIncrement(),
        0x32 => cpu.loadAIntoHLAndDecrement(),
        0x3A => cpu.loadAFromHLAndDecrement(),

        0xE0 => cpu.loadToMemory(highAddress(cpu.constant8()), cpu.registers.a),
        0xE2 => cpu.loadToMemory(highAddress(cpu.registers.c), cpu.registers.a),
        0xF0 => cpu.loadFromMemory(highAddress(cpu.constant8())),
        0xF2 => cpu.loadFromMemory(highAddress(cpu.registers.c)),

        0x3C => cpu.increment("a"),
        0x04 => cpu.increment("b"),
        0x0C => cpu.increment("c"),
        0x14 => cpu.increment("d"),
        0x1C => cpu.increment("e"),
        0x24 => cpu.increment("h"),
        0x2C => cpu.increment("l"),
        0x34 => cpu.incrementHL(),
        0x03 => cpu.increment16("b", "c"),
        0x13 => cpu.increment16("d", "e"),
        0x23 => cpu.increment16("h", "l"),
        0x33 => cpu.incrementStackPointer(),

        0x3D => cpu.decrement("a"),
        0x05 => cpu.decrement("b"),
        0x0D => cpu.decrement("c"),
        0x15 => cpu.decrement("d"),
        0x1D => cpu.decrement("e"),
        0x25 => cpu.decrement("h"),
        0x2D => cpu.decrement("l"),
        0x35 => cpu.decrementHL(),
        0x0B => cpu.decrement16("b", "c"),
        0x1B => cpu.decrement16("d", "e"),
        0x2B => cpu.decrement16("h", "l"),
        0x3B => cpu.decrementStackPointer(),

        0x07 => cpu.rotateALeft(),
        0x0F => cpu.rotateARight(),
        0x17 => cpu.rotateALeftThroughCarry(),
        0x1F => cpu.rotateARightThroughCarry(),
        0x2F => cpu.not(),

        0x37 => cpu.setCarry(),
        0x3F => cpu.invertCarry(),

        0x09 => cpu.addToHL(cpu.registers.bc()),
        0x19 => cpu.addToHL(cpu.registers.de()),
        0x29 => cpu.addToHL(cpu.registers.hl()),
        0x39 => cpu.addToHL(cpu.registers.stack_pointer),

        0x78...0x7F, 0x3E => cpu.load8("a", cpu.operand8(opcode)),
        0x40...0x47, 0x06 => cpu.load8("b", cpu.operand8(opcode)),
        0x48...0x4F, 0x0E => cpu.load8("c", cpu.operand8(opcode)),
        0x50...0x57, 0x16 => cpu.load8("d", cpu.operand8(opcode)),
        0x58...0x5F, 0x1E => cpu.load8("e", cpu.operand8(opcode)),
        0x60...0x67, 0x26 => cpu.load8("h", cpu.operand8(opcode)),
        0x68...0x6F, 0x2E => cpu.load8("l", cpu.operand8(opcode)),
        0x70...0x75, 0x77, 0x36 => cpu.loadToMemory(cpu.registers.hl(), cpu.operand8(opcode)),

        0x10 => cpu.stop(),
        0x76 => cpu.halt(),

        0x27 => cpu.decimalAdjustAccumulator(),

        0x80...0x87, 0xC6 => cpu.add(cpu.operand8(opcode)),
        0x88...0x8F, 0xCE => cpu.addWithCarry(cpu.operand8(opcode)),
        0x90...0x97, 0xD6 => cpu.subtract(cpu.operand8(opcode)),
        0x98...0x9F, 0xDE => cpu.subtractWithCarry(cpu.operand8(opcode)),
        0xA0...0xA7, 0xE6 => cpu.@"and"(cpu.operand8(opcode)),
        0xA8...0xAF, 0xEE => cpu.xor(cpu.operand8(opcode)),
        0xB0...0xB7, 0xF6 => cpu.@"or"(cpu.operand8(opcode)),
        0xB8...0xBF, 0xFE => cpu.compare(cpu.operand8(opcode)),

        0xC1 => cpu.pop("b", "c"),
        0xD1 => cpu.pop("d", "e"),
        0xE1 => cpu.pop("h", "l"),
        0xF1 => cpu.popAF(),
        0xC5 => cpu.push(cpu.registers.b, cpu.registers.c),
        0xD5 => cpu.push(cpu.registers.d, cpu.registers.e),
        0xE5 => cpu.push(cpu.registers.h, cpu.registers.l),
        0xF5 => cpu.push(cpu.registers.a, cpu.flags.int()),

        0x18 => cpu.jumpRelative(cpu.signed8()),
        0x20 => cpu.jumpRelativeIf(!cpu.flags.was_zero, cpu.signed8()),
        0x28 => cpu.jumpRelativeIf(cpu.flags.was_zero, cpu.signed8()),
        0x30 => cpu.jumpRelativeIf(!cpu.flags.carried, cpu.signed8()),
        0x38 => cpu.jumpRelativeIf(cpu.flags.carried, cpu.signed8()),

        0xC3 => cpu.jump(cpu.constant16()),
        0xC2 => cpu.jumpIf(!cpu.flags.was_zero, cpu.constant16()),
        0xCA => cpu.jumpIf(cpu.flags.was_zero, cpu.constant16()),
        0xD2 => cpu.jumpIf(!cpu.flags.carried, cpu.constant16()),
        0xDA => cpu.jumpIf(cpu.flags.carried, cpu.constant16()),

        0xE9 => cpu.jumpHL(),

        0xCD => cpu.call(cpu.constant16()),
        0xC4 => cpu.callIf(!cpu.flags.was_zero, cpu.constant16()),
        0xCC => cpu.callIf(cpu.flags.was_zero, cpu.constant16()),
        0xD4 => cpu.callIf(!cpu.flags.carried, cpu.constant16()),
        0xDC => cpu.callIf(cpu.flags.carried, cpu.constant16()),

        0xC9 => cpu.@"return"(),
        0xC0 => cpu.returnIf(!cpu.flags.was_zero),
        0xC8 => cpu.returnIf(cpu.flags.was_zero),
        0xD0 => cpu.returnIf(!cpu.flags.carried),
        0xD8 => cpu.returnIf(cpu.flags.carried),

        // RST (restart) instructions
        0xC7 => cpu.call(0x00),
        0xCF => cpu.call(0x08),
        0xD7 => cpu.call(0x10),
        0xDF => cpu.call(0x18),
        0xE7 => cpu.call(0x20),
        0xEF => cpu.call(0x28),
        0xF7 => cpu.call(0x30),
        0xFF => cpu.call(0x38),

        0xE8 => cpu.addToStackPointer(cpu.signed8()),
        0xF8 => cpu.addToStackPointerAndLoad(cpu.signed8()),

        0xD9 => cpu.returnAndEnableInterrupts(),
        0xF3 => cpu.disableInterrupts(),
        0xFB => cpu.enableInterrupts(),

        0xCB => cpu.operatePrefixed(cpu.constant8()),

        // Undefined instructions
        0xD3, 0xDB, 0xDD, 0xE3, 0xE4, 0xEB, 0xEC, 0xED, 0xF4, 0xFC, 0xFD => {},
    }
}

fn operatePrefixed(cpu: *CPU, opcode: u8) void {
    const operand = cpu.operandPrefixed(opcode);

    const update, const flags = switch (opcode) {
        0x00...0x07 => rotateLeft(operand),
        0x08...0x0F => rotateRight(operand),
        0x10...0x17 => rotateLeftThroughCarry(cpu.flags, operand),
        0x18...0x1F => rotateRightThroughCarry(cpu.flags, operand),
        0x20...0x27 => shiftLeft(operand),
        0x28...0x2F => shiftRightArithmetically(operand),
        0x30...0x37 => swap(operand),
        0x38...0x3F => shiftRightLogically(operand),
        inline 0x40...0xFF => |code| bit: {
            const bit = comptime bitPrefixed(code);

            const high: u4 = @truncate(code >> 4);

            break :bit switch (high) {
                0x4...0x7 => checkBit(cpu.flags, bit, operand),
                0x8...0xB => zeroBit(cpu.flags, bit, operand),
                0xC...0xF => setBit(cpu.flags, bit, operand),

                else => unreachable,
            };
        },
    };

    if (update) |result| {
        cpu.setPrefixedResult(opcode, result);
    }
    cpu.flags = flags;
}

fn handleInterrupt(cpu: *CPU) void {
    const interrupt = cpu.mmu.currentInterrupt() orelse return;

    cpu.interrupt_master_enable = false;

    cpu.tick();
    cpu.tick();
    cpu.call(interrupt.address());
    cpu.mmu.clearInterrupt(interrupt);
}

fn writeByte(cpu: *CPU, address: u16, value: u8) void {
    cpu.tick();
    cpu.mmu.writeByte(address, value);
}

fn readByte(cpu: *CPU, address: u16) u8 {
    cpu.tick();
    return cpu.mmu.readByte(address);
}

fn operandPrefixed(cpu: *CPU, opcode: u8) u8 {
    // The lower nibble, repeated twice as there are 8
    return switch ((opcode & 0x0F) % 0x08) {
        0x7 => cpu.registers.a,
        0x0 => cpu.registers.b,
        0x1 => cpu.registers.c,
        0x2 => cpu.registers.d,
        0x3 => cpu.registers.e,
        0x4 => cpu.registers.h,
        0x5 => cpu.registers.l,
        0x6 => cpu.readByte(cpu.registers.hl()),
        else => unreachable,
    };
}

fn setPrefixedResult(cpu: *CPU, opcode: u8, result: u8) void {
    // The lower nibble, repeated twice as there are 8
    return switch ((opcode & 0x0F) % 0x08) {
        0x7 => cpu.registers.a = result,
        0x0 => cpu.registers.b = result,
        0x1 => cpu.registers.c = result,
        0x2 => cpu.registers.d = result,
        0x3 => cpu.registers.e = result,
        0x4 => cpu.registers.h = result,
        0x5 => cpu.registers.l = result,
        0x6 => cpu.writeByte(cpu.registers.hl(), result),
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
fn operand8(cpu: *CPU, opcode: u8) u8 {
    // The lower nibble, repeated twice as there are 8
    return switch ((opcode & 0x0F) % 0x08) {
        0x7 => cpu.registers.a,
        0x0 => cpu.registers.b,
        0x1 => cpu.registers.c,
        0x2 => cpu.registers.d,
        0x3 => cpu.registers.e,
        0x4 => cpu.registers.h,
        0x5 => cpu.registers.l,
        0x6 => switch (opcode) {
            0x40...0xBF => cpu.readByte(cpu.registers.hl()),
            else => cpu.constant8(),
        },
        else => unreachable,
    };
}

/// Get the 8 bit value at the program counter
fn constant8(cpu: *CPU) u8 {
    const value = cpu.readByte(cpu.program_counter);
    cpu.program_counter +%= 1;
    return value;
}

fn constant16(cpu: *CPU) u16 {
    const low = cpu.constant8();
    const high = cpu.constant8();

    return to16(high, low);
}

fn signed8(cpu: *CPU) i8 {
    return @bitCast(cpu.constant8());
}

inline fn highAddress(value: u8) u16 {
    return 0xFF00 + @as(u16, value);
}

/// TODO
fn halt(cpu: *CPU) void {
    cpu.tick();
    cpu.tick();
}

/// TODO
fn stop(cpu: *CPU) void {
    cpu.tick();
    cpu.tick();
}

/// Load the value into the given register
fn load8(cpu: *CPU, comptime register: []const u8, operand: u8) void {
    @field(cpu.registers, register) = operand;
}

/// Load the value into the byte pointed to by register
fn loadToMemory(cpu: *CPU, address: u16, operand: u8) void {
    cpu.writeByte(address, operand);
}

fn loadFromMemory(cpu: *CPU, address: u16) void {
    cpu.registers.a = cpu.readByte(address);
}

/// Load the lower half into address
/// and the higher half into address + 1
fn loadStackPointerInAddress(cpu: *CPU, address: u16) void {
    const low: u8 = @truncate(cpu.registers.stack_pointer);
    const high: u8 = @truncate(cpu.registers.stack_pointer >> 8);

    cpu.writeByte(address, low);
    cpu.writeByte(address +% 1, high);
}

/// Load the value into the given registers
fn load16(
    cpu: *CPU,
    comptime high: []const u8,
    comptime low: []const u8,
) void {
    @field(cpu.registers, low) = cpu.constant8();
    @field(cpu.registers, high) = cpu.constant8();
}

/// Load the value into the stack pointer
fn loadStackPointer(cpu: *CPU) void {
    cpu.registers.stack_pointer = cpu.constant16();
}

/// Load the value into the stack pointer
fn loadHLIntoStackPointer(cpu: *CPU) void {
    cpu.registers.stack_pointer = cpu.registers.hl();
    cpu.tick();
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

fn addToStackPointer(cpu: *CPU, operand: i8) void {
    const result, const carried, const half_carried = addSigned(
        cpu.registers.stack_pointer,
        operand,
    );

    cpu.registers.stack_pointer = result;

    cpu.flags = .{
        .carried = carried,
        .half_carried = half_carried,
    };

    cpu.tick();
    cpu.tick();
}

/// Add the signed integer with SP and store in HL
fn addToStackPointerAndLoad(cpu: *CPU, operand: i8) void {
    const result, const carried, const half_carried = addSigned(
        cpu.registers.stack_pointer,
        operand,
    );

    cpu.registers.h = @truncate(result >> 8);
    cpu.registers.l = @truncate(result);

    cpu.flags = .{
        .carried = carried,
        .half_carried = half_carried,
    };

    cpu.tick();
}

fn loadAIntoHLAndIncrement(cpu: *CPU) void {
    const address = cpu.registers.hl();
    cpu.writeByte(address, cpu.registers.a);

    const newAddress = address +% 1;

    cpu.registers.set_hl(newAddress);
}

fn loadAIntoHLAndDecrement(cpu: *CPU) void {
    const address = cpu.registers.hl();
    cpu.writeByte(address, cpu.registers.a);

    const newAddress = address -% 1;

    cpu.registers.set_hl(newAddress);
}

fn loadAFromHLAndIncrement(cpu: *CPU) void {
    const address = cpu.registers.hl();
    cpu.registers.a = cpu.readByte(address);

    const newAddress = address +% 1;

    cpu.registers.set_hl(newAddress);
}

fn loadAFromHLAndDecrement(cpu: *CPU) void {
    const address = cpu.registers.hl();
    cpu.registers.a = cpu.readByte(address);

    const newAddress = address -% 1;

    cpu.registers.set_hl(newAddress);
}

/// Increment the register by 1
fn increment(cpu: *CPU, comptime register: []const u8) void {
    const old = @field(cpu.registers, register);
    @field(cpu.registers, register) = old +% 1;

    cpu.flags = .{
        .half_carried = old & 0xF == 0b1111,
        .carried = cpu.flags.carried,
        .was_zero = @field(cpu.registers, register) == 0,
    };
}

fn incrementHL(cpu: *CPU) void {
    const address = cpu.registers.hl();
    const old = cpu.readByte(address);

    const new = old +% 1;

    cpu.flags = .{
        .half_carried = old & 0xF == 0b1111,
        .carried = cpu.flags.carried,
        .was_zero = new == 0,
    };

    cpu.writeByte(address, new);
}

/// Increment the 16 bit register by 1
fn increment16(
    cpu: *CPU,
    comptime high: []const u8,
    comptime low: []const u8,
) void {
    @field(cpu.registers, low), const overflowed = @addWithOverflow(@field(cpu.registers, low), 1);

    @field(cpu.registers, high) +%= overflowed;

    cpu.tick();
}

fn incrementStackPointer(cpu: *CPU) void {
    cpu.registers.stack_pointer +%= 1;
    cpu.tick();
}

/// Decrement the register by 1
fn decrement(cpu: *CPU, comptime register: []const u8) void {
    const old = @field(cpu.registers, register);
    @field(cpu.registers, register) = old -% 1;

    cpu.flags = .{
        .half_carried = old & 0xF == 0,
        .carried = cpu.flags.carried,
        .was_zero = @field(cpu.registers, register) == 0,
        .subtracted = true,
    };
}

fn decrementHL(cpu: *CPU) void {
    const address = cpu.registers.hl();
    const old = cpu.readByte(address);

    const new = old -% 1;

    cpu.flags = .{
        .half_carried = old & 0xF == 0,
        .carried = cpu.flags.carried,
        .was_zero = new == 0,
        .subtracted = true,
    };

    cpu.writeByte(address, new);
}

fn decrement16(
    cpu: *CPU,
    comptime high: []const u8,
    comptime low: []const u8,
) void {
    @field(cpu.registers, low), const underflowed = @subWithOverflow(@field(cpu.registers, low), 1);

    @field(cpu.registers, high) -%= underflowed;

    cpu.tick();
}

fn decrementStackPointer(cpu: *CPU) void {
    cpu.registers.stack_pointer -%= 1;
    cpu.tick();
}

/// Adjust result of arithmetic to be binary-coded decimal
fn decimalAdjustAccumulator(cpu: *CPU) void {
    if (cpu.flags.subtracted) {
        if (cpu.flags.half_carried) {
            cpu.registers.a -%= 0x6;
        }
        if (cpu.flags.carried) {
            cpu.registers.a -%= 0x60;
        }
    } else {
        const x = cpu.registers.a & 0xF > 0x9;
        const y = cpu.registers.a > 0x99;
        if (cpu.flags.half_carried or x) {
            cpu.registers.a +%= 0x6;
        }
        if (cpu.flags.carried or y) {
            cpu.registers.a +%= 0x60;
            cpu.flags.carried = true;
        }
    }

    cpu.flags.was_zero = cpu.registers.a == 0;
    cpu.flags.half_carried = false;
}

/// Add value to A
/// Put result in A
fn add(cpu: *CPU, operand: u8) void {
    const old = cpu.registers.a;
    cpu.registers.a, const overflowed = @addWithOverflow(cpu.registers.a, operand);

    cpu.flags = .{
        .was_zero = cpu.registers.a == 0,
        .half_carried = (operand & 0xF) + (old & 0xF) > 0b1111,
        .carried = overflowed != 0,
    };
}

/// Add value and carry flag to A
fn addWithCarry(cpu: *CPU, operand: u8) void {
    const carry: u1 = if (cpu.flags.carried) 1 else 0;
    const old = cpu.registers.a;
    cpu.registers.a, const overflowed = @addWithOverflow(cpu.registers.a, operand);
    cpu.registers.a, const carry_overflow = @addWithOverflow(cpu.registers.a, carry);

    cpu.flags = .{
        .was_zero = cpu.registers.a == 0,
        .half_carried = (operand & 0xF) + (old & 0xF) + carry > 0xF,
        .carried = overflowed != 0 or carry_overflow != 0,
    };
}

fn addToHL(
    cpu: *CPU,
    operand: u16,
) void {
    const old = cpu.registers.hl();
    const value, const overflowed = @addWithOverflow(old, operand);

    cpu.flags = .{
        .was_zero = cpu.flags.was_zero,
        .half_carried = (old & 0xFFF) + (operand & 0xFFF) > 0xFFF,
        .carried = overflowed != 0,
    };

    cpu.registers.h = @truncate(value >> 8);
    cpu.registers.l = @truncate(value);

    cpu.tick();
}

/// Subtract value from A
/// Put result in A
fn subtract(cpu: *CPU, operand: u8) void {
    const old = cpu.registers.a;
    cpu.registers.a -%= operand;

    cpu.flags = .{
        .subtracted = true,
        .was_zero = cpu.registers.a == 0,
        .carried = operand > old,
        .half_carried = (old & 0xF) < (operand & 0xF),
    };
}

/// Subtract value and carry flag from A
fn subtractWithCarry(cpu: *CPU, operand: u8) void {
    const carry: u1 = if (cpu.flags.carried) 1 else 0;
    const old = cpu.registers.a;
    cpu.registers.a -%= operand;
    cpu.registers.a -%= carry;

    cpu.flags = .{
        .subtracted = true,
        .was_zero = cpu.registers.a == 0,
        .carried = old < operand or (old - operand) < carry,
        .half_carried = (old & 0xF) < (operand & 0xF) + carry,
    };
}

/// Bitwise and the value with A
fn @"and"(cpu: *CPU, operand: u8) void {
    cpu.registers.a &= operand;

    cpu.flags = .{
        .half_carried = true,
        .was_zero = cpu.registers.a == 0,
    };
}

/// Bitwise or the value with A
fn @"or"(cpu: *CPU, operand: u8) void {
    cpu.registers.a |= operand;

    cpu.flags = .{
        .was_zero = cpu.registers.a == 0,
    };
}

/// Bitwise xor the value with A
fn xor(cpu: *CPU, operand: u8) void {
    cpu.registers.a ^= operand;

    cpu.flags = .{
        .was_zero = cpu.registers.a == 0,
    };
}

/// Bitwise not of A (CPL)
fn not(cpu: *CPU) void {
    cpu.registers.a = ~cpu.registers.a;
    cpu.flags.subtracted = true;
    cpu.flags.half_carried = true;
}

/// Compare value to A
/// If equal, flag zero
/// If register > A, flag carry
fn compare(cpu: *CPU, operand: u8) void {
    const old = cpu.registers.a;
    const result, const underflowed = @subWithOverflow(cpu.registers.a, operand);

    cpu.flags = .{
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
fn rotateALeft(cpu: *CPU) void {
    cpu.registers.a, const overflowed = @shlWithOverflow(cpu.registers.a, 1);

    cpu.registers.a += overflowed;

    cpu.flags = .{ .carried = overflowed != 0 };
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
fn rotateALeftThroughCarry(cpu: *CPU) void {
    cpu.registers.a, const overflowed = @shlWithOverflow(cpu.registers.a, 1);

    cpu.registers.a += if (cpu.flags.carried) 1 else 0;

    cpu.flags = .{
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
fn rotateARight(cpu: *CPU) void {
    const lowestBit: u8 = cpu.registers.a & 1;

    cpu.registers.a >>= 1;

    cpu.registers.a |= lowestBit << 7;

    cpu.flags = .{ .carried = lowestBit != 0 };
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
fn rotateARightThroughCarry(cpu: *CPU) void {
    const lowestBit = cpu.registers.a & 1;

    cpu.registers.a >>= 1;

    const carry_bit: u8 = if (cpu.flags.carried) 1 else 0;

    cpu.registers.a |= carry_bit << 7;

    cpu.flags = .{ .carried = lowestBit != 0 };
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
fn setCarry(cpu: *CPU) void {
    cpu.flags = .{
        .was_zero = cpu.flags.was_zero,
        .carried = true,
    };
}

/// Flip the carry flag (CCF)
fn invertCarry(cpu: *CPU) void {
    cpu.flags = .{
        .was_zero = cpu.flags.was_zero,
        .carried = !cpu.flags.carried,
    };
}

/// Pop a 16-bit value from the stack
fn pop(cpu: *CPU, comptime high: []const u8, comptime low: []const u8) void {
    @field(cpu.registers, low) = cpu.readByte(cpu.registers.stack_pointer);
    cpu.registers.stack_pointer +%= 1;

    @field(cpu.registers, high) = cpu.readByte(cpu.registers.stack_pointer);
    cpu.registers.stack_pointer +%= 1;
}

/// Pop a 16 bit value from the stack to set flags
fn popAF(cpu: *CPU) void {
    cpu.flags = Flags.from(cpu.readByte(cpu.registers.stack_pointer));
    cpu.registers.stack_pointer +%= 1;

    cpu.registers.a = cpu.readByte(cpu.registers.stack_pointer);
    cpu.registers.stack_pointer +%= 1;
}

/// Push a 16-bit value onto the stack
fn push(cpu: *CPU, high: u8, low: u8) void {
    cpu.registers.stack_pointer -%= 1;
    cpu.writeByte(cpu.registers.stack_pointer, high);

    cpu.registers.stack_pointer -%= 1;
    cpu.writeByte(cpu.registers.stack_pointer, low);

    cpu.tick();
}

/// Set the program counter to the given address
fn jump(cpu: *CPU, address: u16) void {
    cpu.program_counter = address;
    cpu.tick();
}

fn jumpHL(cpu: *CPU) void {
    cpu.program_counter = cpu.registers.hl();
}

/// Jump to address specified by the given offset
/// from the program counter
fn jumpRelative(cpu: *CPU, offset: i8) void {
    const result, _, _ = addSigned(cpu.program_counter, offset);

    cpu.jump(result);
}

fn jumpIf(cpu: *CPU, condition: bool, address: u16) void {
    if (condition) cpu.jump(address);
}

fn jumpRelativeIf(cpu: *CPU, condition: bool, offset: i8) void {
    if (condition) cpu.jumpRelative(offset);
}

/// Call a subroutine
fn call(cpu: *CPU, address: u16) void {
    const high, const low = from16(cpu.program_counter);
    cpu.push(high, low);
    cpu.program_counter = address;
}

fn callIf(cpu: *CPU, condition: bool, address: u16) void {
    if (condition) cpu.call(address);
}

/// Return from a subroutine
fn @"return"(cpu: *CPU) void {
    const low = cpu.readByte(cpu.registers.stack_pointer);
    cpu.registers.stack_pointer +%= 1;

    const high = cpu.readByte(cpu.registers.stack_pointer);
    cpu.registers.stack_pointer +%= 1;

    cpu.program_counter = to16(high, low);

    cpu.tick();
}

fn returnIf(cpu: *CPU, condition: bool) void {
    cpu.tick();

    if (condition) cpu.@"return"();
}

/// (RETI)
fn returnAndEnableInterrupts(cpu: *CPU) void {
    cpu.@"return"();
    cpu.interrupt_master_enable = true;
}

/// Enable interrupts after the next instruction (EI)
fn enableInterrupts(cpu: *CPU) void {
    cpu.set_interrupt_after_next_instruction = true;
}

/// Disable interrupts (DI)
fn disableInterrupts(cpu: *CPU) void {
    cpu.interrupt_master_enable = false;
}

inline fn to16(high: u8, low: u8) u16 {
    return (@as(u16, high) << 8) | low;
}

inline fn from16(value: u16) struct { u8, u8 } {
    const high: u8 = @truncate(value >> 8);
    const low: u8 = @truncate(value);

    return .{ high, low };
}

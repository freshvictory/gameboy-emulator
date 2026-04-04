const Interrupts = @This();

enabled: Status = .{},
active: Status = .{},

pub fn enable(self: *Interrupts, value: u8) void {
    self.enabled = .from(value);
}

pub fn activate(self: *Interrupts, value: u8) void {
    self.active = .from(value);
}

pub fn current(self: Interrupts) ?Interrupt {
    return self.active.mask(self.enabled).current();
}

pub fn raise(self: *Interrupts, interrupt: Interrupt) void {
    self.active.raise(interrupt);
}

pub fn clear(self: *Interrupts, interrupt: Interrupt) void {
    self.active.clear(interrupt);
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

pub const Status = packed struct(u5) {
    v_blank: bool = false,
    lcd: bool = false,
    timer: bool = false,
    serial: bool = false,
    joypad: bool = false,

    /// The highest priority interrupt currently set
    pub fn current(self: Status) ?Interrupt {
        if (self.v_blank) return .v_blank;
        if (self.lcd) return .lcd;
        if (self.timer) return .timer;
        if (self.serial) return .serial;
        if (self.joypad) return .joypad;

        return null;
    }

    /// Only enable interrupts that are also enabled in the mask.
    pub fn mask(self: Status, enabled: Status) Status {
        return Status.from(self.int() & enabled.int());
    }

    pub fn raise(self: *Status, interrupt: Interrupt) void {
        switch (interrupt) {
            inline else => |i| @field(self, @tagName(i)) = true,
        }
    }

    pub fn clear(self: *Status, interrupt: Interrupt) void {
        switch (interrupt) {
            inline else => |i| @field(self, @tagName(i)) = false,
        }
    }

    pub inline fn from(value: u8) Status {
        const v: u5 = @truncate(value);
        return @bitCast(v);
    }

    pub inline fn int(self: Status) u8 {
        const value: u5 = @bitCast(self);
        return value;
    }
};

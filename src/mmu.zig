const MMU = @This();

buffer: [0x10000]u8 = [_]u8{0} ** 0x10000,

pub fn init() MMU {
    return .{};
}

pub fn readByte(mmu: MMU, address: u16) u8 {
    return mmu.buffer[address];
}

pub fn writeByte(mmu: *MMU, address: u16, value: u8) void {
    mmu.buffer[address] = value;
}

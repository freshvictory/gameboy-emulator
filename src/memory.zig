const Memory = @This();

ptr: *anyopaque,
vtable: *const VTable,

const VTable = struct {
    readByte: *const fn (*anyopaque, address: u16) u8,

    writeByte: *const fn (*anyopaque, address: u16, value: u8) void,
};

pub fn readByte(memory: Memory, address: u16) u8 {
    return memory.vtable.readByte(memory.ptr, address);
}

pub fn writeByte(memory: *Memory, address: u16, value: u8) void {
    memory.vtable.writeByte(memory.ptr, address, value);
}

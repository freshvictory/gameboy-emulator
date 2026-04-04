const std = @import("std");

const Cartridge = @This();

entry: [4]u8,

title: [15]u8,

sgb_support: bool,

type_: CartridgeType,

contents: []u8,

pub fn init(contents: []u8) Cartridge {
    return .{
        .entry = contents[0x100..0x104].*,
        .title = contents[0x134..0x143].*,
        .sgb_support = contents[0x146] == 0x03,
        .type_ = @enumFromInt(contents[0x147]),
        .contents = contents,
    };
}

pub fn readByte(cartridge: Cartridge, address: u16) u8 {
    return cartridge.contents[address];
}

pub fn writeByte(cartridge: Cartridge, address: u16, value: u8) void {
    cartridge.contents[address] = value;
}

const CartridgeType = enum(u8) {
    rom_only = 0x00,
    mbc1 = 0x01,
    mbc1_ram = 0x02,
    mbc1_ram_battery = 0x03,
    mbc2 = 0x04,
    mbc2_battery = 0x06,
    rom_ram = 0x08,
    rom_ram_battery = 0x09,
    mmm01 = 0x0B,
    mmm01_ram = 0x0C,
    mmm01_ram_battery = 0x0D,
    mbc3_timer_battery = 0x0F,
    mbc3_timer_ram_battery = 0x10,
    mbc3 = 0x11,
    mbc3_ram = 0x12,
    mbc3_ram_battery = 0x13,
    mbc5 = 0x19,
    mbc5_ram = 0x1A,
    mbc5_ram_battery = 0x1B,
    mbc5_rumble = 0x1C,
    mbc5_rumble_ram = 0x1D,
    mbc5_rumble_ram_battery = 0x1E,
    mbc6 = 0x20,
    mbc7_sensor_rumble_ram_battery = 0x22,
    pocket_camera = 0xFC,
    bandai_tama5 = 0xFD,
    huc3 = 0xFE,
    huc1_ram_battery = 0xFF,
};

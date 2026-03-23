const std = @import("std");
const gameboy = @import("gameboy");

pub fn main() !void {
    // Prints to stderr, ignoring potential errors.
    std.debug.print("Hello!\n", .{});
    try gameboy.bufferedPrint();
}

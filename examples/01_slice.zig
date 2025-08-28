const std = @import("std");
const Irc = @import("irc").Irc;

pub fn main() !void {
    // Boilerplate, set up allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a slice of 5 u8-s, notice that the init
    // takes a length argument
    const slice = try Irc(.Slice, u8, .{}).init(allocator, 5);
    defer slice.deinit(allocator); // This line frees memory

    // Retain to increase reference count (0 at start)
    try slice.retain();

    // Do stuff with slice
    @memcpy(slice.items, "12345");
    std.debug.print("This slice contains: {s}\n", .{slice.items});

    // release to decrease reference count (does not free at 0)
    slice.release();
}

const std = @import("std");
const Irc = @import("irc").Irc;

pub fn main() !void {
    // Boilerplate, set up allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Init a pointer-to-one
    const ptr = try Irc(.one, u128, .{ .Counter = u8 }).init(allocator);
    //                                  |_ The reference count type can be changed it
    //                                     must, however, be an unsigned integer type

    // You can add to the reference count by calling `retain`.
    // This could return an error since the reference count could
    // overflow, kind of like an allocator returning `error.OutOfMemory`
    // (the returned error is `error.Overflow` though)
    try ptr.retain();

    // This call triggers a panic since the reference count is not zero.
    // You should not free a non-dangling pointer since it is still used
    // somewhere else.
    // ptr.deinit(allocator);

    // This releases the pointer and decrements the reference count
    // calling release more times than retain (corresponds to negative
    // reference count) is undefined behaviour
    ptr.release() catch |err| {
        std.debug.print("If this prints the reference count hit 0: {}\n", .{err});
        ptr.deinit(allocator);
    };

    // Release and then maybe deinit can be combined into one function call:
    // ptr.releaseDeinitDangling();
}

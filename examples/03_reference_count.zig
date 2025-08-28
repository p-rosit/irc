const std = @import("std");
const Irc = @import("irc").Irc;

pub fn main() !void {
    // Boilerplate, set up allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Init a pointer-to-one
    const ptr = try Irc(.One, u128, .{}).init(allocator);

    // The reference count cannot be accessed directly.
    // Instead you are only able to ask whether the reference
    // count is zero or not with `dangling`.
    //
    // It will start out with a reference count of zero which
    // means that this will print `true`
    std.debug.print("The pointer is dangling after init. dangling={}\n", .{ptr.dangling()});

    // You can add to the reference count by calling `retain`.
    // This could return an error since the reference count could
    // overflow, kind of like an allocator returning `error.OutOfMemory`
    try ptr.retain();

    // Since we called `retain` the pointer is no longer dangling:
    std.debug.print("The pointer is no longer dangling.  dangling={}\n", .{ptr.dangling()});

    // This call would trigger an assert in a Debug or ReleaseSafe build
    // since the reference count is not zero. You should not free a non-dangling
    // pointer since it is still used somewhere else.
    // ptr.deinit(allocator);

    // This releases the pointer and decrements the reference count
    // calling release more times than retain (corresponds to negative
    // reference count) is undefined behaviour
    ptr.release();

    // Now the pointer is dangling again since we `release`d it
    std.debug.print("The pointer is now dangling.        dangling={}\n", .{ptr.dangling()});

    // you might not want to release the pointer if the
    // reference count has hit zero:
    if (ptr.dangling()) {
        ptr.deinit(allocator);
    }

    // Release and then maybe deinit can be combined into one function call:
    // ptr.releaseDeinitDangling();
}

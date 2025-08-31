const std = @import("std");
const Irc = @import("irc").Irc;

pub fn main() !void {
    // Boilerplate, set up allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a pointer-to-one, notice that the init
    // does __not__ take a length argument
    const ptr = try Irc(.One, u8, .{}).init(allocator);
    defer ptr.deinit(allocator); // This frees the memory

    // Retain to increase reference count (0 at start)
    try ptr.retain();

    // Do stuff with pointer
    ptr.items.* = 5;
    std.debug.print("This pointer contains: {}\n", .{ptr.items.*});

    // release to decrease reference count returns `error.Dangling` at 0
    ptr.release() catch {
        // Here we could conditionally `deinit` to free the memory
        // but we're already unconditionally freeing with the
        // `defer slice.deinit` above
    };
}

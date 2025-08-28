const std = @import("std");
const Irc = @import("irc").Irc;

pub fn main() !void {
    // Boilerplate, set up allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Init a pointer-to-one
    const ptr = try Irc(.One, u128, .{}).init(allocator);

    // Pointer can be cast, to see options see `IrcConfig`
    const cast_ptr = ptr.cast(Irc(.One, u128, .{ .is_const = true }));
    defer cast_ptr.deinit(allocator);

    std.debug.print(
        "Original type: {}, Cast type: {}\n",
        .{ @TypeOf(ptr.items), @TypeOf(cast_ptr.items) },
    );

    // The above mimics `@ptrCast` but one might also need
    // to use `@constCast` or `@alignCast`. Here's the mapping:
    //
    //      @ptrCast     -> .cast
    //      @constCast   -> .constCast
    //      @alignCast   -> .alignCast
}

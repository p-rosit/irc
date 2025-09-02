const std = @import("std");
const Irc = @import("irc").Irc;

pub fn main() !void {
    // Boilerplate, set up allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Init a pointer-to-one
    const ptr = try Irc(.one, u128, .{}).init(allocator);

    // Not a compilation error since we have a pointer
    // that does not point to const
    ptr.items.* = 0;

    // Pointer can be cast, to see options see `IrcConfig`
    const cast_ptr = ptr.cast(Irc(.one, u128, .{ .is_const = true }));
    defer cast_ptr.deinit(allocator);

    // Compilation error since we cannot assign the
    // pointed value of pointer-to-const
    // cast_ptr.items.* = 5;

    std.debug.print("Stored value: {}\n", .{cast_ptr.items.*});
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

    // !IMPORTANT!  casting to a lower alignment will make you unable to free
    //              the Irc due to the reference count being stored in front
    //              of the actual pointer data. An Irc must be `deinit`ed
    //              with the same alignment it was `init`ed, see `05_align_cast.zig`
}

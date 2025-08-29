const std = @import("std");
const Irc = @import("irc").Irc;

pub fn main() !void {
    // Boilerplate, set up allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Init a slice, the reference count is stored in front of the pointer.
    // Here is an example where we allocate a slice with the natural alignment
    // of the data:
    //
    //      @sizeOf(Data)       = 4
    //      @alignOf(Data)      = 4
    //      @sizeOf(Counter)    = 2
    //      @alignOf(Counter)   = 2
    //
    //      _ _ c c | d d d d | d d d d | ...
    //          |     |         |
    //          |     |         |_ start of the second element
    //          |     |_ start of the first elemnet
    //          |_ start of the reference count
    //
    // If we instead require an alignment of 8 on the pointer we would instead
    // allocate the following:
    //
    //      _ _ _ _ _ _ c c | d d d d | d d d d | ...
    //
    // Hopefully this makes it clear that the alignment must be known to be
    // able to free the pointer correctly since the only thing that the Irc
    // keeps track of is the start of the elements
    const ptr = try Irc(.Slice, u128, .{ .alignment = 64 }).init(allocator, 10);

    // Cast to lower alignment
    const cast_ptr = ptr.cast(Irc(.Slice, u128, .{ .alignment = 32 }));

    // This would trigger a panic in `Debug` and `ReleaseSafe` the Irc
    // must be freed with the same alignment it was allocated with
    // cast_ptr.deinit(allocator);

    const real_alignment_ptr = cast_ptr.alignCast(Irc(.Slice, u128, .{ .alignment = 64 }));
    std.debug.print(
        "Types are:\n\t{}\n\t{}\n\t{}\n",
        .{
            @TypeOf(ptr.items),
            @TypeOf(cast_ptr.items),
            @TypeOf(real_alignment_ptr.items),
        },
    );

    real_alignment_ptr.deinit(allocator);
}

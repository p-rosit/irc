const std = @import("std");
const Irc = @import("irc").Irc;

pub fn main() !void {
    // Boilerplate, set up allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Init a slice
    const ptr = try Irc(.Slice, u128, .{ .alignment = 64 }).init(allocator, 10);

    // Cast to lower alignment
    const cast_ptr = ptr.cast(Irc(.Slice, u128, .{ .alignment = 32 }));

    // This would trigger a panic in `Debug` and `ReleaseSafe` the Irc
    // must be freed with the same alignment it was allocated with
    // cast_ptr.deinit(allocator);

    const real_alignment_ptr = cast_ptr.alignCast(Irc(.Slice, u128, .{ .alignment = 64 }));
    real_alignment_ptr.deinit(allocator);
}

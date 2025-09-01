const std = @import("std");
const Irc = @import("irc").Irc;

pub fn main() !void {
    // Boilerplate, set up allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const slice = try Irc(.Slice, u8, .{ .atomic = true }).init(allocator, 5);
    //                                    |_ The reference count is now only ever atomically modified
    defer slice.deinit(allocator);

    try slice.retain();

    // Do stuff with slice
    @memcpy(slice.items, "12345");
    std.debug.print(
        \\The reference count can be set to be atomic, i.e. the
        \\Irc can be shared in multiple threads. By default it
        \\is not atomic:
        \\
        \\      default:  atomic={}
        \\      this one: atomic={}
        \\
        \\if a type has an atomic counter it cannot be cast away
        \\and vice versa.
        \\
    ,
        .{ Irc(.Slice, u8, .{}).config.atomic, @TypeOf(slice).config.atomic },
    );

    slice.release() catch {
        // The deinit is taken care of right by the allocation in this case
        // so we don't need to deinit here.
    };
}

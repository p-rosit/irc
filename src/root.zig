const std = @import("std");

pub const IrcConfig = struct {
    counter: type = usize,
};

pub fn IrcSlice(T: type, cfg: IrcConfig) type {
    return struct {
        const Self = @This();
        const ref_count_size = @max(@sizeOf(cfg.counter), @alignOf(T));
        const alignment = @max(@alignOf(cfg.counter), @alignOf(T));

        items: []T,

        pub fn init(allocator: std.mem.Allocator, size: usize) !Self {
            _ = .{ allocator, size };
            unreachable;
        }

        pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
            allocator.free(self.items);
        }
    };
}

test "just make type" {
    _ = IrcSlice(u128, .{});
    _ = IrcSlice(struct { v1: u8, v2: u8, v3: u8 }, .{});
}

test "init and deinit" {
    const a = try IrcSlice(u128, .{}).init(std.testing.allocator, 7);
    defer a.deinit(std.testing.allocator);

    const b = try IrcSlice(struct { v1: u8, v2: u8, v3: u8 }, .{}).init(std.testing.allocator, 7);
    defer b.deinit(std.testing.allocator);
}

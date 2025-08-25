const std = @import("std");

pub const IrcConfig = struct {
    counter: type = usize,
};

pub fn IrcSlice(T: type, cfg: IrcConfig) type {
    comptime std.debug.assert(std.mem.byte_size_in_bits == 8);
    return struct {
        const Self = @This();
        const ref_count_size = @max(@sizeOf(cfg.counter), @alignOf(T));
        const alignment = @max(@alignOf(cfg.counter), @alignOf(T));

        items: []T,

        pub fn init(allocator: std.mem.Allocator, size: usize) !Self {
            const slice_size = std.math.mul(
                usize,
                size,
                @sizeOf(T),
            ) catch return error.OutOfMemory;
            const total_size = std.math.add(
                usize,
                Self.ref_count_size,
                slice_size,
            ) catch return error.OutOfMemory;

            const b = try allocator.alignedAlloc(
                u8,
                Self.alignment,
                total_size,
            );

            const self: Self = .{
                .items = bytesAsSliceCast(T, b[Self.alignment..]),
            };

            return self;
        }

        pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
            allocator.free(self.bytes());
        }

        // This function from `std.mem` has been duplicated since we need
        // to be able to give it slices of length 0 which still contain
        // a valid pointer. Currently there's a special case for empty
        // slices which breaks our code if used
        fn bytesAsSliceCast(S: type, bytes_slice: anytype) CopyPtrAttrs(@TypeOf(bytes_slice), .Slice, S) {
            const cast_target = CopyPtrAttrs(@TypeOf(bytes_slice), .Many, S);
            return @as(cast_target, @ptrCast(bytes_slice))[0..@divExact(bytes_slice.len, @sizeOf(S))];
        }

        fn bytes(self: Self) []align(Self.alignment) u8 {
            const val = @intFromPtr(self.items.ptr) - Self.alignment;
            return @as(
                *[]align(Self.alignment) u8,
                @alignCast(@ptrCast(@constCast(&.{
                    .ptr = @as([*]u8, @ptrFromInt(val)),
                    .len = Self.ref_count_size + self.items.len * @sizeOf(T),
                }))),
            ).*;
        }
    };
}

// This function from `std.mem` must be duplicated because it is
// not marked pub. It is however needed to implement `bytesAsSlice`
fn CopyPtrAttrs(source: type, size: std.builtin.Type.Pointer.Size, child: type) type {
    const info = @typeInfo(source).Pointer;
    return @Type(.{
        .Pointer = .{
            .size = size,
            .is_const = info.is_const,
            .is_volatile = info.is_volatile,
            .is_allowzero = info.is_allowzero,
            .alignment = info.alignment,
            .address_space = info.address_space,
            .child = child,
            .sentinel = null,
        },
    });
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

test "init and deinit empty" {
    const a = try IrcSlice(u128, .{}).init(std.testing.allocator, 0);
    defer a.deinit(std.testing.allocator);

    const b = try IrcSlice(struct { v1: u8, v2: u8, v3: u8 }, .{}).init(std.testing.allocator, 0);
    defer b.deinit(std.testing.allocator);
}

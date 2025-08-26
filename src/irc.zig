const std = @import("std");

pub const IrcConfig = struct {
    Counter: type = usize,
    alignment: ?u16 = null,
};

pub fn IrcSlice(T: type, cfg: IrcConfig) type {
    comptime try std.testing.expectEqual(8, std.mem.byte_size_in_bits);
    const ref_count_size = @as(usize, @max(
        @sizeOf(cfg.Counter),
        cfg.alignment orelse @alignOf(T),
    ));
    const alignment = @as(usize, @max(
        @alignOf(cfg.Counter),
        cfg.alignment orelse @alignOf(T),
    ));

    switch (@typeInfo(cfg.Counter)) {
        .Int => |int| {
            if (int.signedness != .unsigned) {
                @compileError("Reference counter type must be unsigned");
            }
        },
        else => {
            @compileError("Reference counter type must be an unsigned integer");
        },
    }

    return struct {
        const Self = @This();

        items: []align(cfg.alignment orelse @alignOf(T)) T,

        pub fn init(allocator: std.mem.Allocator, size: usize) !Self {
            const slice_size = std.math.mul(
                usize,
                size,
                @sizeOf(T),
            ) catch return error.OutOfMemory;
            const total_size = std.math.add(
                usize,
                ref_count_size,
                slice_size,
            ) catch return error.OutOfMemory;

            const b = try allocator.alignedAlloc(
                u8,
                alignment,
                total_size,
            );
            std.debug.assert(@intFromPtr(b.ptr) < std.math.maxInt(usize) - alignment);

            const self: Self = .{
                .items = bytesAsSliceCast(T, b[alignment..]),
            };
            self.refCountPtr().* = 0;

            return self;
        }

        pub fn releaseDeinit(self: Self, allocator: std.mem.Allocator) void {
            self.release();
            if (self.dangling()) {
                self.deinit(allocator);
            }
        }

        pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
            std.debug.assert(self.dangling());
            allocator.free(self.bytes());
        }

        pub fn dangling(self: Self) bool {
            return self.refCountPtr().* == 0;
        }

        pub fn retain(self: Self) !void {
            self.refCountPtr().* = try std.math.add(cfg.Counter, self.refCountPtr().*, 1);
        }

        pub fn release(self: Self) void {
            std.debug.assert(self.refCountPtr().* > 0);
            self.refCountPtr().* -= 1;
        }

        pub fn cast(self: Self, IrcType: type) IrcType {
            comptime Self.isIrcType(IrcType);
            return .{ .items = @ptrCast(self.items) };
        }

        // This function from `std.mem` has been duplicated since we need
        // to be able to give it slices of length 0 which still contain
        // a valid pointer. Currently there's a special case for empty
        // slices which breaks our code if used
        fn bytesAsSliceCast(S: type, bytes_slice: anytype) CopyPtrAttrs(@TypeOf(bytes_slice), .Slice, S) {
            const cast_target = CopyPtrAttrs(@TypeOf(bytes_slice), .Many, S);
            return @as(cast_target, @ptrCast(bytes_slice))[0..@divExact(bytes_slice.len, @sizeOf(S))];
        }

        fn bytes(self: Self) []align(alignment) u8 {
            return @as(
                [*]align(alignment) u8,
                @ptrFromInt(@intFromPtr(self.items.ptr) - alignment),
            )[0 .. ref_count_size + self.items.len * @sizeOf(T)];
        }

        fn refCountPtr(self: Self) *cfg.Counter {
            const end = ref_count_size;
            const start = end - @sizeOf(cfg.Counter);
            return std.mem.bytesAsValue(cfg.Counter, self.bytes()[start..end]);
        }

        fn isIrcType(IrcType: type) void {
            const irc_info = @typeInfo(IrcType);
            switch (irc_info) {
                .Struct => {},
                else => {
                    @compileError("Not an Irc type, expected a struct");
                },
            }

            var found: bool = false;
            const field_items = "items";
            comptime for (irc_info.Struct.fields) |field| {
                found = found or std.mem.eql(u8, field_items, field.name);
            };
            if (!found) {
                @compileError("Not an Irc type, expected field named 'items'");
            }

            const methods = [_][]const u8{
                "init",
                "deinit",
                "releaseDeinit",
                "dangling",
                "retain",
                "release",
                "cast",
            };
            comptime for (methods) |method| {
                if (!std.meta.hasFn(IrcType, method)) {
                    @compileError("Not an Irc type, missing method '" ++ method ++ "'");
                }
            };

            // Type passes sanity checks...
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

const TestType = struct { v1: u8, v2: u8, v3: u8 };

test "just make type" {
    _ = IrcSlice(u128, .{});
    _ = IrcSlice(TestType, .{});
    comptime std.debug.assert(@alignOf(TestType) < @sizeOf(TestType));
}

test "init and deinit" {
    const a = try IrcSlice(u128, .{}).init(std.testing.allocator, 7);
    defer a.deinit(std.testing.allocator);

    const b = try IrcSlice(TestType, .{}).init(std.testing.allocator, 7);
    defer b.deinit(std.testing.allocator);
}

test "init and deinit empty" {
    const a = try IrcSlice(u128, .{}).init(std.testing.allocator, 0);
    defer a.deinit(std.testing.allocator);

    const b = try IrcSlice(TestType, .{}).init(std.testing.allocator, 0);
    defer b.deinit(std.testing.allocator);
}

test "deinit and maybe release" {
    const a = try IrcSlice(u128, .{}).init(std.testing.allocator, 0);

    try a.retain();
    try a.retain();
    a.releaseDeinit(std.testing.allocator);
    a.releaseDeinit(std.testing.allocator);
}

test "allocation failure" {
    var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    const err = IrcSlice(u8, .{}).init(failing_allocator.allocator(), 3);
    try std.testing.expectError(error.OutOfMemory, err);
}

test "only one allocation" {
    var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    const a = try IrcSlice(u8, .{}).init(failing_allocator.allocator(), 3);
    a.deinit(std.testing.allocator);
}

test "slice size multiplication too big" {
    const err = IrcSlice(struct { v1: u8, v2: u8 }, .{}).init(std.testing.allocator, std.math.maxInt(usize) / 2 + 1);
    try std.testing.expectError(error.OutOfMemory, err);
}

test "slice cannot also fit reference count" {
    comptime std.debug.assert(@sizeOf(usize) > @sizeOf(u8));
    const err = IrcSlice(u8, .{}).init(std.testing.allocator, std.math.maxInt(usize) - 1);
    try std.testing.expectError(error.OutOfMemory, err);
}

test "release and retain" {
    const a = try IrcSlice(u128, .{}).init(std.testing.allocator, 5);
    defer a.deinit(std.testing.allocator);
    @memset(a.items, 0);
    try std.testing.expectEqual(0, a.refCountPtr().*);
    try std.testing.expect(a.dangling());

    try a.retain();
    @memset(a.items, 0);
    try std.testing.expectEqual(1, a.refCountPtr().*);
    try std.testing.expect(!a.dangling());

    a.release();
    @memset(a.items, 0);
    try std.testing.expectEqual(0, a.refCountPtr().*);
    try std.testing.expect(a.dangling());

    const b = try IrcSlice(TestType, .{}).init(std.testing.allocator, 5);
    defer b.deinit(std.testing.allocator);
    @memset(b.items, .{ .v1 = 0, .v2 = 0, .v3 = 0 });
    try std.testing.expectEqual(0, b.refCountPtr().*);
    try std.testing.expect(b.dangling());

    try b.retain();
    @memset(b.items, .{ .v1 = 0, .v2 = 0, .v3 = 0 });
    try std.testing.expectEqual(1, b.refCountPtr().*);
    try std.testing.expect(!b.dangling());

    b.release();
    @memset(b.items, .{ .v1 = 0, .v2 = 0, .v3 = 0 });
    try std.testing.expectEqual(0, b.refCountPtr().*);
    try std.testing.expect(b.dangling());
}

test "release and retain empty" {
    const a = try IrcSlice(u128, .{}).init(std.testing.allocator, 0);
    defer a.deinit(std.testing.allocator);
    try std.testing.expectEqual(0, a.refCountPtr().*);
    try std.testing.expect(a.dangling());

    try a.retain();
    try std.testing.expectEqual(1, a.refCountPtr().*);
    try std.testing.expect(!a.dangling());

    a.release();
    try std.testing.expectEqual(0, a.refCountPtr().*);
    try std.testing.expect(a.dangling());

    const b = try IrcSlice(TestType, .{}).init(std.testing.allocator, 0);
    defer b.deinit(std.testing.allocator);
    try std.testing.expectEqual(0, b.refCountPtr().*);
    try std.testing.expect(b.dangling());

    try b.retain();
    try std.testing.expectEqual(1, b.refCountPtr().*);
    try std.testing.expect(!b.dangling());

    b.release();
    try std.testing.expectEqual(0, b.refCountPtr().*);
    try std.testing.expect(b.dangling());
}

test "retain overflow" {
    const a = try IrcSlice(u128, .{ .Counter = usize }).init(std.testing.allocator, 0);
    defer a.deinit(std.testing.allocator);

    a.refCountPtr().* = std.math.maxInt(usize);
    defer a.refCountPtr().* = 0;

    try std.testing.expectError(error.Overflow, a.retain());

    const b = try IrcSlice(u128, .{ .Counter = u8 }).init(std.testing.allocator, 0);
    defer b.deinit(std.testing.allocator);

    b.refCountPtr().* = std.math.maxInt(u8);
    defer b.refCountPtr().* = 0;

    try std.testing.expectError(error.Overflow, b.retain());
}

test "alignment" {
    const a = try IrcSlice(u128, .{ .alignment = 64 }).init(std.testing.allocator, 0);
    defer a.deinit(std.testing.allocator);

    try std.testing.expect(64 != @alignOf(u128));
    try std.testing.expectEqual([]align(64) u128, @TypeOf(a.items));

    const b = try IrcSlice(TestType, .{ .alignment = 32 }).init(std.testing.allocator, 0);
    defer b.deinit(std.testing.allocator);

    try std.testing.expect(32 != @alignOf(TestType));
    try std.testing.expectEqual([]align(32) TestType, @TypeOf(b.items));
}

test "cast" {
    const a = try IrcSlice(u128, .{ .alignment = 64 }).init(std.testing.allocator, 10);
    defer a.deinit(std.testing.allocator);
    try std.testing.expect(64 != @alignOf(u128));
    try std.testing.expectEqual(0, a.refCountPtr().*);

    const b = a.cast(IrcSlice(u128, .{}));
    try b.retain();

    try std.testing.expectEqual(1, a.refCountPtr().*);
    b.release();
    try std.testing.expectEqual(0, a.refCountPtr().*);
}

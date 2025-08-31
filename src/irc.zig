const std = @import("std");
const builtin = @import("builtin");

pub const IrcConfig = struct {
    Counter: type = usize,
    alignment: ?u16 = null,
    is_const: bool = false,
    is_volatile: bool = false,
    is_allowzero: bool = false,
    address_space: std.builtin.AddressSpace = .generic,
    sentinel: ?*const anyopaque = null,

    const IrcConfigDiff = struct {
        Counter: ?type = null,
        alignment: ?u16 = null,
        is_const: ?bool = null,
        is_volatile: ?bool = null,
        is_allowzero: ?bool = null,
        address_space: ?std.builtin.AddressSpace = null,
        sentinel: ?*const anyopaque = null,
    };

    pub fn copyBut(self: IrcConfig, cfg: IrcConfigDiff) IrcConfig {
        var new_config: IrcConfig = self;
        if (cfg.Counter) |c| new_config.Counter = c;
        if (cfg.alignment) |a| new_config.alignment = a;
        if (cfg.is_const) |c| new_config.is_const = c;
        if (cfg.is_volatile) |v| new_config.is_volatile = v;
        if (cfg.is_allowzero) |a| new_config.is_allowzero = a;
        if (cfg.address_space) |a| new_config.address_space = a;
        if (cfg.sentinel) |s| new_config.sentinel = s;
        return new_config;
    }
};

pub fn Irc(size: std.builtin.Type.Pointer.Size, T: type, cfg: IrcConfig) type {
    comptime try std.testing.expectEqual(8, std.mem.byte_size_in_bits);
    if (size != .One and size != .Slice) {
        @compileError(std.fmt.comptimePrint("Reference counted pointer size may only be 'One' or 'Slice', got: {}", .{size}));
    }

    switch (@typeInfo(cfg.Counter)) {
        .Int => |int| {
            if (int.signedness != .unsigned) {
                @compileError(std.fmt.comptimePrint(
                    "Reference counter type must be unsigned, got {}",
                    .{cfg.Counter},
                ));
            }
        },
        else => {
            @compileError(std.fmt.comptimePrint(
                "Reference counter type must be an unsigned integer, got {}",
                .{cfg.Counter},
            ));
        },
    }

    const alignment = if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe) block: {
        break :block @as(usize, @max(
            @sizeOf(u16), // include alignment information
            @alignOf(cfg.Counter),
            cfg.alignment orelse @alignOf(T),
        ));
    } else block: {
        // don't include alignment of alignment information
        break :block @as(usize, @max(
            @alignOf(cfg.Counter),
            cfg.alignment orelse @alignOf(T),
        ));
    };

    var rc_offset: usize = undefined;
    var al_offset: usize = undefined;

    if (@sizeOf(cfg.Counter) < @sizeOf(u16) and (builtin.mode == .Debug or builtin.mode == .ReleaseSafe)) {
        // counter is smaller than alignment int and Debug/ReleaseSafe is enabled
        // put the alignment directly behind the pointer and the counter after that
        //
        //      _ _ c c a a a a | d d d d | d d d d ...
        //          |   |         |
        //          |   |         |_ start of first element
        //          |   |_ start of alignment data
        //          |_ start of reference count
        //
        // The alignment information is only store in a safe release
        rc_offset = @sizeOf(cfg.Counter) + @sizeOf(u16);
        al_offset = @sizeOf(u16);
    } else {
        // counter is larger than alignment int (or Debug/ReleaseSafe is not enabled)
        // put the reference count directly behind the pointer and the alignment after that
        //
        //      _ _ a a c c c c | d d d d | d d d d ...
        //          |   |         |
        //          |   |         |_ start of first element
        //          |   |_ start of reference count
        //          |_ start of alignment data
        //
        // The alignment information is only store in a safe release
        rc_offset = @sizeOf(cfg.Counter);
        al_offset = @sizeOf(cfg.Counter) + @sizeOf(u16);
    }

    const ref_count_offset = rc_offset;
    const alignment_offset = al_offset;

    const meta_data_size: usize = if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe) block: {
        // include alignment information in allocation
        break :block alignment * try std.math.divCeil(
            usize,
            @max(ref_count_offset, alignment_offset),
            alignment,
        );
    } else block: {
        // don't allocate alignment information
        break :block alignment * try std.math.divCeil(
            usize,
            ref_count_offset,
            alignment,
        );
    };

    return struct {
        const Self = @This();
        pub const config = cfg;

        items: IrcPointerType(size, T, cfg),

        // Complicated shenanigans to change the signature. If the pointer
        // is a slice we need a length and if it's a single element pointer
        // we don't want to take a length
        pub usingnamespace switch (size) {
            .Slice => struct {
                pub fn init(allocator: std.mem.Allocator, length: usize) !Self {
                    const slice_size = std.math.mul(
                        usize,
                        length,
                        @sizeOf(T),
                    ) catch return error.OutOfMemory;
                    const total_size = std.math.add(
                        usize,
                        meta_data_size,
                        slice_size,
                    ) catch return error.OutOfMemory;

                    const b = try allocator.alignedAlloc(
                        u8,
                        alignment,
                        total_size,
                    );
                    // if the input `length` is zero one past the pointer must
                    // be valid since we rely on `ptr + meta_data_size` to not
                    // overflow
                    std.debug.assert(@intFromPtr(b.ptr) < std.math.maxInt(usize) - alignment);

                    const self: Self = .{
                        .items = bytesAsSliceCast(T, b[meta_data_size..]),
                    };
                    self.initMetaData();

                    return self;
                }
            },
            .One => struct {
                pub fn init(allocator: std.mem.Allocator) !Self {
                    const total_size = std.math.add(
                        usize,
                        meta_data_size,
                        @sizeOf(T),
                    ) catch return error.OutOfMemory;

                    const b = try allocator.alignedAlloc(
                        u8,
                        alignment,
                        total_size,
                    );

                    const self: Self = .{
                        .items = std.mem.bytesAsValue(T, b[meta_data_size..]),
                    };
                    self.initMetaData();

                    return self;
                }
            },
            else => @compileError("Internal error, expected Slice or One"),
        };

        fn initMetaData(self: Self) void {
            self.refCountPtr().* = 0;
            if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe) {
                self.alignmentPtr().* = alignment;
            }
        }

        pub fn releaseDeinitDangling(self: Self, allocator: std.mem.Allocator) void {
            self.release();
            if (self.dangling()) {
                self.deinit(allocator);
            }
        }

        pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
            if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe) {
                if (alignment != self.alignmentPtr().*) {
                    @panic(
                        \\Due to the reference count the pointer must be freed with
                        \\the same alignment as it was created with. Detected attempt
                        \\to free pointer with incorrect alignment.
                    );
                }
            }

            if (!self.dangling()) {
                @panic("Irc is not dangling, cannot free memory that is still in use.");
            }
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
            return self.anyCast(IrcType, false, false);
        }

        pub fn alignCast(self: Self, IrcType: type) IrcType {
            return self.anyCast(IrcType, false, true);
        }

        pub fn constCast(self: Self, IrcType: type) IrcType {
            return self.anyCast(IrcType, true, false);
        }

        fn anyCast(self: Self, IrcType: type, comptime const_cast: bool, comptime align_cast: bool) IrcType {
            comptime if (isIrcSanityCheck(IrcType)) |err| {
                @compileError("Cannot cast to non-Irc type: " ++ err);
            };
            if (cfg.Counter != IrcType.config.Counter) {
                @compileError(std.fmt.comptimePrint(
                    \\Cannot cast to Irc with different reference counter type,
                    \\source counter is {} and target counter is {}
                ,
                    .{ cfg.Counter, IrcType.config.Counter },
                ));
            }
            if (const_cast and align_cast) {
                return .{ .items = @ptrCast(@alignCast(@constCast(self.items))) };
            } else if (const_cast) {
                return .{ .items = @ptrCast(@constCast(self.items)) };
            } else if (align_cast) {
                return .{ .items = @ptrCast(@alignCast(self.items)) };
            } else {
                return .{ .items = @ptrCast(self.items) };
            }
        }

        fn bytes(self: Self) []align(alignment) u8 {
            const ptr = switch (size) {
                .Slice => self.items.ptr,
                .One => self.items,
                else => @compileError("Internal error, expected Slice or One"),
            };
            const byte_length = switch (size) {
                .Slice => self.items.len * @sizeOf(T),
                .One => @sizeOf(T),
                else => @compileError("Internal error, expected Slice or One"),
            };
            return @as(
                [*]align(alignment) u8,
                @ptrFromInt(@intFromPtr(ptr) - alignment),
            )[0 .. meta_data_size + byte_length];
        }

        fn refCountPtr(self: Self) *cfg.Counter {
            const ptr = switch (size) {
                .Slice => self.items.ptr,
                .One => self.items,
                else => @compileError("Internal error, expected Slice or One"),
            };
            return @ptrFromInt(@intFromPtr(ptr) - ref_count_offset);
        }

        fn alignmentPtr(self: Self) *u16 {
            if (builtin.mode != .Debug and builtin.mode != .ReleaseSafe) {
                @compileError("Internal error, alignment is not stored in this optimization mode");
            }
            const ptr = switch (size) {
                .Slice => self.items.ptr,
                .One => self.items,
                else => @compileError("Internal error, expected Slice or One"),
            };
            return @ptrFromInt(@intFromPtr(ptr) - alignment_offset);
        }
    };
}

pub fn isIrcSanityCheck(IrcType: type) ?[]const u8 {
    const irc_info = @typeInfo(IrcType);
    switch (irc_info) {
        .Struct => {},
        else => {
            return "expected a struct";
        },
    }

    var found: bool = false;
    const field_items = "items";
    comptime for (irc_info.Struct.fields) |field| {
        found = found or std.mem.eql(u8, field_items, field.name);
    };
    if (!found) {
        return "expected field named 'items'";
    }

    const methods = [_][]const u8{
        "init",
        "deinit",
        "releaseDeinitDangling",
        "dangling",
        "retain",
        "release",
        "cast",
    };
    comptime for (methods) |method| {
        if (!std.meta.hasFn(IrcType, method)) {
            return "missing method '" ++ method ++ "'";
        }
    };

    // Type passes sanity checks...
    return null;
}

fn IrcPointerType(size: std.builtin.Type.Pointer.Size, T: type, config: IrcConfig) type {
    return @Type(.{
        .Pointer = .{
            .size = size,
            .is_const = config.is_const,
            .is_volatile = config.is_volatile,
            .is_allowzero = config.is_allowzero,
            .alignment = config.alignment orelse @alignOf(T),
            .address_space = config.address_space,
            .child = T,
            .sentinel = config.sentinel,
        },
    });
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

// This function from `std.mem` has been duplicated since we need
// to be able to give it slices of length 0 which still contain
// a valid pointer. Currently there's a special case for empty
// slices which breaks our code if used
fn bytesAsSliceCast(T: type, bytes_slice: anytype) CopyPtrAttrs(@TypeOf(bytes_slice), .Slice, T) {
    const cast_target = CopyPtrAttrs(@TypeOf(bytes_slice), .Many, T);
    return @as(cast_target, @ptrCast(bytes_slice))[0..@divExact(bytes_slice.len, @sizeOf(T))];
}

const TestType = struct { v1: u8, v2: u8, v3: u8 };

test "copy config but change something" {
    const cfg: IrcConfig = .{ .is_const = true, .alignment = 32 };
    try std.testing.expectEqual(
        IrcConfig{ .is_const = false, .is_volatile = false, .alignment = 32 },
        cfg.copyBut(.{ .is_const = false, .is_volatile = false }),
    );
}

test "just make type" {
    _ = Irc(.Slice, u128, .{});
    _ = Irc(.Slice, TestType, .{});
    _ = Irc(.One, u128, .{});
    _ = Irc(.One, TestType, .{});
    comptime try std.testing.expect(@alignOf(TestType) < @sizeOf(TestType));
}

test "slice make type with bells and whistles" {
    const T = Irc(.Slice, u128, .{
        .alignment = 32,
        .is_const = true,
        .is_volatile = true,
        .is_allowzero = true,
        .address_space = .gs,
        .sentinel = &@as(u128, 1),
    });
    const a: T = undefined;
    try std.testing.expect(32 != @alignOf(u128));
    try std.testing.expectEqual(
        [:1]allowzero align(32) addrspace(.gs) const volatile u128,
        @TypeOf(a.items),
    );
}

test "one make type with bells and whistles" {
    const T = Irc(.Slice, u128, .{
        .alignment = 32,
        .is_const = true,
        .is_volatile = true,
        .is_allowzero = true,
        .address_space = .gs,
        .sentinel = &@as(u128, 1),
    });
    const b: T = undefined;
    try std.testing.expect(32 != @alignOf(u128));
    try std.testing.expectEqual(
        [:1]allowzero align(32) addrspace(.gs) const volatile u128,
        @TypeOf(b.items),
    );
}

test "slice init and deinit" {
    const a = try Irc(.Slice, u128, .{}).init(std.testing.allocator, 7);
    defer a.deinit(std.testing.allocator);

    const b = try Irc(.Slice, TestType, .{}).init(std.testing.allocator, 7);
    defer b.deinit(std.testing.allocator);
}

test "one init and deinit" {
    const a = try Irc(.One, u128, .{}).init(std.testing.allocator);
    defer a.deinit(std.testing.allocator);

    const b = try Irc(.One, TestType, .{}).init(std.testing.allocator);
    defer b.deinit(std.testing.allocator);
}

test "slice init and deinit empty" {
    const a = try Irc(.Slice, u128, .{}).init(std.testing.allocator, 0);
    defer a.deinit(std.testing.allocator);

    const b = try Irc(.Slice, TestType, .{}).init(std.testing.allocator, 0);
    defer b.deinit(std.testing.allocator);
}

test "slice deinit and maybe release" {
    const a = try Irc(.Slice, u128, .{}).init(std.testing.allocator, 0);

    try a.retain();
    try a.retain();
    a.releaseDeinitDangling(std.testing.allocator);
    a.releaseDeinitDangling(std.testing.allocator);
}

test "one deinit and maybe release" {
    const a = try Irc(.One, u128, .{}).init(std.testing.allocator);

    try a.retain();
    try a.retain();
    a.releaseDeinitDangling(std.testing.allocator);
    a.releaseDeinitDangling(std.testing.allocator);
}

test "slice allocation failure" {
    var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    const err = Irc(.Slice, u8, .{}).init(failing_allocator.allocator(), 3);
    try std.testing.expectError(error.OutOfMemory, err);
}

test "one allocation failure" {
    var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    const err = Irc(.One, u8, .{}).init(failing_allocator.allocator());
    try std.testing.expectError(error.OutOfMemory, err);
}

test "slice only one allocation" {
    var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    const a = try Irc(.Slice, u8, .{}).init(failing_allocator.allocator(), 3);
    a.deinit(std.testing.allocator);
}

test "one only one allocation" {
    var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    const a = try Irc(.One, u8, .{}).init(failing_allocator.allocator());
    a.deinit(std.testing.allocator);
}

test "slice size multiplication too big" {
    const err = Irc(.Slice, struct { v1: u8, v2: u8 }, .{}).init(std.testing.allocator, std.math.maxInt(usize) / 2 + 1);
    try std.testing.expectError(error.OutOfMemory, err);
}

test "slice cannot also fit meta data" {
    comptime try std.testing.expect(@sizeOf(usize) > @sizeOf(u8));
    const err = Irc(.Slice, u8, .{}).init(std.testing.allocator, std.math.maxInt(usize) - 1);
    try std.testing.expectError(error.OutOfMemory, err);
}

test "slice release and retain does not alias data" {
    const a = try Irc(.Slice, u128, .{}).init(std.testing.allocator, 5);
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

    const b = try Irc(.Slice, TestType, .{}).init(std.testing.allocator, 5);
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

test "one release and retain does not alias data" {
    const a = try Irc(.One, u128, .{}).init(std.testing.allocator);
    defer a.deinit(std.testing.allocator);
    a.items.* = 0;
    try std.testing.expectEqual(0, a.refCountPtr().*);
    try std.testing.expect(a.dangling());

    try a.retain();
    a.items.* = 0;
    try std.testing.expectEqual(1, a.refCountPtr().*);
    try std.testing.expect(!a.dangling());

    a.release();
    a.items.* = 0;
    try std.testing.expectEqual(0, a.refCountPtr().*);
    try std.testing.expect(a.dangling());

    const b = try Irc(.One, TestType, .{}).init(std.testing.allocator);
    defer b.deinit(std.testing.allocator);
    b.items.* = .{ .v1 = 0, .v2 = 0, .v3 = 0 };
    try std.testing.expectEqual(0, b.refCountPtr().*);
    try std.testing.expect(b.dangling());

    try b.retain();
    b.items.* = .{ .v1 = 0, .v2 = 0, .v3 = 0 };
    try std.testing.expectEqual(1, b.refCountPtr().*);
    try std.testing.expect(!b.dangling());

    b.release();
    b.items.* = .{ .v1 = 0, .v2 = 0, .v3 = 0 };
    try std.testing.expectEqual(0, b.refCountPtr().*);
    try std.testing.expect(b.dangling());
}

test "slice release and retain empty" {
    const a = try Irc(.Slice, u128, .{}).init(std.testing.allocator, 0);
    defer a.deinit(std.testing.allocator);
    try std.testing.expectEqual(0, a.refCountPtr().*);
    try std.testing.expect(a.dangling());

    try a.retain();
    try std.testing.expectEqual(1, a.refCountPtr().*);
    try std.testing.expect(!a.dangling());

    a.release();
    try std.testing.expectEqual(0, a.refCountPtr().*);
    try std.testing.expect(a.dangling());

    const b = try Irc(.Slice, TestType, .{}).init(std.testing.allocator, 0);
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

test "slice retain release small reference count" {
    const a = try Irc(.Slice, u128, .{ .Counter = u8 }).init(std.testing.allocator, 0);
    defer a.deinit(std.testing.allocator);
    try std.testing.expectEqual(0, a.refCountPtr().*);
    try std.testing.expect(a.dangling());

    try a.retain();
    try std.testing.expectEqual(1, a.refCountPtr().*);
    try std.testing.expect(!a.dangling());

    a.release();
    try std.testing.expectEqual(0, a.refCountPtr().*);
    try std.testing.expect(a.dangling());
}

test "one retain release small reference count" {
    const a = try Irc(.One, u128, .{ .Counter = u8 }).init(std.testing.allocator);
    defer a.deinit(std.testing.allocator);
    try std.testing.expectEqual(0, a.refCountPtr().*);
    try std.testing.expect(a.dangling());

    try a.retain();
    try std.testing.expectEqual(1, a.refCountPtr().*);
    try std.testing.expect(!a.dangling());

    a.release();
    try std.testing.expectEqual(0, a.refCountPtr().*);
    try std.testing.expect(a.dangling());
}

test "slice retain release non power of two reference count" {
    const a = try Irc(.Slice, u8, .{ .Counter = u9 }).init(std.testing.allocator, 3);
    defer a.deinit(std.testing.allocator);
    try std.testing.expectEqual(0, a.refCountPtr().*);
    try std.testing.expect(a.dangling());

    try a.retain();
    try std.testing.expectEqual(1, a.refCountPtr().*);
    try std.testing.expect(!a.dangling());

    a.release();
    try std.testing.expectEqual(0, a.refCountPtr().*);
    try std.testing.expect(a.dangling());
}

test "one retain release non power of two reference count" {
    const a = try Irc(.One, u8, .{ .Counter = u9 }).init(std.testing.allocator);
    defer a.deinit(std.testing.allocator);
    try std.testing.expectEqual(0, a.refCountPtr().*);
    try std.testing.expect(a.dangling());

    try a.retain();
    try std.testing.expectEqual(1, a.refCountPtr().*);
    try std.testing.expect(!a.dangling());

    a.release();
    try std.testing.expectEqual(0, a.refCountPtr().*);
    try std.testing.expect(a.dangling());
}

test "slice retain overflow" {
    const a = try Irc(.Slice, u128, .{ .Counter = usize }).init(std.testing.allocator, 0);
    defer a.deinit(std.testing.allocator);

    a.refCountPtr().* = std.math.maxInt(usize);
    defer a.refCountPtr().* = 0;

    try std.testing.expectError(error.Overflow, a.retain());

    const b = try Irc(.Slice, u128, .{ .Counter = u8 }).init(std.testing.allocator, 0);
    defer b.deinit(std.testing.allocator);

    b.refCountPtr().* = std.math.maxInt(u8);
    defer b.refCountPtr().* = 0;

    try std.testing.expectError(error.Overflow, b.retain());
}

test "one retain overflow" {
    const a = try Irc(.One, u128, .{ .Counter = usize }).init(std.testing.allocator);
    defer a.deinit(std.testing.allocator);

    a.refCountPtr().* = std.math.maxInt(usize);
    defer a.refCountPtr().* = 0;

    try std.testing.expectError(error.Overflow, a.retain());

    const b = try Irc(.One, u128, .{ .Counter = u8 }).init(std.testing.allocator);
    defer b.deinit(std.testing.allocator);

    b.refCountPtr().* = std.math.maxInt(u8);
    defer b.refCountPtr().* = 0;

    try std.testing.expectError(error.Overflow, b.retain());
}

test "slice alignment" {
    const a = try Irc(.Slice, u128, .{ .alignment = 64 }).init(std.testing.allocator, 0);
    defer a.deinit(std.testing.allocator);

    try std.testing.expect(64 != @alignOf(u128));
    try std.testing.expectEqual([]align(64) u128, @TypeOf(a.items));

    const b = try Irc(.Slice, TestType, .{ .alignment = 32 }).init(std.testing.allocator, 0);
    defer b.deinit(std.testing.allocator);

    try std.testing.expect(32 != @alignOf(TestType));
    try std.testing.expectEqual([]align(32) TestType, @TypeOf(b.items));
}

test "one alignment" {
    const a = try Irc(.One, u128, .{ .alignment = 64 }).init(std.testing.allocator);
    defer a.deinit(std.testing.allocator);

    try std.testing.expect(64 != @alignOf(u128));
    try std.testing.expectEqual(*align(64) u128, @TypeOf(a.items));

    const b = try Irc(.One, TestType, .{ .alignment = 32 }).init(std.testing.allocator);
    defer b.deinit(std.testing.allocator);

    try std.testing.expect(32 != @alignOf(TestType));
    try std.testing.expectEqual(*align(32) TestType, @TypeOf(b.items));
}

test "slice cast" {
    const a = try Irc(.Slice, u128, .{ .alignment = 64 }).init(std.testing.allocator, 10);
    defer a.deinit(std.testing.allocator);
    try std.testing.expect(64 != @alignOf(u128));
    try std.testing.expectEqual(0, a.refCountPtr().*);

    const b = a.cast(Irc(.Slice, u128, .{}));
    try b.retain();

    try std.testing.expectEqual(1, a.refCountPtr().*);
    b.release();
    try std.testing.expectEqual(0, a.refCountPtr().*);
}

test "one cast" {
    const a = try Irc(.One, u128, .{ .alignment = 64 }).init(std.testing.allocator);
    defer a.deinit(std.testing.allocator);
    try std.testing.expect(64 != @alignOf(u128));
    try std.testing.expectEqual(0, a.refCountPtr().*);

    const b = a.cast(Irc(.One, u128, .{}));
    try b.retain();

    try std.testing.expectEqual(1, a.refCountPtr().*);
    b.release();
    try std.testing.expectEqual(0, a.refCountPtr().*);
}

test "slice align cast" {
    const a = try Irc(.Slice, u128, .{ .alignment = 64 }).init(std.testing.allocator, 10);
    defer a.deinit(std.testing.allocator);

    const b = a.cast(Irc(.Slice, u128, .{ .alignment = 32 }));
    _ = b.alignCast(Irc(.Slice, u128, .{ .alignment = 64 }));
}

test "one align cast" {
    const a = try Irc(.One, u128, .{ .alignment = 64 }).init(std.testing.allocator);
    defer a.deinit(std.testing.allocator);

    const b = a.cast(Irc(.One, u128, .{ .alignment = 32 }));
    _ = b.alignCast(Irc(.One, u128, .{ .alignment = 64 }));
}

test "slice const cast" {
    const a = try Irc(.Slice, u128, .{ .is_const = false }).init(std.testing.allocator, 10);
    defer a.deinit(std.testing.allocator);

    const b = a.cast(Irc(.Slice, u128, .{ .is_const = true }));
    _ = b.constCast(Irc(.Slice, u128, .{ .is_const = false }));
}

test "one const cast" {
    const a = try Irc(.One, u128, .{ .is_const = false }).init(std.testing.allocator);
    defer a.deinit(std.testing.allocator);

    const b = a.cast(Irc(.One, u128, .{ .is_const = true }));
    _ = b.constCast(Irc(.One, u128, .{ .is_const = false }));
}

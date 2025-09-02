const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("irc", .{
        .root_source_file = b.path("src/irc.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run unit tests");
    inline for (std.meta.fields(std.builtin.OptimizeMode)) |field| {
        const mode: std.builtin.OptimizeMode = @enumFromInt(field.value);
        const mod_test = b.createModule(.{
            .root_source_file = b.path("src/irc.zig"),
            .target = target,
            .optimize = mode,
        });
        const lib_unit_tests = b.addTest(.{ .root_module = mod_test });
        const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
        test_step.dependOn(&run_lib_unit_tests.step);
    }

    const example_index = b.option(usize, "example", "Index of the example to run in the 'Run' step, default value is 1.") orelse 1;

    const example_dir = b.path("examples");
    var dir = std.fs.cwd().openDir(
        example_dir.getPath(b),
        .{ .access_sub_paths = false, .iterate = true },
    ) catch @panic("Could not access 'examples' directory.");
    var it = dir.iterate();

    var ex: ?*std.Build.Step.Compile = null;
    while (it.next() catch @panic("Could not read entries in 'examples' directory")) |entry| {
        const index = std.fmt.parseInt(u8, entry.name[0..2], 10) catch continue;
        if (index == example_index) {
            const example_mod = b.createModule(.{
                .root_source_file = example_dir.path(b, entry.name),
                .target = target,
                .optimize = optimize,
            });
            ex = b.addExecutable(.{
                .name = entry.name,
                .root_module = example_mod,
            });
            break;
        }
    }
    const example = ex orelse @panic("Requested example index does not exist.");
    example.root_module.addImport("irc", mod);

    const run_example = b.addRunArtifact(example);
    const run_step = b.step("run", "Run an example, choose which one with '-Dexample=<index>'.");
    run_step.dependOn(&run_example.step);
}

# IRC - Intrusive Reference Counted pointers

Zig-style reference counted pointers, everything about the pointer can be modified and you can choose whether the reference count is atomic or not in the config:

```zig
Irc(.slice, u8, .{ .is_volatile = true, .atomic = true })
```

This creates the following atomically reference counted type `[]volatile u8`. By default `atomic` is false. You can also create a pointer-to-one:

```zig
Irc(.one, []usize, .{ .is_const = true })
```

This creates the following (not atomically) reference counted type `*const []usize`. Examples on how it is used can be found under the `examples/` folder. More comprehensive usage can be found in the units tests in `src/irc.zig`.

## Installation

To add version `1.0.0` to your project run

```bash
zig fetch --save git+https://github.com/p-rosit/irc/#1.0.0
```

Then add the following to your build file:

```zig
irc = b.dependency("irc", .{
    .target = target,
    .optimize = optimize,
}).module("irc");

build_thing = // Some call to `addExecutable`, `addImport`, `addModule`, etc.
build_thing.root_module.addImport("irc", irc);
```

Then you will be able to write `Irc = @import("irc").Irc;` in your project.

## Examples

There are some examples under the `examples/` folder, these can be run with the following command

```zig
zig build run -Dexample=N -Doptimize=MODE
```

Where `N` is the number of the example you would like to run and `MODE` is the optimization mode. If the optimization mode is not specified a debug build will be made and run.

## Unit tests

To run all unit tests run the following:

```zig
zig build test
```

the unit tests should be comprehensive, if there is some bug an additional unit test will be written to ensure it never appears again (together with fixing the bug)

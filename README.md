# IRC - Intrusive Reference Counted pointers

Zig-style reference counted pointers, everything about the pointer can be modified and you can choose whether the reference count is atomic or not in the config:

```zig
Irc(.Slice, u8, .{ .is_volatile = true, .atomic = true })
```

This creates the following atomically reference counted type `[]volatile u8`. By default `atomic` is false.

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

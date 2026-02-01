# Zig Issue: MachO linker needs support for flat namespace or bundle linking on macOS

## Title

MachO linker: Add support for `-flat_namespace` or `-bundle` linking on macOS

## Labels

enhancement, macos, linker

## Problem

When building dynamic libraries on macOS, Zig's internal MachO linker uses two-level namespace by default. This causes symbol resolution issues when the library needs to use symbols from an executable that loads it (like PostgreSQL extensions).

## Background

macOS has two symbol namespace modes:
- **Two-level namespace** (default): Symbols are bound to specific libraries at link time
- **Flat namespace**: Symbols are resolved at runtime from the flat global namespace

PostgreSQL extensions are loaded by the postgres binary, and they need to call PostgreSQL's internal functions like `hash_create`, `hash_destroy`, etc. However, macOS's `libSystem` exports BSD hsearch functions with the **same names** but different signatures:

- BSD: `HTAB *hash_create(int nel, HASHCTL *hctl, int flags)`
- PostgreSQL: `HTAB *hash_create(const char *tabname, long nelem, const HASHCTL *info, int flags)`

With two-level namespace, Zig's linker binds these symbols to `libSystem` instead of resolving them at runtime from the postgres executable.

## Evidence

When building a PostgreSQL extension with Zig:

```
$ nm -m extension.dylib | grep hash_create
                 (undefined) external _hash_create (from libSystem)
```

The `(from libSystem)` indicates the symbol is bound to the wrong library.

With the correct linking, it should show:
```
$ nm -m extension.dylib | grep hash_create
                 (undefined) external _hash_create (from executable)
```

Or with flat namespace:
```
$ nm -m extension.dylib | grep hash_create
                 (undefined) external _hash_create
```

## Reproduction

1. Build a shared library that calls `hash_create()` (a symbol that exists in both libSystem and PostgreSQL)
2. Load the library into PostgreSQL
3. Call the function - it will crash because libSystem's `hash_create` has a different signature

Minimal test case available at: https://github.com/xataio/pgzx/tree/main/src/testing/extension_c

## Workaround with clang

Building with clang allows passing the necessary linker flags:

```bash
# Option 1: Flat namespace (symbols resolved at runtime from global namespace)
clang -dynamiclib -flat_namespace -undefined dynamic_lookup -o extension.dylib extension.c

# Option 2: Bundle with explicit loader (preferred for extensions)
clang -bundle -bundle_loader /path/to/postgres -o extension.bundle extension.c
```

Both options produce correct symbol binding.

## Attempted Zig Workarounds

The following do not work with Zig's linker:

```bash
# These flags are not recognized by Zig's MachO linker
zig cc -dynamiclib -Xlinker -flat_namespace ...  # Error: unsupported linker arg: -flat_namespace
zig build-lib -dynamic ...  # No option to specify flat namespace
```

Even with `-fuse-ld=ld` to try using the system linker, Zig's layer rejects `-flat_namespace`.

## Requested Feature

Please add support for one or more of:

1. **`-flat_namespace` linker flag** - Builds with flat namespace instead of two-level namespace. This tells the dynamic linker to resolve symbols at runtime from all loaded images rather than binding to specific libraries at link time.

2. **Bundle output type** - Build `MH_BUNDLE` instead of `MH_DYLIB`. Bundles are specifically designed to be loaded by executables and naturally resolve symbols from the loader.

3. **`-bundle_loader` option** - Specify the executable that will load this bundle, allowing the linker to verify and bind symbols correctly.

## Use Case

This is blocking for projects like [pgzx](https://github.com/xataio/pgzx) - a Zig library for building PostgreSQL extensions. The `HTab` wrapper (PostgreSQL hash tables) cannot be used on macOS because of this symbol resolution issue, causing server crashes.

PostgreSQL extensions are a common use case for loadable modules on macOS, and the official PostgreSQL documentation recommends using `-bundle -bundle_loader` for building extensions.

## Technical Details

The MH_TWOLEVEL flag in the Mach-O header controls namespace behavior:
- Present (default): Two-level namespace - symbols bound to specific libraries
- Absent: Flat namespace - symbols resolved globally at runtime

The relevant ld64 flags are:
- `-flat_namespace` - Disable two-level namespace
- `-twolevel_namespace` - Enable two-level namespace (default)
- `-bundle` - Create MH_BUNDLE instead of MH_DYLIB
- `-bundle_loader <executable>` - Specify the executable that loads this bundle

## Related

- Apple's ld64 man page documents these flags
- PostgreSQL extension building documentation: https://www.postgresql.org/docs/current/xfunc-c.html
- Zig issue for @cImport removal: https://github.com/ziglang/zig/issues/20630 (related build system changes)

## Environment

- macOS 26.x (Sequoia) on Apple Silicon
- Zig 0.15.2
- PostgreSQL 16/17/18

# AGENTS.md - pgzx Development Guide

pgzx is a Zig library for developing PostgreSQL extensions. It provides utilities (error handling, memory allocators, wrappers) and a development environment for integrating with the Postgres C codebase.

## Quick Reference

| Task | Command |
|------|---------|
| Enter dev shell | `nix develop` |
| Setup local Postgres | `pglocal && pginit` |
| Start Postgres | `pgstart` |
| Stop Postgres | `pgstop` |
| Build pgzx unit tests | `zig build -p $PG_HOME unit` |
| Build example extension | `cd examples/<name> && zig build -p $PG_HOME` |
| Run example regression tests | `zig build pg_regress` |
| Run example unit tests | `zig build -p $PG_HOME unit` |
| Generate docs | `zig build docs` |
| Serve docs locally | `zig build serve_docs` |
| Run all CI checks | `./ci/run.sh` |
| Run specific test | `zig build -Dtest_filter=<name> unit -p $PG_HOME` |

## Project Structure

```
pgzx/
├── src/
│   ├── pgzx.zig              # Main module entry, re-exports all utilities
│   ├── testing.zig           # Unit test extension entry point
│   └── pgzx/
│       ├── build.zig         # Build system helpers for extensions
│       ├── c.zig             # C bindings to Postgres
│       ├── elog.zig          # Logging (Log, Info, Warning, Error, etc.)
│       ├── err.zig           # Error handling, PG_TRY/PG_CATCH equivalents
│       ├── mem.zig           # Memory context allocators
│       ├── fmgr.zig          # Function manager (PG_FUNCTION_V1, etc.)
│       ├── testing.zig       # Test registration and runner
│       ├── collections/      # Postgres data structure wrappers
│       │   ├── htab.zig      # Hash tables (HTAB)
│       │   ├── list.zig      # Pointer lists
│       │   ├── slist.zig     # Single linked lists
│       │   └── dlist.zig     # Double linked lists
│       ├── spi.zig           # Server Programming Interface
│       ├── bgworker.zig      # Background workers
│       ├── lwlock.zig        # Lightweight locks
│       ├── shmem.zig         # Shared memory
│       └── ...
├── examples/                  # Reference implementations
│   ├── char_count_zig/       # Simple function extension
│   ├── pghostname_zig/       # Returns hostname
│   ├── pgaudit_zig/          # Hooks and GUC settings
│   ├── sqlfns/               # Multiple SQL functions
│   └── spi_sql/              # SPI usage example
├── tools/gennodetags/        # Code generator for node tags
├── dev/bin/                  # Development scripts
├── ci/                       # CI scripts
└── nix/                      # Nix configuration
```

## Development Environment Setup

### Prerequisites

This project uses **Nix flakes** to manage dependencies. Install Nix using the [DeterminateSystems nix-installer](https://github.com/DeterminateSystems/nix-installer).

### Without Nix (Docker)

```bash
./dev/docker/build.sh   # Build Docker image
./dev/docker/run.sh     # Start development shell
```

### Enter Development Shell

```bash
nix develop             # Standard shell
nix develop '.#debug'   # Debug shell (includes tools to build Postgres from source)
```

### Initialize Local Postgres

```bash
pglocal    # Relocate Nix postgres into ./out/default
pginit     # Create local database cluster
pgstart    # Start postgres
pgstop     # Stop postgres
```

### Environment Variables

Set automatically by the dev shell:
- `PRJ_ROOT` - Project root directory
- `PG_HOME` - Local postgres installation (`$PRJ_ROOT/out/default`)
- `NIX_PGLIBDIR` - Override for postgres library directory

## Building Extensions

### pgzx Library Build

```bash
# Build and install unit test extension
zig build -p $PG_HOME unit

# Generate documentation
zig build docs
```

### Example Extension Build

```bash
cd examples/char_count_zig
zig build -p $PG_HOME           # Build and install
zig build pg_regress            # Run regression tests
zig build -p $PG_HOME unit      # Run unit tests
zig build check                 # Check compilation only (no install)
```

### Extension Build Pattern

Extensions use `build.zig` with pgzx build helpers:

```zig
const PGBuild = @import("pgzx").Build;

pub fn build(b: *std.Build) void {
    var pgbuild = PGBuild.create(b, .{
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    });

    const ext = pgbuild.addInstallExtension(.{
        .name = "my_extension",
        .version = .{ .major = 0, .minor = 1 },
        .source_file = b.path("src/main.zig"),
        .root_dir = "src/",
    });

    b.getInstallStep().dependOn(&ext.step);
}
```

## Writing Extensions

### Basic Extension Structure

```zig
const pgzx = @import("pgzx");

comptime {
    pgzx.PG_MODULE_MAGIC();
    pgzx.PG_FUNCTION_V1("my_function", myFunction);
}

fn myFunction(arg1: []const u8) !u32 {
    pgzx.elog.Info(@src(), "Called with: {s}\n", .{arg1});
    // Implementation...
    return result;
}
```

### Logging

Use `elog` module for Postgres-compatible logging:

```zig
pgzx.elog.Log(@src(), "Debug message", .{});
pgzx.elog.Info(@src(), "Info: {s}\n", .{value});
pgzx.elog.Warning(@src(), "Warning!", .{});
pgzx.elog.Error(@src(), "Error: {}", .{code});  // Raises PG error
```

### Error Handling

Postgres uses `longjmp` for errors, which bypasses Zig's `defer`/`errdefer`. Use `pgzx.err.Context` to safely catch Postgres errors:

```zig
var errctx = pgzx.err.Context.init();
defer errctx.deinit();
if (errctx.pg_try()) {
    // Call Postgres functions safely
    return pg.some_function();
} else {
    return errctx.errorValue();
}
```

Or use the convenience wrapper:

```zig
try pgzx.err.wrap(pg.some_function, .{arg1, arg2});
```

### Memory Management

Use Postgres memory contexts via pgzx allocators:

```zig
// Use current memory context
const allocator = pgzx.mem.PGCurrentContextAllocator;

// Create dedicated context
var memctx = try pgzx.mem.createAllocSetContext("my_context", .{
    .parent = pg.CurrentMemoryContext,
});
defer memctx.deinit();
const allocator = memctx.allocator();
```

### Hooks

Register Postgres hooks in `_PG_init`:

```zig
pub export fn _PG_init() void {
    prev_hook = pg.SomeHook;
    pg.SomeHook = my_hook;
}

fn my_hook(...) callconv(.c) void {
    // Implementation
    if (prev_hook) |hook| hook(...);
}
```

### GUC (Configuration) Variables

```zig
var my_setting: pgzx.guc.CustomBoolVariable = undefined;

pub export fn _PG_init() void {
    my_setting.register(.{
        .name = "myext.setting",
        .short_desc = "Description",
        .initial_value = true,
        .flags = pg.PGC_SUSET,
    });
}
```

## Testing

### Unit Tests

Register test suites using `pgzx.testing.registerTests`:

```zig
const Tests = struct {
    pub fn testSomething() !void {
        try std.testing.expectEqual(expected, actual);
    }

    pub fn testAnother() !void {
        // Test implementation
    }
};

comptime {
    pgzx.testing.registerTests(
        @import("build_options").testfn,
        .{Tests},
    );
}
```

Run with:
```bash
zig build -p $PG_HOME unit
```

Behind the scenes this:
1. Builds extension with `testfn=true`
2. Creates `run_tests()` SQL function
3. Calls `SELECT run_tests();`

### Regression Tests

Place SQL files in `sql/` directory and expected output in `expected/`:

```
extension/
├── sql/
│   └── test_name.sql
└── expected/
    └── test_name.out
```

Run with:
```bash
zig build pg_regress
```

### Running Specific Tests

```bash
zig build -Dtest_filter=testName -p $PG_HOME unit
```

## Debugging

### Debug Build

```bash
nix develop '.#debug'
pgbuild                    # Build Postgres in debug mode
pguse local                # Switch to local debug build
```

### Attaching Debugger

1. Start psql session: `psql -U postgres`
2. Get PID: `SELECT pg_backend_pid();`
3. Attach debugger: `lldb -p <PID>`
4. Force library load if needed:
   ```sql
   DROP FUNCTION run_tests;
   CREATE FUNCTION run_tests() RETURNS INTEGER AS '$libdir/pgzx_unit' LANGUAGE C IMMUTABLE;
   ```
5. Set breakpoints and continue:
   ```
   (lldb) b htab.zig:117
   (lldb) c
   ```
6. Trigger from psql: `SELECT run_tests();`

## Code Patterns

### C Interop

Access Postgres C API through `pgzx.pg` (or `pgzx.c`):

```zig
const pg = pgzx.pg;
const result = pg.palloc(size);
pg.pfree(result);
```

### Collections

```zig
// Hash tables
const table = try pgzx.HTab(MyContext).init("name", .{});
defer table.deinit();
const entry = try table.getOrPut(key);

// Lists
var list = pgzx.PointerListOf(MyType).init();
list.append(item);
```

### Return Types

pgzx automatically handles serialization of Zig types to Postgres datums. Supported:
- Integers, floats, booleans
- Slices (`[]const u8` for text)
- Optional types for nullable returns

## CI/CD

### Local CI

```bash
./ci/setup.sh    # Setup local postgres
./ci/run.sh      # Run all tests
```

### Pre-commit Hooks

Enabled hooks (via `pre-commit`):
- `zig fmt` - Zig formatting
- `alejandra` - Nix formatting  
- `deadnix` - Dead Nix code
- `shellcheck` / `shfmt` - Shell scripts
- `actionlint` - GitHub Actions

Run manually:
```bash
pre-commit run --all-files
```

## File Naming Conventions

- Extension SQL files: `<name>--<version>.sql` (e.g., `myext--0.1.sql`)
- Control files: `<name>.control`
- Main source: `src/main.zig` or `src/<name>.zig`
- Extension metadata: `extension/` directory
- Tests: `sql/` and `expected/` directories

## Gotchas

1. **Memory Context**: Always be aware of which memory context you're allocating in. Memory allocated in `CurrentMemoryContext` may be freed unexpectedly.

2. **Error Handling**: Postgres `ereport(ERROR, ...)` does a `longjmp`. Use `pgzx.err.Context` to ensure Zig cleanup code runs.

3. **Cache Invalidation**: Delete `.zig-cache` when switching Postgres versions.

4. **Shared Libraries**: Extension builds as `.dylib` (macOS) or `.so` (Linux). Postgres finds it via `$libdir`.

5. **Build Options**: The `testfn` build option controls whether test infrastructure is included. Set to `false` for production builds.

6. **Zig Version**: Project tracks Zig master branch. Use the Nix dev shell to ensure correct version (currently 0.14.0).

7. **macOS HTab/Hash Table Crash**: On macOS, the `pgzx.HTab` wrapper may crash due to symbol collision with BSD hsearch functions. macOS's `libSystem` exports `hash_create`, `hash_destroy`, and `hash_search` with different signatures than PostgreSQL's internal functions. Zig's linker uses two-level namespace by default, which can bind these symbols to libSystem instead of PostgreSQL. 
   
   **Symptoms**: Server crashes (SIGSEGV) when calling `hash_create()` or `hash_get_num_entries()`.
   
   **Workaround for C extensions**: Build with clang using:
   ```bash
   clang -bundle -bundle_loader $(pg_config --bindir)/postgres ...
   ```
   
   **Status**: HTab tests are disabled on macOS. The Zig build system needs to support `-flat_namespace` or bundle linking for a proper fix.

## Useful Links

- [pgzx Documentation](https://xataio.github.io/pgzx/#docs.pgzx)
- [PostgreSQL Extension Building](https://www.postgresql.org/docs/current/extend-extensions.html)
- [Zig Documentation](https://ziglang.org/documentation/master/)

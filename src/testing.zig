const std = @import("std");
const pgzx = @import("pgzx.zig");

comptime {
    pgzx.PG_MODULE_MAGIC();

    const build_options = @import("build_options");

    const all_suites = .{
        pgzx.collections.list.TestSuite_PointerList,
        pgzx.collections.slist.TestSuite_SList,
        pgzx.collections.dlist.TestSuite_DList,
        // HTab tests are disabled on macOS due to symbol collision with BSD hsearch.
        // macOS's libSystem exports hash_create/hash_destroy with different signatures,
        // and Zig's linker uses two-level namespace which binds to libSystem instead
        // of PostgreSQL. See: https://github.com/xataio/pgzx/issues/XXX
        // Workaround: Build with clang using -bundle -bundle_loader $(pg_config --bindir)/postgres
        // pgzx.collections.htab.TestSuite_HTab,
        pgzx.meta.TestSuite_Meta,
        pgzx.mem.TestSuite_Mem,
        pgzx.node.TestSuite_Node,
    };

    const filter = build_options.test_filter;
    if (filter.len == 0) {
        pgzx.testing.registerTests(
            build_options.testfn,
            all_suites,
        );
    } else {
        var found = false;
        for (all_suites) |suite| {
            if (std.mem.eql(u8, filter, @typeName(suite))) {
                pgzx.testing.registerTests(
                    build_options.testfn,
                    .{suite},
                );
                found = true;
            }
        }
        if (!found) {
            @compileError(std.fmt.comptimePrint("Test suite '{s}' not found. Check spelling and full namespace.", .{filter}));
        }
    }
}

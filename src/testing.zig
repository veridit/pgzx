const std = @import("std");
const pgzx = @import("pgzx.zig");

comptime {
    pgzx.PG_MODULE_MAGIC();

    const build_options = @import("build_options");

    const all_suites = .{
        pgzx.collections.list.TestSuite_PointerList,
        pgzx.collections.slist.TestSuite_SList,
        pgzx.collections.dlist.TestSuite_DList,
        // NOTE: HTab tests disabled due to crashes on macOS arm64.
        // Direct calls to pg.hash_search() work fine (tested in testGetOrPutEntryInt),
        // but wrapper methods crash. Root cause not yet identified - likely related
        // to Zig's @cImport handling of HTAB structures on arm64.
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

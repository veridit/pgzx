const std = @import("std");

// Load pgzx build support. The build utilities use pg_config to find all dependencies
// and provide functions go create and test extensions.
const PGBuild = @import("pgzx").Build;

pub fn build(b: *std.Build) void {
    const NAME = "spi_sql";
    const VERSION = PGBuild.ExtensionVersion{ .major = 0, .minor = 1 };

    const DB_TEST_USER = "postgres";
    const DB_TEST_PORT = 5432;

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var pgbuild = PGBuild.create(b, .{
        .target = target,
        .optimize = optimize,
    });

    const ext = pgbuild.addInstallExtension(.{
        .name = NAME,
        .version = VERSION,
        .source_file = b.path("src/main.zig"),
        .root_dir = "src/",
        .link_libc = true,
        .link_allow_shlib_undefined = true,
    });

    const steps = .{
        .check = b.step("check", "Check if project compiles"),
        .install = b.getInstallStep(),
        .pg_regress = b.step("pg_regress", "Run regression tests"),
    };

    { // build and install extension
        steps.install.dependOn(&ext.step);
    }

    { // check extension Zig source code only. No linkage or installation for faster development.
        const lib = pgbuild.addExtensionLib(.{
            .name = NAME,
            .version = VERSION,
            .source_file = b.path("src/main.zig"),
            .root_dir = "src/",
        });
        lib.linkage = null;
        steps.check.dependOn(&lib.step);
    }

    { // pg_regress tests (regression tests use the default build)
        var regress = pgbuild.addRegress(.{
            .db_user = DB_TEST_USER,
            .db_port = DB_TEST_PORT,
            .root_dir = ".",
            .scripts = &[_][]const u8{
                "spi_sql_test",
            },
        });
        regress.step.dependOn(steps.install);

        steps.pg_regress.dependOn(&regress.step);
    }
}

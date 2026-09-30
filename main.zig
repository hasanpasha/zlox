pub fn main(init: std.process.Init) !void {
    source_manager.init(init.io, init.gpa);
    defer source_manager.deinit();

    const zlox = try ZLOX.init(init.io, init.gpa);
    defer zlox.deinit();

    var args = init.minimal.args.iterate();
    _ = args.next() orelse unreachable;

    if (args.next()) |filepath| {
        try zlox.run_file(filepath);
    } else {
        try zlox.repl();
    }
}

const std = @import("std");
const log = std.log.scoped(.zlox);

const source_manager = @import("source_manager.zig");

const ZLOX = @import("ZLOX.zig");

pub fn main(init: std.process.Init) !void {
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

const ZLOX = @import("ZLOX.zig");

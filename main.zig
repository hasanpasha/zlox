pub fn main(init: std.process.Init) !void {
    source_manager.init(init.io, init.gpa);
    defer source_manager.deinit();

    const zlox = try ZLOX.init(init.io, init.gpa);
    defer zlox.deinit();

    try zlox.repl();
}

const std = @import("std");
const log = std.log.scoped(.zlox);

const source_manager = @import("source_manager.zig");

const ZLOX = @import("ZLOX.zig");

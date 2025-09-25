line: usize,
column: usize,

pub const start: @This() = .{ .line = 1, .column = 1 };

pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("{d:0>2}:{d:0>2}", .{ self.line, self.column });
}

const std = @import("std");

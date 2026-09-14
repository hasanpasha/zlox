pub const OpCode = enum(u8) {
    constant,
    nil,
    true,
    false,
    pop,
    get_global,
    define_global,
    set_global,
    equal,
    greater,
    less,
    negate,
    add,
    subtract,
    multiply,
    divide,
    not,
    print,
    @"return",
    _,

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("{s:<10}", .{@tagName(self)});
    }
};

const std = @import("std");

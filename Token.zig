pub const Kind = enum {
    lparen,
    rparen,
    lcub,
    rcub,
    comma,
    dot,
    minus,
    plus,
    semi,
    slash,
    astrsk,
    excl,
    excl_equl,
    equl,
    equl_equl,
    gt,
    gt_equl,
    lt,
    lt_equl,
    ident,
    str_lit,
    num_lit,
    @"and",
    class,
    @"else",
    false,
    @"for",
    fun,
    @"if",
    nil,
    @"or",
    print,
    @"return",
    super,
    this,
    true,
    @"var",
    @"while",

    err,
};

kind: Kind,
lexeme: []const u8,
location: Location,
error_msg: ?[]const u8 = null,

pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
    if (self.kind == .err) {
        try writer.print("error({s})[{s}] @ {f}", .{ self.error_msg.?, self.lexeme, self.location });
    } else {
        try writer.print("{s}[{s}] @ {f}", .{ @tagName(self.kind), self.lexeme, self.location });
    }
}

const std = @import("std");
const Location = @import("Location.zig");

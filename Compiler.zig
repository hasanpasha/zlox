scanner: Scanner,
chunk: *Chunk,
garbage_collector: *GarbageCollector,
prev: ?Token = null,
cur: ?Token = null,
peek: ?Token = null,
had_error: bool = false,
error_writer: *std.Io.Writer,

pub fn compile(code: []const u8, allocator: std.mem.Allocator, garbage_collector: *GarbageCollector, error_writer: *std.Io.Writer) !*Chunk {
    var self = Compiler{
        .scanner = .init(code),
        .chunk = try Chunk.init(allocator),
        .garbage_collector = garbage_collector,
        .error_writer = error_writer,
    };

    try self.advance();
    try self.advance();
    try self.expression();
    if (self.cur) |_| {
        try self.errorAtCur("expect end of expression.");
    }
    try self.end();

    return self.chunk;
}

fn end(self: *Compiler) !void {
    try self.chunk.write_op(.@"return", self.scanner.loc);
}

fn expression(self: *Compiler) !void {
    try self.parse_prec_expr(.assignment);
}

pub const Precedence = enum {
    none,
    assignment,
    @"or",
    @"and",
    equality,
    comparison,
    term,
    factor,
    unary,
    call,
    primary,

    pub fn le(self: Precedence, other: Precedence) bool {
        return @intFromEnum(self) <= @intFromEnum(other);
    }

    pub fn succ(self: Precedence) Precedence {
        return @enumFromInt(@intFromEnum(self) + 1);
    }
};

pub const PrecedenceRule = struct {
    prefix: *const fn (compiler: *Compiler) anyerror!void = none,
    infix: *const fn (compiler: *Compiler) anyerror!void = none,
    prec: Precedence = .none,

    fn none(self: *Compiler) anyerror!void {
        _ = self;
        return error.no_prefix_or_infix_function;
    }
};

pub const rules: std.EnumArray(TokenKind, PrecedenceRule) = .initDefault(.{}, .{
    .lparen = .{ .prefix = grouping },
    .num_lit = .{ .prefix = number, .prec = .primary },
    .minus = .{ .prefix = unary, .infix = binary, .prec = .term },
    .plus = .{ .infix = binary, .prec = .term },
    .astrsk = .{ .infix = binary, .prec = .factor },
    .slash = .{ .infix = binary, .prec = .factor },
    .nil = .{ .prefix = literal, .prec = .factor },
    .true = .{ .prefix = literal, .prec = .factor },
    .false = .{ .prefix = literal, .prec = .factor },
    .excl = .{ .prefix = unary, .prec = .unary },
    .equl_equl = .{ .infix = binary, .prec = .equality },
    .excl_equl = .{ .infix = binary, .prec = .equality },
    .lt = .{ .infix = binary, .prec = .comparison },
    .lt_equl = .{ .infix = binary, .prec = .comparison },
    .gt = .{ .infix = binary, .prec = .comparison },
    .gt_equl = .{ .infix = binary, .prec = .comparison },
    .str_lit = .{ .prefix = string, .prec = .primary },
});

fn get_cur_rule(self: *Compiler) !PrecedenceRule {
    const cur = self.cur orelse return error.unexpected_end;
    return rules.get(cur.kind);
}

fn parse_prec_expr(self: *Compiler, prec: Precedence) !void {
    const prule = try self.get_cur_rule();
    try prule.prefix(self);

    while (self.cur != null and prec.le((try self.get_cur_rule()).prec)) {
        const irule = try self.get_cur_rule();
        try irule.infix(self);
    }
}

fn unary(self: *Compiler) anyerror!void {
    const operator = self.cur.?;
    try self.advance();

    try self.parse_prec_expr(.unary);

    switch (operator.kind) {
        .minus => try self.emitOp(.negate),
        .excl => try self.emitOp(.not),
        else => unreachable,
    }
}

fn binary(self: *Compiler) anyerror!void {
    const operator = self.cur.?;
    try self.advance();

    const rule = rules.get(operator.kind);
    try self.parse_prec_expr(rule.prec.succ());

    switch (operator.kind) {
        .plus => try self.emitOp(.add),
        .minus => try self.emitOp(.subtract),
        .astrsk => try self.emitOp(.multiply),
        .slash => try self.emitOp(.divide),
        .equl_equl => try self.emitOp(.equal),
        .excl_equl => try self.emitOps(.equal, .not),
        .lt => try self.emitOp(.less),
        .lt_equl => try self.emitOps(.greater, .not),
        .gt => try self.emitOp(.greater),
        .gt_equl => try self.emitOps(.less, .not),
        else => unreachable,
    }
}

fn grouping(self: *Compiler) anyerror!void {
    try self.consume(.lparen);
    try self.expression();
    try self.consume(.rparen);
}

fn number(self: *Compiler) anyerror!void {
    const num = try self.expect(.num_lit);
    const value: f64 = try std.fmt.parseFloat(f64, num.lexeme);
    try self.chunk.write_constant(.{ .number = value }, num.location);
}

fn literal(self: *Compiler) anyerror!void {
    const token = self.cur.?;
    try self.advance();

    switch (token.kind) {
        .true => try self.emitOp(.true),
        .false => try self.emitOp(.false),
        .nil => try self.emitOp(.nil),
        else => unreachable,
    }
}

fn string(self: *Compiler) anyerror!void {
    const token = try self.expect(.str_lit);
    const lit = token.lexeme[1 .. token.lexeme.len - 1];
    const object = Object.castDown(try self.garbage_collector.copyString(lit));
    try self.chunk.write_constant(.{ .object = object }, token.location);
}

fn emitOps(self: *Compiler, a: OpCode, b: OpCode) !void {
    try self.emitOp(a);
    try self.emitOp(b);
}

fn emitOp(self: *Compiler, code: OpCode) !void {
    try self.chunk.write_op(code, self.prev.?.location);
}

fn emitReturn(self: *Compiler) !void {
    self.chunk.write_op(.@"return", self.cur.?.location);
}

fn advance(self: *Compiler) !void {
    self.prev = self.cur;
    self.cur = self.peek;

    while (true) {
        const token = self.scanner.next();
        self.peek = token;

        if (token == null) break;
        if (token.?.kind != .err) break;

        try self.errorAtPeek(token.?.error_msg orelse "");
    }
}

fn expect(self: *Compiler, kind: TokenKind) !Token {
    if (self.cur) |cur| {
        if (cur.kind == kind) {
            try self.advance();
            return cur;
        }

        return error.unexpected_token;
    }

    return error.unexpected_end;
}

fn consume(self: *Compiler, kind: TokenKind) !void {
    _ = try self.expect(kind);
}

fn errorAtCur(self: *Compiler, msg: []const u8) !void {
    try self.errorAt(self.cur, msg);
}

fn errorAtPeek(self: *Compiler, msg: []const u8) !void {
    try self.errorAt(self.peek, msg);
}

fn errorAt(self: *Compiler, token: ?Token, msg: []const u8) !void {
    self.had_error = true;
    if (token) |tok| {
        try self.error_writer.print("[{f}] error: {s}\n", .{ tok.location, msg });
    } else {
        try self.error_writer.print("[{f}] error: {s}\n", .{ self.scanner.loc, msg });
    }
}

const Compiler = @This();
const std = @import("std");
const Scanner = @import("Scanner.zig");
const Chunk = @import("Chunk.zig");
const GarbageCollector = @import("GarbageCollector.zig");
const Token = @import("Token.zig");
const TokenKind = Token.Kind;
const Object = @import("Object.zig");
const OpCode = @import("op_code.zig").OpCode;

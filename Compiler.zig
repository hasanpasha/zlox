scanner: Scanner,
chunk: *Chunk,
garbage_collector: *GarbageCollector,
prev: ?Token = null,
cur: ?Token = null,
peek: ?Token = null,
had_error: bool = false,
error_writer: *std.Io.Writer,

pub const Error = error{
    eoi,
    unexpected_token,
    lexer_error,
};

pub const MainError = (Error || AllocError || WriterError || Chunk.Error || std.fmt.ParseFloatError);

pub fn compile(code: []const u8, allocator: std.mem.Allocator, garbage_collector: *GarbageCollector, error_writer: *std.Io.Writer) MainError!*Chunk {
    var self = Compiler{
        .scanner = .init(code),
        .chunk = try Chunk.init(allocator),
        .garbage_collector = garbage_collector,
        .error_writer = error_writer,
    };

    errdefer self.chunk.deinit();

    try self.advance();
    try self.advance();

    while (self.cur) |_| {
        try self.declaration();
    }

    if (self.cur) |_| {
        try self.error_at_cur("expect end of expression.");
    }

    try self.end();

    return self.chunk;
}

fn end(self: *Compiler) AllocError!void {
    try self.chunk.write_op(.@"return", self.scanner.loc);
}

fn synchronize(self: *Compiler) Error!void {
    while (self.cur) |cur| {
        if (self.prev) |prev| {
            if (prev.kind == .semi) return;
        }

        switch (cur.kind) {
            .class, .fun, .@"var", .@"for", .@"if", .@"while", .print, .@"return" => return,
            else => {},
        }
        self.advance() catch {};
    }
}

fn declaration(self: *Compiler) MainError!void {
    const cur = self.cur orelse unreachable;

    switch (cur.kind) {
        .@"var" => try self.var_decl(),
        else => self.statement() catch |err| {
            try self.error_writer.print("syntax error: {}\n", .{err});
            try self.error_writer.flush();

            try switch (err) {
                Error.unexpected_token, Error.lexer_error => self.synchronize(),
                else => err,
            };
        },
    }
}

fn var_decl(self: *Compiler) MainError!void {
    try self.consume(.@"var");
    const global = try self.parse_variable();

    if (self.match(.equl)) {
        try self.expression();
    } else {
        try self.emit_op(.nil);
    }
    try self.consume(.semi);

    try self.define_variable(global);
}

fn parse_variable(self: *Compiler) MainError!u8 {
    const tok = try self.expect(.ident);
    return self.ident_constant(tok);
}

fn define_variable(self: *Compiler, global: u8) AllocError!void {
    try self.emit_op(.define_global);
    try self.chunk.write(global, self.prev.?.location);
}

fn ident_constant(self: *Compiler, tok: Token) MainError!u8 {
    const ident = (try self.garbage_collector.copyString(tok.lexeme));
    return self.chunk.add_constant(.{ .object = Object.castDown(ident) });
}

fn statement(self: *Compiler) MainError!void {
    const cur = self.cur orelse unreachable;
    switch (cur.kind) {
        .print => try self.print_stmt(),
        else => try self.expr_stmt(),
    }
}

fn print_stmt(self: *Compiler) MainError!void {
    const print_tok = try self.expect(.print);
    try self.expression();
    try self.consume(.semi);
    try self.chunk.write_op(.print, print_tok.location);
}

fn expr_stmt(self: *Compiler) MainError!void {
    try self.expression();
    try self.consume(.semi);
    try self.emit_op(.pop);
}

fn expression(self: *Compiler) MainError!void {
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
    prefix: *const fn (compiler: *Compiler, can_assign: bool) MainError!void = no_prefix,
    infix: *const fn (compiler: *Compiler) MainError!void = no_infix,
    prec: Precedence = .none,

    fn no_prefix(_: *Compiler, _: bool) MainError!void {
        return error.unexpected_token;
    }

    fn no_infix(_: *Compiler) MainError!void {
        return error.unexpected_token;
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
    .ident = .{ .prefix = variable, .prec = .primary },
});

fn get_cur_rule(self: *Compiler) MainError!PrecedenceRule {
    const cur = self.cur orelse return Error.eoi;
    return rules.get(cur.kind);
}

fn parse_prec_expr(self: *Compiler, prec: Precedence) MainError!void {
    const prule = try self.get_cur_rule();
    try prule.prefix(self, prec.le(.assignment));

    while (self.cur != null and prec.le((try self.get_cur_rule()).prec)) {
        const irule = try self.get_cur_rule();
        try irule.infix(self);
    }
}

fn unary(self: *Compiler, _: bool) MainError!void {
    const operator = self.cur.?;
    try self.advance();

    try self.parse_prec_expr(.unary);

    switch (operator.kind) {
        .minus => try self.emit_op(.negate),
        .excl => try self.emit_op(.not),
        else => unreachable,
    }
}

fn binary(self: *Compiler) MainError!void {
    const operator = self.cur.?;
    try self.advance();

    const rule = rules.get(operator.kind);
    try self.parse_prec_expr(rule.prec.succ());

    switch (operator.kind) {
        .plus => try self.emit_op(.add),
        .minus => try self.emit_op(.subtract),
        .astrsk => try self.emit_op(.multiply),
        .slash => try self.emit_op(.divide),
        .equl_equl => try self.emit_op(.equal),
        .excl_equl => try self.emit_ops(.equal, .not),
        .lt => try self.emit_op(.less),
        .lt_equl => try self.emit_ops(.greater, .not),
        .gt => try self.emit_op(.greater),
        .gt_equl => try self.emit_ops(.less, .not),
        else => unreachable,
    }
}

fn grouping(self: *Compiler, _: bool) MainError!void {
    try self.consume(.lparen);
    try self.expression();
    try self.consume(.rparen);
}

fn number(self: *Compiler, _: bool) MainError!void {
    const num = try self.expect(.num_lit);
    const value: f64 = try std.fmt.parseFloat(f64, num.lexeme);
    try self.chunk.write_constant(.{ .number = value }, num.location);
}

fn literal(self: *Compiler, _: bool) MainError!void {
    const token = self.cur.?;
    try self.advance();

    switch (token.kind) {
        .true => try self.emit_op(.true),
        .false => try self.emit_op(.false),
        .nil => try self.emit_op(.nil),
        else => unreachable,
    }
}

fn string(self: *Compiler, _: bool) MainError!void {
    const token = try self.expect(.str_lit);
    const lit = token.lexeme[1 .. token.lexeme.len - 1];
    const object = Object.castDown(try self.garbage_collector.copyString(lit));
    try self.chunk.write_constant(.{ .object = object }, token.location);
}

fn variable(self: *Compiler, can_assign: bool) MainError!void {
    const tok = try self.expect(.ident);
    try self.named_variable(tok, can_assign);
}

fn named_variable(self: *Compiler, tok: Token, can_assign: bool) MainError!void {
    const arg = try self.ident_constant(tok);

    if (can_assign and self.match(.equl)) {
        try self.expression();
        try self.emit_op(.set_global);
    } else {
        try self.emit_op(.get_global);
    }

    try self.chunk.write(arg, tok.location);
}

fn emit_ops(self: *Compiler, a: OpCode, b: OpCode) AllocError!void {
    try self.emit_op(a);
    try self.emit_op(b);
}

fn emit_op(self: *Compiler, code: OpCode) AllocError!void {
    try self.chunk.write_op(code, self.prev.?.location);
}

fn emit_return(self: *Compiler) AllocError!void {
    self.chunk.write_op(.@"return", self.cur.?.location);
}

fn advance(self: *Compiler) MainError!void {
    self.prev = self.cur;
    self.cur = self.peek;

    while (true) {
        const token = self.scanner.next();
        self.peek = token;

        if (token == null) break;
        if (token.?.kind != .err) break;

        try self.error_at_peek(token.?.error_msg orelse "");
    }
}

fn match(self: *Compiler, kind: TokenKind) bool {
    if (self.cur) |cur| {
        if (cur.kind == kind) {
            self.advance() catch unreachable;
            return true;
        }
    }

    return false;
}

fn expect(self: *Compiler, kind: TokenKind) MainError!Token {
    if (self.cur) |cur| {
        if (cur.kind == kind) {
            try self.advance();
            return cur;
        }

        return Error.unexpected_token;
    }

    return Error.eoi;
}

fn consume(self: *Compiler, kind: TokenKind) MainError!void {
    _ = try self.expect(kind);
}

fn error_at_cur(self: *Compiler, msg: []const u8) WriterError!void {
    try self.error_at(self.cur, msg);
}

fn error_at_peek(self: *Compiler, msg: []const u8) WriterError!void {
    try self.error_at(self.peek, msg);
}

fn error_at(self: *Compiler, token: ?Token, msg: []const u8) WriterError!void {
    self.had_error = true;
    if (token) |tok| {
        try self.error_writer.print("[{f}] error: {s}\n", .{ tok.location, msg });
    } else {
        try self.error_writer.print("[{f}] error: {s}\n", .{ self.scanner.loc, msg });
    }
}

const Compiler = @This();
const std = @import("std");
const AllocError = std.mem.Allocator.Error;
const WriterError = std.Io.Writer.Error;

const Scanner = @import("Scanner.zig");
const Chunk = @import("Chunk.zig");
const GarbageCollector = @import("GarbageCollector.zig");
const Token = @import("Token.zig");
const TokenKind = Token.Kind;
const Object = @import("Object.zig");
const OpCode = @import("op_code.zig").OpCode;

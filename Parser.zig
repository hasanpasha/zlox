tokens: std.ArrayList(Token),

pos: usize = 0,
fuel: u32 = 256,
events: std.ArrayList(Event) = .empty,

arena: std.mem.Allocator,

pub const Event = union(enum) {
    open: CST.Tree.Tag,
    close,
    advance,
};

pub const MarkOpened = enum(usize) { _ };

pub const MarkClosed = enum(usize) { _ };

pub const Error = std.mem.Allocator.Error;

fn open(self: *Parser) Error!MarkOpened {
    const mark: MarkOpened = @enumFromInt(self.events.items.len);
    try self.events.append(self.arena, undefined);
    return mark;
}

fn open_before(self: *Parser, mark: MarkClosed) Error!MarkOpened {
    const open_mark: MarkOpened = @enumFromInt(@intFromEnum(mark));
    try self.events.insert(self.arena, @intFromEnum(mark), undefined);
    return open_mark;
}

fn close(self: *Parser, mark: MarkOpened, kind: CST.Tree.Tag) Error!MarkClosed {
    self.events.items[@intFromEnum(mark)] = .{ .open = kind };
    try self.events.append(self.arena, .close);
    return @enumFromInt(@intFromEnum(mark));
}

fn advance(self: *Parser) Error!void {
    // if (self.eof()) @panic("EOF");
    self.fuel = 256;

    for (self.pos..self.tokens.items.len) |pos| {
        try self.events.append(self.arena, .advance);
        self.pos += 1;
        if (self.tokens.items[pos].tag.is_trivia()) continue;
        break;
    }
}

fn eof(self: *Parser) bool {
    return self.nth_tag(0) == .eof;
}

fn nth_token(self: *Parser, lookahead: usize) Token {
    if (self.fuel == 0) @panic("parser is stuck");
    self.fuel -= 1;

    var look_idx: usize = 0;
    for (self.pos..self.tokens.items.len) |j| {
        const token = self.tokens.items[j];

        if (token.tag.is_trivia()) continue;

        if (look_idx == lookahead) return token;

        look_idx += 1;
    }

    return self.tokens.getLast();
}

fn nth_span(self: *Parser, lookahead: usize) Token.Span {
    return self.nth_token(lookahead).span;
}

fn nth_tag(self: *Parser, lookahead: usize) Token.Tag {
    return self.nth_token(lookahead).tag;
}

fn at(self: *Parser, kind: Token.Tag) bool {
    return self.nth_tag(0) == kind;
}

fn at_any(self: *Parser, kinds: []const Token.Tag) bool {
    const cur = self.nth_tag(0);

    return for (kinds) |kind| {
        if (cur == kind) return true;
    } else false;
}

fn eat(self: *Parser, kind: Token.Tag) Error!bool {
    if (!self.at(kind)) return false;
    try self.advance();
    return true;
}

fn expect(self: *Parser, kind: Token.Tag) Error!void {
    if (try self.eat(kind)) return;

    // const cur_token = self.nth_token(0);

    // self.diags.err(
    //     self.source_idx,
    //     cur_token.span,
    //     "unexpected token: expected `{t}`, found `{t}`",
    //     .{ kind, cur_token.Tag },
    // );

    const m = try self.open();
    _ = try self.close(m, .err);
}

fn expect_one_of(self: *Parser, kinds: []const Token.Tag) Error!void {
    if (self.at_any(kinds)) {
        try self.advance();
    } else {
        const m = try self.open();
        _ = try self.close(m, .err);
    }
}

fn advance_with_error(self: *Parser, err: []const u8) Error!void {
    const m = try self.open();

    _ = err;
    // self.diags.err(self.source_idx, self.nth_span(0), "{s}", .{err});

    try self.advance();

    _ = try self.close(m, .err);
}

fn advance_until(self: *Parser, kinds: []const Token.Tag) Error!void {
    while (!(self.at_any(kinds)) and !self.eof()) {
        try self.advance();
    }
}

fn advance_with_error_until(self: *Parser, err: []const u8, kinds: []const Token.Tag) Error!void {
    const m = try self.open();

    _ = err;
    // self.diags.err(self.source_idx, self.nth_span(0), "{s}", .{err});
    try self.advance_until(kinds);

    _ = try self.close(m, .err);
}

fn build_tree(self: *Parser) Error!Tree {
    var tokens: TokenIter = .{ .tokens = self.tokens.items };
    var stack: std.ArrayList(Tree) = .empty;

    // Special case: pop the last `Close` event to ensure
    // that the stack is non-empty inside the loop.
    _ = self.events.pop();

    for (self.events.items) |event| {
        switch (event) {
            .open => |tag| {
                try stack.append(self.arena, .{ .tag = tag, .children = .empty });
            },
            .close => {
                const tree = stack.pop() orelse unreachable;
                try stack.items[stack.items.len - 1].children.append(self.arena, .{ .tree = tree });
            },
            .advance => {
                const token = tokens.next() orelse unreachable;
                try stack.items[stack.items.len - 1].children.append(self.arena, .{ .token = token });
            },
        }
    }

    std.debug.assert(tokens.next() == null);

    return stack.pop() orelse unreachable;
}

const TokenIter = struct {
    tokens: []const Token,
    idx: usize = 0,

    pub fn next(self: *TokenIter) ?Token {
        if (self.idx == self.tokens.len) return null;
        defer self.idx += 1;
        return self.tokens[self.idx];
    }
};

const EXPR_RESUME = [_]Token.Tag{ .number, .plus, .minus, .star, .slash, .left_paren };
const EXPR_BOUNDARY = [_]Token.Tag{ .semicolon, .right_paren, .right_brace, .comma } ++ STMT_RECOVERY ++ DECL_RECOVERY;

const STMT_RECOVERY = [_]Token.Tag{ .@"return", .print };
const DECL_RECOVERY = [_]Token.Tag{.@"var"};

const STMT_TAGS = [_]Token.Tag{ .left_brace, .print, .@"var" };

const Precedence = enum {
    assignment, // =
    equality, // == !=
    comparison, // > >= < <=
    term, // + -
    factor, // * /
    unary, // ! -
    parimary, // literals

    pub const lowest: Precedence = @enumFromInt(0);

    pub fn le(self: Precedence, other: Precedence) bool {
        return @intFromEnum(self) <= @intFromEnum(other);
    }

    pub fn next(self: Precedence) Precedence {
        return @enumFromInt(@intFromEnum(self) + 1);
    }
};

const PrecedenceRule = struct {
    prefix: ?*const fn (self: *Parser) Error!MarkClosed = null,
    infix: ?*const fn (self: *Parser, mark: MarkClosed) Error!MarkClosed = null,
    prec: Precedence = .lowest,
    associativity: enum { left, right } = .left,
};

fn literal_expr(self: *Parser) Error!MarkClosed {
    const m = try self.open();

    try self.expect_one_of(&.{ .number, .string, .true, .false, .nil });

    return try self.close(m, .literal_expr);
}

fn var_expr(self: *Parser) Error!MarkClosed {
    const m = try self.open();

    try self.expect(.identifier);

    return try self.close(m, .var_expr);
}

fn unary_expr(self: *Parser) Error!MarkClosed {
    const m = try self.open();

    try self.advance();
    try self.parse_expr_prec(.unary);

    return try self.close(m, .unary_expr);
}

fn binary_expr(self: *Parser, lhs: MarkClosed) Error!MarkClosed {
    const m = try self.open_before(lhs);

    const op = self.nth_tag(0);
    try self.advance();
    try self.parse_expr_prec(rules.get(op).prec.next());

    return try self.close(m, .binary_expr);
}

fn assign_expr(self: *Parser, lhs: MarkClosed) Error!MarkClosed {
    const m = try self.open_before(lhs);

    const op = self.nth_tag(0);
    try self.advance();
    try self.parse_expr_prec(rules.get(op).prec);

    return try self.close(m, .assign_expr);
}

fn grouping_expr(self: *Parser) Error!MarkClosed {
    const m = try self.open();

    try self.expect(.left_paren);
    try self.expr();
    try self.expect(.right_paren);

    return try self.close(m, .group_expr);
}

const rules: std.enums.EnumArray(Token.Tag, PrecedenceRule) = .initDefault(.{}, .{
    .equal = .{ .infix = assign_expr, .prec = .assignment },
    .equal_equal = .{ .infix = binary_expr, .prec = .equality },
    .bang_equal = .{ .infix = binary_expr, .prec = .equality },
    .less = .{ .infix = binary_expr, .prec = .comparison },
    .less_equal = .{ .infix = binary_expr, .prec = .comparison },
    .greater = .{ .infix = binary_expr, .prec = .comparison },
    .greater_equal = .{ .infix = binary_expr, .prec = .comparison },
    .plus = .{ .infix = binary_expr, .prec = .term },
    .minus = .{ .prefix = unary_expr, .infix = binary_expr, .prec = .term },
    .star = .{ .infix = binary_expr, .prec = .factor },
    .slash = .{ .infix = binary_expr, .prec = .factor },
    .bang = .{ .prefix = unary_expr },
    .number = .{ .prefix = literal_expr },
    .string = .{ .prefix = literal_expr },
    .true = .{ .prefix = literal_expr },
    .false = .{ .prefix = literal_expr },
    .nil = .{ .prefix = literal_expr },
    .left_paren = .{ .prefix = grouping_expr },
    .identifier = .{ .prefix = var_expr },
});

fn prefix_err_expr(self: *Parser) Error!MarkClosed {
    const m = try self.open();

    // self.diags.err(self.source_idx, self.nth_span(0), "can't parse prefix expression", .{});

    if (!self.at_any(&EXPR_BOUNDARY)) {
        try self.advance_until(&(EXPR_RESUME ++ EXPR_BOUNDARY));
    }

    return try self.close(m, .err);
}

fn infix_err_expr(self: *Parser, lhs: MarkClosed) Error!MarkClosed {
    const m = try self.open_before(lhs);

    try self.advance_with_error_until("can't parse infix expression", &(EXPR_RESUME ++ EXPR_BOUNDARY));

    if (self.at_any(&.{ .number, .minus, .left_paren })) {
        try self.parse_expr_prec(rules.get(self.nth_tag(0)).prec.next());
        return self.close(m, .binary_expr);
    } else {
        return self.close(m, .err);
    }
}

fn parse_expr_prec(self: *Parser, prec: Precedence) Error!void {
    const prefix_fn = rules.get(self.nth_tag(0)).prefix orelse prefix_err_expr;

    var lhs = try prefix_fn(self);

    while (!self.eof() and !self.at_any(&EXPR_BOUNDARY)) {
        const next_rule = rules.get(self.nth_tag(0));

        if (!prec.le(next_rule.prec)) break;

        const infix_fn = next_rule.infix orelse infix_err_expr;

        lhs = try infix_fn(self, lhs);
    }
}

fn expr(self: *Parser) Error!void {
    try self.parse_expr_prec(.lowest);
}

fn print_stmt(self: *Parser) Error!void {
    const m = try self.open();

    try self.expect(.print);
    try self.expr();
    try self.expect(.semicolon);

    _ = try self.close(m, .print_stmt);
}

fn block_stmt(self: *Parser) Error!void {
    const m = try self.open();

    try self.expect(.left_brace);

    while (!self.eof() and !self.at(.right_brace)) {
        try self.decl();
    }

    try self.expect(.right_brace);

    _ = try self.close(m, .block_stmt);
}

fn expr_stmt(self: *Parser) Error!void {
    const m = try self.open();

    try self.expr();
    try self.expect(.semicolon);

    _ = try self.close(m, .expr_stmt);
}

fn stmt(self: *Parser) Error!void {
    switch (self.nth_tag(0)) {
        .print => try self.print_stmt(),
        .left_brace => try self.block_stmt(),
        else => try self.expr_stmt(),
    }
}

fn var_decl(self: *Parser) Error!void {
    const m = try self.open();

    try self.expect(.@"var");
    try self.expect(.identifier);

    if (try self.eat(.equal)) {
        try self.expr();
    }

    try self.expect(.semicolon);

    _ = try self.close(m, .var_decl);
}

fn decl(self: *Parser) Error!void {
    switch (self.nth_tag(0)) {
        .@"var" => try self.var_decl(),
        else => try self.stmt(),
    }
}

fn program(self: *Parser) Error!void {
    const m = try self.open();

    while (!self.eof())
        try self.decl();

    try self.expect(.eof);

    _ = try self.close(m, .program);
}

fn repl_cmd(self: *Parser) Error!void {
    const m = try self.open();

    try self.expect(.colon);

    try self.expect(.identifier);

    _ = try self.close(m, .repl_cmd);
}

fn repl_item(self: *Parser) Error!void {
    const m = try self.open();

    const tag = self.nth_tag(0);
    if (tag.is_one_of(&STMT_TAGS)) {
        try self.decl();
    } else if (tag == .colon) {
        try self.repl_cmd();
    } else {
        try self.expr();
    }

    try self.expect(.eof);

    _ = try self.close(m, .repl_item);
}

pub fn parse_program(tokens: std.ArrayList(Token), allocator: Allocator) Error!HeapValue(Tree) {
    var cst: HeapValue(Tree) = .create(allocator);
    errdefer cst.free();

    var self: Parser = .{ .tokens = tokens, .arena = cst.arena.allocator() };

    try self.program();
    cst.value = try self.build_tree();

    return cst;
}

pub fn parse_repl_item(tokens: std.ArrayList(Token), allocator: Allocator) Error!HeapValue(Tree) {
    var cst: HeapValue(Tree) = .create(allocator);
    errdefer cst.free();

    var self: Parser = .{ .tokens = tokens, .arena = cst.arena.allocator() };

    try self.repl_item();
    cst.value = try self.build_tree();

    return cst;
}

const Parser = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.parser);

const Mode = @import("ZLOX.zig").Mode;

const Token = @import("Token.zig");
const Lexer = @import("Lexer.zig");

const CST = @import("CST.zig");
const Tree = CST.Tree;

const Source = @import("source_manager.zig").Source;

const HeapValue = @import("heap_value.zig").HeapValue;

// const Diagnostics = @import("Diagnostics.zig");

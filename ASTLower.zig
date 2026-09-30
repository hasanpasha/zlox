source: Source,
source_manager: *const SourceManager,
arena: std.mem.Allocator,

pub const Error = error{
    deformed_cst,
    invalid_number,
    invalid_literal,
    invalid_operator,
    missing_semicolon,
    invalid_lvalue,
} || std.mem.Allocator.Error;

const ITER_CONF: []const Tree.Iter.Ignore = &.{.token_tag_check(Token.Tag.is_trivia)};

fn alloc_expr(self: *ASTLower, exp: Expr) Error!*Expr {
    const mem = try self.arena.create(Expr);
    mem.* = exp;
    return mem;
}

fn literal_expr(self: *ASTLower, tree: Tree) Error!?Expr {
    var iter = tree.iter(ITER_CONF);

    const literal_tok = iter.next_token() orelse return Error.deformed_cst;
    const literal_exp: Expr.Literal = switch (literal_tok.tag) {
        .number => blk: {
            const lexeme = self.source_manager.get_lexeme(self.source, literal_tok.span);
            const number = std.fmt.parseFloat(f64, lexeme) catch return Error.invalid_number;
            break :blk .{ .number = number };
        },
        .string => blk: {
            const lexeme = self.source_manager.get_lexeme(self.source, literal_tok.span);
            break :blk .{ .string = lexeme[1 .. lexeme.len - 1] };
        },
        .true => .{ .boolean = true },
        .false => .{ .boolean = false },
        .nil => .nil,
        else => return Error.invalid_literal,
    };

    if (iter.peek()) |_| return Error.deformed_cst;

    return .{ .literal = literal_exp };
}

fn var_expr(self: *ASTLower, tree: Tree) Error!?Expr {
    var iter = tree.iter(ITER_CONF);

    const ident_tok = iter.next_token_if(&.{.identifier}) orelse return Error.deformed_cst;
    const name = self.source_manager.get_lexeme(self.source, ident_tok.span);

    if (iter.peek()) |_| return Error.deformed_cst;

    return .{ .@"var" = name };
}

fn unary_expr(self: *ASTLower, tree: Tree) Error!?Expr {
    var iter = tree.iter(ITER_CONF);

    const op_child = iter.next() orelse return Error.deformed_cst;
    const op_tok = if (op_child == .token) op_child.token else return null;
    const op: Expr.Unary.Op = switch (op_tok.tag) {
        .bang => .not,
        .minus => .neg,
        else => return Error.invalid_operator,
    };

    const rhs_tree = iter.next_tree() orelse return Error.deformed_cst;
    const rhs_exp = try self.expr(rhs_tree) orelse return null;
    const rhs = try self.alloc_expr(rhs_exp);

    if (iter.peek()) |_| return Error.deformed_cst;

    return .{ .unary = .{
        .op = op,
        .rhs = rhs,
    } };
}

fn binary_expr(self: *ASTLower, tree: Tree) Error!?Expr {
    var iter = tree.iter(ITER_CONF);

    const lhs_tree = iter.next_tree() orelse return Error.deformed_cst;
    const lhs_exp = try self.expr(lhs_tree) orelse return null;
    const lhs = try self.alloc_expr(lhs_exp);

    const op_child = iter.next() orelse return Error.deformed_cst;
    const op_tok = if (op_child == .token) op_child.token else return null;

    const op: Expr.Binary.Op = switch (op_tok.tag) {
        .plus => .add,
        .minus => .sub,
        .star => .mul,
        .slash => .div,
        .less => .lt,
        .less_equal => .le,
        .greater => .gt,
        .greater_equal => .ge,
        .equal_equal => .eq,
        .bang_equal => .ne,
        else => return Error.invalid_operator,
    };

    const rhs_tree = iter.next_tree() orelse return Error.deformed_cst;
    const rhs_exp = try self.expr(rhs_tree) orelse return null;
    const rhs = try self.alloc_expr(rhs_exp);

    if (iter.peek()) |_| return Error.deformed_cst;

    return .{ .binary = .{
        .op = op,
        .lhs = lhs,
        .rhs = rhs,
    } };
}

fn assign_expr(self: *ASTLower, tree: Tree) Error!?Expr {
    var iter = tree.iter(ITER_CONF);

    const lhs_tree = iter.next_tree() orelse return Error.deformed_cst;
    const lhs_exp = try self.expr(lhs_tree) orelse return null;
    const name = switch (lhs_exp) {
        .@"var" => |name| name,
        else => return Error.invalid_lvalue,
    };

    if (!iter.match_token(.equal)) return Error.deformed_cst;

    const value_tree = iter.next_tree() orelse return Error.deformed_cst;
    const value_exp = try self.expr(value_tree) orelse return null;
    const value = try self.alloc_expr(value_exp);

    if (iter.peek()) |_| return Error.deformed_cst;

    return .{ .assign = .{
        .name = name,
        .value = value,
    } };
}

fn group_expr(self: *ASTLower, tree: Tree) Error!?Expr {
    var iter = tree.iter(ITER_CONF);

    if (!iter.match_token(.left_paren)) return Error.deformed_cst;

    const exp_tree = iter.next_tree() orelse return Error.deformed_cst;
    const exp = try self.expr(exp_tree) orelse return null;

    if (!iter.match_token(.right_paren)) return Error.deformed_cst;

    if (iter.peek()) |_| return Error.deformed_cst;

    return exp;
}

fn expr(self: *ASTLower, tree: Tree) Error!?Expr {
    return switch (tree.tag) {
        .literal_expr => try self.literal_expr(tree),
        .var_expr => try self.var_expr(tree),
        .unary_expr => try self.unary_expr(tree),
        .binary_expr => try self.binary_expr(tree),
        .assign_expr => try self.assign_expr(tree),
        .group_expr => try self.group_expr(tree),
        .err => return null,
        else => unreachable,
    };
}

fn expr_stmt(self: *ASTLower, tree: Tree) Error!?Stmt {
    var iter = tree.iter(ITER_CONF);

    const exp_tree = iter.next_tree() orelse return Error.deformed_cst;
    const exp = try self.expr(exp_tree) orelse return null;

    if (!iter.match_token(.semicolon)) return Error.missing_semicolon;

    if (iter.peek()) |_| return Error.deformed_cst;

    return .{ .expr = exp };
}

fn print_stmt(self: *ASTLower, tree: Tree) Error!?Stmt {
    var iter = tree.iter(ITER_CONF);

    if (!iter.match_token(.print)) return Error.deformed_cst;

    const exp_tree = iter.next_tree() orelse return Error.deformed_cst;
    const exp = try self.expr(exp_tree) orelse return null;

    if (!iter.match_token(.semicolon)) return Error.missing_semicolon;

    if (iter.peek()) |_| return Error.deformed_cst;

    return .{ .print = exp };
}

fn block_stmt(self: *ASTLower, tree: Tree) Error!?Stmt {
    var iter = tree.iter(ITER_CONF);

    if (!iter.match_token(.left_brace)) return Error.deformed_cst;

    var block: std.ArrayList(Stmt) = .empty;

    while (iter.next_tree()) |stmt_tree| {
        if (try self.stmt(stmt_tree)) |inner_stmt| {
            try block.append(self.arena, inner_stmt);
        }
    }

    if (!iter.match_token(.right_brace)) return Error.deformed_cst;

    if (iter.peek()) |_| return Error.deformed_cst;

    return .{ .block = block };
}

fn var_decl(self: *ASTLower, tree: Tree) Error!?Stmt {
    var iter = tree.iter(ITER_CONF);

    if (!iter.match_token(.@"var")) return Error.deformed_cst;

    const ident_tok = iter.next_token_if(&.{.identifier}) orelse return Error.deformed_cst;
    // const name = ident_tok.lexeme();
    const name = self.source_manager.get_lexeme(self.source, ident_tok.span);

    const initializer = if (iter.match_token(.equal)) blk: {
        const exp_tree = iter.next_tree() orelse return Error.deformed_cst;
        break :blk try self.expr(exp_tree) orelse null;
    } else null;

    if (!iter.match_token(.semicolon)) return Error.missing_semicolon;

    if (iter.peek()) |_| return Error.deformed_cst;

    return .{ .var_decl = .{ .name = name, .initializer = initializer } };
}

fn stmt(self: *ASTLower, tree: Tree) Error!?Stmt {
    return switch (tree.tag) {
        .err => return null,
        .expr_stmt => self.expr_stmt(tree),
        .block_stmt => self.block_stmt(tree),
        .print_stmt => self.print_stmt(tree),
        .var_decl => self.var_decl(tree),
        else => unreachable,
    };
}

fn program(self: *ASTLower, tree: Tree) Error!Program {
    assert(tree.tag == .program);

    var iter = tree.iter(ITER_CONF);

    var prg: Program = .{ .stmts = .empty };

    while (iter.next_tree()) |stmt_tree| {
        if (try self.stmt(stmt_tree)) |_stmt| {
            try prg.stmts.append(self.arena, _stmt);
        }
    }

    if (!iter.match_token(.eof)) return Error.deformed_cst;

    if (iter.peek()) |_| return Error.deformed_cst;

    return prg;
}

const repl_cmds: std.StaticStringMap(ReplItem.Cmd) = .initComptime(&.{
    .{ "quit", .quit },
});

fn repl_cmd(self: *ASTLower, tree: Tree) Error!?ReplItem {
    assert(tree.tag == .repl_cmd);

    var iter = tree.iter(ITER_CONF);

    if (!iter.match_token(.colon)) return Error.deformed_cst;

    const cmd_token = iter.next_token() orelse return null;
    const cmd_lexeme = self.source_manager.get_lexeme(self.source, cmd_token.span);

    const cmd = repl_cmds.get(cmd_lexeme) orelse return null;

    if (iter.peek()) |_| return Error.deformed_cst;

    return .{ .cmd = cmd };
}

fn repl_item(self: *ASTLower, tree: Tree) Error!?ReplItem {
    assert(tree.tag == .repl_item);

    var iter = tree.iter(ITER_CONF);

    const item_tree = iter.next_tree() orelse return null;

    const item: ReplItem = switch (item_tree.tag) {
        .repl_cmd => (try self.repl_cmd(item_tree)) orelse return null,
        .literal_expr,
        .var_expr,
        .unary_expr,
        .binary_expr,
        .assign_expr,
        .group_expr,
        => .{ .expr = (try self.expr(item_tree)) orelse return null },
        .expr_stmt,
        .print_stmt,
        .block_stmt,
        .var_decl,
        => .{ .stmt = (try self.stmt(item_tree)) orelse return null },
        .err => return null,
        .program, .repl_item => unreachable,
    };

    if (!iter.match_token(.eof)) return Error.deformed_cst;

    if (iter.peek()) |_| return Error.deformed_cst;

    return item;
}

pub fn lower_program(tree: Tree, source: Source, source_manager: *const SourceManager, allocator: std.mem.Allocator) Error!HeapValue(Program) {
    var ast: HeapValue(Program) = .create(allocator);
    errdefer ast.free();

    var self: ASTLower = .{
        .arena = ast.arena.allocator(),
        .source = source,
        .source_manager = source_manager,
    };

    ast.value = try self.program(tree);

    return ast;
}

pub fn lower_repl_item(tree: Tree, source: Source, source_manager: *const SourceManager, allocator: std.mem.Allocator) Error!?HeapValue(ReplItem) {
    var ast: HeapValue(ReplItem) = .create(allocator);
    errdefer ast.free();

    var self: ASTLower = .{
        .arena = ast.arena.allocator(),
        .source = source,
        .source_manager = source_manager,
    };

    ast.value = try self.repl_item(tree) orelse {
        ast.free();
        return null;
    };

    return ast;
}

const ASTLower = @This();

const std = @import("std");
const assert = std.debug.assert;
const panic = std.debug.panic;

const Token = @import("Token.zig");

const AST = @import("AST.zig");
const Program = AST.Program;
const ReplItem = AST.ReplItem;
const Stmt = AST.Stmt;
const Expr = AST.Expr;

const CST = @import("CST.zig");
const Tree = CST.Tree;
const Child = Tree.Child;

const SourceManager = @import("SourceManager.zig");
const Source = SourceManager.Source;

const HeapValue = @import("heap_value.zig").HeapValue;

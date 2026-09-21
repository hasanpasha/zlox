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

fn literal_expr(_: *ASTLower, tree: Tree) Error!?Expr {
    var iter = tree.iter(ITER_CONF);

    const literal_tok = iter.next_token() orelse return Error.deformed_cst;
    const literal_exp: Expr.Literal = switch (literal_tok.tag) {
        .number => blk: {
            const lexeme = literal_tok.lexeme();
            const number = std.fmt.parseFloat(f64, lexeme) catch return Error.invalid_number;
            break :blk .{ .number = number };
        },
        .string => blk: {
            const lexeme = literal_tok.lexeme();
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

fn var_expr(_: *ASTLower, tree: Tree) Error!?Expr {
    var iter = tree.iter(ITER_CONF);

    const ident_tok = iter.next_token_if(&.{.identifier}) orelse return Error.deformed_cst;
    const name = ident_tok.lexeme();

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

pub fn expr(self: *ASTLower, tree: Tree) Error!?Expr {
    return switch (tree.tag) {
        .err => return null,
        .expr => |exp| switch (exp) {
            .literal => try self.literal_expr(tree),
            .@"var" => try self.var_expr(tree),
            .unary => try self.unary_expr(tree),
            .binary => try self.binary_expr(tree),
            .assign => try self.assign_expr(tree),
            .group => try self.group_expr(tree),
        },
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

    var block: std.ArrayList(Decl) = .empty;

    while (iter.next_tree()) |decl_tree| {
        if (try self.decl(decl_tree)) |inner_decl| {
            try block.append(self.arena, inner_decl);
        }
    }

    if (!iter.match_token(.right_brace)) return Error.deformed_cst;

    if (iter.peek()) |_| return Error.deformed_cst;

    return .{ .block = block };
}

fn stmt(self: *ASTLower, tree: Tree) Error!?Stmt {
    return switch (tree.tag) {
        .err => return null,
        .stmt => |_stmt| switch (_stmt) {
            .expr => self.expr_stmt(tree),
            .block => self.block_stmt(tree),
            .print => self.print_stmt(tree),
        },
        else => unreachable,
    };
}

fn var_decl(self: *ASTLower, tree: Tree) Error!?Decl {
    var iter = tree.iter(ITER_CONF);

    if (!iter.match_token(.@"var")) return Error.deformed_cst;

    const ident_tok = iter.next_token_if(&.{.identifier}) orelse return Error.deformed_cst;
    const name = ident_tok.lexeme();

    const initializer = if (iter.match_token(.equal)) blk: {
        const exp_tree = iter.next_tree() orelse return Error.deformed_cst;
        break :blk try self.expr(exp_tree) orelse null;
    } else null;

    if (!iter.match_token(.semicolon)) return Error.missing_semicolon;

    if (iter.peek()) |_| return Error.deformed_cst;

    return .{ .@"var" = .{ .name = name, .initializer = initializer } };
}

fn stmt_decl(self: *ASTLower, tree: Tree) Error!?Decl {
    var iter = tree.iter(ITER_CONF);

    const stmt_tree = iter.next_tree() orelse return Error.deformed_cst;
    const _stmt = try self.stmt(stmt_tree) orelse return null;

    if (iter.peek()) |_| return Error.deformed_cst;

    return .{ .stmt = _stmt };
}

fn decl(self: *ASTLower, tree: Tree) Error!?Decl {
    return switch (tree.tag) {
        .err => return null,
        .decl => |_decl| switch (_decl) {
            .@"var" => self.var_decl(tree),
            .stmt => self.stmt_decl(tree),
        },
        else => |tag| panic("unexpected Tree tag '{t}'", .{tag}),
    };
}

fn program(self: *ASTLower, tree: Tree) Error!Program {
    var iter = tree.iter(ITER_CONF);

    var prg: Program = .{ .decls = .empty };

    while (iter.next_tree()) |decl_tree| {
        if (try self.decl(decl_tree)) |_decl| {
            try prg.decls.append(self.arena, _decl);
        }
    }

    return prg;
}

pub fn lower(mode: Mode, tree: Tree, allocator: std.mem.Allocator) Error!?HeapValue(Node) {
    var ast: HeapValue(Node) = .create(allocator);
    errdefer ast.free();

    var self: ASTLower = .{ .arena = ast.arena.allocator() };

    ast.value = switch (mode) {
        .expr => if (try self.expr(tree)) |_expr| .{ .expr = _expr } else return null,
        .program => .{ .program = try self.program(tree) },
    };

    return ast;
}

const ASTLower = @This();

const std = @import("std");
const panic = std.debug.panic;

const Token = @import("Token.zig");
const Mode = @import("ZLOX.zig").Mode;

const AST = @import("AST.zig");
const Node = AST.Node;
const Program = AST.Program;
const Decl = AST.Decl;
const Stmt = AST.Stmt;
const Expr = AST.Expr;

const CST = @import("CST.zig");
const Tree = CST.Tree;
const Child = Tree.Child;

const HeapValue = @import("heap_value.zig").HeapValue;

stdout: *Writer,
gpa: Allocator,
environment: *Environment,
strings: std.StringHashMap(void),

pub const Environment = struct {
    gpa: Allocator,
    values: std.StringHashMap(Literal),
    enclosing: ?*Environment,

    pub const Error = error{undefined_variable} || Allocator.Error;

    pub fn init(gpa: Allocator, enclosing: ?*Environment) Allocator.Error!*Environment {
        const self: *Environment = try gpa.create(Environment);
        self.* = .{
            .gpa = gpa,
            .values = .init(gpa),
            .enclosing = enclosing,
        };
        return self;
    }

    pub fn deinit(self: *Environment) void {
        self.values.deinit();
        self.gpa.destroy(self);
    }

    pub fn define(self: *Environment, name: []const u8, value: Literal) Environment.Error!void {
        try self.values.put(name, value);
    }

    pub fn get(self: *Environment, name: []const u8) Environment.Error!Literal {
        return self.values.get(name) orelse
            if (self.enclosing) |enclosing|
                enclosing.get(name)
            else
                error.undefined_variable;
    }

    pub fn assign(self: *Environment, name: []const u8, value: Literal) Environment.Error!void {
        if (self.values.contains(name))
            try self.values.put(name, value)
        else if (self.enclosing) |enclosing|
            try enclosing.assign(name, value)
        else
            return error.undefined_variable;
    }
};

pub const Error = error{
    operand_not_number,
    operand_not_string,
} || Environment.Error || Allocator.Error || Writer.Error;

pub fn init(stdout: *Writer, gpa: Allocator) Allocator.Error!Interpreter {
    return .{
        .stdout = stdout,
        .gpa = gpa,
        .environment = try .init(gpa, null),
        .strings = .init(gpa),
    };
}

pub fn deinit(self: *Interpreter) void {
    var str_iter = self.strings.keyIterator();
    while (str_iter.next()) |key| {
        self.gpa.free(key.*);
    }
    self.environment.deinit();
    self.strings.deinit();
}

fn intern(self: *Interpreter, slice: []const u8) Error![]const u8 {
    if (self.strings.getKey(slice)) |key|
        return key;

    const key = try self.gpa.dupe(u8, slice);
    try self.strings.put(key, {});
    return key;
}

fn literals_are_equal(lhs: Literal, rhs: Literal) bool {
    if (activeTag(lhs) != activeTag(rhs)) return false;
    return switch (lhs) {
        .number => |lhs_num| lhs_num == rhs.number,
        .string => |lhs_str| std.mem.eql(u8, lhs_str, rhs.string),
        .boolean => |lhs_bool| lhs_bool == rhs.boolean,
        .nil => true,
    };
}

fn literal_is_truthy(lit: Literal) bool {
    return switch (lit) {
        .nil => false,
        .boolean => |boolean| boolean,
        else => true,
    };
}

fn literal_expr(self: *Interpreter, lit: Literal) Error!Literal {
    return switch (lit) {
        .string => |str| .{ .string = try self.intern(str) },
        else => lit,
    };
}

fn unary_expr(self: *Interpreter, unary: Expr.Unary) Error!Literal {
    const rhs = try self.eval_expr(unary.rhs.*);
    return switch (unary.op) {
        .neg => switch (rhs) {
            .number => |value| .{ .number = -value },
            else => return Error.operand_not_number,
        },
        .not => .{ .boolean = !literal_is_truthy(rhs) },
    };
}

fn binary_expr(self: *Interpreter, binary: Expr.Binary) Error!Literal {
    const lhs = try self.eval_expr(binary.lhs.*);
    const rhs = try self.eval_expr(binary.rhs.*);

    return switch (binary.op) {
        .add => switch (lhs) {
            .number => |lhs_num| blk: {
                if (rhs != .number) return Error.operand_not_number;
                break :blk .{ .number = lhs_num + rhs.number };
            },
            .string => |lhs_str| blk: {
                if (rhs != .string) return Error.operand_not_string;

                const concat_string = try std.mem.concat(self.gpa, u8, &.{ lhs_str, rhs.string });
                const new_string = if (self.strings.getKey(concat_string)) |prev_string| nblk: {
                    self.gpa.free(concat_string);
                    break :nblk prev_string;
                } else nblk: {
                    try self.strings.put(concat_string, {});
                    break :nblk concat_string;
                };

                break :blk .{ .string = new_string };
            },
            else => unreachable,
        },
        .sub, .mul, .div, .lt, .le, .gt, .ge => blk: {
            const lhs_num = switch (lhs) {
                .number => |num| num,
                else => return Error.operand_not_number,
            };
            const rhs_num = switch (rhs) {
                .number => |num| num,
                else => return Error.operand_not_number,
            };

            break :blk switch (binary.op) {
                .sub => .{ .number = lhs_num + rhs_num },
                .mul => .{ .number = lhs_num * rhs_num },
                .div => .{ .number = lhs_num / rhs_num },
                .lt => .{ .boolean = lhs_num < rhs_num },
                .le => .{ .boolean = lhs_num <= rhs_num },
                .gt => .{ .boolean = lhs_num > rhs_num },
                .ge => .{ .boolean = lhs_num >= rhs_num },
                else => unreachable,
            };
        },
        .eq => .{ .boolean = literals_are_equal(lhs, rhs) },
        .ne => .{ .boolean = !literals_are_equal(lhs, rhs) },
    };
}

fn var_expr(self: *Interpreter, name: []const u8) Error!Literal {
    return self.environment.get(name);
}

fn assign_expr(self: *Interpreter, assign: Expr.Assign) Error!Literal {
    const value = try self.eval_expr(assign.value.*);

    try self.environment.assign(try self.intern(assign.name), value);

    return value;
}

pub fn eval_expr(self: *Interpreter, exp: Expr) Error!Literal {
    return switch (exp) {
        .literal => |literal| self.literal_expr(literal),
        .@"var" => |name| self.var_expr(name),
        .unary => |unary| try self.unary_expr(unary),
        .binary => |binary| try self.binary_expr(binary),
        .assign => |assign| try self.assign_expr(assign),
    };
}

fn execute_block(self: *Interpreter, _block: std.ArrayList(Stmt), new_env: *Environment) Error!void {
    const prev_env = self.environment;
    defer self.environment = prev_env;
    errdefer self.environment = prev_env;

    self.environment = new_env;
    for (_block.items) |inner_stmt| {
        try self.execute_stmt(inner_stmt);
    }
}

pub fn execute_stmt(self: *Interpreter, _stmt: Stmt) Error!void {
    switch (_stmt) {
        .expr => |exp| _ = try self.eval_expr(exp),
        .print => |exp| {
            const value = try self.eval_expr(exp);
            try self.stdout.print("{f}\n", .{value});
        },
        .block => |_block| {
            var env: *Environment = try .init(self.gpa, self.environment);
            defer env.deinit();
            try self.execute_block(_block, env);
        },
        .var_decl => |_var| {
            const value: Literal = if (_var.initializer) |_init| try self.eval_expr(_init) else .nil;
            try self.environment.define(try self.intern(_var.name), value);
        },
    }
}

pub fn run_program(self: *Interpreter, _program: Program) Error!void {
    for (_program.stmts.items) |_stmt| {
        try self.execute_stmt(_stmt);
    }
}

const Interpreter = @This();

const std = @import("std");
const activeTag = std.meta.activeTag;
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;

const AST = @import("AST.zig");
const ReplItem = AST.ReplItem;
const Program = AST.Program;
const Stmt = AST.Stmt;
const Expr = AST.Expr;
const Literal = Expr.Literal;

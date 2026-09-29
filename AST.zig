pub const Expr = union(enum) {
    literal: Literal,
    @"var": []const u8,
    unary: Unary,
    binary: Binary,
    assign: Assign,

    pub const Literal = union(enum) {
        number: f64,
        string: []const u8,
        boolean: bool,
        nil,

        pub fn format(self: Literal, writer: *Writer) Writer.Error!void {
            switch (self) {
                .number => |num| try writer.print("{}", .{num}),
                .string => |string| try writer.print("\"{s}\"", .{string}),
                .boolean => |boolean| try writer.print("{}", .{boolean}),
                .nil => try writer.writeAll("nil"),
            }
        }
    };

    pub const Unary = struct {
        op: Op,
        rhs: *Expr,

        pub const Op = enum {
            not,
            neg,
        };
    };

    pub const Binary = struct {
        op: Op,
        lhs: *Expr,
        rhs: *Expr,

        pub const Op = enum {
            add,
            sub,
            mul,
            div,
            gt,
            ge,
            lt,
            le,
            eq,
            ne,
        };
    };

    pub const Assign = struct {
        name: []const u8,
        value: *Expr,
    };

    pub fn format(self: Expr, writer: *Writer) Writer.Error!void {
        try writer.print("{t}(", .{self});
        switch (self) {
            .literal => |literal| try writer.print("{f}", .{literal}),
            .@"var" => |name| try writer.print("\"{s}\"", .{name}),
            .unary => |unary| try writer.print("{t}, {f}", .{ unary.op, unary.rhs.* }),
            .binary => |binary| try writer.print("{t}, {f}, {f}", .{
                binary.op,
                binary.lhs.*,
                binary.rhs.*,
            }),
            .assign => |assign| try writer.print("{s}, {f}", .{ assign.name, assign.value.* }),
        }
        try writer.writeByte(')');
    }
};

pub const Stmt = union(enum) {
    expr: Expr,
    print: Expr,
    block: std.ArrayList(Stmt),
    var_decl: VarDecl,

    pub const VarDecl = struct {
        name: []const u8,
        initializer: ?Expr,
    };

    pub fn format(self: Stmt, writer: *Writer) Writer.Error!void {
        try writer.print("{t}(", .{self});
        switch (self) {
            .expr, .print => |exp| try writer.print("{f}", .{exp}),
            .block => |stmts| {
                try writer.writeByte('[');
                for (0.., stmts.items) |i, _decl| {
                    if (i > 0) try writer.writeAll(", ");
                    try writer.print("{f}", .{_decl});
                }
                try writer.writeByte(']');
            },
            .var_decl => |_var| try writer.print("\"{s}\", {?f}", .{ _var.name, _var.initializer }),
        }
        try writer.writeByte(')');
    }
};

pub const Program = struct {
    stmts: std.ArrayList(Stmt),

    pub fn format(self: Program, writer: *Writer) Writer.Error!void {
        try writer.writeByte('[');
        for (0.., self.stmts.items) |i, _stmt| {
            if (i > 0) try writer.writeAll(", ");
            try writer.print("{f}", .{_stmt});
        }
        try writer.writeByte(']');
    }
};

pub const ReplItem = union(enum) {
    expr: Expr,
    stmt: Stmt,
    cmd: Cmd,

    pub const Cmd = enum {
        quit,
    };

    pub fn format(self: ReplItem, writer: *Writer) Writer.Error!void {
        try writer.print("{t}(", .{self});
        switch (self) {
            .cmd => |cmd| try writer.print("{t}", .{cmd}),
            inline else => |item| try writer.print("{f}", .{item}),
        }
        try writer.writeByte(')');
    }
};

const std = @import("std");
const Writer = std.Io.Writer;

const Mode = @import("ZLOX.zig").Mode;

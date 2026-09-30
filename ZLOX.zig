io: Io,
gpa: Allocator,
stdin: File.Reader,
stdout: File.Writer,
stderr: File.Writer,

source_manager: SourceManager,
diags: Diagnostics,

interpreter: Interpreter,

pub const Error = Allocator.Error || Io.Reader.Error || Io.Writer.Error || SourceManager.Error;

var stdin_buffer: [1024]u8 = undefined;
var stdout_buffer: [1024]u8 = undefined;
var stderr_buffer: [1024]u8 = undefined;

pub fn init(io: Io, gpa: Allocator) Error!*ZLOX {
    const self: *ZLOX = try gpa.create(ZLOX);
    errdefer gpa.destroy(self);

    self.* = .{
        .io = io,
        .gpa = gpa,
        .stdin = File.stdin().reader(io, &stdin_buffer),
        .stdout = File.stdout().writer(io, &stdout_buffer),
        .stderr = File.stderr().writer(io, &stderr_buffer),
        .source_manager = .init(io, gpa),
        .diags = undefined,
        .interpreter = undefined,
    };

    self.interpreter = try .init(&self.stdout.interface, self.gpa);
    self.diags = .init(&self.source_manager, self.gpa);

    return self;
}

pub fn deinit(self: *ZLOX) void {
    self.interpreter.deinit();
    self.source_manager.deinit();
    self.gpa.destroy(self);
}

pub fn repl(self: *ZLOX) Error!void {
    const repl_source: Source = try self.source_manager.new("repl");

    const PS = ">>> ";

    while (true) {
        try self.stdout.interface.writeAll(PS);
        try self.stdout.interface.flush();

        const line = self.stdin.interface.takeDelimiter('\n') catch |err| {
            if (err == error.StreamTooLong) continue;
            return @errorCast(err);
        } orelse break;
        try self.source_manager.update_source_code_from_slice(repl_source, line);

        var tokens = try Lexer.lex(self.source_manager.get_source_code(repl_source), self.gpa);
        defer tokens.deinit(self.gpa);

        var cst = try Parser.parse_repl_item(tokens, self.gpa, &self.diags);
        defer cst.free();

        std.log.debug("{f}", .{cst.value.pp(repl_source, &self.source_manager)});

        var ast = ASTLower.lower_repl_item(cst.value, repl_source, &self.source_manager, self.gpa) catch |err| {
            if (@TypeOf(err) == Error) return @errorCast(err);
            try self.stderr.interface.print("parser error: {t}\n", .{err});
            try self.stderr.interface.flush();
            continue;
        } orelse continue;
        defer ast.free();

        switch (ast.value) {
            .expr => |expr| {
                const value = self.interpreter.eval_expr(expr) catch |err| {
                    if (@TypeOf(err) == Error) return @errorCast(err);
                    try self.stderr.interface.print("runtime error: {t}\n", .{err});
                    try self.stderr.interface.flush();
                    continue;
                };
                try self.stdout.interface.print("{f}\n", .{value});
            },
            .stmt => |stmt| self.interpreter.execute_stmt(stmt) catch |err| {
                if (@TypeOf(err) == Error) return @errorCast(err);
                try self.stderr.interface.print("runtime error: {t}\n", .{err});
                try self.stderr.interface.flush();
                continue;
            },
            .cmd => |cmd| switch (cmd) {
                .quit => break,
            },
        }

        try self.stdout.interface.flush();
        try self.stderr.interface.flush();
    }
}

pub fn run_file(self: *ZLOX, filepath: []const u8) Error!void {
    const source: Source = try self.source_manager.new(filepath);
    try self.source_manager.updateSourceCodeFromFile(source);

    var tokens = try Lexer.lex(self.source_manager.get_source_code(source), self.gpa);
    defer tokens.deinit(self.gpa);

    var cst = try Parser.parse_program(tokens, self.gpa, &self.diags);
    defer cst.free();

    var ast = ASTLower.lower_program(cst.value, source, &self.source_manager, self.gpa) catch |err| {
        if (@TypeOf(err) == Error) return @errorCast(err);
        try self.stderr.interface.print("parser error: {t}\n", .{err});
        try self.stderr.interface.flush();
        return;
    };
    defer ast.free();

    self.interpreter.run_program(ast.value) catch |err| {
        if (@TypeOf(err) == Error) return @errorCast(err);
        try self.stderr.interface.print("runtime error: {t}\n", .{err});
        try self.stderr.interface.flush();
    };

    try self.stdout.interface.flush();
    try self.stderr.interface.flush();
}

const ZLOX = @This();

const std = @import("std");
const log = std.log.scoped(.zlox);
const Io = std.Io;
const File = Io.File;
const mem = std.mem;
const Allocator = mem.Allocator;

const Lexer = @import("Lexer.zig");
const Tree = @import("CST.zig").Tree;
const Parser = @import("Parser.zig");
const AST = @import("AST.zig");
const ASTLower = @import("ASTLower.zig");
const Interpreter = @import("Interpreter.zig");

const SourceManager = @import("SourceManager.zig");
const Source = SourceManager.Source;

const Diagnostics = @import("Diagnostics.zig");

const HeapValue = @import("heap_value.zig").HeapValue;

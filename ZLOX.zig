io: Io,
gpa: Allocator,
stdin: File.Reader,
stdout: File.Writer,
stderr: File.Writer,

interpreter: Interpreter,

pub const Error = Allocator.Error || Io.Reader.Error || Io.Writer.Error || Source.Error;

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
        .interpreter = undefined,
    };

    try self.init_interpreter();

    return self;
}

fn init_interpreter(self: *ZLOX) Error!void {
    self.interpreter = try .init(&self.stdout.interface, self.gpa);
}

pub fn deinit(self: *ZLOX) void {
    self.interpreter.deinit();
    self.gpa.destroy(self);
}

pub const Mode = enum {
    expr,
    program,
};

pub fn repl(self: *ZLOX) Error!void {
    const stdin_source: Source = try .new("stdin");

    while (true) {
        try self.stdout.interface.writeAll(">>> ");
        try self.stdout.interface.flush();

        const line = self.stdin.interface.takeDelimiter('\n') catch |err| {
            if (err == error.StreamTooLong) continue;
            return @errorCast(err);
        } orelse break;

        try stdin_source.updateSourceCodeFromSlice(line);

        const node: HeapValue(Node) = self.parse(.expr, stdin_source) catch |err| blk: {
            if (err != error.parse_failed) return @errorCast(err);
            break :blk self.parse(.program, stdin_source) catch |prg_err| {
                if (prg_err != error.parse_failed) return @errorCast(err);

                try self.stdout.interface.flush();
                try self.stderr.interface.flush();
                continue;
            };
        };
        defer node.free();

        self.interpreter.interpret(node.value) catch |err| {
            if (@TypeOf(err) == Error) return err;

            try self.stderr.interface.print("runtime error: {t}\n", .{err});

            try self.stdout.interface.flush();
            try self.stderr.interface.flush();
            continue;
        };

        try self.stdout.interface.flush();
        try self.stderr.interface.flush();
    }
}

fn parse(self: *ZLOX, mode: Mode, source: Source) (error{parse_failed} || Error)!HeapValue(Node) {
    var tokens = try Lexer.lex(source, self.gpa);
    defer tokens.deinit(self.gpa);

    const cst = try Parser.parse(mode, tokens, self.gpa);
    defer cst.free();

    return ASTLower.lower(mode, cst.value, self.gpa) catch |err| {
        if (@TypeOf(err) == Error) return err;

        try self.stderr.interface.print("parser error: {t}\n", .{err});
        return error.parse_failed;
    } orelse error.parse_failed;
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
const Node = AST.Node;
const ASTLower = @import("ASTLower.zig");
const Interpreter = @import("Interpreter.zig");

const Source = @import("source_manager.zig").Source;

const HeapValue = @import("heap_value.zig").HeapValue;

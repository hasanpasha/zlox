var sources: std.ArrayList(SourceInfo) = .empty;
var io: std.Io = undefined;
var gpa: Allocator = undefined;

pub const Source = enum(usize) {
    _,

    pub const Error = error{
        cant_load_file,
    } || Allocator.Error;

    pub fn new(name: []const u8) Error!Source {
        const source: Source = @enumFromInt(sources.items.len);
        const source_info: SourceInfo = .{
            .name = name,
            .code = &.{},
            .lines = &.{},
            .arena = .init(gpa),
        };

        try sources.append(gpa, source_info);

        return source;
    }

    pub fn updateSourceCodeFromSlice(self: Source, slice: []const u8) Error!void {
        const source_info = self.getSourceInfo();
        _ = source_info.arena.reset(.retain_capacity);

        source_info.code = try source_info.arena.allocator().dupe(u8, slice);
        source_info.lines = try getLines(source_info.code, source_info.arena.allocator());
    }

    pub fn updateSourceCodeFromFile(self: Source) Error!void {
        const source_info = self.getSourceInfo();
        _ = source_info.arena.reset(.retain_capacity);

        source_info.code = std.Io.Dir.cwd().readFileAlloc(
            io,
            source_info.name,
            source_info.arena.allocator(),
            .unlimited,
        ) catch return Error.cant_load_file;
        source_info.lines = try getLines(source_info.code, source_info.arena.allocator());
    }

    fn getLines(code: []const u8, allocator: std.mem.Allocator) Error![]const Span {
        var spans: std.ArrayList(Span) = .empty;

        var start: usize = 0;
        var end: usize = 0;

        for (0.., code) |i, c| {
            end = i;
            if (c == '\n') {
                try spans.append(allocator, .{ .start = start, .end = end });
                start = i;
            }
        }
        try spans.append(allocator, .{ .start = start, .end = end });

        return try spans.toOwnedSlice(allocator);
    }

    pub fn getSourceInfo(self: Source) *SourceInfo {
        return &sources.items[@intFromEnum(self)];
    }

    pub fn getSourceName(self: Source) []const u8 {
        return self.getSourceInfo().name;
    }

    pub fn getSourceCode(self: Source) []const u8 {
        return self.getSourceInfo().code;
    }

    pub fn getLexeme(self: Source, start: usize, end: usize) []const u8 {
        return self.getSourceCode()[start..end];
    }

    pub fn getLocation(self: Source, offset: usize) Location {
        return for (0.., self.getSourceInfo().lines) |line, span| {
            if (offset >= span.start and offset <= span.end) break .{
                .line = line,
                .column = offset - span.start + 1,
            };
        } else unreachable;
    }
};

pub const SourceInfo = struct {
    name: []const u8,
    code: []const u8,
    lines: []const Span,

    arena: std.heap.ArenaAllocator,
};

pub const Location = struct {
    line: usize,
    column: usize,

    pub const start: Location = .{ .line = 1, .column = 1 };

    pub fn format(self: Location, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("{[line]}:{[column]}", self);
    }
};

pub fn init(_io: std.Io, _gpa: Allocator) void {
    io = _io;
    gpa = _gpa;
}

pub fn deinit() void {
    for (sources.items) |source_info| {
        source_info.arena.deinit();
    }

    sources.deinit(gpa);
}

const std = @import("std");
const Allocator = std.mem.Allocator;

const Token = @import("Token.zig");
const Span = Token.Span;

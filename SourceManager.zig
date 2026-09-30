sources: std.ArrayList(SourceInfo) = .empty,
io: Io = undefined,
gpa: Allocator = undefined,

pub fn init(_io: Io, _gpa: Allocator) SourceManager {
    return .{ .io = _io, .gpa = _gpa };
}

pub fn deinit(self: *SourceManager) void {
    for (self.sources.items) |source_info| {
        source_info.arena.deinit();
    }

    self.sources.deinit(self.gpa);
}

pub const Source = enum(usize) {
    _,
};

pub const Error = error{
    cant_load_file,
} || Allocator.Error || Io.Dir.ReadFileAllocError;

pub fn new(self: *SourceManager, name: []const u8) Error!Source {
    const source: Source = @enumFromInt(self.sources.items.len);
    const source_info: SourceInfo = .{
        .name = name,
        .code = &.{},
        .lines = &.{},
        .arena = .init(self.gpa),
    };

    try self.sources.append(self.gpa, source_info);

    return source;
}

pub fn update_source_code_from_slice(self: *SourceManager, source: Source, slice: []const u8) Error!void {
    const source_info = self.get_source_info_mut(source);
    _ = source_info.arena.reset(.retain_capacity);

    source_info.code = try source_info.arena.allocator().dupe(u8, slice);
    source_info.lines = try get_lines(source_info.code, source_info.arena.allocator());
}

pub fn updateSourceCodeFromFile(self: *SourceManager, source: Source) Error!void {
    const source_info = self.get_source_info_mut(source);
    _ = source_info.arena.reset(.retain_capacity);

    source_info.code = try std.Io.Dir.cwd().readFileAlloc(
        self.io,
        source_info.name,
        source_info.arena.allocator(),
        .unlimited,
    );
    source_info.lines = try get_lines(source_info.code, source_info.arena.allocator());
}

fn get_lines(code: []const u8, allocator: std.mem.Allocator) Error![]const Span {
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

fn get_source_info_mut(self: *SourceManager, source: Source) *SourceInfo {
    return &self.sources.items[@intFromEnum(source)];
}

pub fn get_source_info(self: *const SourceManager, source: Source) *const SourceInfo {
    return &self.sources.items[@intFromEnum(source)];
}

pub fn get_source_name(self: *const SourceManager, source: Source) []const u8 {
    return self.get_source_info(source).name;
}

pub fn get_source_code(self: *const SourceManager, source: Source) []const u8 {
    return self.get_source_info(source).code;
}

pub fn get_lexeme(self: *const SourceManager, source: Source, span: Span) []const u8 {
    return self.get_source_code(source)[span.start..span.end];
}

pub fn get_location(self: *const SourceManager, source: Source, offset: usize) Location {
    return for (0.., self.get_source_info(source).lines) |line, span| {
        if (offset >= span.start and offset <= span.end) break .{
            .line = line,
            .column = offset - span.start + 1,
        };
    } else unreachable;
}

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

const SourceManager = @This();

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const Token = @import("Token.zig");
const Span = Token.Span;

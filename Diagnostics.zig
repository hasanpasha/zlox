diags: std.ArrayList(Diagnostic),
source_manager: *const SourceManager,

gpa: Allocator,

pub const Diagnostic = struct {
    level: Level,
    message: []const u8,

    source: Source,
    span: Span,

    pub const Level = enum {
        warn,
        err,
    };
};

pub fn init(source_manager: *const SourceManager, allocator: Allocator) Diagnostics {
    return .{
        .diags = .empty,
        .source_manager = source_manager,
        .gpa = allocator,
    };
}

pub fn deinit(self: *Diagnostics) void {
    for (self.diags.items) |diag| {
        self.gpa.free(diag.message);
    }

    self.diags.deinit(self.gpa);
}

pub fn has_error(self: *const Diagnostics) bool {
    return for (self.diags.items) |diag| {
        if (diag.level == .err) return true;
    } else false;
}

pub fn add(
    self: *Diagnostics,
    level: Diagnostic.Level,
    source: Source,
    span: Span,
    comptime fmt: []const u8,
    args: anytype,
) !void {
    try self.diags.append(self.gpa, .{
        .level = level,
        .source = source,
        .span = span,
        .message = try std.fmt.allocPrint(self.gpa, fmt, args),
    });
}

pub fn format(self: Diagnostics, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    for (self.diags.items) |diag| {
        const source_name = self.source_manager.get_source_name(diag.source);
        const location = self.source_manager.get_location(diag.source, diag.span.start);
        const lexeme = self.source_manager.get_lexeme(diag.source, diag.span.start, diag.span.end);

        try writer.print("{s}:{f}: {t}: {s}\n{s}\n", .{
            source_name,
            location,
            diag.level,
            diag.message,
            lexeme,
        });
    }
}

const Diagnostics = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const Span = @import("Token.zig").Span;

const SourceManager = @import("SourceManager.zig");
const Source = SourceManager.Source;

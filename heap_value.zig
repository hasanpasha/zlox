pub fn HeapValue(comptime T: type) type {
    return struct {
        value: T,
        arena: std.heap.ArenaAllocator,

        pub fn create(allocator: std.mem.Allocator) @This() {
            return .{ .value = undefined, .arena = .init(allocator) };
        }

        pub fn free(self: @This()) void {
            self.arena.deinit();
        }

        pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
            try writer.print("{f}", .{self.value});
        }
    };
}

const std = @import("std");

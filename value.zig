pub const ValueKind = enum {
    nil,
    bool,
    number,
    object,
};

pub const Value = union(ValueKind) {
    nil,
    bool: bool,
    number: f64,
    object: *Object,

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (self) {
            .nil => try writer.writeAll("nil"),
            .bool => |val| try writer.print("{}", .{val}),
            .number => |val| try writer.print("{}", .{val}),
            .object => |val| try writer.print("{f}", .{val.fmt()}),
        }
    }

    pub fn isObjectType(self: Value, kind: ObjectKind) bool {
        return self == .object and self.object.kind == kind;
    }
};

const std = @import("std");
const Object = @import("Object.zig");
const ObjectKind = Object.Kind;

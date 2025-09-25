pub const Kind = enum {
    string,
};

const Object = @This();

kind: Kind,
next: ?*Object = null,

pub fn fmt(self: *Object) std.fmt.Alt(*Object, objFmt) {
    return .{ .data = self };
}

fn objFmt(self: *Object, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    switch (self.kind) {
        .string => {
            const string = String.case(self);
            try writer.print("\"{s}\"", .{string.data});
        },
    }
}

pub fn castUp(self: *Object) *anyopaque {
    return switch (self.kind) {
        .string => @ptrCast(String.case(self)),
    };
}

pub fn castDown(child: anytype) *Object {
    return @as(*Object, &child.base);
}

pub const String = struct {
    base: Object,
    data: [:0]const u8,

    pub fn case(object: *Object) *String {
        return @alignCast((@fieldParentPtr("base", object)));
    }
};

const std = @import("std");

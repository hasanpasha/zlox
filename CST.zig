root: Tree,

pub const Tree = struct {
    tag: Tag,
    children: std.ArrayList(Child),

    pub const Tag = union(enum) {
        expr: Expr,
        stmt: Stmt,
        decl: Decl,
        err: Err,
        program,

        pub const Expr = enum {
            literal,
            @"var",
            unary,
            binary,
            assign,
            group,
        };

        pub const Stmt = enum {
            print,
            block,
            expr,
        };

        pub const Decl = enum {
            @"var",
            stmt,
        };

        pub const Err = enum {
            unexpected,
            missing,
            skipped,
        };

        pub fn format(self: Tag, writer: *std.Io.Writer) std.Io.Writer.Error!void {
            switch (self) {
                .program => try writer.print("{t}", .{self}),
                inline else => |inner_tag, tag| try writer.print("{t}_{t}", .{ inner_tag, tag }),
            }
        }
    };

    pub const ChildKind = enum {
        token,
        tree,
    };

    pub const Child = union(ChildKind) {
        token: Token,
        tree: Tree,
    };

    pub const Iter = struct {
        tree: Tree,
        idx: usize = 0,

        ignores: []const Ignore,

        pub const Ignore = union(ChildKind) {
            token: *const fn (Token) bool,
            tree: *const fn (Tree) bool,

            pub fn token_tag_check(comptime pred: fn (Token.Tag) bool) Ignore {
                return .{ .token = struct {
                    pub fn cb(tok: Token) bool {
                        return pred(tok.tag);
                    }
                }.cb };
            }
        };

        fn should_ignore(self: *const Iter, child: Child) bool {
            const activeTag = std.meta.activeTag;
            return for (self.ignores) |ignore| {
                if (activeTag(child) != activeTag(ignore)) continue;
                switch (ignore) {
                    .token => |fun| if (fun(child.token)) break true,
                    .tree => |fun| if (fun(child.tree)) break true,
                }
            } else false;
        }

        pub fn peek(self: *const Iter) ?Child {
            if (self.idx >= self.tree.children.items.len) return null;

            return for (self.idx..self.tree.children.items.len) |i| {
                const child = self.tree.children.items[i];

                if (self.should_ignore(child)) continue;

                break child;
            } else null;
        }

        pub fn advance(self: *Iter) void {
            if (self.idx >= self.tree.children.items.len) return;

            while (self.idx < self.tree.children.items.len) {
                const child = self.tree.children.items[self.idx];
                self.idx += 1;

                if (self.should_ignore(child)) continue;

                break;
            }
        }

        pub fn next(self: *Iter) ?Child {
            return if (self.peek()) |child| blk: {
                self.advance();
                break :blk child;
            } else null;
        }

        pub fn next_token(self: *Iter) ?Token {
            const next_child = self.peek() orelse return null;
            if (next_child != .token) return null;
            self.advance();
            return next_child.token;
        }

        pub fn next_token_if(self: *Iter, tags: []const Token.Tag) ?Token {
            return if (self.peek()) |child| blk: {
                if (child != .token) break :blk null;
                const token = child.token;
                break :blk for (tags) |tag| {
                    if (tag == token.tag) {
                        self.advance();
                        break :blk token;
                    }
                } else null;
            } else null;
        }

        pub fn next_tree(self: *Iter) ?Tree {
            const next_child = self.peek() orelse return null;
            if (next_child != .tree) return null;
            self.advance();
            return next_child.tree;
        }

        pub fn match_token(self: *Iter, token_kind: Token.Tag) bool {
            const next_child = self.peek() orelse return false;
            if (next_child != .token) return false;
            if (next_child.token.tag != token_kind) return false;
            self.advance();
            return true;
        }
    };

    pub fn format(self: Tree, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        var buffer: [1024]bool = undefined;
        var pretty: Pretty = .{ .is_last = .initBuffer(&buffer) };
        try pretty.print_tree(self, writer);
    }

    pub fn iter(self: Tree, ignores: []const Iter.Ignore) Iter {
        return .{ .tree = self, .ignores = ignores };
    }
};

pub const Pretty = struct {
    is_last: std.ArrayList(bool),

    fn print_tree(
        self: *Pretty,
        tree: Tree,
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print("{f}\n", .{tree.tag});

        var children = tree.iter(&.{.token_tag_check(Token.Tag.is_trivia)});

        while (children.next()) |child| {
            try self.print_child(
                child,
                children.peek() == null,
                writer,
            );
        }
    }

    fn print_child(
        self: *Pretty,
        child: Tree.Child,
        is_last: bool,
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        for (self.is_last.items) |parent_is_last| {
            try writer.writeAll(
                if (parent_is_last) "    " else "│   ",
            );
        }

        try writer.writeAll(if (is_last) "└── " else "├── ");

        switch (child) {
            .token => |token| {
                try writer.print("{t} ", .{token.tag});

                switch (token.tag) {
                    .number, .string, .identifier => try writer.print("'{s}'", .{token.lexeme()}),
                    else => {},
                }

                try writer.writeByte('\n');
            },

            .tree => |child_tree| {
                self.is_last.appendAssumeCapacity(is_last);
                defer _ = self.is_last.pop();

                try self.print_tree(child_tree, writer);
            },
        }
    }
};

const std = @import("std");

const Token = @import("Token.zig");

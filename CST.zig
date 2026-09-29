root: Tree,

pub const Tree = struct {
    tag: Tag,
    children: std.ArrayList(Child),

    pub const Tag = enum {
        literal_expr,
        var_expr,
        unary_expr,
        binary_expr,
        assign_expr,
        group_expr,

        expr_stmt,
        print_stmt,
        block_stmt,
        var_decl,

        program,

        repl_item,
        repl_cmd,

        err,
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
        var pretty: TreePrettyPrinter = .{ .are_last = .initBuffer(&buffer), .writer = writer };
        try pretty.pp_tree(self);
    }

    pub fn iter(self: Tree, ignores: []const Iter.Ignore) Iter {
        return .{ .tree = self, .ignores = ignores };
    }
};

pub const TreePrettyPrinter = struct {
    are_last: std.ArrayList(bool),
    writer: *Writer,

    const Writer = std.Io.Writer;

    fn pp_tree(self: *TreePrettyPrinter, tree: Tree) Writer.Error!void {
        try self.writer.print("{t}\n", .{tree.tag});

        var children = tree.iter(&.{.token_tag_check(Token.Tag.is_trivia)});

        const is_last = self.are_last.addOneAssumeCapacity();
        defer _ = self.are_last.pop();

        while (children.next()) |child| {
            is_last.* = children.peek() == null;

            try self.pp_child(child);
        }
    }

    fn pp_child(self: *TreePrettyPrinter, child: Tree.Child) Writer.Error!void {
        for (1.., self.are_last.items) |i, parent_is_last| {
            const prefix = if (i == self.are_last.items.len)
                if (parent_is_last) "└── " else "├── "
            else if (parent_is_last) "    " else "│   ";

            try self.writer.writeAll(prefix);
        }

        switch (child) {
            .token => |token| {
                try self.writer.print("{t} ", .{token.tag});

                if (token.tag.is_one_of(&.{ .number, .string, .identifier }))
                    try self.writer.print("'{s}'", .{token.lexeme()});

                try self.writer.writeByte('\n');
            },

            .tree => |child_tree| try self.pp_tree(child_tree),
        }
    }
};

const std = @import("std");

const Token = @import("Token.zig");

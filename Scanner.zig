pub const std = @import("std");
pub const Token = @import("Token.zig");
pub const TokenKind = Token.Kind;
pub const Location = @import("Location.zig");

const Scanner = @This();

src: []const u8,
ch: ?u8 = null,
start_pos: u8 = 0,
pos: u8 = 0,
start_loc: Location = .start,
loc: Location = .start,

pub fn init(src: []const u8) Scanner {
    var self: Scanner = .{ .src = src };

    if (self.src.len > 0)
        self.ch = self.src[self.pos];

    return self;
}

const keywords: std.StaticStringMap(TokenKind) = .initComptime(&.{
    .{ "and", .@"and" },
    .{ "class", .class },
    .{ "else", .@"else" },
    .{ "false", .false },
    .{ "for", .@"for" },
    .{ "fun", .fun },
    .{ "if", .@"if" },
    .{ "nil", .nil },
    .{ "or", .@"or" },
    .{ "print", .print },
    .{ "return", .@"return" },
    .{ "super", .super },
    .{ "this", .this },
    .{ "true", .true },
    .{ "var", .@"var" },
    .{ "while", .@"while" },
});

fn sync(self: *Scanner) void {
    self.start_pos = self.pos;
    self.start_loc = self.loc;
}

pub fn next(self: *Scanner) ?Token {
    self.sync();
    defer self.sync();

    const ch = self.ch orelse return null;

    const kind = switch (ch) {
        '(' => self.advance_with(.lparen),
        ')' => self.advance_with(.rparen),
        '{' => self.advance_with(.lcub),
        '}' => self.advance_with(.rcub),
        ',' => self.advance_with(.comma),
        '.' => self.advance_with(.dot),
        ';' => self.advance_with(.semi),
        '-' => self.advance_with(.minus),
        '+' => self.advance_with(.plus),
        '/' => kind: {
            self.advance();
            if (self.ch == '/') {
                self.advance();
                while (self.ch != null and self.ch.? != '\n')
                    self.advance();
                return self.next();
            } else if (self.ch == '*') {
                self.advance();
                while (self.ch != null and self.ch.? != '*' and self.peek() != null and self.peek().? != '/')
                    self.advance();
                self.advance();
                self.advance();
                return self.next();
            }

            break :kind .slash;
        },
        '*' => self.advance_with(.astrsk),
        '!' => self.advance_with(if (self.match('=')) .excl_equl else .excl),
        '=' => self.advance_with(if (self.match('=')) .equl_equl else .equl),
        '<' => self.advance_with(if (self.match('=')) .lt_equl else .lt),
        '>' => self.advance_with(if (self.match('=')) .gt_equl else .gt),
        '0'...'9' => kind: {
            var encountered_point = false;

            while (self.ch) |_ch|
                switch (_ch) {
                    '0'...'9' => self.advance(),
                    '.' => {
                        if (encountered_point)
                            return self.err("invalid number")
                        else
                            encountered_point = true;
                        self.advance();
                    },
                    else => break,
                };

            break :kind .num_lit;
        },
        'a'...'z', 'A'...'Z', '_' => kind: {
            while (self.ch) |_ch|
                switch (_ch) {
                    'a'...'z', 'A'...'Z', '0'...'9', '_' => self.advance(),
                    else => break,
                };

            const lexeme = self.current_lexeme();
            break :kind keywords.get(lexeme) orelse .ident;
        },
        '"' => kind: {
            self.advance();
            while (self.ch) |_ch| {
                switch (_ch) {
                    '"' => break,
                    else => self.advance(),
                }
            }

            if (self.ch == '"') {
                self.advance();
                break :kind .str_lit;
            } else {
                return self.err("unterminated string");
            }
        },
        ' ', '\t', '\n', '\r' => {
            while (self.ch) |_ch| {
                switch (_ch) {
                    ' ', '\t', '\n', '\r' => self.advance(),
                    else => break,
                }
            }
            return self.next();
        },
        else => {
            self.advance();
            return self.err("unrecognized character");
        },
    };

    return .{
        .kind = kind,
        .lexeme = self.current_lexeme(),
        .location = self.start_loc,
    };
}

fn err(self: *Scanner, msg: []const u8) Token {
    return .{
        .kind = .err,
        .lexeme = self.current_lexeme(),
        .location = self.start_loc,
        .error_msg = msg,
    };
}

fn current_lexeme(self: *Scanner) []const u8 {
    return self.src[self.start_pos..self.pos];
}

fn advance_with(self: *Scanner, kind: TokenKind) TokenKind {
    self.advance();
    return kind;
}

fn advance(self: *Scanner) void {
    const ch = self.ch orelse return;

    if (ch == '\n') {
        self.loc.line += 1;
        self.loc.column = 1;
    } else {
        self.loc.column += 1;
    }

    self.ch = self.peek();
    self.pos += 1;
}

fn peek(self: *Scanner) ?u8 {
    if (self.pos + 1 >= self.src.len)
        return null;

    return self.src[self.pos + 1];
}

fn match(self: *Scanner, ch: u8) bool {
    if (self.peek() == ch) {
        self.advance();
        return true;
    }
    return false;
}

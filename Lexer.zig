source: Source,
start_pos: usize = 0,
cur_pos: usize = 0,

fn is_at_end(self: Lexer) bool {
    return self.cur_pos >= self.source.getSourceCode().len;
}

fn cur_char(self: Lexer) u8 {
    return self.source.getSourceCode()[self.cur_pos];
}

fn peek_char(self: Lexer) ?u8 {
    const code = self.source.getSourceCode();
    if (self.cur_pos + 1 >= code.len) return null;
    return code[self.cur_pos + 1];
}

fn cur_lexeme(self: Lexer) []const u8 {
    return self.source.getSourceCode()[self.start_pos..self.cur_pos];
}

fn cur_span(self: Lexer) Span {
    return .{ .start = self.start_pos, .end = self.cur_pos };
}

fn advance(self: *Lexer) ?u8 {
    if (self.is_at_end()) return null;
    defer self.cur_pos += 1;
    return self.cur_char();
}

fn match(self: *Lexer, c: u8) bool {
    if (self.is_at_end()) return false;
    if (self.cur_char() != c) return false;
    _ = self.advance();
    return true;
}

fn tok(self: *const Lexer, tag: Tag) Token {
    return .{
        .tag = tag,
        .source = self.source,
        .span = self.cur_span(),
    };
}

fn advance_while(self: *Lexer, pred: fn (u8) bool) void {
    while (!self.is_at_end() and pred(self.cur_char())) {
        _ = self.advance();
    }
}

fn is_not_newline(c: u8) bool {
    return c != '\n';
}

fn single_line_comment(self: *Lexer) Tag {
    self.advance_while(is_not_newline);
    return .single_line_comment;
}

fn multi_line_comment(self: *Lexer) Tag {
    return while (self.advance()) |c| {
        if (c == '*' and self.advance() == '/') {
            break .multi_line_comment;
        }
    } else .unterminated_multi_line_comment_err;
}

fn string(self: *Lexer) Tag {
    return while (self.advance()) |c| {
        if (c == '"') {
            break .string;
        }
    } else .unterminated_string_err;
}

fn is_ident_start(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}

fn is_ident_part(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

fn identifier_or_keyword(self: *Lexer) Tag {
    self.advance_while(is_ident_part);

    const lexeme = self.cur_lexeme();
    return for (Tag.keywords) |keyword| {
        if (std.mem.eql(u8, @tagName(keyword), lexeme)) break keyword;
    } else .identifier;
}

fn is_number_start(c: u8) bool {
    return std.ascii.isDigit(c);
}

fn number(self: *Lexer) Tag {
    self.advance_while(is_number_start);

    if (!self.is_at_end() and self.cur_char() == '.') {
        if (self.peek_char()) |c| {
            if (is_number_start(c)) {
                _ = self.advance();
                self.advance_while(is_number_start);
            }
        }
    }

    return .number;
}

pub fn next_token(self: *Lexer) ?Token {
    self.start_pos = self.cur_pos;
    const c = self.advance() orelse return null;

    const tag: Tag = switch (c) {
        '(' => .left_paren,
        ')' => .right_paren,
        '{' => .left_brace,
        '}' => .right_brace,
        ',' => .comma,
        ';' => .semicolon,
        '.' => .dot,
        '+' => .plus,
        '-' => .minus,
        '*' => .star,
        '/' => if (self.match('/')) self.single_line_comment() else if (self.match('*')) self.multi_line_comment() else .slash,
        '!' => if (self.match('=')) .bang_equal else .bang,
        '=' => if (self.match('=')) .equal_equal else .equal,
        '>' => if (self.match('=')) .greater_equal else .greater,
        '<' => if (self.match('=')) .less_equal else .less,
        '"' => self.string(),
        0x20 => .space,
        0x09 => .horizontal_tab,
        0x0A => .newline,
        0x0B => .vertical_tab,
        0x0C => .page_break,
        0x0D => .carriage_return,
        else => if (is_ident_start(c))
            self.identifier_or_keyword()
        else if (is_number_start(c))
            self.number()
        else
            .unknown_character_err,
    };

    return self.tok(tag);
}

pub fn lex(source: Source, gpa: Allocator) Allocator.Error!std.ArrayList(Token) {
    var tokens: std.ArrayList(Token) = .empty;
    errdefer tokens.deinit(gpa);

    var lexer: Lexer = .{ .source = source };
    while (lexer.next_token()) |t| {
        try tokens.append(gpa, t);
    }
    try tokens.append(gpa, lexer.tok(.eof));

    return tokens;
}

const Lexer = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const Token = @import("Token.zig");
const Tag = Token.Tag;
const Span = Token.Span;

const source_manager = @import("source_manager.zig");
const Source = source_manager.Source;

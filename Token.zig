tag: Tag,
source: Source,
span: Span,

pub const Tag = enum {
    // zig fmt: off
    
    // single-character
    left_paren, right_paren, left_brace, right_brace,
    comma, colon, semicolon, dot, plus, minus, star, slash,

    // one or two character
    bang, bang_equal, equal, equal_equal,
    greater, greater_equal, less, less_equal,
    
    // literals
    identifier, string, number,

    // keywords
    @"and", class, @"else", false, fun, @"for", 
    @"if", nil, @"or", print, @"return",
    super, this, true, @"var", @"while",

    // trivia
    single_line_comment, multi_line_comment,
    space, horizontal_tab, newline, vertical_tab, 
    page_break, carriage_return,

    // errors
    unknown_character_err,
    unterminated_multi_line_comment_err,
    unterminated_string_err,

    eof,
    
    // zig fmt: on

    pub fn is_one_of(self: Tag, comptime tags: []const Tag) bool {
        return inline for (tags) |other| {
            if (self == other) break true;
        } else false;
    }

    pub const keywords = [_]Tag{
        .@"and", .class, .@"else", .false,    .fun,       .@"for",
        .@"if",  .nil,   .@"or",   .print,    .@"return", .super,
        .this,   .true,  .@"var",  .@"while",
    };

    pub fn is_keyword(self: Tag) bool {
        return self.is_one_of(&keywords);
    }

    pub const comments = [_]Tag{ .single_line_comment, .multi_line_comment };

    pub fn is_comment(self: Tag) bool {
        return self.is_one_of(&comments);
    }

    pub const whitespaces = [_]Tag{ .space, .horizontal_tab, .newline, .vertical_tab, .page_break, .carriage_return };

    pub fn is_whitespace(self: Tag) bool {
        return self.is_one_of(&whitespaces);
    }

    pub fn is_trivia(self: Tag) bool {
        return self.is_comment() or self.is_whitespace();
    }

    pub const errs = [_]Tag{ .unknown_character_err, .unterminated_multi_line_comment_err, .unterminated_string_err };

    pub fn is_err(self: Tag) bool {
        return self.is_one_of(&errs);
    }
};

pub const Span = struct {
    start: usize,
    end: usize,
};

pub fn lexeme(self: Token) []const u8 {
    return self.source.getLexeme(self.span.start, self.span.end);
}

pub fn location(self: Token) source_manager.Location {
    return self.source.getLocation(self.span.start);
}

pub fn format(self: Token, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("{t}('{s}')", .{ self.tag, self.lexeme() });
}

const Token = @This();

const std = @import("std");

const source_manager = @import("source_manager.zig");
const Source = source_manager.Source;

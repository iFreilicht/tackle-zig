const std = @import("std");
const state = @import("state.zig");
const constants = @import("constants.zig");
const Player = state.Player;
const column_letters = constants.column_letters;
const block_sigil = constants.block_sigil;
const max_turn_str_len = 22;

const CommentQuality = enum {
    very_good, // (!!)
    good, // (!)
    interesting, // (!?)
    bad, // (?)
    very_bad, // (??)
};
const SpecialAction = enum {
    // These can't happen in the same turn
    gold_removed, // (>)
    worm, // (w)
};
const CommentWinning = enum {
    job_in_one, // x
    win, // xx
};

const Corner = enum {
    bottom_left, // A1
    bottom_right, // J1
    top_left, // A10
    top_right, // J10
};
const DiagonalMove = struct {
    from: Corner,
    distance: u4,

    pub fn format(self: @This(), writer: *std.io.Writer) std.io.Writer.Error!void {
        const start_x: u4 = switch (self.from) {
            .bottom_left => 1,
            .bottom_right => 10,
            .top_left => 1,
            .top_right => 10,
        };
        const start_y: u4 = switch (self.from) {
            .bottom_left => 1,
            .bottom_right => 1,
            .top_left => 10,
            .top_right => 10,
        };
        const end_x: u4 = switch (self.from) {
            .bottom_left => start_x + self.distance,
            .bottom_right => start_x - self.distance,
            .top_left => start_x + self.distance,
            .top_right => start_x - self.distance,
        };
        const end_y: u4 = switch (self.from) {
            .bottom_left => start_y + self.distance,
            .bottom_right => start_y + self.distance,
            .top_left => start_y - self.distance,
            .top_right => start_y - self.distance,
        };
        const start_x_str = column_letters[start_x - 1];
        const end_e_x_str = column_letters[end_x - 1];
        _ = try writer.print("{c}{}-{c}{}", .{ start_x_str, start_y, end_e_x_str, end_y });
    }
};

const HorizontalMove = struct {
    from_x: u4,
    to_x: u4,
    y: u4,
    block_height: u2, // 0 means no block (i.e. height of 1), 1 means block of height 2, etc.

    fn is_block(self: @This()) bool {
        return self.block_height > 0;
    }

    pub fn format(self: @This(), writer: *std.io.Writer) std.io.Writer.Error!void {
        const start_x = column_letters[self.from_x];
        const end_x = column_letters[self.to_x];
        const start_y: u4 = self.y + 1;
        if (self.is_block()) {
            const block_y = start_y + self.block_height;
            _ = try writer.print("▢{c}{}{}-{c}{}{}", .{
                start_x,
                start_y,
                block_y,
                end_x,
                start_y,
                block_y,
            });
        } else {
            _ = try writer.print("{c}{}-{c}{}", .{
                start_x,
                start_y,
                end_x,
                start_y,
            });
        }
    }
};
const VerticalMove = struct {
    from_y: u4,
    to_y: u4,
    x: u4,
    block_width: u2, // 0 means no block (i.e. width of 1), 1 means block of width 2, etc.

    fn is_block(self: @This()) bool {
        return self.block_width > 0;
    }

    pub fn format(self: @This(), writer: *std.io.Writer) std.io.Writer.Error!void {
        const start_x = column_letters[self.x];
        const start_y: u4 = self.from_y + 1;
        const end_y: u4 = self.to_y + 1;
        if (self.is_block()) {
            const block_x = column_letters[self.x + self.block_width];
            _ = try writer.print("{s}{c}{c}{}-{c}{c}{}", .{
                block_sigil,
                start_x,
                block_x,
                start_y,
                start_x,
                block_x,
                end_y,
            });
        } else {
            _ = try writer.print("{c}{}-{c}{}", .{
                start_x,
                start_y,
                start_x,
                end_y,
            });
        }
    }
};

const Move = union(enum) {
    diagonal: DiagonalMove,
    horizontal: HorizontalMove,
    vertical: VerticalMove,

    pub fn format(self: @This(), writer: *std.io.Writer) std.io.Writer.Error!void {
        _ = try switch (self) {
            .diagonal => |d| d.format(writer),
            .horizontal => |h| h.format(writer),
            .vertical => |v| v.format(writer),
        };
    }
};

const Turn = struct {
    by: Player,
    move: Move,
    winning: ?CommentWinning = null,
    special_action: ?SpecialAction = null,
    quality: ?CommentQuality = null,

    pub fn format(self: @This(), writer: *std.io.Writer) std.io.Writer.Error!void {
        // Write player color
        _ = try writer.write(switch (self.by) {
            .white => "w",
            .black => "b",
        });

        // Write move
        _ = try self.move.format(writer);

        // Write comment for winning state
        if (self.winning) |winning| {
            _ = try writer.write(switch (winning) {
                .job_in_one => "x",
                .win => "xx",
            });
        }

        // Write special action
        if (self.special_action) |special_action| {
            _ = try writer.write(switch (special_action) {
                .gold_removed => "(>)",
                .worm => "(w)",
            });
        }
        // Write comment for quality
        if (self.quality) |quality| {
            _ = try writer.write(switch (quality) {
                .very_good => "(!!)",
                .good => "(!)",
                .interesting => "(!?)",
                .bad => "(?)",
                .very_bad => "(??)",
            });
        }
    }
};

const TurnParser = struct {
    const State = enum {
        start,
        color,
        block,
        letter_start,
        second_letter_start,
        number_start,
        second_number_start,
        dash,
        letter_end,
        second_letter_end,
        number_end,
        second_number_end,
        winning,
        special_action,
        quality,
        done,
    };

    const Error = error{
        ColorInvalid,
        ColumnInvalid,
        SecondColumnSmallerThanFirst,
        RowTooShort,
        RowInvalid,
        FirstRowIs10,
        SecondRowSmallerThanFirst,
        DiagonalMoveIllegal,
        BlockInTwoDirections,
        WinningCommentInvalid,
    };

    by: ?Player = null,
    column_start: ?u4 = null,
    row_start: ?u4 = null,
    column_end: ?u4 = null,
    row_end: ?u4 = null,
    block_width: ?u2 = null,
    block_height: ?u2 = null,
    move: ?Move = null,
    winning: ?CommentWinning = null,
    special_action: ?SpecialAction = null,
    quality: ?CommentQuality = null,

    pub fn parse(reader: *std.io.Reader) !Turn {
        var self: TurnParser = .{};
        parse: switch (State.start) {
            .start => {
                continue :parse .color;
            },
            .color => {
                const c = try reader.takeByte();
                self.by = switch (c) {
                    'w' => .white,
                    'b' => .black,
                    else => return Error.ColorInvalid,
                };
                continue :parse .block;
            },
            .block => {
                try reader.fill(block_sigil.len);
                const s = try reader.peek(block_sigil.len);
                if (std.mem.eql(u8, s, block_sigil)) {
                    reader.toss(block_sigil.len);
                    // Block size is determined later. It's not an error if the move
                    // is a block move despite the block symbol missing from the input.
                }
                continue :parse .letter_start;
            },
            .letter_start => {
                self.column_start = try parse_letter(reader);
                continue :parse .second_letter_start;
            },
            .second_letter_start => {
                const column: u4 = parse_letter(reader) catch |err| {
                    if (err == Error.ColumnInvalid) {
                        // No second column means no block move
                        self.block_width = 0;
                        continue :parse .number_start;
                    } else {
                        return err;
                    }
                };
                const column_start = self.column_start orelse unreachable;
                if (column <= column_start) return Error.SecondColumnSmallerThanFirst;
                self.block_width = @intCast(column - column_start);
                continue :parse .number_start;
            },
            .number_start => {
                self.row_start = try parse_number(reader);
                if (self.row_start == 10) continue :parse .dash;
                continue :parse .second_number_start;
            },
            .second_number_start => {
                const row = parse_number(reader) catch |err| {
                    if (err == Error.RowInvalid) {
                        // No second row means no block move
                        self.block_height = 0;
                        continue :parse .dash;
                    } else {
                        return err;
                    }
                };
                const row_start = self.row_start orelse unreachable;
                if (row <= row_start) return Error.SecondRowSmallerThanFirst;
                self.block_height = @intCast(row - row_start);
                continue :parse .dash;
            },
            .dash => {
                _ = try reader.takeDelimiter('-');
                continue :parse .letter_end;
            },
            .letter_end => {
                self.column_end = try parse_letter(reader);
                continue :parse .second_letter_end;
            },
            .second_letter_end => {
                const column = parse_letter(reader) catch |err| {
                    if (err == Error.ColumnInvalid) {
                        continue :parse .number_end;
                    } else {
                        return err;
                    }
                };
                if (column <= self.column_start orelse unreachable) return Error.SecondColumnSmallerThanFirst;
                // block width was already determined when parsing the start letters
                continue :parse .number_end;
            },
            .number_end => {
                self.row_end = try parse_number(reader);
                continue :parse .second_number_end;
            },
            .second_number_end => {
                const row = parse_number(reader) catch |err| {
                    if (err == Error.RowInvalid) {
                        continue :parse .winning;
                    } else if (err == error.EndOfStream) {
                        continue :parse .done;
                    } else {
                        return err;
                    }
                };
                if (row <= self.row_end orelse unreachable) return Error.SecondRowSmallerThanFirst;
                // block height was already determined when parsing the start numbers
                continue :parse .winning;
            },
            .winning => {
                const s = reader.takeDelimiterExclusive('(') catch |err| {
                    if (err == error.EndOfStream) {
                        continue :parse .done;
                    } else {
                        return err;
                    }
                };
                if (std.mem.eql(u8, s, "x")) {
                    self.winning = .job_in_one;
                } else if (std.mem.eql(u8, s, "xx")) {
                    self.winning = .win;
                } else if (s.len != 0) return Error.WinningCommentInvalid;
                continue :parse .special_action;
            },
            .special_action => {
                const s = reader.takeDelimiterInclusive(')') catch |err| {
                    if (err == error.EndOfStream) {
                        continue :parse .done;
                    } else {
                        return err;
                    }
                };
                if (std.mem.startsWith(u8, s, "(>)")) {
                    self.special_action = .gold_removed;
                } else if (std.mem.startsWith(u8, s, "(w)")) {
                    self.special_action = .worm;
                } else {
                    // Rewind the reader as this comment might be a quality comment
                    reader.seek -= @intCast(s.len);
                }
                continue :parse .quality;
            },
            .quality => {
                const s = reader.takeDelimiterInclusive(')') catch |err| {
                    if (err == error.EndOfStream) {
                        continue :parse .done;
                    } else {
                        return err;
                    }
                };
                if (s.len == 0) continue :parse .done;
                if (std.mem.startsWith(u8, s, "(!!)")) {
                    self.quality = .very_good;
                } else if (std.mem.startsWith(u8, s, "(!)")) {
                    self.quality = .good;
                } else if (std.mem.startsWith(u8, s, "(!?)")) {
                    self.quality = .interesting;
                } else if (std.mem.startsWith(u8, s, "(?)")) {
                    self.quality = .bad;
                } else if (std.mem.startsWith(u8, s, "(??)")) {
                    self.quality = .very_bad;
                }
                continue :parse .done;
            },
            else => {},
        }

        const col_start = self.column_start orelse unreachable;
        const col_end = self.column_end orelse unreachable;
        const row_start = self.row_start orelse unreachable;
        const row_end = self.row_end orelse unreachable;
        if (row_start == row_end) {
            // Horizontal move
            self.move = .{ .horizontal = .{
                .from_x = col_start,
                .to_x = col_end,
                .y = row_start,
                .block_height = self.block_height orelse unreachable,
            } };
        } else if (col_start == col_end) {
            // Vertical move
            self.move = .{ .vertical = .{
                .from_y = row_start,
                .to_y = row_end,
                .x = col_start,
                .block_width = self.block_width orelse unreachable,
            } };
        } else {
            // Diagonal move
            const from: Corner = switch (row_start) {
                1 => if (col_start == 1) .bottom_left else .bottom_right,
                10 => if (col_start == 1) .top_left else .top_right,
                else => return Error.RowTooShort,
            };
            const distance_col = if (from == .bottom_left or from == .top_left) col_end - col_start else col_start - col_end;
            const distance_row = if (from == .bottom_left or from == .bottom_right) row_end - row_start else row_start - row_end;
            if (distance_col != distance_row) {
                return Error.DiagonalMoveIllegal;
            }

            self.move = .{ .diagonal = .{
                .from = from,
                .distance = distance_col,
            } };
        }

        // After parsing, construct the Turn object
        return Turn{
            .by = self.by orelse return error.InvalidFormat,
            .move = self.move orelse return error.InvalidFormat,
            .winning = self.winning,
            .special_action = self.special_action,
            .quality = self.quality,
        };
    }

    fn parse_letter(reader: *std.io.Reader) !u4 {
        const c = try reader.peek(1);
        const col = std.mem.indexOf(u8, &column_letters, c) orelse return Error.ColumnInvalid;
        reader.toss(1);
        return @intCast(col + 1);
    }

    fn parse_number(reader: *std.io.Reader) !u4 {
        const s = reader.peek(2) catch try reader.peek(1);
        if (std.mem.eql(u8, s, "10")) {
            reader.toss(2);
            return 10;
        }
        const c = s[0];
        if (c < '1' or c > '9') return Error.RowInvalid;
        reader.toss(1);
        return @intCast(c - '0');
    }
};

test "format horizontal simple move" {
    const turn: Turn = .{
        .by = .black,
        .move = .{ .horizontal = .{
            .from_x = 5,
            .to_x = 2,
            .y = 3,
            .block_height = 0,
        } },
    };

    var buffer: [6]u8 = undefined;
    var writer = std.io.Writer.fixed(&buffer);
    _ = try writer.print("{f}", .{turn});
    try std.testing.expectEqualStrings("bF4-C4", &buffer);
}

test "format horizontal block move" {
    const turn: Turn = .{
        .by = .white,
        .move = .{ .horizontal = .{
            .from_x = 0,
            .to_x = 2,
            .y = 4,
            .block_height = 1,
        } },
    };

    var buffer: [11]u8 = undefined;
    var writer = std.io.Writer.fixed(&buffer);
    _ = try writer.print("{f}", .{turn});
    try std.testing.expectEqualStrings("w▢A56-C56", &buffer);
}

test "format vertical simple move" {
    const turn: Turn = .{
        .by = .black,
        .move = .{ .vertical = .{
            .from_y = 1,
            .to_y = 4,
            .x = 6,
            .block_width = 0,
        } },
    };

    var buffer: [6]u8 = undefined;
    var writer = std.io.Writer.fixed(&buffer);
    _ = try writer.print("{f}", .{turn});
    try std.testing.expectEqualStrings("bG2-G5", &buffer);
}

test "format vertical block move" {
    const turn: Turn = .{
        .by = .white,
        .move = .{ .vertical = .{
            .from_y = 9,
            .to_y = 0,
            .x = 3,
            .block_width = 2,
        } },
    };

    var buffer: [12]u8 = undefined;
    var writer = std.io.Writer.fixed(&buffer);
    _ = try writer.print("{f}", .{turn});
    try std.testing.expectEqualStrings("w▢DF10-DF1", &buffer);
}

test "format diagonal move 1" {
    const turn: Turn = .{
        .by = .black,
        .move = .{ .diagonal = .{
            .from = .bottom_left,
            .distance = 4,
        } },
    };

    var buffer: [6]u8 = undefined;
    var writer = std.io.Writer.fixed(&buffer);
    _ = try writer.print("{f}", .{turn});
    try std.testing.expectEqualStrings("bA1-E5", &buffer);
}

test "format diagonal move 2" {
    const move: Move = .{ .diagonal = .{
        .from = .top_right,
        .distance = 3,
    } };

    var buffer: [6]u8 = undefined;
    var writer = std.io.Writer.fixed(&buffer);
    _ = try writer.print("{f}", .{move});
    try std.testing.expectEqualStrings("J10-G7", &buffer);
}

test "format diagonal move 3" {
    const move: Move = .{ .diagonal = .{
        .from = .top_left,
        .distance = 5,
    } };

    var buffer: [6]u8 = undefined;
    var writer = std.io.Writer.fixed(&buffer);
    _ = try writer.print("{f}", .{move});
    try std.testing.expectEqualStrings("A10-F5", &buffer);
}

test "format diagonal move 4" {
    const move: Move = .{ .diagonal = .{
        .from = .bottom_right,
        .distance = 9,
    } };

    var buffer: [6]u8 = undefined;
    var writer = std.io.Writer.fixed(&buffer);
    _ = try writer.print("{f}", .{move});
    try std.testing.expectEqualStrings("J1-A10", &buffer);
}

test "format full move with comments" {
    const turn: Turn = .{
        .by = .black,
        .move = .{ .vertical = .{
            .from_y = 0,
            .to_y = 9,
            .x = 4,
            .block_width = 1,
        } },
        .special_action = .gold_removed,
        .quality = .interesting,
        .winning = .job_in_one,
    };

    var buffer: [20]u8 = undefined;
    var writer = std.io.Writer.fixed(&buffer);
    _ = try writer.print("{f}", .{turn});
    try std.testing.expectEqualStrings("b▢EF1-EF10x(>)(!?)", &buffer);
}

test "format move resulting in maximum string length" {
    const turn: Turn = .{
        .by = .white,
        .move = .{ .horizontal = .{
            .from_x = 3,
            .to_x = 9,
            .y = 7,
            .block_height = 2,
        } },
        .special_action = .gold_removed,
        .quality = .very_good,
        .winning = .win,
    };

    var buffer: [max_turn_str_len]u8 = .{255} ** max_turn_str_len;
    var writer = std.io.Writer.fixed(&buffer);
    _ = try writer.print("{f}", .{turn});
    try std.testing.expectEqualStrings("w▢D810-J810xx(>)(!!)", &buffer);

    // Ensure that no bytes in the buffer were unused.
    // This confirms that max_turn_str_len is the smallest it can be.
    for (buffer) |b| {
        try std.testing.expect(b != 255);
    }
}

test "parse horizontal simple move" {
    var input = std.io.Reader.fixed("bH4-B4");
    const turn = try TurnParser.parse(&input);
    const expected: Turn = .{
        .by = .black,
        .move = .{ .horizontal = .{
            .from_x = 8,
            .to_x = 2,
            .y = 4,
            .block_height = 0,
        } },
    };

    try std.testing.expectEqualDeep(expected, turn);
}

test "parse horizontal block move" {
    var input = std.io.Reader.fixed("w▢D56-G56");
    const turn = try TurnParser.parse(&input);
    const expected: Turn = .{
        .by = .white,
        .move = .{ .horizontal = .{
            .from_x = 4,
            .to_x = 7,
            .y = 5,
            .block_height = 1,
        } },
    };

    try std.testing.expectEqualDeep(expected, turn);
}

test "parse vertical simple move" {
    var input = std.io.Reader.fixed("wC2-C5");
    const turn = try TurnParser.parse(&input);
    const expected: Turn = .{
        .by = .white,
        .move = .{ .vertical = .{
            .from_y = 2,
            .to_y = 5,
            .x = 3,
            .block_width = 0,
        } },
    };

    try std.testing.expectEqualDeep(expected, turn);
}

test "parse vertical block move" {
    var input = std.io.Reader.fixed("b▢EF10-EF1");
    const turn = try TurnParser.parse(&input);
    const expected: Turn = .{
        .by = .black,
        .move = .{ .vertical = .{
            .from_y = 10,
            .to_y = 1,
            .x = 5,
            .block_width = 1,
        } },
    };

    try std.testing.expectEqualDeep(expected, turn);
}

test "parse diagonal move 1" {
    var input = std.io.Reader.fixed("wA1-E5");
    const turn = try TurnParser.parse(&input);
    const expected: Turn = .{
        .by = .white,
        .move = .{ .diagonal = .{
            .from = .bottom_left,
            .distance = 4,
        } },
    };

    try std.testing.expectEqualDeep(expected, turn);
}

test "parse diagonal move 2" {
    var input = std.io.Reader.fixed("bJ10-G7");
    const turn = try TurnParser.parse(&input);
    const expected: Turn = .{
        .by = .black,
        .move = .{ .diagonal = .{
            .from = .top_right,
            .distance = 3,
        } },
    };

    try std.testing.expectEqualDeep(expected, turn);
}

test "parse diagonal move 3" {
    var input = std.io.Reader.fixed("wA10-F5");
    const turn = try TurnParser.parse(&input);
    const expected: Turn = .{
        .by = .white,
        .move = .{ .diagonal = .{
            .from = .top_left,
            .distance = 5,
        } },
    };

    try std.testing.expectEqualDeep(expected, turn);
}

test "parse diagonal move 4" {
    var input = std.io.Reader.fixed("bJ1-A10");
    const turn = try TurnParser.parse(&input);
    const expected: Turn = .{
        .by = .black,
        .move = .{ .diagonal = .{
            .from = .bottom_right,
            .distance = 9,
        } },
    };

    try std.testing.expectEqualDeep(expected, turn);
}

test "parse full move with comments" {
    var input = std.io.Reader.fixed("b▢EF1-EF10x(>)(!?)");
    const turn = try TurnParser.parse(&input);
    const expected: Turn = .{
        .by = .black,
        .move = .{ .vertical = .{
            .from_y = 1,
            .to_y = 10,
            .x = 5,
            .block_width = 1,
        } },
        .special_action = .gold_removed,
        .quality = .interesting,
        .winning = .job_in_one,
    };

    try std.testing.expectEqualDeep(expected, turn);
}

test "parse move only with quality comment" {
    var input = std.io.Reader.fixed("wA1-A2(!!)");
    const turn = try TurnParser.parse(&input);
    const expected: Turn = .{
        .by = .white,
        .move = .{ .vertical = .{
            .from_y = 1,
            .to_y = 2,
            .x = 1,
            .block_width = 0,
        } },
        .quality = .very_good,
    };

    try std.testing.expectEqualDeep(expected, turn);
}

test "parse move only with special action comment" {
    var input = std.io.Reader.fixed("bJ10-J9(>)");
    const turn = try TurnParser.parse(&input);
    const expected: Turn = .{
        .by = .black,
        .move = .{ .vertical = .{
            .from_y = 10,
            .to_y = 9,
            .x = 10,
            .block_width = 0,
        } },
        .special_action = .gold_removed,
    };

    try std.testing.expectEqualDeep(expected, turn);
}

test "parse move only with winning comment" {
    var input = std.io.Reader.fixed("wC3-C4x");
    const turn = try TurnParser.parse(&input);
    const expected: Turn = .{
        .by = .white,
        .move = .{ .vertical = .{
            .from_y = 3,
            .to_y = 4,
            .x = 3,
            .block_width = 0,
        } },
        .winning = .job_in_one,
    };

    try std.testing.expectEqualDeep(expected, turn);
}

test "parse move with maximum string length" {
    var input = std.io.Reader.fixed("w▢D810-J810xx(>)(!!)");
    const turn = try TurnParser.parse(&input);
    const expected: Turn = .{
        .by = .white,
        .move = .{ .horizontal = .{
            .from_x = 4,
            .to_x = 10,
            .y = 8,
            .block_height = 2,
        } },
        .special_action = .gold_removed,
        .quality = .very_good,
        .winning = .win,
    };

    try std.testing.expectEqualDeep(expected, turn);
}

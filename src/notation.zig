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

/// A row on the board, identified by its Y coordinate (1-10, 0 is not a valid value!)
/// Rows are labeled 1-10.
const RowY = enum(u4) {
    _1 = 1,
    _2 = 2,
    _3 = 3,
    _4 = 4,
    _5 = 5,
    _6 = 6,
    _7 = 7,
    _8 = 8,
    _9 = 9,
    _10 = 10,

    pub fn plus(self: @This(), block_size: BlockSize) @This() {
        return @enumFromInt(@intFromEnum(self) + @intFromEnum(block_size));
    }

    pub fn distance(self: @This(), other: @This()) u4 {
        const s = @intFromEnum(self);
        const o = @intFromEnum(other);
        return if (s > o) s - o else o - s;
    }

    fn parse(reader: *std.io.Reader) !@This() {
        const s = reader.peek(2) catch try reader.peek(1);
        if (std.mem.eql(u8, s, "10")) {
            reader.toss(2);
            return ._10;
        }
        const c = s[0];
        if (c < '1' or c > '9') return error.RowInvalid;
        reader.toss(1);
        return @enumFromInt(c - '0');
    }
};

fn get_block_height(first: RowY, last: RowY) BlockSize {
    return @enumFromInt(@intFromEnum(last) - @intFromEnum(first));
}

/// A column on the board, identified by its X coordinate (1-10, 0 is not a valid value!)
/// Columns are labeled A-J, see also the `column_letters` constant.
const ColumnX = enum(u4) {
    A = 1,
    B = 2,
    C = 3,
    D = 4,
    E = 5,
    F = 6,
    G = 7,
    H = 8,
    I = 9, // output as 'i', see `column_letters`
    J = 10,

    pub fn plus(self: @This(), block_size: BlockSize) @This() {
        return @enumFromInt(@intFromEnum(self) + @intFromEnum(block_size));
    }

    pub fn distance(self: @This(), other: @This()) u4 {
        const s = @intFromEnum(self);
        const o = @intFromEnum(other);
        return if (s > o) s - o else o - s;
    }

    pub fn format(self: @This(), writer: *std.io.Writer) std.io.Writer.Error!void {
        const c = column_letters[@intFromEnum(self) - 1];
        _ = try writer.writeByte(c);
    }

    fn parse(reader: *std.io.Reader) !@This() {
        const c = try reader.peek(1);
        const col = std.mem.indexOf(u8, &column_letters, c) orelse return error.ColumnInvalid;
        reader.toss(1);
        return @enumFromInt(col + 1);
    }
};

fn get_block_width(first: ColumnX, last: ColumnX) BlockSize {
    return @enumFromInt(@intFromEnum(last) - @intFromEnum(first));
}

/// Size of a block perpendicular to the move direction (2-4, 0 means no block)
/// Blocks can easily be longer than 4 in the move direction, but this is not represented
/// in the notation anyway. 4 is the maximum because for a block of 5 to move perpendicularly
/// to the side that is 5 units wide, the block would have to contain 25 pieces.
/// However, a maximum of 18 pieces can be placed per player, so a block of 5 is impossible.
/// A block of 4 is also unlikely to happen in regular play, but still possible in theory.
const BlockSize = enum(u2) { no_block = 0, _2 = 1, _3 = 2, _4 = 3 };

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
        _ = try writer.print("{c}{d}-{c}{d}", .{ start_x_str, start_y, end_e_x_str, end_y });
    }
};

const HorizontalMove = struct {
    from_x: ColumnX,
    to_x: ColumnX,
    y: RowY,
    block_height: BlockSize,

    fn is_block(self: @This()) bool {
        return self.block_height != .no_block;
    }

    pub fn format(self: @This(), writer: *std.io.Writer) std.io.Writer.Error!void {
        const start_x = self.from_x;
        const end_x = self.to_x;
        const start_y = self.y;
        if (self.is_block()) {
            const block_y = start_y.plus(self.block_height);
            _ = try writer.print("▢{f}{d}{d}-{f}{d}{d}", .{
                start_x,
                start_y,
                block_y,
                end_x,
                start_y,
                block_y,
            });
        } else {
            _ = try writer.print("{f}{d}-{f}{d}", .{
                start_x,
                start_y,
                end_x,
                start_y,
            });
        }
    }
};

const VerticalMove = struct {
    from_y: RowY,
    to_y: RowY,
    x: ColumnX,
    block_width: BlockSize,

    fn is_block(self: @This()) bool {
        return self.block_width != .no_block;
    }

    pub fn format(self: @This(), writer: *std.io.Writer) std.io.Writer.Error!void {
        const start_x = self.x;
        const start_y = self.from_y;
        const end_y = self.to_y;
        if (self.is_block()) {
            const block_x = start_x.plus(self.block_width);
            _ = try writer.print("{s}{f}{f}{d}-{f}{f}{d}", .{
                block_sigil,
                start_x,
                block_x,
                start_y,
                start_x,
                block_x,
                end_y,
            });
        } else {
            _ = try writer.print("{f}{d}-{f}{d}", .{
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
        SecondColumnSmallerThanFirst,
        RowTooShort,
        FirstRowIs10,
        SecondRowSmallerThanFirst,
        DiagonalMoveIllegal,
        BlockInTwoDirections,
        WinningCommentInvalid,
    };

    pub fn parse(reader: *std.io.Reader) !Turn {
        var by: Player = undefined;
        var column_start: ColumnX = undefined;
        var row_start: RowY = undefined;
        var column_end: ColumnX = undefined;
        var row_end: RowY = undefined;
        var block_width: ?BlockSize = null;
        var block_height: ?BlockSize = null;
        var winning: ?CommentWinning = null;
        var special_action: ?SpecialAction = null;
        var quality: ?CommentQuality = null;

        parse: switch (State.start) {
            .start => {
                continue :parse .color;
            },
            .color => {
                const c = try reader.takeByte();
                by = switch (c) {
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
                column_start = try ColumnX.parse(reader);
                continue :parse .second_letter_start;
            },
            .second_letter_start => {
                const column = ColumnX.parse(reader) catch |err| {
                    if (err == error.ColumnInvalid) {
                        // No second column means no block move
                        block_width = .no_block;
                        continue :parse .number_start;
                    } else {
                        return err;
                    }
                };
                if (@intFromEnum(column) <= @intFromEnum(column_start)) return Error.SecondColumnSmallerThanFirst;
                block_width = get_block_width(column_start, column);
                continue :parse .number_start;
            },
            .number_start => {
                row_start = try RowY.parse(reader);
                if (row_start == ._10) continue :parse .dash;
                continue :parse .second_number_start;
            },
            .second_number_start => {
                const row = RowY.parse(reader) catch |err| {
                    if (err == error.RowInvalid) {
                        // No second row means no block move
                        block_height = .no_block;
                        continue :parse .dash;
                    } else {
                        return err;
                    }
                };
                if (@intFromEnum(row) <= @intFromEnum(row_start)) return Error.SecondRowSmallerThanFirst;
                block_height = get_block_height(row_start, row);
                continue :parse .dash;
            },
            .dash => {
                _ = try reader.takeDelimiter('-');
                continue :parse .letter_end;
            },
            .letter_end => {
                column_end = try ColumnX.parse(reader);
                continue :parse .second_letter_end;
            },
            .second_letter_end => {
                const column = ColumnX.parse(reader) catch |err| {
                    if (err == error.ColumnInvalid) {
                        continue :parse .number_end;
                    } else {
                        return err;
                    }
                };
                if (@intFromEnum(column) <= @intFromEnum(column_start)) return Error.SecondColumnSmallerThanFirst;
                // block width was already determined when parsing the start letters
                continue :parse .number_end;
            },
            .number_end => {
                row_end = try RowY.parse(reader);
                continue :parse .second_number_end;
            },
            .second_number_end => {
                const row = RowY.parse(reader) catch |err| {
                    if (err == error.RowInvalid) {
                        continue :parse .winning;
                    } else if (err == error.EndOfStream) {
                        continue :parse .done;
                    } else {
                        return err;
                    }
                };
                if (@intFromEnum(row) <= @intFromEnum(row_end)) return Error.SecondRowSmallerThanFirst;
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
                    winning = .job_in_one;
                } else if (std.mem.eql(u8, s, "xx")) {
                    winning = .win;
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
                    special_action = .gold_removed;
                } else if (std.mem.startsWith(u8, s, "(w)")) {
                    special_action = .worm;
                } else {
                    // Rewind the reader as this comment might be a quality comment
                    reader.seek -= s.len;
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
                    quality = .very_good;
                } else if (std.mem.startsWith(u8, s, "(!)")) {
                    quality = .good;
                } else if (std.mem.startsWith(u8, s, "(!?)")) {
                    quality = .interesting;
                } else if (std.mem.startsWith(u8, s, "(?)")) {
                    quality = .bad;
                } else if (std.mem.startsWith(u8, s, "(??)")) {
                    quality = .very_bad;
                }
                continue :parse .done;
            },
            .done => {},
        }

        var move: Move = undefined;
        if (row_start == row_end) {
            // Horizontal move
            move = .{ .horizontal = .{
                .from_x = column_start,
                .to_x = column_end,
                .y = row_start,
                .block_height = block_height orelse unreachable,
            } };
        } else if (column_start == column_end) {
            // Vertical move
            move = .{ .vertical = .{
                .from_y = row_start,
                .to_y = row_end,
                .x = column_start,
                .block_width = block_width orelse unreachable,
            } };
        } else {
            // Diagonal move
            const from: Corner = switch (row_start) {
                ._1 => if (column_start == .A) .bottom_left else .bottom_right,
                ._10 => if (column_start == .A) .top_left else .top_right,
                else => return Error.RowTooShort,
            };
            const distance_col = column_start.distance(column_end);
            const distance_row = row_start.distance(row_end);
            if (distance_col != distance_row) return Error.DiagonalMoveIllegal;

            move = .{ .diagonal = .{
                .from = from,
                .distance = distance_col,
            } };
        }

        // After parsing, construct the Turn object
        return Turn{
            .by = by,
            .move = move,
            .winning = winning,
            .special_action = special_action,
            .quality = quality,
        };
    }
};

test "format horizontal simple move" {
    const turn: Turn = .{
        .by = .black,
        .move = .{ .horizontal = .{
            .from_x = .F,
            .to_x = .C,
            .y = ._4,
            .block_height = .no_block,
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
            .from_x = .A,
            .to_x = .C,
            .y = ._5,
            .block_height = ._2,
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
            .from_y = ._2,
            .to_y = ._5,
            .x = .G,
            .block_width = .no_block,
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
            .from_y = ._10,
            .to_y = ._1,
            .x = .D,
            .block_width = ._3,
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
            .from_y = ._1,
            .to_y = ._10,
            .x = .E,
            .block_width = ._2,
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
            .from_x = .D,
            .to_x = .J,
            .y = ._8,
            .block_height = ._3,
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
            .from_x = .H,
            .to_x = .B,
            .y = ._4,
            .block_height = .no_block,
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
            .from_x = .D,
            .to_x = .G,
            .y = ._5,
            .block_height = ._2,
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
            .from_y = ._2,
            .to_y = ._5,
            .x = .C,
            .block_width = .no_block,
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
            .from_y = ._10,
            .to_y = ._1,
            .x = .E,
            .block_width = ._2,
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
            .from_y = ._1,
            .to_y = ._10,
            .x = .E,
            .block_width = ._2,
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
            .from_y = ._1,
            .to_y = ._2,
            .x = .A,
            .block_width = .no_block,
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
            .from_y = ._10,
            .to_y = ._9,
            .x = .J,
            .block_width = .no_block,
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
            .from_y = ._3,
            .to_y = ._4,
            .x = .C,
            .block_width = .no_block,
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
            .from_x = .D,
            .to_x = .J,
            .y = ._8,
            .block_height = ._3,
        } },
        .special_action = .gold_removed,
        .quality = .very_good,
        .winning = .win,
    };

    try std.testing.expectEqualDeep(expected, turn);
}

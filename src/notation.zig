const std = @import("std");

const tackle = @import("root.zig");

const column_letters = tackle.constants.column_letters;
const block_sigil = tackle.constants.block_sigil;
const max_turn_str_len = 22;

const Move = tackle.Move;
const Corner = tackle.position.Corner;
const ColumnX = tackle.position.ColumnX;
const RowY = tackle.position.RowY;
const Position = tackle.position.Position;
const BlockSize = tackle.position.BlockSize;
const getBlockWidth = tackle.position.getBlockWidth;
const getBlockHeight = tackle.position.getBlockHeight;
const PieceColor = tackle.enums.PieceColor;

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

/// An action taken by a player, either placing a piece or moving one.
pub const Action = union(enum) {
    place: Position,
    move: Move,

    pub fn format(self: @This(), writer: *std.io.Writer) std.io.Writer.Error!void {
        switch (self) {
            .place => |pos| {
                _ = try writer.print("{f}{f}", .{ pos.@"0", pos.@"1" });
            },
            .move => |mv| {
                try mv.format(writer);
            },
        }
    }
};

pub const Turn = struct {
    color: PieceColor,
    action: Action,
    winning: ?CommentWinning = null,
    special_action: ?SpecialAction = null,
    quality: ?CommentQuality = null,

    pub fn format(self: @This(), writer: *std.io.Writer) std.io.Writer.Error!void {
        // Write player color
        _ = try writer.write(switch (self.color) {
            .white => "w",
            .black => "b",
            .gold => "g",
        });

        // Write move
        _ = try self.action.format(writer);

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

/// Parse a turn in the standard notation from the given reader.
/// The `known_color` parameter can be used to substitute for the color prefix
/// in the notation, which is mostly used for human text-based input,
/// when the color is already known from the game state.
/// In file parsing, this parameter should be null to ensure all lines
/// can be parsed independently of each other.
pub fn parseTurn(reader: *std.io.Reader, known_color: ?PieceColor) !Turn {
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
    var color: PieceColor = undefined;
    var column_start: ColumnX = undefined;
    var row_start: RowY = undefined;
    var column_end: ?ColumnX = null;
    var row_end: ?RowY = null;
    var block_width: ?BlockSize = null;
    var block_height: ?BlockSize = null;
    var winning: ?CommentWinning = null;
    var special_action: ?SpecialAction = null;
    var quality: ?CommentQuality = null;

    parse: switch (State.start) {
        .start => {
            if (known_color) |c| {
                color = c;
                continue :parse .block;
            }
            continue :parse .color;
        },
        .color => {
            const c = try reader.takeByte();
            color = switch (c) {
                'w' => .white,
                'b' => .black,
                'g' => .gold,
                else => return error.ColorInvalid,
            };
            continue :parse .block;
        },
        .block => {
            reader.fill(block_sigil.len) catch |err| {
                if (err == error.EndOfStream) continue :parse .letter_start;
                return err;
            };
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
            if (@intFromEnum(column) <= @intFromEnum(column_start)) return error.SecondColumnSmallerThanFirst;
            block_width = getBlockWidth(column_start, column);
            continue :parse .number_start;
        },
        .number_start => {
            row_start = try RowY.parse(reader);
            if (row_start == ._10) continue :parse .dash;
            continue :parse .second_number_start;
        },
        .second_number_start => {
            const row = RowY.parse(reader) catch |err| {
                if (err == error.RowInvalid or err == error.EndOfStream) {
                    // No second row means no block move
                    block_height = .no_block;
                    continue :parse .dash;
                } else {
                    return err;
                }
            };
            if (@intFromEnum(row) <= @intFromEnum(row_start)) return error.SecondRowSmallerThanFirst;
            block_height = getBlockHeight(row_start, row);
            continue :parse .dash;
        },
        .dash => {
            _ = reader.takeDelimiterInclusive('-') catch |err| {
                if (err == error.EndOfStream) continue :parse .quality;
                return err;
            };
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
            if (@intFromEnum(column) <= @intFromEnum(column_end.?)) return error.SecondColumnSmallerThanFirst;
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
            if (@intFromEnum(row) <= @intFromEnum(row_end.?)) return error.SecondRowSmallerThanFirst;
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
            } else if (s.len != 0) return error.WinningCommentInvalid;
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

    if (column_end == null and row_end == null) {
        // It's a placement!
        // We don't consider the case where only one of column_end or row_end is null,
        // the parsing logic should prevent that from happening.
        return Turn{
            .color = color,
            .action = .{ .place = .{ column_start, row_start } },
            .quality = quality,
        };
    }

    var move: Move = undefined;
    if (row_start == row_end) {
        // Horizontal move
        move = .{ .horizontal = .{
            .from_x = column_start,
            .to_x = column_end orelse unreachable,
            .y = row_start,
            .block_height = block_height orelse unreachable,
        } };
    } else if (column_start == column_end) {
        // Vertical move
        move = .{ .vertical = .{
            .from_y = row_start,
            .to_y = row_end orelse unreachable,
            .x = column_start,
            .block_width = block_width orelse unreachable,
        } };
    } else {
        // Diagonal move
        const from: Corner = switch (row_start) {
            ._1 => if (column_start == .A) .bottom_left else .bottom_right,
            ._10 => if (column_start == .A) .top_left else .top_right,
            else => return error.RowTooShort,
        };
        const distance_col = column_start.distance(column_end.?);
        const distance_row = row_start.distance(row_end.?);
        if (distance_col != distance_row) return error.DiagonalMoveIllegal;

        move = .{ .diagonal = .{
            .from = from,
            .distance = distance_col,
        } };
    }

    // After parsing, construct the Turn object
    return Turn{
        .color = color,
        .action = .{ .move = move },
        .winning = winning,
        .special_action = special_action,
        .quality = quality,
    };
}

test "format horizontal simple move" {
    const turn: Turn = .{
        .color = .black,
        .action = .{ .move = .{ .horizontal = .{
            .from_x = .F,
            .to_x = .C,
            .y = ._4,
            .block_height = .no_block,
        } } },
    };

    var buffer: [6]u8 = undefined;
    var writer = std.io.Writer.fixed(&buffer);
    _ = try writer.print("{f}", .{turn});
    try std.testing.expectEqualStrings("bF4-C4", &buffer);
}

test "format horizontal block move" {
    const turn: Turn = .{
        .color = .white,
        .action = .{ .move = .{ .horizontal = .{
            .from_x = .A,
            .to_x = .C,
            .y = ._5,
            .block_height = ._2,
        } } },
    };

    var buffer: [11]u8 = undefined;
    var writer = std.io.Writer.fixed(&buffer);
    _ = try writer.print("{f}", .{turn});
    try std.testing.expectEqualStrings("w▢A56-C56", &buffer);
}

test "format vertical simple move" {
    const turn: Turn = .{
        .color = .black,
        .action = .{ .move = .{ .vertical = .{
            .from_y = ._2,
            .to_y = ._5,
            .x = .G,
            .block_width = .no_block,
        } } },
    };

    var buffer: [6]u8 = undefined;
    var writer = std.io.Writer.fixed(&buffer);
    _ = try writer.print("{f}", .{turn});
    try std.testing.expectEqualStrings("bG2-G5", &buffer);
}

test "format vertical block move" {
    const turn: Turn = .{
        .color = .white,
        .action = .{ .move = .{ .vertical = .{
            .from_y = ._10,
            .to_y = ._1,
            .x = .D,
            .block_width = ._3,
        } } },
    };

    var buffer: [12]u8 = undefined;
    var writer = std.io.Writer.fixed(&buffer);
    _ = try writer.print("{f}", .{turn});
    try std.testing.expectEqualStrings("w▢DF10-DF1", &buffer);
}

test "format diagonal move 1" {
    const turn: Turn = .{
        .color = .black,
        .action = .{ .move = .{ .diagonal = .{
            .from = .bottom_left,
            .distance = 4,
        } } },
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
        .color = .black,
        .action = .{ .move = .{ .vertical = .{
            .from_y = ._1,
            .to_y = ._10,
            .x = .E,
            .block_width = ._2,
        } } },
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
        .color = .white,
        .action = .{ .move = .{ .horizontal = .{
            .from_x = .D,
            .to_x = .J,
            .y = ._8,
            .block_height = ._3,
        } } },
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

test "parse placement" {
    var input = std.io.Reader.fixed("wA5");
    const turn = try parseTurn(&input, null);
    const expected: Turn = .{
        .color = .white,
        .action = .{ .place = .{ .A, ._5 } },
    };

    try std.testing.expectEqualDeep(expected, turn);
}

test "parse placement with no color prefix" {
    var input = std.io.Reader.fixed("F1");
    const turn = try parseTurn(&input, .black);
    const expected: Turn = .{
        .color = .black,
        .action = .{ .place = .{ .F, ._1 } },
    };

    try std.testing.expectEqualDeep(expected, turn);
}

test "parse placement with quality comment" {
    var input = std.io.Reader.fixed("bJ10(!!)");
    const turn = try parseTurn(&input, null);
    const expected: Turn = .{
        .color = .black,
        .action = .{ .place = .{ .J, ._10 } },
        .quality = .very_good,
    };

    try std.testing.expectEqualDeep(expected, turn);
}

test "parse horizontal simple move" {
    var input = std.io.Reader.fixed("bH4-B4");
    const turn = try parseTurn(&input, null);
    const expected: Turn = .{
        .color = .black,
        .action = .{ .move = .{ .horizontal = .{
            .from_x = .H,
            .to_x = .B,
            .y = ._4,
            .block_height = .no_block,
        } } },
    };

    try std.testing.expectEqualDeep(expected, turn);
}

test "parse horizontal block move" {
    var input = std.io.Reader.fixed("w▢D56-G56");
    const turn = try parseTurn(&input, null);
    const expected: Turn = .{
        .color = .white,
        .action = .{ .move = .{ .horizontal = .{
            .from_x = .D,
            .to_x = .G,
            .y = ._5,
            .block_height = ._2,
        } } },
    };

    try std.testing.expectEqualDeep(expected, turn);
}

test "parse vertical simple move" {
    var input = std.io.Reader.fixed("wC2-C5");
    const turn = try parseTurn(&input, null);
    const expected: Turn = .{
        .color = .white,
        .action = .{ .move = .{ .vertical = .{
            .from_y = ._2,
            .to_y = ._5,
            .x = .C,
            .block_width = .no_block,
        } } },
    };

    try std.testing.expectEqualDeep(expected, turn);
}

test "parse vertical block move" {
    var input = std.io.Reader.fixed("b▢EF10-EF1");
    const turn = try parseTurn(&input, null);
    const expected: Turn = .{
        .color = .black,
        .action = .{ .move = .{ .vertical = .{
            .from_y = ._10,
            .to_y = ._1,
            .x = .E,
            .block_width = ._2,
        } } },
    };

    try std.testing.expectEqualDeep(expected, turn);
}

test "parse diagonal move 1" {
    var input = std.io.Reader.fixed("wA1-E5");
    const turn = try parseTurn(&input, null);
    const expected: Turn = .{
        .color = .white,
        .action = .{ .move = .{ .diagonal = .{
            .from = .bottom_left,
            .distance = 4,
        } } },
    };

    try std.testing.expectEqualDeep(expected, turn);
}

test "parse diagonal move 2" {
    var input = std.io.Reader.fixed("bJ10-G7");
    const turn = try parseTurn(&input, null);
    const expected: Turn = .{
        .color = .black,
        .action = .{ .move = .{ .diagonal = .{
            .from = .top_right,
            .distance = 3,
        } } },
    };

    try std.testing.expectEqualDeep(expected, turn);
}

test "parse diagonal move 3" {
    var input = std.io.Reader.fixed("wA10-F5");
    const turn = try parseTurn(&input, null);
    const expected: Turn = .{
        .color = .white,
        .action = .{ .move = .{ .diagonal = .{
            .from = .top_left,
            .distance = 5,
        } } },
    };

    try std.testing.expectEqualDeep(expected, turn);
}

test "parse diagonal move 4" {
    var input = std.io.Reader.fixed("bJ1-A10");
    const turn = try parseTurn(&input, null);
    const expected: Turn = .{
        .color = .black,
        .action = .{ .move = .{ .diagonal = .{
            .from = .bottom_right,
            .distance = 9,
        } } },
    };

    try std.testing.expectEqualDeep(expected, turn);
}

test "parse full move with comments" {
    var input = std.io.Reader.fixed("b▢EF1-EF10x(>)(!?)");
    const turn = try parseTurn(&input, null);
    const expected: Turn = .{
        .color = .black,
        .action = .{ .move = .{ .vertical = .{
            .from_y = ._1,
            .to_y = ._10,
            .x = .E,
            .block_width = ._2,
        } } },
        .special_action = .gold_removed,
        .quality = .interesting,
        .winning = .job_in_one,
    };

    try std.testing.expectEqualDeep(expected, turn);
}

test "parse move only with quality comment" {
    var input = std.io.Reader.fixed("wA1-A2(!!)");
    const turn = try parseTurn(&input, null);
    const expected: Turn = .{
        .color = .white,
        .action = .{ .move = .{ .vertical = .{
            .from_y = ._1,
            .to_y = ._2,
            .x = .A,
            .block_width = .no_block,
        } } },
        .quality = .very_good,
    };

    try std.testing.expectEqualDeep(expected, turn);
}

test "parse move only with special action comment" {
    var input = std.io.Reader.fixed("bJ10-J9(>)");
    const turn = try parseTurn(&input, null);
    const expected: Turn = .{
        .color = .black,
        .action = .{ .move = .{ .vertical = .{
            .from_y = ._10,
            .to_y = ._9,
            .x = .J,
            .block_width = .no_block,
        } } },
        .special_action = .gold_removed,
    };

    try std.testing.expectEqualDeep(expected, turn);
}

test "parse move only with winning comment" {
    var input = std.io.Reader.fixed("wC3-C4x");
    const turn = try parseTurn(&input, null);
    const expected: Turn = .{
        .color = .white,
        .action = .{ .move = .{ .vertical = .{
            .from_y = ._3,
            .to_y = ._4,
            .x = .C,
            .block_width = .no_block,
        } } },
        .winning = .job_in_one,
    };

    try std.testing.expectEqualDeep(expected, turn);
}

test "parse move with maximum string length" {
    var input = std.io.Reader.fixed("w▢D810-J810xx(>)(!!)");
    const turn = try parseTurn(&input, null);
    const expected: Turn = .{
        .color = .white,
        .action = .{ .move = .{ .horizontal = .{
            .from_x = .D,
            .to_x = .J,
            .y = ._8,
            .block_height = ._3,
        } } },
        .special_action = .gold_removed,
        .quality = .very_good,
        .winning = .win,
    };

    try std.testing.expectEqualDeep(expected, turn);
}

const std = @import("std");
const state = @import("state.zig");
const constants = @import("constants.zig");
const Player = state.Player;
const column_letters = constants.column_letters;
const max_turn_str_len = 24;

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
const DiagonalMove = struct { from: Corner, distance: u4 };

const HorizontalMove = struct {
    from_x: u4,
    to_x: u4,
    y: u4,
    block_height: u2, // 0 means no block (i.e. height of 1), 1 means block of height 2, etc.

    fn is_block(self: @This()) bool {
        return self.block_height > 0;
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
};

const Move = union(enum) {
    diagonal: DiagonalMove,
    horizontal: HorizontalMove,
    vertical: VerticalMove,
};

const Turn = struct {
    by: Player,
    move: Move,
    special_action: ?SpecialAction = null,
    quality: ?CommentQuality = null,
    winning: ?CommentWinning = null,
};

fn format_turn(turn: Turn) ![max_turn_str_len]u8 {
    var buffer = [1]u8{0} ** max_turn_str_len;
    var fbs = std.io.fixedBufferStream(&buffer);
    var writer = fbs.writer();

    // Write player color
    _ = try writer.write(switch (turn.by) {
        .white => "w",
        .black => "b",
    });

    // Write move
    switch (turn.move) {
        .diagonal => |d| {
            const start_x: u4 = switch (d.from) {
                .bottom_left => 1,
                .bottom_right => 10,
                .top_left => 1,
                .top_right => 10,
            };
            const start_y: u4 = switch (d.from) {
                .bottom_left => 1,
                .bottom_right => 1,
                .top_left => 10,
                .top_right => 10,
            };
            const end_x: u4 = switch (d.from) {
                .bottom_left => start_x + d.distance,
                .bottom_right => start_x - d.distance,
                .top_left => start_x + d.distance,
                .top_right => start_x - d.distance,
            };
            const end_y: u4 = switch (d.from) {
                .bottom_left => start_y + d.distance,
                .bottom_right => start_y + d.distance,
                .top_left => start_y - d.distance,
                .top_right => start_y - d.distance,
            };
            const start_x_str = column_letters[start_x - 1];
            const end_e_x_str = column_letters[end_x - 1];
            _ = try writer.print("{c}{}-{c}{}", .{ start_x_str, start_y, end_e_x_str, end_y });
        },
        .horizontal => |h| {
            const start_x = column_letters[h.from_x];
            const end_x = column_letters[h.to_x];
            const start_y: u4 = h.y + 1;
            if (h.is_block()) {
                const block_y = start_y + h.block_height;
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
        },
        .vertical => |v| {
            const start_x = column_letters[v.x];
            const start_y: u4 = v.from_y + 1;
            const end_y: u4 = v.to_y + 1;
            if (v.is_block()) {
                const block_x = column_letters[v.x + v.block_width];
                _ = try writer.print("▢{c}{c}{}-{c}{c}{}", .{
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
        },
    }

    // Write comment for winning state
    if (turn.winning) |winning| {
        _ = try writer.write(switch (winning) {
            .job_in_one => "x",
            .win => "xx",
        });
    }

    // Write special action
    if (turn.special_action) |special_action| {
        _ = try writer.write(switch (special_action) {
            .gold_removed => "(>)",
            .worm => "(w)",
        });
    }
    // Write comment for quality
    if (turn.quality) |quality| {
        _ = try writer.write(switch (quality) {
            .very_good => "(!!)",
            .good => "(!)",
            .interesting => "(!?)",
            .bad => "(?)",
            .very_bad => "(??)",
        });
    }

    return buffer;
}

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

    const formatted = try format_turn(turn);
    try std.testing.expectEqualStrings("bF4-C4", formatted[0..6]);
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

    const formatted = try format_turn(turn);
    try std.testing.expectEqualStrings("w▢A56-C56", formatted[0..11]);
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

    const formatted = try format_turn(turn);
    try std.testing.expectEqualStrings("bG2-G5", formatted[0..6]);
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

    const formatted = try format_turn(turn);
    try std.testing.expectEqualStrings("w▢DF10-DF1", formatted[0..12]);
}

test "format diagonal move 1" {
    const turn: Turn = .{
        .by = .black,
        .move = .{ .diagonal = .{
            .from = .bottom_left,
            .distance = 4,
        } },
    };

    const formatted = try format_turn(turn);
    try std.testing.expectEqualStrings("bA1-E5", formatted[0..6]);
}

test "format diagonal move 2" {
    const turn: Turn = .{
        .by = .white,
        .move = .{ .diagonal = .{
            .from = .top_right,
            .distance = 3,
        } },
    };

    const formatted = try format_turn(turn);
    try std.testing.expectEqualStrings("wJ10-G7", formatted[0..7]);
}

test "format diagonal move 3" {
    const turn: Turn = .{
        .by = .black,
        .move = .{ .diagonal = .{
            .from = .top_left,
            .distance = 5,
        } },
    };

    const formatted = try format_turn(turn);
    try std.testing.expectEqualStrings("bA10-F5", formatted[0..7]);
}

test "format diagonal move 4" {
    const turn: Turn = .{
        .by = .white,
        .move = .{ .diagonal = .{
            .from = .bottom_right,
            .distance = 9,
        } },
    };

    const formatted = try format_turn(turn);
    try std.testing.expectEqualStrings("wJ1-A10", formatted[0..7]);
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

    const formatted = try format_turn(turn);
    try std.testing.expectEqualStrings("b▢EF1-EF10x(>)(!?)", formatted[0..20]);
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

    const formatted = try format_turn(turn);
    try std.testing.expectEqualStrings("w▢D810-J810xx(>)(!!)", formatted[0..22]);
}

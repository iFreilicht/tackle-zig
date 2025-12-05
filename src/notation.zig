const std = @import("std");
const state = @import("state.zig");
const constants = @import("constants.zig");
const Player = state.Player;
const column_letters = constants.column_letters;
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
    special_action: ?SpecialAction = null,
    quality: ?CommentQuality = null,
    winning: ?CommentWinning = null,

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

    var buffer: [max_turn_str_len]u8 = undefined;
    var writer = std.io.Writer.fixed(&buffer);
    _ = try writer.print("{f}", .{turn});
    try std.testing.expectEqualStrings("w▢D810-J810xx(>)(!!)", &buffer);
    try std.testing.expectEqual(max_turn_str_len, buffer.len);
}

const std = @import("std");

const tackle = @import("root.zig");

const column_letters = tackle.constants.column_letters;
const Direction = tackle.enums.Direction;

pub const Corner = enum {
    bottom_left, // A1
    bottom_right, // J1
    top_left, // A10
    top_right, // J10

    /// Return the Position of this corner on the board.
    pub fn toPosition(self: @This()) Position {
        return switch (self) {
            .bottom_left => .{ .A, ._1 },
            .bottom_right => .{ .J, ._1 },
            .top_left => .{ .A, ._10 },
            .top_right => .{ .J, ._10 },
        };
    }

    /// Return a List of all Positions along the diagonal from this corner
    /// to the opposite corner, excluding this corner itself.
    /// Pretty naive way of implementing iteration, but it's fine for now.
    pub fn toList(self: @This()) [9]Position {
        return switch (self) {
            .bottom_left => .{
                .{ .B, ._2 },
                .{ .C, ._3 },
                .{ .D, ._4 },
                .{ .E, ._5 },
                .{ .F, ._6 },
                .{ .G, ._7 },
                .{ .H, ._8 },
                .{ .I, ._9 },
                .{ .J, ._10 },
            },
            .bottom_right => .{
                .{ .I, ._2 },
                .{ .H, ._3 },
                .{ .G, ._4 },
                .{ .F, ._5 },
                .{ .E, ._6 },
                .{ .D, ._7 },
                .{ .C, ._8 },
                .{ .B, ._9 },
                .{ .A, ._10 },
            },
            .top_left => .{
                .{ .B, ._9 },
                .{ .C, ._8 },
                .{ .D, ._7 },
                .{ .E, ._6 },
                .{ .F, ._5 },
                .{ .G, ._4 },
                .{ .H, ._3 },
                .{ .I, ._2 },
                .{ .J, ._1 },
            },
            .top_right => .{
                .{ .I, ._9 },
                .{ .H, ._8 },
                .{ .G, ._7 },
                .{ .F, ._6 },
                .{ .E, ._5 },
                .{ .D, ._4 },
                .{ .C, ._3 },
                .{ .B, ._2 },
                .{ .A, ._1 },
            },
        };
    }
};

/// A row on the board, identified by its Y coordinate (1-10, 0 is not a valid value!)
/// Rows are labeled 1-10.
pub const RowY = enum(u4) {
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

    pub fn index(self: @This()) u4 {
        const i = @intFromEnum(self);
        return i - 1;
    }

    pub fn fromIndex(idx: u4) @This() {
        return @enumFromInt(idx + 1);
    }

    pub fn plus(self: @This(), block_size: u4) @This() {
        return @enumFromInt(@intFromEnum(self) + block_size);
    }

    pub fn minus(self: @This(), block_size: u4) @This() {
        return @enumFromInt(@intFromEnum(self) - block_size);
    }

    pub fn min(self: @This(), other: @This()) @This() {
        return if (@intFromEnum(self) < @intFromEnum(other)) self else other;
    }

    pub fn max(self: @This(), other: @This()) @This() {
        return if (@intFromEnum(self) > @intFromEnum(other)) self else other;
    }

    pub fn distance(self: @This(), other: @This()) u4 {
        const s = @intFromEnum(self);
        const o = @intFromEnum(other);
        return if (s > o) s - o else o - s;
    }

    pub fn format(self: @This(), writer: *std.io.Writer) std.io.Writer.Error!void {
        switch (self) {
            ._10 => _ = try writer.write("10"),
            else => {
                const d: u8 = @intFromEnum(self);
                _ = try writer.writeByte(@as(u8, '0' + d));
            },
        }
    }

    pub fn parse(reader: *std.io.Reader) !@This() {
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

pub fn getBlockHeight(first: RowY, last: RowY) BlockSize {
    return @enumFromInt(@intFromEnum(last) - @intFromEnum(first));
}

/// A column on the board, identified by its X coordinate (1-10, 0 is not a valid value!)
/// Columns are labeled A-J, see also the `column_letters` constant.
pub const ColumnX = enum(u4) {
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

    pub fn index(self: @This()) u4 {
        const i = @intFromEnum(self);
        return i - 1;
    }

    pub fn fromIndex(idx: u4) @This() {
        return @enumFromInt(idx + 1);
    }

    pub fn plus(self: @This(), block_size: u4) @This() {
        return @enumFromInt(@intFromEnum(self) + block_size);
    }

    pub fn minus(self: @This(), block_size: u4) @This() {
        return @enumFromInt(@intFromEnum(self) - block_size);
    }

    pub fn min(self: @This(), other: @This()) @This() {
        return if (@intFromEnum(self) < @intFromEnum(other)) self else other;
    }

    pub fn max(self: @This(), other: @This()) @This() {
        return if (@intFromEnum(self) > @intFromEnum(other)) self else other;
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

    pub fn parse(reader: *std.io.Reader) !@This() {
        const c = try reader.peek(1);
        const col = std.mem.indexOf(u8, &column_letters, c) orelse return error.ColumnInvalid;
        reader.toss(1);
        return @enumFromInt(col + 1);
    }
};

pub fn getBlockWidth(first: ColumnX, last: ColumnX) BlockSize {
    return @enumFromInt(@intFromEnum(last) - @intFromEnum(first));
}

/// Return true if the given square is on the border of the board.
/// Pieces can only be placed on the border during the opening phase.
pub fn isOnBorder(position: Position) bool {
    const col, const row = position;
    return col == .A or col == .J or row == ._1 or row == ._10;
}

/// Return true if the given square is in the court, i.e. not on the border.
/// All pieces of a job must be in the court for the job to be completed.
/// Once all pieces of a player are in the court, the gold piece is removed.
pub fn isInCourt(position: Position) bool {
    return !isOnBorder(position);
}

/// Return true if the given square is in the core, i.e. the centermost 16 squares.
/// The gold piece can only be placed in the core.
pub fn isInCore(position: Position) bool {
    const col, const row = position;
    const col_int = @intFromEnum(col);
    const col_in_core = (col_int >= @intFromEnum(ColumnX.D)) and (col_int <= @intFromEnum(ColumnX.G));
    const row_int = @intFromEnum(row);
    const row_in_core = (row_int >= @intFromEnum(RowY._4)) and (row_int <= @intFromEnum(RowY._7));
    return col_in_core and row_in_core;
}

/// Size of a block perpendicular to the move direction (2-4, 0 means no block)
/// Blocks can easily be longer than 4 in the move direction, but this is not represented
/// in the notation anyway. 4 is the maximum because for a block of 5 to move perpendicularly
/// to the side that is 5 units wide, the block would have to contain 25 pieces.
/// However, a maximum of 18 pieces can be placed per player, so a block of 5 is impossible.
/// A block of 4 is also unlikely to happen in regular play, but still possible in theory.
pub const BlockSize = enum(u2) {
    no_block = 0,
    _2 = 1,
    _3 = 2,
    _4 = 3,

    /// Return the number of pieces this block size represents.
    pub fn numPieces(self: @This()) u4 {
        return @intFromEnum(self) + 1;
    }
};

/// A position on the board, identified by its column and row.
pub const Position = struct { ColumnX, RowY };

/// Move the given position in the given direction by the given distance,
/// if possible (i.e. if it stays within the board boundaries).
/// Return null if the move would go out of bounds.
pub fn movePositionIfPossible(pos: Position, direction: Direction, distance: u4) ?Position {
    if (distance == 0) return pos;
    if (distance > 9) return null; // Maximum distance on 10x10 board is 9
    const col, const row = pos;
    var new_pos: Position = undefined;
    switch (direction) {
        .up => {
            if (@intFromEnum(RowY._10) - distance < @intFromEnum(row)) return null;
            new_pos = .{ col, row.plus(distance) };
        },
        .down => {
            if (@intFromEnum(RowY._1) + distance > @intFromEnum(row)) return null;
            new_pos = .{ col, row.minus(distance) };
        },
        .left => {
            if (@intFromEnum(ColumnX.A) + distance > @intFromEnum(col)) return null;
            new_pos = .{ col.minus(distance), row };
        },
        .right => {
            if (@intFromEnum(ColumnX.J) - distance < @intFromEnum(col)) return null;
            new_pos = .{ col.plus(distance), row };
        },
    }
    return new_pos;
}

/// Move the given position in the given direction by the given distance.
/// Assumes that the move is possible (i.e. stays within the board boundaries),
/// performed checks depend on Zig's build mode.
pub fn movePosition(pos: Position, direction: Direction, distance: u4) Position {
    const col, const row = pos;
    return switch (direction) {
        .up => .{ col, row.plus(distance) },
        .down => .{ col, row.minus(distance) },
        .left => .{ col.minus(distance), row },
        .right => .{ col.plus(distance), row },
    };
}

/// A position represented as two u4 integers for easier calculations.
/// 1-10 for both coordinates, 0 is not a valid value!
pub const IntPosition = struct { u4, u4 };

pub fn intFromPos(pos: Position) IntPosition {
    return .{ @intFromEnum(pos.@"0"), @intFromEnum(pos.@"1") };
}
pub fn posFromInt(int: IntPosition) Position {
    return .{ @enumFromInt(int.@"0"), @enumFromInt(int.@"1") };
}

test movePosition {
    const pos: Position = .{ .D, ._5 };
    try std.testing.expectEqual(.{ .D, ._7 }, movePosition(pos, .up, 2));
    try std.testing.expectEqual(.{ .D, ._3 }, movePosition(pos, .down, 2));
    try std.testing.expectEqual(.{ .B, ._5 }, movePosition(pos, .left, 2));
    try std.testing.expectEqual(.{ .F, ._5 }, movePosition(pos, .right, 2));
}

test movePositionIfPossible {
    const pos: Position = .{ .D, ._8 };
    try std.testing.expectEqual(.{ .D, ._9 }, movePositionIfPossible(pos, .up, 1));
    try std.testing.expectEqual(.{ .D, ._10 }, movePositionIfPossible(pos, .up, 2));
    try std.testing.expectEqual(.{ .D, ._4 }, movePositionIfPossible(pos, .down, 4));
    try std.testing.expectEqual(.{ .D, ._1 }, movePositionIfPossible(pos, .down, 7));
    try std.testing.expectEqual(.{ .B, ._8 }, movePositionIfPossible(pos, .left, 2));
    try std.testing.expectEqual(.{ .A, ._8 }, movePositionIfPossible(pos, .left, 3));
    try std.testing.expectEqual(.{ .I, ._8 }, movePositionIfPossible(pos, .right, 5));
    try std.testing.expectEqual(.{ .J, ._8 }, movePositionIfPossible(pos, .right, 6));
    try std.testing.expect(movePositionIfPossible(pos, .up, 3) == null);
    try std.testing.expect(movePositionIfPossible(pos, .down, 8) == null);
    try std.testing.expect(movePositionIfPossible(pos, .left, 4) == null);
    try std.testing.expect(movePositionIfPossible(pos, .right, 7) == null);

    const pos2: Position = .{ .A, ._1 };
    try std.testing.expectEqual(.{ .A, ._1 }, movePositionIfPossible(pos2, .up, 0));
    try std.testing.expectEqual(.{ .A, ._10 }, movePositionIfPossible(pos2, .up, 9));
    try std.testing.expectEqual(.{ .J, ._1 }, movePositionIfPossible(pos2, .right, 9));

    const pos3: Position = .{ .J, ._10 };
    try std.testing.expectEqual(.{ .J, ._1 }, movePositionIfPossible(pos3, .down, 9));
    try std.testing.expectEqual(.{ .A, ._10 }, movePositionIfPossible(pos3, .left, 9));
}

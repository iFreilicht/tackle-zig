const std = @import("std");

const tackle = @import("root.zig");

const block_sigil = tackle.constants.block_sigil;

const Direction = tackle.enums.Direction;
const Corner = tackle.position.Corner;
const ColumnX = tackle.position.ColumnX;
const RowY = tackle.position.RowY;
const Position = tackle.position.Position;
const BlockSize = tackle.position.BlockSize;

const intFromPos = tackle.position.intFromPos;
const posFromInt = tackle.position.posFromInt;

pub const DiagonalMove = struct {
    from: Corner,
    distance: u4,

    /// Return the starting Position of this diagonal move.
    pub fn start(self: @This()) Position {
        return self.from.toPosition();
    }
    /// Return the ending Position of this diagonal move.
    pub fn end(self: @This()) Position {
        const start_x, const start_y = intFromPos(self.start());
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
        return posFromInt(.{ end_x, end_y });
    }

    pub fn format(self: @This(), writer: *std.io.Writer) std.io.Writer.Error!void {
        const start_x, const start_y = self.start();
        const end_x, const end_y = self.end();
        _ = try writer.print("{f}{f}-{f}{f}", .{ start_x, start_y, end_x, end_y });
    }
};

pub const HorizontalMove = struct {
    from_x: ColumnX,
    to_x: ColumnX,
    y: RowY,
    block_height: BlockSize = .no_block,

    fn isBlock(self: @This()) bool {
        return self.block_height != .no_block;
    }

    pub fn start(self: @This()) Position {
        return .{ self.from_x, self.y };
    }
    pub fn startBlockEnd(self: @This()) Position {
        return .{ self.from_x, self.y.plus(@intFromEnum(self.block_height)) };
    }
    pub fn direction(self: @This()) Direction {
        return if (@intFromEnum(self.from_x) < @intFromEnum(self.to_x)) .right else .left;
    }
    pub fn distance(self: @This()) u4 {
        return self.from_x.distance(self.to_x);
    }
    pub fn blockBreadth(self: @This()) u4 {
        return self.block_height.numPieces();
    }

    pub fn format(self: @This(), writer: *std.io.Writer) std.io.Writer.Error!void {
        const start_x = self.from_x;
        const end_x = self.to_x;
        const start_y = self.y;
        if (self.isBlock()) {
            const block_y = start_y.plus(@intFromEnum(self.block_height));
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

pub const VerticalMove = struct {
    from_y: RowY,
    to_y: RowY,
    x: ColumnX,
    block_width: BlockSize = .no_block,

    fn isBlock(self: @This()) bool {
        return self.block_width != .no_block;
    }

    pub fn start(self: @This()) Position {
        return .{ self.x, self.from_y };
    }
    pub fn startBlockEnd(self: @This()) Position {
        return .{ self.x.plus(@intFromEnum(self.block_width)), self.from_y };
    }
    pub fn direction(self: @This()) Direction {
        return if (@intFromEnum(self.from_y) < @intFromEnum(self.to_y)) .up else .down;
    }
    pub fn distance(self: @This()) u4 {
        return self.from_y.distance(self.to_y);
    }
    pub fn blockBreadth(self: @This()) u4 {
        return self.block_width.numPieces();
    }

    pub fn format(self: @This(), writer: *std.io.Writer) std.io.Writer.Error!void {
        const start_x = self.x;
        const start_y = self.from_y;
        const end_y = self.to_y;
        if (self.isBlock()) {
            const block_x = start_x.plus(@intFromEnum(self.block_width));
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

pub const Move = union(enum) {
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

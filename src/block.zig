const std = @import("std");

const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

const enums = @import("enums.zig");
const position = @import("position.zig");

const Direction = enums.Direction;
const Position = position.Position;

pub const Block = struct {
    lower_left_corner: Position,
    /// Width in columns. 0 is not a valid value!
    width: u4,
    /// Height in rows. 0 is not a valid value!
    height: u4,

    pub fn init(corner1: Position, corner2: Position) Block {
        const min_col = corner1.@"0".min(corner2.@"0");
        const max_col = corner1.@"0".max(corner2.@"0");
        const min_row = corner1.@"1".min(corner2.@"1");
        const max_row = corner1.@"1".max(corner2.@"1");

        return Block{
            .lower_left_corner = Position{ min_col, min_row },
            .width = @intFromEnum(max_col) - @intFromEnum(min_col) + 1,
            .height = @intFromEnum(max_row) - @intFromEnum(min_row) + 1,
        };
    }

    /// Return a list of all positions covered by this block, in column-major order,
    /// ordered from the front of the block to the back. The front is defined as the
    /// side which the block is moving towards.
    /// This does not check whether the block is actually allowed to move in that direction!
    pub fn toList(self: Block, buffer: []Position, direction: Direction) []Position {
        var index: usize = 0;

        for (0..self.width) |dx| {
            for (0..self.height) |dy| {
                var dx_corrected = dx;
                var dy_corrected = dy;
                switch (direction) {
                    // When moving down, the front is the bottom side, so we order row from bottom
                    // to top. Nothing to do in that case, that is the default iteration order.
                    .down => {},
                    // When moving up, the front is the top side, so we order rows from top to bottom.
                    // The order of the columns is irrelevant.
                    .up => {
                        dy_corrected = self.height - dy - 1;
                    },
                    // When moving left, the front is the left side, so we order columns from left
                    // to right. Nothing to do in that case, that is the default iteration order.
                    .left => {},
                    // When moving right, the front is the right side, so we order columns from right
                    // to left. The order of the rows is irrelevant.
                    .right => {
                        dx_corrected = self.width - dx - 1;
                    },
                }
                buffer[index] = Position{
                    @enumFromInt(@intFromEnum(self.lower_left_corner.@"0") + dx_corrected),
                    @enumFromInt(@intFromEnum(self.lower_left_corner.@"1") + dy_corrected),
                };
                index += 1;
            }
        }

        return buffer[0..index];
    }
};

test "block init" {
    const block = Block.init(.{ .C, ._7 }, .{ .D, ._4 });
    try expectEqual(.{ .C, ._4 }, block.lower_left_corner);
    try expectEqual(2, block.width);
    try expectEqual(4, block.height);

    const block2 = Block.init(.{ .H, ._2 }, .{ .F, ._5 });
    try expectEqual(.{ .F, ._2 }, block2.lower_left_corner);
    try expectEqual(3, block2.width);
    try expectEqual(4, block2.height);

    const block3 = Block.init(.{ .A, ._1 }, .{ .A, ._2 });
    try expectEqual(.{ .A, ._1 }, block3.lower_left_corner);
    try expectEqual(1, block3.width);
    try expectEqual(2, block3.height);
}

test "block toList" {
    const block = Block.init(.{ .B, ._2 }, .{ .D, ._4 });
    var buffer: [9]Position = undefined;
    const positions = block.toList(&buffer, .up);
    const expected: [9]Position = .{
        .{ .B, ._4 },
        .{ .B, ._3 },
        .{ .B, ._2 },
        .{ .C, ._4 },
        .{ .C, ._3 },
        .{ .C, ._2 },
        .{ .D, ._4 },
        .{ .D, ._3 },
        .{ .D, ._2 },
    };
    try expectEqualSlices(Position, &expected, positions);

    const positions2 = block.toList(&buffer, .right);
    const expected2: [9]Position = .{
        .{ .D, ._2 },
        .{ .D, ._3 },
        .{ .D, ._4 },
        .{ .C, ._2 },
        .{ .C, ._3 },
        .{ .C, ._4 },
        .{ .B, ._2 },
        .{ .B, ._3 },
        .{ .B, ._4 },
    };
    try expectEqualSlices(Position, &expected2, positions2);

    const positions3 = block.toList(&buffer, .down);
    const expected3: [9]Position = .{
        .{ .B, ._2 },
        .{ .B, ._3 },
        .{ .B, ._4 },
        .{ .C, ._2 },
        .{ .C, ._3 },
        .{ .C, ._4 },
        .{ .D, ._2 },
        .{ .D, ._3 },
        .{ .D, ._4 },
    };
    try expectEqualSlices(Position, &expected3, positions3);

    const positions4 = block.toList(&buffer, .left);
    const expected4: [9]Position = .{
        .{ .B, ._2 },
        .{ .B, ._3 },
        .{ .B, ._4 },
        .{ .C, ._2 },
        .{ .C, ._3 },
        .{ .C, ._4 },
        .{ .D, ._2 },
        .{ .D, ._3 },
        .{ .D, ._4 },
    };
    try expectEqualSlices(Position, &expected4, positions4);
}

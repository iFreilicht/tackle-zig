const std = @import("std");

const expectEqual = std.testing.expectEqual;

const constants = @import("constants.zig");
const board_module = @import("board.zig");
const enums = @import("enums.zig");
const position = @import("position.zig");
const text_renderer = @import("text_renderer.zig");

const max_job_size = constants.max_job_size;
const Board = board_module.Board;
const SquareContent = enums.SquareContent;
const Player = enums.Player;
const PieceColor = enums.PieceColor;
const Position = position.Position;
const pos_from_int = position.pos_from_int;

/// Requirement that a square must fulfill for a job to be considered complete.
pub const JobRequirement = enum {
    /// The square must contain a piece of the player color
    piece,
    /// The square must NOT contain a piece of the player color
    other,
    /// The square may be empty or contain a piece of any color
    any,
};

/// Number of different rotations that need to be tested.
/// Can be 1, 2, or 4 depending on the rotational symmetry of the job.
pub const RotationCount = enum(u2) {
    one = 0,
    two = 1,
    four = 3,

    pub fn to_rotations(self: @This()) usize {
        return @as(usize, @intFromEnum(self)) + 1;
    }
};
pub const Job = struct {
    /// Width of the job in squares
    /// This and `height` define how `requirements` is interpreted.
    /// The maximum is 8, because that's the size of the court, and a job is only
    /// considered done if all pieces are within the court.
    width: u3,
    /// Height of the job in squares
    height: u3,
    /// Requirements for each square in the job in column-major order
    /// Unforunately, this array needs to cover every square of the court so a
    /// job like treppe8 can be represented, even though most jobs will only
    /// use a small portion of it.
    requirements: [max_job_size * max_job_size]JobRequirement,
    total_pieces: u4, // Maximum of 16 pieces, see also `max_pieces_per_player`
    rotation_count: RotationCount,

    pub fn init(
        width: u3,
        height: u3,
        requirements: []const JobRequirement,
    ) Job {
        std.debug.assert(width > 0);
        std.debug.assert(height > 0);

        const total_pieces: u4 = @intCast(std.mem.count(JobRequirement, requirements, &.{.piece}));
        std.debug.assert(total_pieces > 0);

        const unique_rotations: RotationCount = if (is_symmetric_90(
            width,
            height,
            requirements,
        ))
            .one
        else if (is_symmetric_180(
            width,
            height,
            requirements,
        ))
            .two
        else
            .four;

        var job = Job{
            .width = width,
            .height = height,
            .requirements = .{.any} ** (max_job_size * max_job_size),
            .total_pieces = total_pieces,
            .rotation_count = unique_rotations,
        };
        std.mem.copyForwards(JobRequirement, job.requirements[0..requirements.len], requirements);

        return job;
    }

    /// Check if rotating 90° gives the same pattern
    fn is_symmetric_90(width: u3, height: u3, requirements: []const JobRequirement) bool {
        // 90° rotation only makes sense if width == height (square pattern)
        if (width != height) return false;

        // When rotating 90° clockwise: (x, y) -> (y, width - 1 - x)
        for (0..width) |x| {
            for (0..height) |y| {
                if (requirements[x * height + y] !=
                    requirements[y * height + (width - 1 - x)])
                    return false;
            }
        }
        return true;
    }

    /// Check if rotating 180° gives the same pattern
    fn is_symmetric_180(width: u3, height: u3, requirements: []const JobRequirement) bool {
        for (0..width) |x| {
            for (0..height) |y| {
                if (requirements[x * height + y] !=
                    requirements[(width - 1 - x) * height + (height - 1 - y)])
                    return false;
            }
        }
        return true;
    }

    pub fn turm3() Job {
        return init(1, 3, &.{
            .piece, .piece, .piece,
        });
    }

    pub fn treppe3() Job {
        return init(3, 3, &.{
            .any,   .any,   .piece,
            .any,   .piece, .any,
            .piece, .any,   .any,
        });
    }

    pub fn turm4() Job {
        return init(1, 4, &.{
            .piece, .piece, .piece, .piece,
        });
    }

    pub fn treppe4() Job {
        return init(4, 4, &.{
            .any,   .any,   .any,   .piece,
            .any,   .any,   .piece, .any,
            .any,   .piece, .any,   .any,
            .piece, .any,   .any,   .any,
        });
    }

    pub fn quadrat() Job {
        return init(2, 2, &.{
            .piece, .piece, .piece, .piece,
        });
    }

    pub fn bluete() Job {
        return init(3, 3, &.{
            .any,   .piece, .any,
            .piece, .other, .piece,
            .any,   .piece, .any,
        });
    }

    pub fn fisch() Job {
        return init(3, 3, &.{
            .any,   .piece, .piece,
            .any,   .piece, .piece,
            .piece, .any,   .any,
        });
    }

    pub fn kreuz() Job {
        return init(3, 4, &.{
            .any,   .piece, .any,
            .piece, .piece, .piece,
            .any,   .piece, .any,
            .any,   .piece, .any,
        });
    }

    pub fn vogel() Job {
        return init(4, 4, &.{
            .any,   .any,   .any,   .piece,
            .any,   .piece, .piece, .any,
            .any,   .piece, .piece, .any,
            .piece, .any,   .any,   .any,
        });
    }

    pub fn is_fulfilled(self: Job, board: Board, player: Player) bool {
        const player_color = SquareContent.from_player(player);
        const rotations_to_check = self.rotation_count.to_rotations();

        for (0..rotations_to_check) |rotation| {
            // Get dimensions for this rotation
            // 0° and 180°: use original width/height
            // 90° and 270°: swap width/height
            const rotated_width = if (rotation % 2 == 0) self.width else self.height;
            const rotated_height = if (rotation % 2 == 0) self.height else self.width;

            const board_x_end: u4 = 9 - @as(u4, rotated_width) + 2;
            const board_y_end: u4 = 9 - @as(u4, rotated_height) + 2;

            // Scan all possible positions on the board where the job could fit.
            // Iteration is done line-by-line from bottom-left to top-right because
            // this is the counting order of positions.
            for (2..board_y_end) |board_y| {
                for (2..board_x_end) |board_x| potential_position: {
                    // Scan all squares of the job at this position. We also iterate
                    // from bottom-left to top-right here for consistency.
                    // This means the job is checked upside-down, but as we check
                    // all rotations anyway, this doesn't matter in practice.
                    for (0..self.height) |job_y| {
                        for (0..self.width) |job_x| {
                            const req = self.requirements[job_x + job_y * self.width];

                            // Map job coordinates to board coordinates based on rotation
                            const offset_x, const offset_y = rotate_coords(
                                job_x,
                                job_y,
                                @intCast(rotation),
                                self.width,
                                self.height,
                            );

                            const pos = pos_from_int(.{ @intCast(board_x + offset_x), @intCast(board_y + offset_y) });
                            const content = board.get_square(pos);

                            switch (req) {
                                .piece => if (content != player_color) break :potential_position,
                                .other => if (content == player_color) break :potential_position,
                                .any => {},
                            }
                        }
                    }
                    return true;
                }
            }
        }
        return false;
    }

    /// Map job coordinates to rotated board offset coordinates
    /// rotation: 0 = 0°, 1 = 90°, 2 = 180°, 3 = 270°
    fn rotate_coords(x: usize, y: usize, rotation: u2, orig_width: u3, orig_height: u3) struct { usize, usize } {
        return switch (rotation) {
            0 => .{ x, y }, // 0°: no change
            1 => .{ y, orig_width - 1 - x }, // 90° clockwise
            2 => .{ orig_width - 1 - x, orig_height - 1 - y }, // 180°
            3 => .{ orig_height - 1 - y, x }, // 270° clockwise
        };
    }
};

test "Job.init detects correct rotation counts" {
    const quadrat = Job.quadrat();
    try expectEqual(.one, quadrat.rotation_count);

    const turm3 = Job.turm3();
    try expectEqual(.two, turm3.rotation_count);

    const fisch = Job.fisch();
    try expectEqual(.four, fisch.rotation_count);

    const kreuz = Job.kreuz();
    try expectEqual(.four, kreuz.rotation_count);

    const vogel = Job.vogel();
    try expectEqual(.two, vogel.rotation_count);
}

test "is_fulfilled detects turm3 in lower left corner" {
    var board = Board{};
    try board.place_piece(.black, .{ .B, ._4 });
    try board.place_piece(.black, .{ .B, ._3 });
    try board.place_piece(.black, .{ .B, ._2 });

    const job = Job.turm3();
    try expectEqual(true, job.is_fulfilled(board, .black));
}

test "is_fulfilled detects treppe3 in center" {
    var board = Board{};
    try board.place_piece(.white, .{ .E, ._5 });
    try board.place_piece(.white, .{ .F, ._4 });
    try board.place_piece(.white, .{ .G, ._3 });

    const job = Job.treppe3();
    try expectEqual(true, job.is_fulfilled(board, .white));
}

test "is_fulfilled detects turm3 in upper right corner" {
    var board = Board{};
    try board.place_piece(.black, .{ .I, ._9 });
    try board.place_piece(.black, .{ .I, ._8 });
    try board.place_piece(.black, .{ .I, ._7 });

    const job = Job.turm3();
    try expectEqual(true, job.is_fulfilled(board, .black));
}

test "is_fulfilled detects turm3 in rotated position in lower left corner" {
    var board = Board{};
    try board.place_piece(.black, .{ .B, ._2 });
    try board.place_piece(.black, .{ .C, ._2 });
    try board.place_piece(.black, .{ .D, ._2 });

    const job = Job.turm3();
    try expectEqual(true, job.is_fulfilled(board, .black));
}

test "is_fulfilled detects treppe3 in rotated position in center" {
    var board = Board{};
    try board.place_piece(.white, .{ .F, ._5 });
    try board.place_piece(.white, .{ .E, ._4 });
    try board.place_piece(.white, .{ .D, ._3 });

    const job = Job.treppe3();
    try expectEqual(true, job.is_fulfilled(board, .white));
}

test "is_fulfilled detects turm3 in rotated position in upper right corner" {
    var board = Board{};
    try board.place_piece(.black, .{ .I, ._9 });
    try board.place_piece(.black, .{ .H, ._9 });
    try board.place_piece(.black, .{ .G, ._9 });

    const job = Job.turm3();
    try expectEqual(true, job.is_fulfilled(board, .black));
}

test "is_fulfilled returns false when job not fulfilled" {
    var board = Board{};
    try board.place_piece(.white, .{ .E, ._5 });
    try board.place_piece(.white, .{ .F, ._5 });
    // Missing third piece for turm3

    const job = Job.turm3();
    try expectEqual(false, job.is_fulfilled(board, .white));
}

test "is_fulfilled detects bluete job" {
    var board = Board{};
    try board.place_piece(.white, .{ .E, ._5 });
    try board.place_piece(.white, .{ .D, ._4 });
    try board.place_piece(.white, .{ .F, ._4 });
    try board.place_piece(.white, .{ .E, ._3 });

    const job = Job.bluete();
    try expectEqual(true, job.is_fulfilled(board, .white));
}

test "job_is_fullfilled detects bluete job when center contains opponent piece" {
    var board = Board{};
    try board.place_piece(.white, .{ .E, ._5 });
    try board.place_piece(.white, .{ .D, ._4 });
    try board.place_piece(.black, .{ .E, ._4 }); // Opponent piece in center
    try board.place_piece(.white, .{ .F, ._4 });
    try board.place_piece(.white, .{ .E, ._3 });

    const job = Job.bluete();
    try expectEqual(true, job.is_fulfilled(board, .white));
}

test "is_fulfilled returns false when center of bluete is filled" {
    var board = Board{};
    try board.place_piece(.white, .{ .E, ._5 });
    try board.place_piece(.white, .{ .D, ._4 });
    try board.place_piece(.white, .{ .E, ._4 }); // Wrong: center should be empty
    try board.place_piece(.white, .{ .F, ._4 });
    try board.place_piece(.white, .{ .E, ._3 });

    const job = Job.bluete();
    try expectEqual(false, job.is_fulfilled(board, .white));
}

test "is_fulfilled detects kreuz job rotated 0 degrees" {
    var board = Board{};
    try board.place_piece(.black, .{ .C, ._5 });
    try board.place_piece(.black, .{ .B, ._4 });
    try board.place_piece(.black, .{ .C, ._4 });
    try board.place_piece(.black, .{ .D, ._4 });
    try board.place_piece(.black, .{ .C, ._3 });
    try board.place_piece(.black, .{ .C, ._2 });

    const job = Job.kreuz();
    try expectEqual(true, job.is_fulfilled(board, .black));
}

test "is_fulfilled detects kreuz job rotated 90 degrees" {
    var board = Board{};
    try board.place_piece(.black, .{ .B, ._8 });
    try board.place_piece(.black, .{ .C, ._8 });
    try board.place_piece(.black, .{ .D, ._7 });
    try board.place_piece(.black, .{ .D, ._8 });
    try board.place_piece(.black, .{ .D, ._9 });
    try board.place_piece(.black, .{ .E, ._8 });

    const job = Job.kreuz();
    try expectEqual(true, job.is_fulfilled(board, .black));
}

test "is_fulfilled detects kreuz job rotated 180 degrees" {
    var board = Board{};
    try board.place_piece(.black, .{ .H, ._2 });
    try board.place_piece(.black, .{ .I, ._3 });
    try board.place_piece(.black, .{ .H, ._3 });
    try board.place_piece(.black, .{ .G, ._3 });
    try board.place_piece(.black, .{ .H, ._4 });
    try board.place_piece(.black, .{ .H, ._5 });

    const job = Job.kreuz();
    try expectEqual(true, job.is_fulfilled(board, .black));
}

test "is_fulfilled detects kreuz job rotated 270 degrees" {
    var board = Board{};
    try board.place_piece(.black, .{ .I, ._8 });
    try board.place_piece(.black, .{ .H, ._8 });
    try board.place_piece(.black, .{ .G, ._7 });
    try board.place_piece(.black, .{ .G, ._8 });
    try board.place_piece(.black, .{ .G, ._9 });
    try board.place_piece(.black, .{ .F, ._8 });

    const job = Job.kreuz();
    try expectEqual(true, job.is_fulfilled(board, .black));
}

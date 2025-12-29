const std = @import("std");

const expectEqual = std.testing.expectEqual;

const constants = @import("constants.zig");
const board_module = @import("board.zig");
const enums = @import("enums.zig");
const position = @import("position.zig");

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

    pub fn init(
        width: u3,
        height: u3,
        requirements: []const JobRequirement,
    ) Job {
        std.debug.assert(width > 0);
        std.debug.assert(height > 0);

        const total_pieces: u4 = @intCast(std.mem.count(JobRequirement, requirements, &.{.piece}));
        var job = Job{
            .width = width,
            .height = height,
            .requirements = .{.any} ** (max_job_size * max_job_size),
            .total_pieces = total_pieces,
        };
        std.mem.copyForwards(JobRequirement, job.requirements[0..requirements.len], requirements);

        return job;
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

    pub fn job_is_fulfilled(self: *const Job, board: *const Board, player: Player) bool {
        const player_color = SquareContent.from_player(player);

        const board_x_end: u4 = 9 - @as(u4, self.width) + 2;
        const board_y_end: u4 = 9 - @as(u4, self.height) + 2;
        for (2..board_x_end) |board_x| {
            for (2..board_y_end) |board_y| potential_position: {
                for (0..self.width) |job_x| {
                    for (0..self.height) |job_y| {
                        const req = self.requirements[job_x * self.width + job_y];
                        const pos = pos_from_int(.{ @intCast(board_x + job_x), @intCast(board_y + job_y) });
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
        return false;
    }
};

test "job_is_fulfilled detects turm3 in lower left corner" {
    var board = Board{};
    try board.place_piece(.black, .{ .B, ._4 });
    try board.place_piece(.black, .{ .B, ._3 });
    try board.place_piece(.black, .{ .B, ._2 });

    const job = Job.turm3();
    try expectEqual(true, job.job_is_fulfilled(&board, .black));
}

test "job_is_fulfilled detects treppe3 in center" {
    var board = Board{};
    try board.place_piece(.white, .{ .E, ._5 });
    try board.place_piece(.white, .{ .F, ._4 });
    try board.place_piece(.white, .{ .G, ._3 });

    const job = Job.treppe3();
    try expectEqual(true, job.job_is_fulfilled(&board, .white));
}

test "job_is_fulfilled detects turm3 in upper right corner" {
    var board = Board{};
    try board.place_piece(.black, .{ .I, ._9 });
    try board.place_piece(.black, .{ .I, ._8 });
    try board.place_piece(.black, .{ .I, ._7 });

    const job = Job.turm3();
    try expectEqual(true, job.job_is_fulfilled(&board, .black));
}

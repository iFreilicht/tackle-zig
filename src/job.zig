const Job = @This();
const std = @import("std");

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const tackle = @import("root.zig");

const max_pieces_in_job = tackle.constants.max_pieces_in_job;
const max_job_edge_length = tackle.constants.max_job_edge_length;
const max_job_size = tackle.constants.max_job_size;
const Board = tackle.Board;
const SquareContent = tackle.enums.SquareContent;
const Player = tackle.enums.Player;
const PieceColor = tackle.enums.PieceColor;
const Position = tackle.position.Position;
const posFromInt = tackle.position.posFromInt;

/// If the job is an official one, this is its official name.
name: ?OfficialJobName,
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
requirements: [max_job_size]JobRequirement,
total_pieces: u4, // Maximum of 16 pieces, see also `max_pieces_per_player`
rotation_count: RotationCount,

/// All names of the official jobs
pub const OfficialJobName = enum {
    turm3,
    treppe3,
    turm4,
    treppe4,
    quadrat,
    bluete,
    turm5,
    treppe5,
    fuenf,
    fisch,
    turm6,
    block6,
    kreuz,
    vogel,
    block8,
    brunnen,
    block9,
};

pub fn show_official_job_names(writer: *std.io.Writer) !void {
    try writer.print("Official jobs:\n", .{});
    for (Job.official_jobs) |job| {
        try writer.print(" - {t}\n", .{job.name.?});
    }
}

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

    pub fn toRotations(self: @This()) usize {
        return @as(usize, @intFromEnum(self)) + 1;
    }
};

pub fn init(
    name: ?OfficialJobName,
    width: u3,
    height: u3,
    requirements: []const JobRequirement,
) !Job {
    if (width == 0 or height == 0) {
        return error.JobDimensionsCannotBeZero;
    }
    if (width > max_job_edge_length) {
        return error.JobWidthTooLarge;
    }
    if (height > max_job_edge_length) {
        return error.JobHeightTooLarge;
    }
    if (@as(u6, width) * @as(u6, height) > max_job_size) {
        return error.JobSizeTooLarge;
    }
    if (requirements.len > max_job_size) {
        return error.JobRequirementsTooLong;
    }

    const total_pieces: u4 = @intCast(std.mem.count(JobRequirement, requirements, &.{.piece}));
    if (total_pieces < 3) {
        return error.JobMustRequireAtLeastThreePieces;
    }
    if (total_pieces > max_pieces_in_job) {
        return error.JobHasTooManyPieces;
    }

    const unique_rotations: RotationCount = if (isSymmetric90(
        width,
        height,
        requirements,
    ))
        .one
    else if (isSymmetric180(
        width,
        height,
        requirements,
    ))
        .two
    else
        .four;

    var job = Job{
        .name = name,
        .width = width,
        .height = height,
        .requirements = .{.any} ** max_job_size,
        .total_pieces = total_pieces,
        .rotation_count = unique_rotations,
    };
    std.mem.copyForwards(JobRequirement, job.requirements[0..requirements.len], requirements);

    return job;
}

/// Check if rotating 90° gives the same pattern
fn isSymmetric90(width: u3, height: u3, requirements: []const JobRequirement) bool {
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
fn isSymmetric180(width: u3, height: u3, requirements: []const JobRequirement) bool {
    for (0..width) |x| {
        for (0..height) |y| {
            if (requirements[x * height + y] !=
                requirements[(width - 1 - x) * height + (height - 1 - y)])
                return false;
        }
    }
    return true;
}

// 3-piece jobs
pub fn turm3() Job {
    return init(.turm3, 1, 3, &.{
        .piece, .piece, .piece,
    }) catch unreachable;
}

pub fn treppe3() Job {
    return init(.treppe3, 3, 3, &.{
        .any,   .any,   .piece,
        .any,   .piece, .any,
        .piece, .any,   .any,
    }) catch unreachable;
}

// 4-piece jobs
pub fn turm4() Job {
    return init(.turm4, 1, 4, &.{
        .piece, .piece, .piece, .piece,
    }) catch unreachable;
}

pub fn treppe4() Job {
    return init(.treppe4, 4, 4, &.{
        .any,   .any,   .any,   .piece,
        .any,   .any,   .piece, .any,
        .any,   .piece, .any,   .any,
        .piece, .any,   .any,   .any,
    }) catch unreachable;
}

pub fn quadrat() Job {
    return init(.quadrat, 2, 2, &.{
        .piece, .piece, .piece, .piece,
    }) catch unreachable;
}

pub fn bluete() Job {
    return init(.bluete, 3, 3, &.{
        .any,   .piece, .any,
        .piece, .other, .piece,
        .any,   .piece, .any,
    }) catch unreachable;
}

// 5-piece jobs
pub fn turm5() Job {
    return init(.turm5, 1, 5, &.{
        .piece, .piece, .piece, .piece, .piece,
    }) catch unreachable;
}

pub fn treppe5() Job {
    return init(.treppe5, 5, 5, &.{
        .any,   .any,   .any,   .any,   .piece,
        .any,   .any,   .any,   .piece, .any,
        .any,   .any,   .piece, .any,   .any,
        .any,   .piece, .any,   .any,   .any,
        .piece, .any,   .any,   .any,   .any,
    }) catch unreachable;
}

pub fn fuenf() Job {
    return init(.fuenf, 3, 3, &.{
        .piece, .other, .piece,
        .other, .piece, .other,
        .piece, .other, .piece,
    }) catch unreachable;
}

pub fn fisch() Job {
    return init(.fisch, 3, 3, &.{
        .any,   .piece, .piece,
        .any,   .piece, .piece,
        .piece, .any,   .any,
    }) catch unreachable;
}

// 6-piece jobs
pub fn turm6() Job {
    return init(.turm6, 1, 6, &.{
        .piece, .piece, .piece, .piece, .piece, .piece,
    }) catch unreachable;
}

pub fn block6() Job {
    return init(.block6, 3, 2, &.{
        .piece, .piece, .piece,
        .piece, .piece, .piece,
    }) catch unreachable;
}

pub fn kreuz() Job {
    return init(.kreuz, 3, 4, &.{
        .any,   .piece, .any,
        .piece, .piece, .piece,
        .any,   .piece, .any,
        .any,   .piece, .any,
    }) catch unreachable;
}

pub fn vogel() Job {
    return init(.vogel, 4, 4, &.{
        .any,   .any,   .any,   .piece,
        .any,   .piece, .piece, .any,
        .any,   .piece, .piece, .any,
        .piece, .any,   .any,   .any,
    }) catch unreachable;
}

// 8-piece jobs
pub fn block8() Job {
    return init(.block8, 4, 2, &.{
        .piece, .piece, .piece, .piece,
        .piece, .piece, .piece, .piece,
    }) catch unreachable;
}

pub fn brunnen() Job {
    return init(.brunnen, 3, 3, &.{
        .piece, .piece, .piece,
        .piece, .other, .piece,
        .piece, .piece, .piece,
    }) catch unreachable;
}

// 9-piece jobs
pub fn block9() Job {
    return init(.block9, 3, 3, &.{
        .piece, .piece, .piece,
        .piece, .piece, .piece,
        .piece, .piece, .piece,
    }) catch unreachable;
}

pub const official_jobs = [_]Job{
    turm3(),
    treppe3(),
    turm4(),
    treppe4(),
    quadrat(),
    bluete(),
    turm5(),
    treppe5(),
    fuenf(),
    fisch(),
    turm6(),
    block6(),
    kreuz(),
    vogel(),
    block8(),
    brunnen(),
    block9(),
};

/// Get a Job by its official name
pub fn fromName(name: []const u8) !Job {
    for (official_jobs) |job| {
        if (std.mem.eql(u8, name, @tagName(job.name.?))) {
            return job;
        }
    }
    return error.UnknownJobName;
}

/// Get the number of pieces each player must place
/// during the opening phase if this job is used.
pub fn piecesPerPlayer(self: Job) u4 {
    return self.total_pieces + 2;
}

pub fn isFulfilled(self: Job, board: Board, player: Player) bool {
    const player_color = SquareContent.fromPlayer(player);
    const rotations_to_check = self.rotation_count.toRotations();

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
                        const offset_x, const offset_y = rotateCoordinates(
                            job_x,
                            job_y,
                            @intCast(rotation),
                            self.width,
                            self.height,
                        );

                        const pos = posFromInt(.{ @intCast(board_x + offset_x), @intCast(board_y + offset_y) });
                        const content = board.getSquare(pos);

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
fn rotateCoordinates(x: usize, y: usize, rotation: u2, orig_width: u3, orig_height: u3) struct { usize, usize } {
    return switch (rotation) {
        0 => .{ x, y }, // 0°: no change
        1 => .{ y, orig_width - 1 - x }, // 90° clockwise
        2 => .{ orig_width - 1 - x, orig_height - 1 - y }, // 180°
        3 => .{ orig_height - 1 - y, x }, // 270° clockwise
    };
}

test "Job.init detects correct rotation counts" {
    try expectEqual(.one, quadrat().rotation_count);
    try expectEqual(.two, turm3().rotation_count);
    try expectEqual(.four, fisch().rotation_count);
    try expectEqual(.four, kreuz().rotation_count);
    try expectEqual(.two, vogel().rotation_count);
}

test "all official jobs initialize without error" {
    _ = turm3();
    _ = treppe3();
    _ = turm4();
    _ = treppe4();
    _ = quadrat();
    _ = bluete();
    _ = turm5();
    _ = treppe5();
    _ = fuenf();
    _ = fisch();
    _ = turm6();
    _ = block6();
    _ = kreuz();
    _ = vogel();
    _ = block8();
    _ = brunnen();
    _ = block9();
}

test "all official jobs are displayed by show_official_job_names" {
    var buffer: [1024]u8 = undefined;
    var writer = std.io.Writer.fixed(&buffer);

    try show_official_job_names(&writer);

    for (official_jobs) |job| {
        const job_name = @tagName(job.name.?);
        try expect(std.mem.containsAtLeast(
            u8,
            buffer[0..writer.end],
            1,
            job_name,
        ));
    }
}

test "isFulfilled detects turm3 in lower left corner" {
    var board = Board{};
    try board.placePiece(.black, .{ .B, ._4 });
    try board.placePiece(.black, .{ .B, ._3 });
    try board.placePiece(.black, .{ .B, ._2 });

    const job = Job.turm3();
    try expectEqual(true, job.isFulfilled(board, .black));
}

test "isFulfilled detects treppe3 in center" {
    var board = Board{};
    try board.placePiece(.white, .{ .E, ._5 });
    try board.placePiece(.white, .{ .F, ._4 });
    try board.placePiece(.white, .{ .G, ._3 });

    const job = treppe3();
    try expectEqual(true, job.isFulfilled(board, .white));
}

test "isFulfilled detects turm3 in upper right corner" {
    var board = Board{};
    try board.placePiece(.black, .{ .I, ._9 });
    try board.placePiece(.black, .{ .I, ._8 });
    try board.placePiece(.black, .{ .I, ._7 });

    const job = turm3();
    try expectEqual(true, job.isFulfilled(board, .black));
}

test "isFulfilled detects turm3 in rotated position in lower left corner" {
    var board = Board{};
    try board.placePiece(.black, .{ .B, ._2 });
    try board.placePiece(.black, .{ .C, ._2 });
    try board.placePiece(.black, .{ .D, ._2 });

    const job = turm3();
    try expectEqual(true, job.isFulfilled(board, .black));
}

test "isFulfilled detects treppe3 in rotated position in center" {
    var board = Board{};
    try board.placePiece(.white, .{ .F, ._5 });
    try board.placePiece(.white, .{ .E, ._4 });
    try board.placePiece(.white, .{ .D, ._3 });

    const job = treppe3();
    try expectEqual(true, job.isFulfilled(board, .white));
}

test "isFulfilled detects turm3 in rotated position in upper right corner" {
    var board = Board{};
    try board.placePiece(.black, .{ .I, ._9 });
    try board.placePiece(.black, .{ .H, ._9 });
    try board.placePiece(.black, .{ .G, ._9 });

    const job = turm3();
    try expectEqual(true, job.isFulfilled(board, .black));
}

test "isFulfilled returns false when job not fulfilled" {
    var board = Board{};
    try board.placePiece(.white, .{ .E, ._5 });
    try board.placePiece(.white, .{ .F, ._5 });
    // Missing third piece for turm3

    const job = turm3();
    try expectEqual(false, job.isFulfilled(board, .white));
}

test "isFulfilled detects bluete job" {
    var board = Board{};
    try board.placePiece(.white, .{ .E, ._5 });
    try board.placePiece(.white, .{ .D, ._4 });
    try board.placePiece(.white, .{ .F, ._4 });
    try board.placePiece(.white, .{ .E, ._3 });

    const job = bluete();
    try expectEqual(true, job.isFulfilled(board, .white));
}

test "job_is_fullfilled detects bluete job when center contains opponent piece" {
    var board = Board{};
    try board.placePiece(.white, .{ .E, ._5 });
    try board.placePiece(.white, .{ .D, ._4 });
    try board.placePiece(.black, .{ .E, ._4 }); // Opponent piece in center
    try board.placePiece(.white, .{ .F, ._4 });
    try board.placePiece(.white, .{ .E, ._3 });

    const job = bluete();
    try expectEqual(true, job.isFulfilled(board, .white));
}

test "isFulfilled returns false when center of bluete is filled" {
    var board = Board{};
    try board.placePiece(.white, .{ .E, ._5 });
    try board.placePiece(.white, .{ .D, ._4 });
    try board.placePiece(.white, .{ .E, ._4 }); // Wrong: center should be empty
    try board.placePiece(.white, .{ .F, ._4 });
    try board.placePiece(.white, .{ .E, ._3 });

    const job = bluete();
    try expectEqual(false, job.isFulfilled(board, .white));
}

test "isFulfilled detects kreuz job rotated 0 degrees" {
    var board = Board{};
    try board.placePiece(.black, .{ .C, ._5 });
    try board.placePiece(.black, .{ .B, ._4 });
    try board.placePiece(.black, .{ .C, ._4 });
    try board.placePiece(.black, .{ .D, ._4 });
    try board.placePiece(.black, .{ .C, ._3 });
    try board.placePiece(.black, .{ .C, ._2 });

    const job = kreuz();
    try expectEqual(true, job.isFulfilled(board, .black));
}

test "isFulfilled detects kreuz job rotated 90 degrees" {
    var board = Board{};
    try board.placePiece(.black, .{ .B, ._8 });
    try board.placePiece(.black, .{ .C, ._8 });
    try board.placePiece(.black, .{ .D, ._7 });
    try board.placePiece(.black, .{ .D, ._8 });
    try board.placePiece(.black, .{ .D, ._9 });
    try board.placePiece(.black, .{ .E, ._8 });

    const job = kreuz();
    try expectEqual(true, job.isFulfilled(board, .black));
}

test "isFulfilled detects kreuz job rotated 180 degrees" {
    var board = Board{};
    try board.placePiece(.black, .{ .H, ._2 });
    try board.placePiece(.black, .{ .I, ._3 });
    try board.placePiece(.black, .{ .H, ._3 });
    try board.placePiece(.black, .{ .G, ._3 });
    try board.placePiece(.black, .{ .H, ._4 });
    try board.placePiece(.black, .{ .H, ._5 });

    const job = kreuz();
    try expectEqual(true, job.isFulfilled(board, .black));
}

test "isFulfilled detects kreuz job rotated 270 degrees" {
    var board = Board{};
    try board.placePiece(.black, .{ .I, ._8 });
    try board.placePiece(.black, .{ .H, ._8 });
    try board.placePiece(.black, .{ .G, ._7 });
    try board.placePiece(.black, .{ .G, ._8 });
    try board.placePiece(.black, .{ .G, ._9 });
    try board.placePiece(.black, .{ .F, ._8 });

    const job = kreuz();
    try expectEqual(true, job.isFulfilled(board, .black));
}

test fromName {
    try expectEqual(turm3(), try Job.fromName("turm3"));
    try expectEqual(treppe5(), try Job.fromName("treppe5"));
    try expectEqual(block9(), try Job.fromName("block9"));

    try std.testing.expectError(error.UnknownJobName, Job.fromName("unknownjob"));
}

test piecesPerPlayer {
    try expectEqual(@as(u4, 5), turm3().piecesPerPlayer());
    try expectEqual(@as(u4, 7), treppe5().piecesPerPlayer());
    try expectEqual(@as(u4, 11), block9().piecesPerPlayer());
}

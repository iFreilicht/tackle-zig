const std = @import("std");
const constants = @import("constants.zig");
const notation = @import("notation.zig");
const expectError = std.testing.expectError;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;
const board_size = constants.board_size;
const max_job_size = constants.max_job_size;
const max_pieces_per_player = constants.max_pieces_per_player;

const ColumnX = notation.ColumnX;
const RowY = notation.RowY;
const Position = notation.Position;
const Move = notation.Move;

pub const Player = enum(u2) { white = 1, black = 2 };
pub const PieceColor = enum(u2) { white = 1, black = 2, gold = 3 };
pub const SquareContent = enum(u2) {
    empty = 0,
    white = 1,
    black = 2,
    gold = 3,

    pub fn from_color(c: PieceColor) @This() {
        return @enumFromInt(@intFromEnum(c));
    }
};
pub const Board = struct {
    /// Board squares in column-major order. Be careful! Use `index`!
    squares: [board_size * board_size]SquareContent = .{.empty} ** (board_size * board_size),
    /// Indices of white pieces on the board for fast iteration
    white_pieces: [max_pieces_per_player]u8 = undefined,
    /// Indices of black pieces on the board for fast iteration
    black_pieces: [max_pieces_per_player]u8 = undefined,
    /// Count of white pieces on the board. Aids in branch prediction during iteration.
    white_count: u8 = 0,
    /// Count of white pieces on the board. Aids in branch prediction during iteration.
    black_count: u8 = 0,
    /// Index of the gold piece on the board, or 0xff if not placed yet
    gold_piece: u8 = GOLD_EMPTY,

    // Max index is 10*10=100, so we can use a sentinel value to represent the empty state
    const GOLD_EMPTY = 0xff;

    pub fn index(position: Position) u8 {
        const col, const row = position;
        const x: u8 = col.index();
        const y: u8 = row.index();
        return x * board_size + y;
    }

    /// Place a piece on the board. This is a low-level function that only checks
    /// for data invariants, not game rules.
    pub fn place_piece(self: *Board, color: PieceColor, at: Position) !void {
        const idx = index(at);
        if (self.squares[idx] != .empty) return error.SquareOccupied;

        self.squares[idx] = SquareContent.from_color(color);
        switch (color) {
            .white => {
                self.white_pieces[self.white_count] = idx;
                self.white_count += 1;
            },
            .black => {
                self.black_pieces[self.black_count] = idx;
                self.black_count += 1;
            },
            .gold => {
                if (self.gold_piece != 0xff) return error.GoldPieceAlreadyPlaced;
                self.gold_piece = idx;
            },
        }
    }

    /// Remove a piece from the board. Only happens during a worm move, undo, or
    /// when the gold piece is removed. This is a low-level function that only checks
    /// for data invariants, not game rules.
    /// Do not use `remove_piece` and `place_piece` to move pieces around, use
    /// `move_single_piece` instead!
    pub fn remove_piece(self: *Board, from: Position) !void {
        const idx = index(from);

        switch (self.squares[idx]) {
            .empty => return error.SquareEmpty,
            .white => {
                for (0..self.white_count) |i| {
                    if (self.white_pieces[i] == idx) {
                        // Overwrite with last entry (might be a noop)
                        self.white_pieces[i] = self.white_pieces[self.white_count];
                        // Remove last entry
                        self.white_count -= 1;
                    }
                }
            },
            .black => {
                for (0..self.black_count) |i| {
                    if (self.black_pieces[i] == idx) {
                        self.black_pieces[i] = self.black_pieces[self.black_count];
                        self.black_count -= 1;
                    }
                }
            },
            .gold => {
                self.gold_piece = GOLD_EMPTY;
            },
        }

        self.squares[idx] = .empty;
    }

    /// Move a single piece from one position to another. This is a low-level
    /// function that only checks for data invariants, not game rules.
    pub fn move_single_piece(self: *Board, from: Position, to: Position) !void {
        const idx_from = index(from);
        const idx_to = index(to);

        switch (self.squares[idx_from]) {
            .empty => return error.SquareEmpty,
            .gold => return error.MovingGoldNotAllowed,
            .white, .black => {},
        }

        if (self.squares[idx_to] != .empty) return error.SquareOccupied;

        self.squares[idx_to] = self.squares[idx_from];
        self.squares[idx_from] = .empty;

        // Update piece position in the relevant array
        const color = self.squares[idx_to];
        switch (color) {
            .white => {
                for (0..self.white_count) |i| {
                    if (self.white_pieces[i] == idx_from) {
                        self.white_pieces[i] = idx_to;
                    }
                }
            },
            .black => {
                for (0..self.black_count) |i| {
                    if (self.black_pieces[i] == idx_from) {
                        self.black_pieces[i] = idx_to;
                    }
                }
            },
            .gold, .empty => unreachable,
        }
    }

    pub fn get_square(self: *const Board, at: Position) SquareContent {
        const idx = index(at);
        return self.squares[idx];
    }

    pub fn is_square_empty(self: *const Board, position: Position) bool {
        return self.get_square(position) == .empty;
    }
};

pub const JobRequirement = enum { piece, empty, any };
pub const Job = struct {
    size_x: u3,
    size_y: u3,
    requirements: [max_job_size * max_job_size]JobRequirement,
    total_pieces: u4, // Maximum of 16 pieces, see also `max_pieces_per_player`
};

pub const Phase = enum(u2) {
    /// Initial phase where pieces are placed on the board
    opening,
    /// Zero-turn phase after black's last piece has been placed,
    /// in which they place the gold piece in the core
    place_gold,
    main,
    finished,
};

pub const GameState = struct {
    /// Turn count, starting with zero
    turn: u32,
    phase: Phase,
    board: Board,
    job: Job,

    fn init(job: Job) GameState {
        return GameState{
            .next_player = .white,
            .board = Board,
            .job = job,
        };
    }

    fn next_player(self: *const GameState) Player {
        return if (self.turn % 2 == 0) .white else .black;
    }

    fn pieces_per_player(self: *const GameState) u4 {
        return self.job.total_pieces + 2;
    }

    fn end_turn(self: *GameState) void {
        switch (self.phase) {
            .opening => {
                if (self.turn == self.pieces_per_player() * 2 - 1) {
                    self.phase = .place_gold;
                    // Placing the gold piece is part of black's last turn during
                    // the opening, so DON'T increment the turn number here!
                } else {
                    self.turn += 1;
                }
            },
            .place_gold => {
                self.phase = .main;
                self.turn += 1;
            },
            .main => {
                self.turn += 1;
                // TODO: Check for win condition
            },
            .finished => unreachable,
        }
    }

    /// Place a piece for the current player and end their turn.
    /// Only allows placing pieces in the border, according to game rules.
    pub fn place_next_piece(self: *GameState, position: Position) !void {
        switch (self.phase) {
            .opening => {
                if (!notation.is_on_border(position)) return error.PieceNotOnBorder;
                try self.board.place_piece(self.next_player(), position);
            },
            .place_gold => {
                if (!notation.is_in_core(position)) return error.GoldNotInCore;
                try self.board.place_piece(.gold, position);
            },
            .main => return error.InvalidPhase,
            .finished => return error.InvalidPhase,
        }

        self.end_turn();
    }
};

/// Validate that the piece being moved belongs to the player
fn validate_color(player: Player, color: SquareContent) !void {
    switch (player) {
        .white => if (color != .white) return error.IllegalMove,
        .black => if (color != .black) return error.IllegalMove,
    }
}

/// Move a piece according to the specified move, checking for
/// violations of game rules.
pub fn move_piece(board: *Board, player: Player, move: Move) !void {
    switch (move) {
        .diagonal => |d| {
            const start = d.to_start();
            const content = board.get_square(start);
            try validate_color(player, content);

            const positions = d.from.to_list();
            for (0..d.distance) |i| {
                const position = positions[i];
                if (!board.is_square_empty(position)) return error.PathBlocked;
            }

            const end = d.to_end();
            try board.move_single_piece(start, end);
        },
        .horizontal => |h| {
            const start = Position{ h.from_x, h.y };
            const content = board.get_square(start);
            try validate_color(player, content);

            // TODO: Check for obstructions
            // TODO: Handle block height
            // TODO: Implement pushing logic
            // TODO: Implement worm moves

            const end = Position{ h.to_x, h.y };
            try board.move_single_piece(start, end);
        },
        .vertical => |v| {
            const start = Position{ v.x, v.from_y };
            const content = board.get_square(start);
            try validate_color(player, content);

            // TODO: Check for obstructions
            // TODO: Handle block height
            // TODO: Implement pushing logic
            // TODO: Implement worm moves

            const end = Position{ v.x, v.to_y };
            try board.move_single_piece(start, end);
        },
    }
}

test "place pieces" {
    var board: Board = .{};

    try board.place_piece(.white, .{ .B, ._5 });
    try board.place_piece(.white, .{ .C, ._4 });
    try board.place_piece(.black, .{ .H, ._6 });
    try board.place_piece(.gold, .{ .E, ._5 });

    try expectEqualSlices(u8, &[_]u8{ 14, 23 }, board.white_pieces[0..2]);
    try expectEqualSlices(u8, &[_]u8{75}, board.black_pieces[0..1]);
    try expectEqual(2, board.white_count);
    try expectEqual(1, board.black_count);
    try expectEqual(44, board.gold_piece);
    try expectEqual(.white, board.get_square(.{ .B, ._5 }));
    try expectEqual(.black, board.get_square(.{ .H, ._6 }));
    try expectEqual(.gold, board.get_square(.{ .E, ._5 }));
}

test "place piece errors" {
    var board: Board = .{};

    try board.place_piece(.white, .{ .B, ._5 });
    try expectError(error.SquareOccupied, board.place_piece(.black, .{ .B, ._5 }));

    try board.place_piece(.gold, .{ .E, ._5 });
    try expectError(error.GoldPieceAlreadyPlaced, board.place_piece(.gold, .{ .F, ._6 }));
}

test "test index" {
    try expectEqual(0, Board.index(.{ .A, ._1 }));
    try expectEqual(3, Board.index(.{ .A, ._4 }));
    try expectEqual(16, Board.index(.{ .B, ._7 }));
    try expectEqual(20, Board.index(.{ .C, ._1 }));
    try expectEqual(75, Board.index(.{ .H, ._6 }));
    try expectEqual(82, Board.index(.{ .I, ._3 }));
    try expectEqual(99, Board.index(.{ .J, ._10 }));
}

test "move single piece" {
    var board: Board = .{};

    try board.place_piece(.white, .{ .B, ._5 });
    try board.place_piece(.black, .{ .I, ._8 });
    try board.place_piece(.black, .{ .J, ._10 });
    try expectEqual(.white, board.get_square(.{ .B, ._5 }));
    try expectEqual(.black, board.get_square(.{ .I, ._8 }));
    try expectEqual(.black, board.get_square(.{ .J, ._10 }));
    try expectEqualSlices(u8, &[_]u8{14}, board.white_pieces[0..1]);
    try expectEqualSlices(u8, &[_]u8{ 87, 99 }, board.black_pieces[0..2]);

    try board.move_single_piece(.{ .B, ._5 }, .{ .B, ._7 });
    try expectEqual(.empty, board.get_square(.{ .B, ._5 }));
    try expectEqual(.white, board.get_square(.{ .B, ._7 }));
    try expectEqualSlices(u8, &[_]u8{16}, board.white_pieces[0..1]);
    try expectEqualSlices(u8, &[_]u8{ 87, 99 }, board.black_pieces[0..2]);

    try board.move_single_piece(.{ .I, ._8 }, .{ .C, ._8 });
    try expectEqual(.empty, board.get_square(.{ .I, ._8 }));
    try expectEqual(.black, board.get_square(.{ .C, ._8 }));
    try expectEqualSlices(u8, &[_]u8{16}, board.white_pieces[0..1]);
    try expectEqualSlices(u8, &[_]u8{ 27, 99 }, board.black_pieces[0..2]);

    try board.move_single_piece(.{ .J, ._10 }, .{ .D, ._4 });
    try expectEqual(.empty, board.get_square(.{ .J, ._10 }));
    try expectEqual(.black, board.get_square(.{ .D, ._4 }));
    try expectEqualSlices(u8, &[_]u8{16}, board.white_pieces[0..1]);
    try expectEqualSlices(u8, &[_]u8{ 27, 33 }, board.black_pieces[0..2]);
}

test "move single piece errors" {
    var board: Board = .{};

    try board.place_piece(.white, .{ .B, ._5 });
    try board.place_piece(.white, .{ .E, ._5 });
    try board.place_piece(.white, .{ .B, ._6 });
    try expectEqual(.white, board.get_square(.{ .B, ._5 }));
    try expectEqual(.white, board.get_square(.{ .E, ._5 }));
    try expectEqual(.white, board.get_square(.{ .B, ._6 }));
    try expectEqualSlices(u8, &[_]u8{ 14, 44, 15 }, board.white_pieces[0..3]);

    try expectError(error.SquareEmpty, board.move_single_piece(.{ .C, ._3 }, .{ .C, ._4 }));
    try expectError(error.SquareOccupied, board.move_single_piece(.{ .B, ._5 }, .{ .E, ._5 }));
    try expectError(error.SquareOccupied, board.move_single_piece(.{ .B, ._5 }, .{ .B, ._6 }));
    try expectEqual(.white, board.get_square(.{ .B, ._5 }));
    try expectEqual(.white, board.get_square(.{ .E, ._5 }));
    try expectEqual(.white, board.get_square(.{ .B, ._6 }));
    try expectEqualSlices(u8, &[_]u8{ 14, 44, 15 }, board.white_pieces[0..3]);

    try board.place_piece(.gold, .{ .E, ._6 });
    try expectEqual(.gold, board.get_square(.{ .E, ._6 }));
    try expectEqual(board.gold_piece, 45);
    try expectError(error.MovingGoldNotAllowed, board.move_single_piece(.{ .E, ._6 }, .{ .E, ._7 }));
    try expectEqual(.gold, board.get_square(.{ .E, ._6 }));
    try expectEqual(board.gold_piece, 45);
}

test "move piece diagonally" {
    var board: Board = .{};

    const top_left_pos = notation.Corner.top_left.to_position();
    try board.place_piece(.white, top_left_pos);
    try board.place_piece(.black, .{ .I, ._8 });

    try expectEqual(.white, board.get_square(top_left_pos));
    try expectEqual(.black, board.get_square(.{ .I, ._8 }));

    const move = Move{ .diagonal = notation.DiagonalMove{
        .from = .top_left,
        .distance = 3,
    } };
    try move_piece(&board, .white, move);
    try expectEqual(.empty, board.get_square(top_left_pos));
    try expectEqual(.white, board.get_square(.{ .D, ._7 }));
}

test "move piece diagonally with obstruction error" {
    var board: Board = .{};

    const bottom_left_pos = notation.Corner.bottom_left.to_position();
    try board.place_piece(.white, bottom_left_pos);
    try board.place_piece(.black, .{ .C, ._3 }); // Obstruction

    const move = Move{ .diagonal = notation.DiagonalMove{
        .from = .bottom_left,
        .distance = 5,
    } };
    try expectError(error.PathBlocked, move_piece(&board, .white, move));

    try expectEqual(.white, board.get_square(bottom_left_pos));
    try expectEqual(.black, board.get_square(.{ .C, ._3 }));
}

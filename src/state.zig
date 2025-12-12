const std = @import("std");
const constants = @import("constants.zig");
const notation = @import("notation.zig");
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;
const board_size = constants.board_size;
const max_job_size = constants.max_job_size;
const max_pieces_per_player = constants.max_pieces_per_player;

const ColumnX = notation.ColumnX;
const RowY = notation.RowY;
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
pub const JobRequirement = enum { piece, empty, any };
pub const Job = struct {
    size_x: usize,
    size_y: usize,
    requirements: [max_job_size * max_job_size]JobRequirement,
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

    pub fn index(col: ColumnX, row: RowY) u8 {
        const x: u8 = col.index();
        const y: u8 = row.index();
        return x * board_size + y;
    }

    /// Place a piece on the board. This is a low-level function that only checks
    /// for data invariants, not game rules.
    pub fn place_piece(self: *Board, color: PieceColor, col: ColumnX, row: RowY) !void {
        const idx = index(col, row);
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

    pub fn remove_piece(self: *Board, col: ColumnX, row: RowY) !void {
        const idx = index(col, row);

        switch (self.squares[idx]) {
            .content => return error.SquareEmpty,
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

    pub fn get_square(self: *const Board, col: ColumnX, row: RowY) SquareContent {
        const idx = index(col, row);
        return self.squares[idx];
    }

    pub fn is_square_empty(self: *const Board, col: ColumnX, row: RowY) bool {
        return self.get_square(col, row) == .empty;
    }
};

pub const GameState = struct {
    next: Player,
    board: Board,
    job: Job,

    fn init(job: Job) GameState {
        return GameState{
            .next = .white,
            .board = Board,
            .job = job,
        };
    }
};

pub fn move_piece(board: *Board, move: Move) !Board {
    switch (move) {
        .diagonal => |d| {
            try board.remove_piece(d, d.from_row);
            try board.place_piece(d.color, d.to_col, d.to_row);
        },
        .horizontal => |h| {
            for (h.from_x..h.to_x) |x| {
                _ = x; // autofix
            }
        },
    }
}

test "place pieces" {
    var board: Board = .{};

    try board.place_piece(.white, .B, ._5);
    try board.place_piece(.white, .C, ._4);
    try board.place_piece(.black, .H, ._6);
    try board.place_piece(.gold, .E, ._5);

    try expectEqualSlices(u8, &[_]u8{ 14, 23 }, board.white_pieces[0..2]);
    try expectEqualSlices(u8, &[_]u8{75}, board.black_pieces[0..1]);
    try expectEqual(2, board.white_count);
    try expectEqual(1, board.black_count);
    try expectEqual(44, board.gold_piece);
    try expectEqual(.white, board.get_square(.B, ._5));
    try expectEqual(.black, board.get_square(.H, ._6));
    try expectEqual(.gold, board.get_square(.E, ._5));
}

test "test index" {
    try expectEqual(0, Board.index(.A, ._1));
    try expectEqual(3, Board.index(.A, ._4));
    try expectEqual(16, Board.index(.B, ._7));
    try expectEqual(20, Board.index(.C, ._1));
    try expectEqual(75, Board.index(.H, ._6));
    try expectEqual(82, Board.index(.I, ._3));
    try expectEqual(99, Board.index(.J, ._10));
}

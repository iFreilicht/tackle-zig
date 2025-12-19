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
const BlockSize = notation.BlockSize;
const Direction = notation.Direction;
const move_position = notation.move_position;

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
    pub fn to_list(self: *const Block, buffer: []Position, direction: Direction) []Position {
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

pub const Board = struct {
    const Squares = [board_size * board_size]SquareContent;

    /// Board squares in column-major order. Be careful! Use `index` to convert
    /// positions to indices that can be used here and update all other fields
    /// whenever you modify this array!
    squares: Squares = .{.empty} ** (board_size * board_size),
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

    /// Return a new Squares array with the piece moved from one index to another.
    /// It might seem VERY inefficient to copy the entire array just to move a single piece,
    /// especially when we need to do this multiple times in a row when moving blocks of pieces.
    /// However, this allows us to move all pieces in a block first to check for errors without
    /// modifying the original board state, and only commit the changes once all moves have
    /// succeeded.
    /// For now, we trust that the Zig compiler will optimize away the copying as much as possible
    /// until we have proper profiling data to prove otherwise.
    /// This is a low-level function that only checks for data invariants, not game rules.
    /// TODO: But maybe it should also check for collisions along the path?
    fn move_piece(squares: Squares, idx_from: u8, idx_to: u8) !Squares {
        var new_squares = squares;
        switch (new_squares[idx_from]) {
            .empty => return error.SquareEmpty,
            .gold => return error.MovingGoldNotAllowed,
            .white, .black => {},
        }

        if (new_squares[idx_to] != .empty) return error.SquareOccupied;

        new_squares[idx_to] = new_squares[idx_from];
        new_squares[idx_from] = .empty;
        return new_squares;
    }

    /// Update the position of a piece in the relevant array after it has been moved.
    /// Will crash if `self.squares[new_idx]` is `.empty` or `.gold`; if those were moved, our data invariants
    /// are already broken and can't be reconciled.
    fn update_piece_position(self: *Board, old_idx: u8, new_idx: u8) void {
        const content = self.squares[new_idx];
        switch (content) {
            .white => {
                for (0..self.white_count) |i| {
                    if (self.white_pieces[i] == old_idx) {
                        self.white_pieces[i] = new_idx;
                    }
                }
            },
            .black => {
                for (0..self.black_count) |i| {
                    if (self.black_pieces[i] == old_idx) {
                        self.black_pieces[i] = new_idx;
                    }
                }
            },
            .gold, .empty => unreachable,
        }
    }

    /// Move a single piece from one position to another. This is a low-level
    /// function that only checks for data invariants, not game rules.
    pub fn move_single_piece(self: *Board, from: Position, to: Position) !void {
        const idx_from = index(from);
        const idx_to = index(to);

        // Update squares array
        self.squares = try Board.move_piece(self.squares, idx_from, idx_to);

        // Update piece position in the relevant lookup array
        self.update_piece_position(idx_from, idx_to);
    }

    /// Try to move all pieces at the given start positions in the specified direction and distance.
    /// This only checks for data invariants, not game rules.
    /// The positions must be provided in the order the pieces will be moved in, so the pieces at the
    /// front of the pushed block must come first and the rear pieces of the moving block last.
    fn move_many_pieces(squares: Squares, start_positions: []Position, direction: Direction, distance: u4) !Squares {
        var working_squares = squares;
        for (0..start_positions.len) |i| {
            const pos = start_positions[i];
            const target_pos = move_position(pos, direction, distance);
            working_squares = try Board.move_piece(working_squares, index(pos), index(target_pos));
        }
        return working_squares;
    }

    pub fn move_blocks(self: *Board, moved_block: Block, pushed_block: ?Block, direction: Direction, distance: u4) !void {
        // The absolute maximum number of positions we might need to move is 16+12=28,
        // because the biggest block is 4x4=16 and the biggest block it can push is 3x4=12.
        var start_positions_buffer: [4 * 4 + 3 * 4]Position = undefined;
        var working_squares = self.squares;

        // Determine start positions of pushed block first so it gets moved out of the way
        const start_positions_pushed = if (pushed_block) |pb|
            pb.to_list(&start_positions_buffer, direction)
        else
            start_positions_buffer[0..0];

        // Determine start positions of moved block
        const remaining_buffer = start_positions_buffer[start_positions_pushed.len..];
        const start_positions_moved = moved_block.to_list(remaining_buffer, direction);

        // Combine both slices and move all pieces
        const start_positions = start_positions_buffer[0..(start_positions_pushed.len + start_positions_moved.len)];
        working_squares = try Board.move_many_pieces(working_squares, start_positions, direction, distance);

        // Commit the changes to self.squares and update piece positions in lookup arrays
        self.squares = working_squares;
        for (0..start_positions.len) |i| {
            const pos = start_positions[i];
            const target_pos = move_position(pos, direction, distance);
            self.update_piece_position(index(pos), index(target_pos));
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

test "block to_list" {
    const block = Block.init(.{ .B, ._2 }, .{ .D, ._4 });
    var buffer: [9]Position = undefined;
    const positions = block.to_list(&buffer, .up);
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

    const positions2 = block.to_list(&buffer, .right);
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

    const positions3 = block.to_list(&buffer, .down);
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

    const positions4 = block.to_list(&buffer, .left);
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

test "move blocks" {
    var board: Board = .{};

    try board.place_piece(.white, .{ .B, ._5 });
    try board.place_piece(.white, .{ .C, ._5 });
    try board.place_piece(.black, .{ .E, ._5 });
    try board.place_piece(.black, .{ .F, ._5 });

    const moved_block = Block.init(.{ .B, ._5 }, .{ .C, ._5 });
    const pushed_block = Block.init(.{ .E, ._5 }, .{ .F, ._5 });

    try board.move_blocks(moved_block, pushed_block, .right, 2);

    try expectEqual(.empty, board.get_square(.{ .B, ._5 }));
    try expectEqual(.empty, board.get_square(.{ .C, ._5 }));
    try expectEqual(.white, board.get_square(.{ .D, ._5 }));
    try expectEqual(.white, board.get_square(.{ .E, ._5 }));
    try expectEqual(.black, board.get_square(.{ .G, ._5 }));
    try expectEqual(.black, board.get_square(.{ .H, ._5 }));
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

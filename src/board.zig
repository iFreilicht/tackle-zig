const std = @import("std");

const block = @import("block.zig");
const constants = @import("constants.zig");
const enums = @import("enums.zig");
const move_module = @import("move.zig");
const position = @import("position.zig");

const expectError = std.testing.expectError;
const expectEqual = std.testing.expectEqual;
const expectEqualDeep = std.testing.expectEqualDeep;
const expectEqualSlices = std.testing.expectEqualSlices;

const board_size = constants.board_size;
const max_pieces_per_player = constants.max_pieces_per_player;

const Block = block.Block;
const Move = move_module.Move;
const Direction = enums.Direction;
const PieceColor = enums.PieceColor;
const Player = enums.Player;
const SquareContent = enums.SquareContent;
const Corner = position.Corner;
const Position = position.Position;

const validate_color = enums.validate_color;
const validate_color_when_placing = enums.validate_color_when_placing;
const move_position = position.move_position;
const move_position_if_possible = position.move_position_if_possible;
const is_on_border = position.is_on_border;

/// Representation of the game board and the pieces on it.
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

    pub fn index(pos: Position) u8 {
        const col, const row = pos;
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
    fn move_single_piece(self: *Board, from: Position, to: Position) !void {
        const idx_from = index(from);
        const idx_to = index(to);

        // Update squares array
        self.squares = try Board.move_piece(self.squares, idx_from, idx_to);

        // Update piece position in the relevant lookup array
        self.update_piece_position(idx_from, idx_to);
    }

    /// Try to move all pieces at the given start positions in the specified direction and distance.
    /// This only checks for data invariants, not game rules.
    /// The positions must be provided from rear to front, so the pieces pushing come before the pieces
    /// being pushed. The order perpendicular to the movement direction does not matter.
    fn move_many_pieces(self: *Board, start_positions: []const Position, direction: Direction, distance: u4) !void {
        var working_squares = self.squares;
        // Iterate from front to rear to avoid collisions when moving pieces
        // We expect the caller to provide the positions in order from rear to front
        // because that's the order in which they are discovered when checking for maximum move distances.
        for (0..start_positions.len) |i_reverse| {
            const i = start_positions.len - 1 - i_reverse;
            const pos = start_positions[i];
            const target_pos = move_position(pos, direction, distance);
            working_squares = try Board.move_piece(working_squares, index(pos), index(target_pos));
        }

        // Commit the changes to self.squares and update piece positions in lookup arrays
        self.squares = working_squares;
        for (0..start_positions.len) |i| {
            const pos = start_positions[i];
            const target_pos = move_position(pos, direction, distance);
            self.update_piece_position(index(pos), index(target_pos));
        }
    }

    /// A list that describes how far one column or row shall or can move in a certain direction
    /// before being blocked by an opponent's piece or gold piece, the length of that block in
    /// the movement direction and the position of all pieces that would need to be moved in order to
    /// perform that move.
    /// A move of a block with a height or width greater than 1 consists of multiple such move lists.
    const MoveList = struct {
        distance: u4,
        /// This is also called "block strength" in the game rules
        block_length: u4,
        positions: []const Position,
    };

    /// Get the `MoveList` representing the longest legal move from the start position in the specified direction,
    /// considering all game rules about blocks, piece colors, and pushing opponent pieces.
    /// It is guaranteed that the returned `MoveList` contains valid input for `move_many_pieces` and that
    /// performing that move will not violate any game rules.
    fn get_max_move_list(self: *const Board, start: Position, direction: Direction, position_buffer: []Position) MoveList {
        var distance: u4 = 0;
        var current_pos = start;
        const EMPTY = MoveList{ .distance = 0, .block_length = 0, .positions = position_buffer[0..0] };

        const start_content = self.squares[index(current_pos)];
        const start_color: PieceColor = switch (start_content) {
            .white => .white,
            .black => .black,
            .gold => return EMPTY,
            .empty => return EMPTY,
        };
        const opponent_color: PieceColor = if (start_color == .white) .black else .white;

        const _Phase = enum { own, opponent, empty };
        var phase: _Phase = .own;
        var block_strength: u4 = 1; // A block could be 9 pieces long, so u3 is not enough
        var opponent_block_strength: u4 = 0;
        var pos_index: usize = 1;
        position_buffer[0] = start;

        while (true) {
            current_pos = move_position_if_possible(current_pos, direction, 1) orelse break;
            const idx = index(current_pos);
            if (idx >= self.squares.len) break;
            const content = self.squares[idx];

            check_content: switch (phase) {
                .own => {
                    if (SquareContent.from_color(start_color) == content) {
                        block_strength += 1;
                        position_buffer[pos_index] = current_pos;
                        pos_index += 1;
                    } else {
                        phase = .opponent;
                        continue :check_content phase;
                    }
                },
                .opponent => {
                    if (SquareContent.from_color(opponent_color) == content) {
                        opponent_block_strength += 1;
                        if (opponent_block_strength >= block_strength) return EMPTY;
                        position_buffer[pos_index] = current_pos;
                        pos_index += 1;
                    } else if (content == .empty) {
                        phase = .empty;
                        continue :check_content phase;
                    } else {
                        // Ran into own piece or gold piece
                        return EMPTY;
                    }
                },
                .empty => {
                    if (content != .empty) break;
                    distance += 1;
                },
            }
        }

        return .{
            .distance = distance,
            .block_length = block_strength,
            .positions = position_buffer[0..pos_index],
        };
    }

    pub fn get_square(self: *const Board, at: Position) SquareContent {
        const idx = index(at);
        return self.squares[idx];
    }

    pub fn is_square_empty(self: *const Board, at: Position) bool {
        return self.get_square(at) == .empty;
    }

    /// Move a piece according to the specified move, checking for
    /// violations of game rules.
    pub fn execute_move(board: *Board, player: Player, move: Move) !void {
        switch (move) {
            .diagonal => |d| {
                const start = d.start();
                const content = board.get_square(start);
                try validate_color(player, content);

                const positions = d.from.to_list();
                for (0..d.distance) |i| {
                    const pos = positions[i];
                    if (!board.is_square_empty(pos)) return error.PathBlocked;
                }

                const end = d.end();
                try board.move_single_piece(start, end);
            },
            inline .horizontal, .vertical => |m| {
                const start = m.start();
                const content = board.get_square(start);
                try validate_color(player, content);

                const direction = m.direction();
                const distance = m.distance();

                const block_rear_edge = Block.init(m.start(), m.start_block_end());
                var rear_position_buffer: [4]Position = undefined;
                const positions = block_rear_edge.to_list(&rear_position_buffer, direction);

                // The absolute maximum number of positions we might need to move is 16+12=28,
                // because the biggest block is 4x4=16 and the biggest block it can push is 3x4=12.
                var start_positions_buffer: [4 * 4 + 3 * 4]Position = undefined;
                var pos_index: usize = 0;
                var block_length: u4 = 0;
                for (positions) |pos| {
                    const move_list = board.get_max_move_list(
                        pos,
                        direction,
                        start_positions_buffer[pos_index..],
                    );
                    if (distance > move_list.distance) return error.PathBlocked;
                    pos_index += move_list.positions.len;
                    if (block_length == 0) {
                        block_length = move_list.block_length;
                    } else if (block_length != move_list.block_length) {
                        // The block must be rectangular, so all move lists must have the same block strength
                        return error.InvalidBlockShape;
                    }
                }

                if (block_length < m.block_breadth()) {
                    return error.BlockCannotMoveSideways;
                }

                // TODO: Implement worm moves

                try board.move_many_pieces(start_positions_buffer[0..pos_index], direction, distance);
            },
        }
    }
};

/// Check whether the board has exactly the specified pieces in the specified positions.
/// Also checks that the internal data invariants are upheld.
/// This function is mostly useful for testing.
pub fn expectBoardContent(board: *const Board, white_pieces: []const Position, black_pieces: []const Position, gold_piece: ?Position) !void {
    // Fail fast if counts don't match
    if (board.white_count != white_pieces.len) return error.WhiteCountDiffers;
    if (board.black_count != black_pieces.len) return error.BlackCountDiffers;

    // Check whether all pieces are in the expected positions
    for (white_pieces) |pos| {
        if (board.get_square(pos) != .white) return error.SquareDoesNotContainWhitePiece;
    }

    for (black_pieces) |pos| {
        if (board.get_square(pos) != .black) return error.SquareDoesNotContainBlackPiece;
    }

    if (gold_piece) |gp| {
        if (board.get_square(gp) != .gold) return error.SquareDoesNotContainGoldPiece;
    }

    // Ensure that the data invariants are upheld
    var white_count: u8 = 0;
    var white_positions: [board_size * board_size]u8 = undefined;
    var black_count: u8 = 0;
    var black_positions: [board_size * board_size]u8 = undefined;
    var gold_count: u8 = 0;
    var gold_positions: [board_size * board_size]u8 = undefined;
    for (board.squares, 0..) |content, idx| {
        switch (content) {
            .white => {
                white_positions[white_count] = @intCast(idx);
                white_count += 1;
            },
            .black => {
                black_positions[black_count] = @intCast(idx);
                black_count += 1;
            },
            .gold => {
                gold_positions[gold_count] = @intCast(idx);
                gold_count += 1;
            },
            .empty => {},
        }
    }

    const board_white_pieces = board.white_pieces[0..board.white_count];
    const found_white_pieces = white_positions[0..white_count];
    if (white_count != board.white_count) return error.WhiteCountInvariantBroken;
    for (found_white_pieces) |idx| {
        if (!std.mem.containsAtLeastScalar(u8, board_white_pieces, 1, idx)) {
            return error.WhitePositionsInvariantBroken;
        }
    }
    for (board_white_pieces) |idx| {
        if (!std.mem.containsAtLeastScalar(u8, found_white_pieces, 1, idx)) {
            return error.WhitePositionsInvariantBroken;
        }
    }

    const board_black_pieces = board.black_pieces[0..board.black_count];
    const found_black_pieces = black_positions[0..black_count];
    if (black_count != board.black_count) return error.BlackCountInvariantBroken;
    for (found_black_pieces) |idx| {
        if (!std.mem.containsAtLeastScalar(u8, board_black_pieces, 1, idx)) {
            return error.BlackPositionsInvariantBroken;
        }
    }
    for (board_black_pieces) |idx| {
        if (!std.mem.containsAtLeastScalar(u8, found_black_pieces, 1, idx)) {
            return error.BlackPositionsInvariantBroken;
        }
    }

    if (gold_count > 1) return error.GoldCountInvariantBroken;
    if (gold_count == 1) {
        if (board.gold_piece != gold_positions[0]) return error.GoldPositionInvariantBroken;
    } else {
        if (board.gold_piece != Board.GOLD_EMPTY) return error.GoldPieceNotEmpty;
    }
}

test expectBoardContent {
    var board: Board = .{};

    try board.place_piece(.white, .{ .A, ._1 });
    try board.place_piece(.white, .{ .J, ._2 });
    try board.place_piece(.black, .{ .A, ._4 });
    try board.place_piece(.black, .{ .F, ._3 });
    try board.place_piece(.gold, .{ .E, ._5 });

    const white_positions: [2]Position = .{ .{ .A, ._1 }, .{ .J, ._2 } };
    const black_positions: [2]Position = .{ .{ .A, ._4 }, .{ .F, ._3 } };
    const gold_position: Position = .{ .E, ._5 };

    try expectBoardContent(&board, &white_positions, &black_positions, gold_position);

    // Test for all the errors that can occur. These follow the same order that the
    // expected errors are returned in in the function under test to make it easier
    // to verify that all cases are covered.

    // Remove white piece without breaking invariants
    var broken_board1 = board;
    try broken_board1.remove_piece(.{ .A, ._1 });
    try expectError(
        error.WhiteCountDiffers,
        expectBoardContent(&broken_board1, &white_positions, &black_positions, gold_position),
    );

    // Remove black piece without breaking invariants
    var broken_board2 = board;
    try broken_board2.remove_piece(.{ .F, ._3 });
    try expectError(
        error.BlackCountDiffers,
        expectBoardContent(&broken_board2, &white_positions, &black_positions, gold_position),
    );

    // Move white piece without breaking invariants
    var broken_board3 = board;
    try broken_board3.move_single_piece(.{ .A, ._1 }, .{ .B, ._1 });
    try expectError(
        error.SquareDoesNotContainWhitePiece,
        expectBoardContent(&broken_board3, &white_positions, &black_positions, gold_position),
    );

    // Move black piece without breaking invariants
    var broken_board4 = board;
    try broken_board4.move_single_piece(.{ .F, ._3 }, .{ .F, ._4 });
    try expectError(
        error.SquareDoesNotContainBlackPiece,
        expectBoardContent(&broken_board4, &white_positions, &black_positions, gold_position),
    );

    // Move gold piece without breaking invariants
    var broken_board5 = board;
    broken_board5.squares[Board.index(.{ .E, ._5 })] = .empty;
    broken_board5.squares[Board.index(.{ .E, ._6 })] = .gold;
    broken_board5.gold_piece = Board.index(.{ .E, ._6 });
    try expectError(
        error.SquareDoesNotContainGoldPiece,
        expectBoardContent(&broken_board5, &white_positions, &black_positions, gold_position),
    );

    // Add white piece so the count is incorrect
    var broken_board6 = board;
    broken_board6.squares[Board.index(.{ .C, ._1 })] = .white;
    try expectError(
        error.WhiteCountInvariantBroken,
        expectBoardContent(&broken_board6, &white_positions, &black_positions, gold_position),
    );

    // Modify white piece positions so it's inconsistent with the squares array
    var broken_board7 = board;
    broken_board7.white_pieces[0] = Board.index(.{ .C, ._1 });
    try expectError(
        error.WhitePositionsInvariantBroken,
        expectBoardContent(&broken_board7, &white_positions, &black_positions, gold_position),
    );

    // Add black piece so the count is incorrect
    var broken_board8 = board;
    broken_board8.squares[Board.index(.{ .G, ._3 })] = .black;
    try expectError(
        error.BlackCountInvariantBroken,
        expectBoardContent(&broken_board8, &white_positions, &black_positions, gold_position),
    );

    // Modify black piece positions so it's inconsistent with the squares array
    var broken_board9 = board;
    broken_board9.black_pieces[0] = Board.index(.{ .G, ._3 });
    try expectError(
        error.BlackPositionsInvariantBroken,
        expectBoardContent(&broken_board9, &white_positions, &black_positions, gold_position),
    );

    // Add second gold piece
    var broken_board10 = board;
    broken_board10.squares[Board.index(.{ .E, ._6 })] = .gold;
    try expectError(
        error.GoldCountInvariantBroken,
        expectBoardContent(&broken_board10, &white_positions, &black_positions, gold_position),
    );

    // Modify gold piece position so it's inconsistent with the gold_piece field
    var broken_board11 = board;
    broken_board11.gold_piece = Board.index(.{ .E, ._6 });
    try expectError(
        error.GoldPositionInvariantBroken,
        expectBoardContent(&broken_board11, &white_positions, &black_positions, gold_position),
    );

    // Remove gold piece from board but not from gold_piece field
    var broken_board12 = board;
    broken_board12.squares[Board.index(.{ .E, ._5 })] = .empty;
    try expectError(
        error.GoldPieceNotEmpty,
        expectBoardContent(&broken_board12, &white_positions, &black_positions, null),
    );
}

test "move many pieces horizontal right" {
    var board: Board = .{};

    try board.place_piece(.white, .{ .B, ._5 });
    try board.place_piece(.white, .{ .C, ._5 });
    try board.place_piece(.black, .{ .E, ._5 });
    try board.place_piece(.black, .{ .F, ._5 });

    const start_positions = [_]Position{
        .{ .B, ._5 },
        .{ .C, ._5 },
        .{ .E, ._5 },
        .{ .F, ._5 },
    };

    try board.move_many_pieces(start_positions[0..4], .right, 2);

    try expectBoardContent(
        &board,
        &.{ .{ .D, ._5 }, .{ .E, ._5 } },
        &.{ .{ .G, ._5 }, .{ .H, ._5 } },
        null,
    );
}

test "move many pieces horizontal left" {
    var board: Board = .{};

    try board.place_piece(.black, .{ .J, ._3 });
    try board.place_piece(.black, .{ .I, ._3 });
    try board.place_piece(.white, .{ .H, ._3 });
    try board.place_piece(.white, .{ .G, ._3 });

    const start_positions = [_]Position{
        .{ .J, ._3 },
        .{ .I, ._3 },
        .{ .H, ._3 },
        .{ .G, ._3 },
    };

    try board.move_many_pieces(start_positions[0..4], .left, 4);

    try expectBoardContent(
        &board,
        &.{ .{ .D, ._3 }, .{ .C, ._3 } },
        &.{ .{ .F, ._3 }, .{ .E, ._3 } },
        null,
    );
}

test "move many pieces vertical up" {
    var board: Board = .{};

    try board.place_piece(.white, .{ .D, ._1 });
    try board.place_piece(.white, .{ .D, ._2 });
    try board.place_piece(.black, .{ .D, ._3 });
    try board.place_piece(.black, .{ .D, ._4 });

    const start_positions = [_]Position{
        .{ .D, ._1 },
        .{ .D, ._2 },
        .{ .D, ._3 },
        .{ .D, ._4 },
    };

    try board.move_many_pieces(start_positions[0..4], .up, 6);

    try expectBoardContent(
        &board,
        &.{ .{ .D, ._7 }, .{ .D, ._8 } },
        &.{ .{ .D, ._9 }, .{ .D, ._10 } },
        null,
    );
}

test "move many pieces vertical down" {
    var board: Board = .{};

    try board.place_piece(.black, .{ .F, ._10 });
    try board.place_piece(.black, .{ .F, ._9 });
    try board.place_piece(.black, .{ .F, ._8 });
    try board.place_piece(.white, .{ .F, ._7 });
    try board.place_piece(.white, .{ .F, ._6 });

    const start_positions = [_]Position{
        .{ .F, ._10 },
        .{ .F, ._9 },
        .{ .F, ._8 },
        .{ .F, ._7 },
        .{ .F, ._6 },
    };

    try board.move_many_pieces(start_positions[0..5], .down, 5);

    try expectBoardContent(
        &board,
        &.{ .{ .F, ._2 }, .{ .F, ._1 } },
        &.{ .{ .F, ._5 }, .{ .F, ._4 }, .{ .F, ._3 } },
        null,
    );
}

test "get max move list single piece up" {
    var board: Board = .{};

    try board.place_piece(.white, .{ .C, ._5 });

    var position_buffer: [1]Position = undefined;
    const move_list = board.get_max_move_list(.{ .C, ._5 }, .up, &position_buffer);
    try expectEqualDeep(Board.MoveList{
        .distance = 5,
        .block_length = 1,
        .positions = &[_]Position{.{ .C, ._5 }},
    }, move_list);
}

test "get max move list pushing opponent down" {
    var board: Board = .{};

    try board.place_piece(.white, .{ .E, ._5 });
    try board.place_piece(.white, .{ .E, ._6 });
    try board.place_piece(.black, .{ .E, ._7 });
    try board.place_piece(.black, .{ .E, ._8 });
    try board.place_piece(.black, .{ .E, ._9 });

    var position_buffer: [5]Position = undefined;
    const move_list = board.get_max_move_list(.{ .E, ._9 }, .down, &position_buffer);
    try expectEqualDeep(Board.MoveList{
        .distance = 4,
        .block_length = 3,
        .positions = &[_]Position{
            .{ .E, ._9 },
            .{ .E, ._8 },
            .{ .E, ._7 },
            .{ .E, ._6 },
            .{ .E, ._5 },
        },
    }, move_list);
}

test "get max move list pushing opponent right blocked by own piece" {
    var board: Board = .{};

    try board.place_piece(.black, .{ .A, ._4 });
    try board.place_piece(.black, .{ .B, ._4 });
    try board.place_piece(.white, .{ .C, ._4 });
    try board.place_piece(.black, .{ .G, ._4 });

    var position_buffer: [3]Position = undefined;
    const move_list = board.get_max_move_list(.{ .A, ._4 }, .right, &position_buffer);
    try expectEqualDeep(Board.MoveList{
        .distance = 3,
        .block_length = 2,
        .positions = &[_]Position{
            .{ .A, ._4 },
            .{ .B, ._4 },
            .{ .C, ._4 },
        },
    }, move_list);
}

test "get max move list pushing opponent left blocked by opponent piece" {
    var board: Board = .{};

    try board.place_piece(.white, .{ .I, ._2 });
    try board.place_piece(.white, .{ .H, ._2 });
    try board.place_piece(.white, .{ .G, ._2 });
    try board.place_piece(.black, .{ .F, ._2 });
    try board.place_piece(.black, .{ .D, ._2 });

    var position_buffer: [4]Position = undefined;
    const move_list = board.get_max_move_list(.{ .I, ._2 }, .left, &position_buffer);
    try expectEqualDeep(Board.MoveList{
        .distance = 1,
        .block_length = 3,
        .positions = &[_]Position{
            .{ .I, ._2 },
            .{ .H, ._2 },
            .{ .G, ._2 },
            .{ .F, ._2 },
        },
    }, move_list);
}

test "get max move list for gold piece and empty square" {
    var board: Board = .{};

    try board.place_piece(.gold, .{ .E, ._5 });

    var position_buffer: [1]Position = undefined;
    const move_list_gold = board.get_max_move_list(.{ .E, ._5 }, .up, &position_buffer);
    const expected_move_list = Board.MoveList{
        .distance = 0,
        .block_length = 0,
        .positions = &[_]Position{},
    };
    try expectEqualDeep(expected_move_list, move_list_gold);

    const move_list_empty = board.get_max_move_list(.{ .A, ._1 }, .right, &position_buffer);
    try expectEqualDeep(expected_move_list, move_list_empty);
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

test "execute move diagonally" {
    var board: Board = .{};

    const top_left_pos = Corner.top_left.to_position();
    try board.place_piece(.white, top_left_pos);
    try board.place_piece(.black, .{ .I, ._8 });

    try expectBoardContent(
        &board,
        &.{top_left_pos},
        &.{.{ .I, ._8 }},
        null,
    );

    const move = Move{ .diagonal = .{
        .from = .top_left,
        .distance = 3,
    } };
    try board.execute_move(.white, move);

    try expectBoardContent(
        &board,
        &.{.{ .D, ._7 }},
        &.{.{ .I, ._8 }},
        null,
    );
}

test "execute move diagonally with obstruction error" {
    var board: Board = .{};

    const bottom_left_pos = Corner.bottom_left.to_position();
    try board.place_piece(.white, bottom_left_pos);
    try board.place_piece(.black, .{ .C, ._3 }); // Obstruction

    const move = Move{ .diagonal = .{
        .from = .bottom_left,
        .distance = 5,
    } };
    try expectError(error.PathBlocked, board.execute_move(.white, move));

    try expectBoardContent(
        &board,
        &.{bottom_left_pos},
        &.{.{ .C, ._3 }},
        null,
    );
}

test "execute move horizontally with 2x3 block pushing 3 irregular pieces" {
    var board: Board = .{};

    try board.place_piece(.white, .{ .B, ._5 });
    try board.place_piece(.white, .{ .B, ._6 });
    try board.place_piece(.white, .{ .C, ._5 });
    try board.place_piece(.white, .{ .C, ._6 });
    try board.place_piece(.white, .{ .D, ._5 });
    try board.place_piece(.white, .{ .D, ._6 });
    try board.place_piece(.black, .{ .E, ._5 });
    try board.place_piece(.black, .{ .E, ._6 });
    try board.place_piece(.black, .{ .F, ._5 });

    const move = Move{ .horizontal = .{
        .from_x = .B,
        .to_x = .E,
        .y = ._5,
        .block_height = ._2,
    } };
    try board.execute_move(.white, move);

    try expectBoardContent(
        &board,
        &.{ .{ .E, ._5 }, .{ .E, ._6 }, .{ .F, ._5 }, .{ .F, ._6 }, .{ .G, ._5 }, .{ .G, ._6 } },
        &.{ .{ .H, ._5 }, .{ .H, ._6 }, .{ .I, ._5 } },
        null,
    );
}

test "execute move horizontally with invalid block shape error" {
    var board: Board = .{};

    try board.place_piece(.white, .{ .B, ._5 });
    try board.place_piece(.white, .{ .B, ._6 });
    try board.place_piece(.white, .{ .C, ._5 });

    const move = Move{ .horizontal = .{
        .from_x = .B,
        .to_x = .D,
        .y = ._5,
        .block_height = ._2,
    } };
    try expectError(
        error.InvalidBlockShape,
        board.execute_move(.white, move),
    );

    try expectBoardContent(
        &board,
        &.{ .{ .B, ._5 }, .{ .B, ._6 }, .{ .C, ._5 } },
        &.{},
        null,
    );
}

test "execute move horizontally with block cannot move sideways error" {
    var board: Board = .{};

    try board.place_piece(.white, .{ .B, ._5 });
    try board.place_piece(.white, .{ .B, ._6 });

    const move = Move{ .horizontal = .{
        .from_x = .B,
        .to_x = .D,
        .y = ._5,
        .block_height = ._2,
    } };
    try expectError(
        error.BlockCannotMoveSideways,
        board.execute_move(.white, move),
    );

    try expectBoardContent(
        &board,
        &.{ .{ .B, ._5 }, .{ .B, ._6 } },
        &.{},
        null,
    );
}

test "execute move vertically with 3x2 block pushing 2 irregular pieces" {
    var board: Board = .{};

    try board.place_piece(.black, .{ .F, ._8 });
    try board.place_piece(.black, .{ .G, ._8 });
    try board.place_piece(.black, .{ .F, ._9 });
    try board.place_piece(.black, .{ .G, ._9 });
    try board.place_piece(.black, .{ .F, ._10 });
    try board.place_piece(.black, .{ .G, ._10 });
    try board.place_piece(.white, .{ .F, ._7 });
    try board.place_piece(.white, .{ .G, ._7 });
    try board.place_piece(.white, .{ .F, ._6 });

    const move = Move{ .vertical = .{
        .from_y = ._10,
        .to_y = ._5,
        .x = .F,
        .block_width = ._2,
    } };
    try board.execute_move(.black, move);

    try expectBoardContent(
        &board,
        &.{ .{ .F, ._2 }, .{ .F, ._1 }, .{ .G, ._2 } },
        &.{ .{ .F, ._5 }, .{ .F, ._4 }, .{ .F, ._3 }, .{ .G, ._5 }, .{ .G, ._4 }, .{ .G, ._3 } },
        null,
    );
}

test "execute move vertically with invalid block shape error" {
    var board: Board = .{};

    try board.place_piece(.black, .{ .H, ._8 });
    try board.place_piece(.black, .{ .H, ._9 });
    try board.place_piece(.black, .{ .I, ._9 });

    const move = Move{ .vertical = .{
        .from_y = ._9,
        .to_y = ._6,
        .x = .H,
        .block_width = ._2,
    } };
    try expectError(
        error.InvalidBlockShape,
        board.execute_move(.black, move),
    );

    try expectBoardContent(
        &board,
        &.{},
        &.{ .{ .H, ._8 }, .{ .H, ._9 }, .{ .I, ._9 } },
        null,
    );
}

test "execute move vertically with block cannot move sideways error" {
    var board: Board = .{};

    try board.place_piece(.black, .{ .D, ._8 });
    try board.place_piece(.black, .{ .E, ._8 });

    const move = Move{ .vertical = .{
        .from_y = ._8,
        .to_y = ._6,
        .x = .D,
        .block_width = ._2,
    } };
    try expectError(
        error.BlockCannotMoveSideways,
        board.execute_move(.black, move),
    );

    try expectBoardContent(
        &board,
        &.{},
        &.{ .{ .D, ._8 }, .{ .E, ._8 } },
        null,
    );
}

//! Representation of the game board and the pieces on it.

const Board = @This();
const std = @import("std");

const tackle = @import("root.zig");

const expectError = std.testing.expectError;
const expectEqual = std.testing.expectEqual;
const expectEqualDeep = std.testing.expectEqualDeep;
const expectEqualSlices = std.testing.expectEqualSlices;

const board_size = tackle.constants.board_size;
const max_pieces_per_player = tackle.constants.max_pieces_per_player;

const Block = tackle.Block;
const Move = tackle.Move;
const Direction = tackle.enums.Direction;
const PieceColor = tackle.enums.PieceColor;
const Player = tackle.enums.Player;
const SquareContent = tackle.enums.SquareContent;
const BlockSize = tackle.position.BlockSize;
const Corner = tackle.position.Corner;
const Position = tackle.position.Position;
const ColumnX = tackle.position.ColumnX;
const RowY = tackle.position.RowY;

const validateColor = tackle.enums.validateColor;
const movePosition = tackle.position.movePosition;
const movePositionIfPossible = tackle.position.movePositionIfPossible;
const isOnBorder = tackle.position.isOnBorder;
const isInCore = tackle.position.isInCore;

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

const Squares = [board_size * board_size]SquareContent;

// Max index is 10*10=100, so we can use a sentinel value to represent the empty state
const GOLD_EMPTY = 0xff;

fn positionFromIndex(idx: u8) Position {
    const col = ColumnX.fromIndex(@intCast(idx / board_size));
    const row = RowY.fromIndex(@intCast(idx % board_size));
    return .{ col, row };
}

pub fn index(pos: Position) u8 {
    const col, const row = pos;
    const x: u8 = col.index();
    const y: u8 = row.index();
    return x * board_size + y;
}

/// Place a piece on the board. This is a low-level function that only checks
/// for data invariants, not game rules.
/// For a game-rule-compliant placement, use `executePlacement` instead.
pub fn placePiece(self: *Board, color: PieceColor, at: Position) !void {
    const idx = index(at);
    if (self.squares[idx] != .empty) return error.SquareOccupied;

    self.squares[idx] = SquareContent.fromColor(color);
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
/// Do not use `removePiece` and `placePiece` to move pieces around!
/// Use `moveSinglePiece` for board logic instead, or use
/// `executeMove` for game-rule-compliant moves.
pub fn removePiece(self: *Board, from: Position) !void {
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
fn movePiece(squares: Squares, idx_from: u8, idx_to: u8) !Squares {
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
fn updatePiecePosition(self: *Board, old_idx: u8, new_idx: u8) void {
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
fn moveSinglePiece(self: *Board, from: Position, to: Position) !void {
    const idx_from = index(from);
    const idx_to = index(to);

    // Update squares array
    self.squares = try Board.movePiece(self.squares, idx_from, idx_to);

    // Update piece position in the relevant lookup array
    self.updatePiecePosition(idx_from, idx_to);
}

/// Try to move all pieces at the given start positions in the specified direction and distance.
/// This only checks for data invariants, not game rules.
/// The positions must be provided from rear to front, so the pieces pushing come before the pieces
/// being pushed. The order perpendicular to the movement direction does not matter.
fn moveManyPieces(self: *Board, start_positions: []const Position, direction: Direction, distance: u4) !void {
    var working_squares = self.squares;
    // Iterate from front to rear to avoid collisions when moving pieces
    // We expect the caller to provide the positions in order from rear to front
    // because that's the order in which they are discovered when checking for maximum move distances.
    for (0..start_positions.len) |i_reverse| {
        const i = start_positions.len - 1 - i_reverse;
        const pos = start_positions[i];
        const target_pos = movePosition(pos, direction, distance);
        working_squares = try Board.movePiece(working_squares, index(pos), index(target_pos));
    }

    // Commit the changes to self.squares and update piece positions in lookup arrays
    self.squares = working_squares;
    for (0..start_positions.len) |i| {
        const pos = start_positions[i];
        const target_pos = movePosition(pos, direction, distance);
        self.updatePiecePosition(index(pos), index(target_pos));
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
    /// Positions of all pieces that would need to be moved in order to perform the move.
    /// The positions are ordered from rear to front in the movement direction, so the piece
    /// that is pushing is guaranteed to be first.
    positions: []const Position,
};

/// Get the `MoveList` representing the longest legal move from the start position in the specified direction,
/// considering all game rules about blocks, piece colors, and pushing opponent pieces.
/// It is guaranteed that the returned `MoveList` contains valid input for `moveManyPieces` and that
/// performing that move will not violate any game rules.
/// It is guaranteed that no more than 10 elements will be written to `position_buffer`.
fn getMaxMoveList(self: Board, start: Position, direction: Direction, position_buffer: []Position) MoveList {
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
        current_pos = movePositionIfPossible(current_pos, direction, 1) orelse break;
        const idx = index(current_pos);
        if (idx >= self.squares.len) break;
        const content = self.squares[idx];

        check_content: switch (phase) {
            .own => {
                if (SquareContent.fromColor(start_color) == content) {
                    block_strength += 1;
                    position_buffer[pos_index] = current_pos;
                    pos_index += 1;
                } else {
                    phase = .opponent;
                    continue :check_content phase;
                }
            },
            .opponent => {
                if (SquareContent.fromColor(opponent_color) == content) {
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

pub fn getSquare(self: Board, at: Position) SquareContent {
    const idx = index(at);
    return self.squares[idx];
}

pub fn isSquareEmpty(self: Board, at: Position) bool {
    return self.getSquare(at) == .empty;
}

/// Place a piece at the specified position, checking for violations of game rules.
pub fn executePlacement(self: *Board, color: PieceColor, at: Position) !void {
    switch (color) {
        .white, .black => {
            if (!isOnBorder(at)) return error.PieceNotOnBorder;
            const c = SquareContent.fromColor(color);

            // Check neighboring squares for same-color pieces
            if (at.@"0" == .A or at.@"0" == .J) {
                const up_pos = movePositionIfPossible(at, .up, 1);
                const down_pos = movePositionIfPossible(at, .down, 1);
                if (up_pos) |p| {
                    if (self.getSquare(p) == c) return error.PieceBlockedByUpperNeighbor;
                }
                if (down_pos) |p| {
                    if (self.getSquare(p) == c) return error.PieceBlockedByLowerNeighbor;
                }
            }
            if (at.@"1" == ._1 or at.@"1" == ._10) {
                const left_pos = movePositionIfPossible(at, .left, 1);
                const right_pos = movePositionIfPossible(at, .right, 1);
                if (left_pos) |p| {
                    if (self.getSquare(p) == c) return error.PieceBlockedByLeftNeighbor;
                }
                if (right_pos) |p| {
                    if (self.getSquare(p) == c) return error.PieceBlockedByRightNeighbor;
                }
            }
        },
        .gold => {
            if (!isInCore(at)) return error.GoldPieceNotInCore;
            if (self.gold_piece != Board.GOLD_EMPTY) return error.GoldPieceAlreadyPlaced;
        },
    }

    try self.placePiece(color, at);
}

/// Move a piece according to the specified move, checking for
/// violations of game rules.
pub fn executeMove(self: *Board, player: Player, move: Move) !void {
    switch (move) {
        .diagonal => |d| {
            const start = d.start();
            const content = self.getSquare(start);
            try validateColor(player, content);

            const positions = d.from.toList();
            for (0..d.distance) |i| {
                const pos = positions[i];
                if (!self.isSquareEmpty(pos)) return error.PathBlocked;
            }

            const end = d.end();
            try self.moveSinglePiece(start, end);
        },
        inline .horizontal, .vertical => |m| {
            const start = m.start();
            const content = self.getSquare(start);
            try validateColor(player, content);

            const direction = m.direction();
            const distance = m.distance();

            const block_rear_edge = Block.init(m.start(), m.startBlockEnd());
            var rear_position_buffer: [4]Position = undefined;
            const rear_edge_positions = block_rear_edge.toList(&rear_position_buffer, direction);

            // The absolute maximum number of positions we might need to move is 16+12=28,
            // because the biggest block is 4x4=16 and the biggest block it can push is 3x4=12.
            var start_positions_buffer: [4 * 4 + 3 * 4]Position = undefined;
            var pos_index: usize = 0;
            var block_length: u4 = 0;
            for (rear_edge_positions) |pos| {
                const move_list = self.getMaxMoveList(
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

            if (block_length < m.blockBreadth()) {
                return error.BlockCannotMoveSideways;
            }

            // TODO: Implement worm moves

            try self.moveManyPieces(start_positions_buffer[0..pos_index], direction, distance);
        },
    }
}

pub const MoveIterator = struct {
    board: Board,
    player: Player,
    piece_indices: [max_pieces_per_player]u8,
    current_piece_indices_index: usize = 0,
    current_direction: Direction = .up,

    current_start_position: ?Position = null,
    current_block_breadth: BlockSize = .no_block,
    current_maximum_distance: u4 = 0,
    current_distance: u4 = 1,

    fn setNextDirectionAndPiece(self: *MoveIterator) void {
        self.current_direction = switch (self.current_direction) {
            .up => .down,
            .down => .right,
            .right => .left,
            .left => .up,
        };
        if (self.current_direction == .up) self.current_piece_indices_index += 1;
    }

    fn getCurrentPieceIndex(self: *MoveIterator) ?u8 {
        if (self.current_piece_indices_index >= self.piece_indices.len) return null;
        return self.piece_indices[self.current_piece_indices_index];
    }

    fn setNextMaximumMoveProperties(self: *MoveIterator) !void {
        // This data will be thrown away before returning, so we can safely allocate it on the stack
        var positions_buffer: [10]Position = undefined;

        // TODO: Logic that detects if diagonal moves from the corners are possible and handles them accordingly
        // Right now, only horizontal and vertical moves are handled
        const next_move_list = while (true) {
            const piece_idx = self.getCurrentPieceIndex() orelse break null;
            const start_pos = Board.positionFromIndex(piece_idx);

            // TODO: Logic that detects if block moves with a breadth of 2 or more are possible and handles them accordingly
            // Right now, we only handle block moves with a breadth of 1, i.e. `BlockSize.no_block`
            const ml = self.board.getMaxMoveList(
                start_pos,
                self.current_direction,
                &positions_buffer,
            );
            if (ml.positions.len == 0) {
                self.setNextDirectionAndPiece();
                continue;
            }
            break ml;
        };

        self.current_distance = 1;
        self.current_block_breadth = .no_block;
        if (next_move_list) |ml| {
            self.current_start_position = ml.positions[0];
            self.current_maximum_distance = ml.distance;
        } else {
            self.current_start_position = null;
            self.current_maximum_distance = 0;
        }
    }

    pub fn next(self: *MoveIterator) !?Move {
        // Check if iteration has finished
        if (self.current_piece_indices_index >= self.piece_indices.len) return null;

        if (self.current_start_position == null) {
            // Search for first move
            try self.setNextMaximumMoveProperties();
        } else if (self.current_distance > self.current_maximum_distance) {
            // Move to next possible move
            self.setNextDirectionAndPiece();
            try self.setNextMaximumMoveProperties();
        }
        if (self.current_start_position == null) {
            // No more moves available
            return null;
        }

        const start_pos = self.current_start_position.?;
        const target_pos = movePosition(start_pos, self.current_direction, self.current_distance);
        const move: Move = switch (self.current_direction) {
            .up, .down => .{ .vertical = .{
                .from_y = start_pos.@"1",
                .to_y = target_pos.@"1",
                .x = start_pos.@"0",
                .block_width = .no_block,
            } },
            .left, .right => .{ .horizontal = .{
                .from_x = start_pos.@"0",
                .to_x = target_pos.@"0",
                .y = start_pos.@"1",
                .block_height = .no_block,
            } },
        };

        // Return current move and increment distance for next call
        self.current_distance += 1;
        return move;
    }
};

/// Return an iterator over all possible moves for the specified player in the current board state.
pub fn getPossibleMoves(self: Board, player: Player) !MoveIterator {
    const piece_indices = switch (player) {
        .white => self.white_pieces,
        .black => self.black_pieces,
    };

    return MoveIterator{
        .board = self,
        .player = player,
        .piece_indices = piece_indices,
    };
}

/// Check whether the board has exactly the specified pieces in the specified positions.
/// Also checks that the internal data invariants are upheld.
/// This function is mostly useful for testing.
pub fn expectContent(board: Board, white_pieces: []const Position, black_pieces: []const Position, gold_piece: ?Position) !void {
    // Fail fast if counts don't match
    if (board.white_count != white_pieces.len) return error.WhiteCountDiffers;
    if (board.black_count != black_pieces.len) return error.BlackCountDiffers;

    // Check whether all pieces are in the expected positions
    for (white_pieces) |pos| {
        if (board.getSquare(pos) != .white) return error.SquareDoesNotContainWhitePiece;
    }

    for (black_pieces) |pos| {
        if (board.getSquare(pos) != .black) return error.SquareDoesNotContainBlackPiece;
    }

    if (gold_piece) |gp| {
        if (board.getSquare(gp) != .gold) return error.SquareDoesNotContainGoldPiece;
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

test expectContent {
    var board: Board = .{};

    try board.placePiece(.white, .{ .A, ._1 });
    try board.placePiece(.white, .{ .J, ._2 });
    try board.placePiece(.black, .{ .A, ._4 });
    try board.placePiece(.black, .{ .F, ._3 });
    try board.placePiece(.gold, .{ .E, ._5 });

    const white_positions: [2]Position = .{ .{ .A, ._1 }, .{ .J, ._2 } };
    const black_positions: [2]Position = .{ .{ .A, ._4 }, .{ .F, ._3 } };
    const gold_position: Position = .{ .E, ._5 };

    try expectContent(board, &white_positions, &black_positions, gold_position);

    // Test for all the errors that can occur. These follow the same order that the
    // expected errors are returned in in the function under test to make it easier
    // to verify that all cases are covered.

    // Remove white piece without breaking invariants
    var broken_board1 = board;
    try broken_board1.removePiece(.{ .A, ._1 });
    try expectError(
        error.WhiteCountDiffers,
        expectContent(broken_board1, &white_positions, &black_positions, gold_position),
    );

    // Remove black piece without breaking invariants
    var broken_board2 = board;
    try broken_board2.removePiece(.{ .F, ._3 });
    try expectError(
        error.BlackCountDiffers,
        expectContent(broken_board2, &white_positions, &black_positions, gold_position),
    );

    // Move white piece without breaking invariants
    var broken_board3 = board;
    try broken_board3.moveSinglePiece(.{ .A, ._1 }, .{ .B, ._1 });
    try expectError(
        error.SquareDoesNotContainWhitePiece,
        expectContent(broken_board3, &white_positions, &black_positions, gold_position),
    );

    // Move black piece without breaking invariants
    var broken_board4 = board;
    try broken_board4.moveSinglePiece(.{ .F, ._3 }, .{ .F, ._4 });
    try expectError(
        error.SquareDoesNotContainBlackPiece,
        expectContent(broken_board4, &white_positions, &black_positions, gold_position),
    );

    // Move gold piece without breaking invariants
    var broken_board5 = board;
    broken_board5.squares[Board.index(.{ .E, ._5 })] = .empty;
    broken_board5.squares[Board.index(.{ .E, ._6 })] = .gold;
    broken_board5.gold_piece = Board.index(.{ .E, ._6 });
    try expectError(
        error.SquareDoesNotContainGoldPiece,
        expectContent(broken_board5, &white_positions, &black_positions, gold_position),
    );

    // Add white piece so the count is incorrect
    var broken_board6 = board;
    broken_board6.squares[Board.index(.{ .C, ._1 })] = .white;
    try expectError(
        error.WhiteCountInvariantBroken,
        expectContent(broken_board6, &white_positions, &black_positions, gold_position),
    );

    // Modify white piece positions so it's inconsistent with the squares array
    var broken_board7 = board;
    broken_board7.white_pieces[0] = Board.index(.{ .C, ._1 });
    try expectError(
        error.WhitePositionsInvariantBroken,
        expectContent(broken_board7, &white_positions, &black_positions, gold_position),
    );

    // Add black piece so the count is incorrect
    var broken_board8 = board;
    broken_board8.squares[Board.index(.{ .G, ._3 })] = .black;
    try expectError(
        error.BlackCountInvariantBroken,
        expectContent(broken_board8, &white_positions, &black_positions, gold_position),
    );

    // Modify black piece positions so it's inconsistent with the squares array
    var broken_board9 = board;
    broken_board9.black_pieces[0] = Board.index(.{ .G, ._3 });
    try expectError(
        error.BlackPositionsInvariantBroken,
        expectContent(broken_board9, &white_positions, &black_positions, gold_position),
    );

    // Add second gold piece
    var broken_board10 = board;
    broken_board10.squares[Board.index(.{ .E, ._6 })] = .gold;
    try expectError(
        error.GoldCountInvariantBroken,
        expectContent(broken_board10, &white_positions, &black_positions, gold_position),
    );

    // Modify gold piece position so it's inconsistent with the gold_piece field
    var broken_board11 = board;
    broken_board11.gold_piece = Board.index(.{ .E, ._6 });
    try expectError(
        error.GoldPositionInvariantBroken,
        expectContent(broken_board11, &white_positions, &black_positions, gold_position),
    );

    // Remove gold piece from board but not from gold_piece field
    var broken_board12 = board;
    broken_board12.squares[Board.index(.{ .E, ._5 })] = .empty;
    try expectError(
        error.GoldPieceNotEmpty,
        expectContent(broken_board12, &white_positions, &black_positions, null),
    );
}

test "move many pieces horizontal right" {
    var board: Board = .{};

    try board.placePiece(.white, .{ .B, ._5 });
    try board.placePiece(.white, .{ .C, ._5 });
    try board.placePiece(.black, .{ .E, ._5 });
    try board.placePiece(.black, .{ .F, ._5 });

    const start_positions = [_]Position{
        .{ .B, ._5 },
        .{ .C, ._5 },
        .{ .E, ._5 },
        .{ .F, ._5 },
    };

    try board.moveManyPieces(start_positions[0..4], .right, 2);

    try expectContent(
        board,
        &.{ .{ .D, ._5 }, .{ .E, ._5 } },
        &.{ .{ .G, ._5 }, .{ .H, ._5 } },
        null,
    );
}

test "move many pieces horizontal left" {
    var board: Board = .{};

    try board.placePiece(.black, .{ .J, ._3 });
    try board.placePiece(.black, .{ .I, ._3 });
    try board.placePiece(.white, .{ .H, ._3 });
    try board.placePiece(.white, .{ .G, ._3 });

    const start_positions = [_]Position{
        .{ .J, ._3 },
        .{ .I, ._3 },
        .{ .H, ._3 },
        .{ .G, ._3 },
    };

    try board.moveManyPieces(start_positions[0..4], .left, 4);

    try expectContent(
        board,
        &.{ .{ .D, ._3 }, .{ .C, ._3 } },
        &.{ .{ .F, ._3 }, .{ .E, ._3 } },
        null,
    );
}

test "move many pieces vertical up" {
    var board: Board = .{};

    try board.placePiece(.white, .{ .D, ._1 });
    try board.placePiece(.white, .{ .D, ._2 });
    try board.placePiece(.black, .{ .D, ._3 });
    try board.placePiece(.black, .{ .D, ._4 });

    const start_positions = [_]Position{
        .{ .D, ._1 },
        .{ .D, ._2 },
        .{ .D, ._3 },
        .{ .D, ._4 },
    };

    try board.moveManyPieces(start_positions[0..4], .up, 6);

    try expectContent(
        board,
        &.{ .{ .D, ._7 }, .{ .D, ._8 } },
        &.{ .{ .D, ._9 }, .{ .D, ._10 } },
        null,
    );
}

test "move many pieces vertical down" {
    var board: Board = .{};

    try board.placePiece(.black, .{ .F, ._10 });
    try board.placePiece(.black, .{ .F, ._9 });
    try board.placePiece(.black, .{ .F, ._8 });
    try board.placePiece(.white, .{ .F, ._7 });
    try board.placePiece(.white, .{ .F, ._6 });

    const start_positions = [_]Position{
        .{ .F, ._10 },
        .{ .F, ._9 },
        .{ .F, ._8 },
        .{ .F, ._7 },
        .{ .F, ._6 },
    };

    try board.moveManyPieces(start_positions[0..5], .down, 5);

    try expectContent(
        board,
        &.{ .{ .F, ._2 }, .{ .F, ._1 } },
        &.{ .{ .F, ._5 }, .{ .F, ._4 }, .{ .F, ._3 } },
        null,
    );
}

test "get max move list single piece up" {
    var board: Board = .{};

    try board.placePiece(.white, .{ .C, ._5 });

    var position_buffer: [1]Position = undefined;
    const move_list = board.getMaxMoveList(.{ .C, ._5 }, .up, &position_buffer);
    try expectEqualDeep(Board.MoveList{
        .distance = 5,
        .block_length = 1,
        .positions = &[_]Position{.{ .C, ._5 }},
    }, move_list);
}

test "get max move list pushing opponent down" {
    var board: Board = .{};

    try board.placePiece(.white, .{ .E, ._5 });
    try board.placePiece(.white, .{ .E, ._6 });
    try board.placePiece(.black, .{ .E, ._7 });
    try board.placePiece(.black, .{ .E, ._8 });
    try board.placePiece(.black, .{ .E, ._9 });

    var position_buffer: [5]Position = undefined;
    const move_list = board.getMaxMoveList(.{ .E, ._9 }, .down, &position_buffer);
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

    try board.placePiece(.black, .{ .A, ._4 });
    try board.placePiece(.black, .{ .B, ._4 });
    try board.placePiece(.white, .{ .C, ._4 });
    try board.placePiece(.black, .{ .G, ._4 });

    var position_buffer: [3]Position = undefined;
    const move_list = board.getMaxMoveList(.{ .A, ._4 }, .right, &position_buffer);
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

    try board.placePiece(.white, .{ .I, ._2 });
    try board.placePiece(.white, .{ .H, ._2 });
    try board.placePiece(.white, .{ .G, ._2 });
    try board.placePiece(.black, .{ .F, ._2 });
    try board.placePiece(.black, .{ .D, ._2 });

    var position_buffer: [4]Position = undefined;
    const move_list = board.getMaxMoveList(.{ .I, ._2 }, .left, &position_buffer);
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

    try board.placePiece(.gold, .{ .E, ._5 });

    var position_buffer: [1]Position = undefined;
    const move_list_gold = board.getMaxMoveList(.{ .E, ._5 }, .up, &position_buffer);
    const expected_move_list = Board.MoveList{
        .distance = 0,
        .block_length = 0,
        .positions = &[_]Position{},
    };
    try expectEqualDeep(expected_move_list, move_list_gold);

    const move_list_empty = board.getMaxMoveList(.{ .A, ._1 }, .right, &position_buffer);
    try expectEqualDeep(expected_move_list, move_list_empty);
}

test "place pieces" {
    var board: Board = .{};

    try board.placePiece(.white, .{ .B, ._5 });
    try board.placePiece(.white, .{ .C, ._4 });
    try board.placePiece(.black, .{ .H, ._6 });
    try board.placePiece(.gold, .{ .E, ._5 });

    try expectEqualSlices(u8, &[_]u8{ 14, 23 }, board.white_pieces[0..2]);
    try expectEqualSlices(u8, &[_]u8{75}, board.black_pieces[0..1]);
    try expectEqual(2, board.white_count);
    try expectEqual(1, board.black_count);
    try expectEqual(44, board.gold_piece);
    try expectEqual(.white, board.getSquare(.{ .B, ._5 }));
    try expectEqual(.black, board.getSquare(.{ .H, ._6 }));
    try expectEqual(.gold, board.getSquare(.{ .E, ._5 }));
}

test "place piece errors" {
    var board: Board = .{};

    try board.placePiece(.white, .{ .B, ._5 });
    try expectError(error.SquareOccupied, board.placePiece(.black, .{ .B, ._5 }));

    try board.placePiece(.gold, .{ .E, ._5 });
    try expectError(error.GoldPieceAlreadyPlaced, board.placePiece(.gold, .{ .F, ._6 }));
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

    try board.placePiece(.white, .{ .B, ._5 });
    try board.placePiece(.black, .{ .I, ._8 });
    try board.placePiece(.black, .{ .J, ._10 });
    try expectEqual(.white, board.getSquare(.{ .B, ._5 }));
    try expectEqual(.black, board.getSquare(.{ .I, ._8 }));
    try expectEqual(.black, board.getSquare(.{ .J, ._10 }));
    try expectEqualSlices(u8, &[_]u8{14}, board.white_pieces[0..1]);
    try expectEqualSlices(u8, &[_]u8{ 87, 99 }, board.black_pieces[0..2]);

    try board.moveSinglePiece(.{ .B, ._5 }, .{ .B, ._7 });
    try expectEqual(.empty, board.getSquare(.{ .B, ._5 }));
    try expectEqual(.white, board.getSquare(.{ .B, ._7 }));
    try expectEqualSlices(u8, &[_]u8{16}, board.white_pieces[0..1]);
    try expectEqualSlices(u8, &[_]u8{ 87, 99 }, board.black_pieces[0..2]);

    try board.moveSinglePiece(.{ .I, ._8 }, .{ .C, ._8 });
    try expectEqual(.empty, board.getSquare(.{ .I, ._8 }));
    try expectEqual(.black, board.getSquare(.{ .C, ._8 }));
    try expectEqualSlices(u8, &[_]u8{16}, board.white_pieces[0..1]);
    try expectEqualSlices(u8, &[_]u8{ 27, 99 }, board.black_pieces[0..2]);

    try board.moveSinglePiece(.{ .J, ._10 }, .{ .D, ._4 });
    try expectEqual(.empty, board.getSquare(.{ .J, ._10 }));
    try expectEqual(.black, board.getSquare(.{ .D, ._4 }));
    try expectEqualSlices(u8, &[_]u8{16}, board.white_pieces[0..1]);
    try expectEqualSlices(u8, &[_]u8{ 27, 33 }, board.black_pieces[0..2]);
}

test "move single piece errors" {
    var board: Board = .{};

    try board.placePiece(.white, .{ .B, ._5 });
    try board.placePiece(.white, .{ .E, ._5 });
    try board.placePiece(.white, .{ .B, ._6 });
    try expectEqual(.white, board.getSquare(.{ .B, ._5 }));
    try expectEqual(.white, board.getSquare(.{ .E, ._5 }));
    try expectEqual(.white, board.getSquare(.{ .B, ._6 }));
    try expectEqualSlices(u8, &[_]u8{ 14, 44, 15 }, board.white_pieces[0..3]);

    try expectError(error.SquareEmpty, board.moveSinglePiece(.{ .C, ._3 }, .{ .C, ._4 }));
    try expectError(error.SquareOccupied, board.moveSinglePiece(.{ .B, ._5 }, .{ .E, ._5 }));
    try expectError(error.SquareOccupied, board.moveSinglePiece(.{ .B, ._5 }, .{ .B, ._6 }));
    try expectEqual(.white, board.getSquare(.{ .B, ._5 }));
    try expectEqual(.white, board.getSquare(.{ .E, ._5 }));
    try expectEqual(.white, board.getSquare(.{ .B, ._6 }));
    try expectEqualSlices(u8, &[_]u8{ 14, 44, 15 }, board.white_pieces[0..3]);

    try board.placePiece(.gold, .{ .E, ._6 });
    try expectEqual(.gold, board.getSquare(.{ .E, ._6 }));
    try expectEqual(board.gold_piece, 45);
    try expectError(error.MovingGoldNotAllowed, board.moveSinglePiece(.{ .E, ._6 }, .{ .E, ._7 }));
    try expectEqual(.gold, board.getSquare(.{ .E, ._6 }));
    try expectEqual(board.gold_piece, 45);
}

test "execute placement" {
    var board: Board = .{};

    try board.executePlacement(.white, .{ .A, ._1 });
    try board.executePlacement(.black, .{ .J, ._10 });
    try board.executePlacement(.gold, .{ .E, ._5 });

    try expectContent(
        board,
        &.{.{ .A, ._1 }},
        &.{.{ .J, ._10 }},
        .{ .E, ._5 },
    );
}

test "execute placement errors" {
    var board: Board = .{};

    try board.executePlacement(.white, .{ .A, ._1 });
    try expectError(
        error.PieceBlockedByLowerNeighbor,
        board.executePlacement(.white, .{ .A, ._2 }),
    );

    try expectError(
        error.PieceBlockedByLeftNeighbor,
        board.executePlacement(.white, .{ .B, ._1 }),
    );

    try board.executePlacement(.black, .{ .B, ._10 });
    try expectError(
        error.PieceBlockedByRightNeighbor,
        board.executePlacement(.black, .{ .A, ._10 }),
    );

    try board.executePlacement(.white, .{ .J, ._2 });
    try expectError(
        error.PieceBlockedByUpperNeighbor,
        board.executePlacement(.white, .{ .J, ._1 }),
    );

    try board.executePlacement(.gold, .{ .E, ._5 });
    try expectError(
        error.GoldPieceAlreadyPlaced,
        board.executePlacement(.gold, .{ .F, ._5 }),
    );
}

test "execute move diagonally" {
    var board: Board = .{};

    const top_left_pos = Corner.top_left.toPosition();
    try board.placePiece(.white, top_left_pos);
    try board.placePiece(.black, .{ .I, ._8 });

    try expectContent(
        board,
        &.{top_left_pos},
        &.{.{ .I, ._8 }},
        null,
    );

    const move = Move{ .diagonal = .{
        .from = .top_left,
        .distance = 3,
    } };
    try board.executeMove(.white, move);

    try expectContent(
        board,
        &.{.{ .D, ._7 }},
        &.{.{ .I, ._8 }},
        null,
    );
}

test "execute move diagonally with obstruction error" {
    var board: Board = .{};

    const bottom_left_pos = Corner.bottom_left.toPosition();
    try board.placePiece(.white, bottom_left_pos);
    try board.placePiece(.black, .{ .C, ._3 }); // Obstruction

    const move = Move{ .diagonal = .{
        .from = .bottom_left,
        .distance = 5,
    } };
    try expectError(error.PathBlocked, board.executeMove(.white, move));

    try expectContent(
        board,
        &.{bottom_left_pos},
        &.{.{ .C, ._3 }},
        null,
    );
}

test "execute move horizontally with 2x3 block pushing 3 irregular pieces" {
    var board: Board = .{};

    try board.placePiece(.white, .{ .B, ._5 });
    try board.placePiece(.white, .{ .B, ._6 });
    try board.placePiece(.white, .{ .C, ._5 });
    try board.placePiece(.white, .{ .C, ._6 });
    try board.placePiece(.white, .{ .D, ._5 });
    try board.placePiece(.white, .{ .D, ._6 });
    try board.placePiece(.black, .{ .E, ._5 });
    try board.placePiece(.black, .{ .E, ._6 });
    try board.placePiece(.black, .{ .F, ._5 });

    const move = Move{ .horizontal = .{
        .from_x = .B,
        .to_x = .E,
        .y = ._5,
        .block_height = ._2,
    } };
    try board.executeMove(.white, move);

    try expectContent(
        board,
        &.{ .{ .E, ._5 }, .{ .E, ._6 }, .{ .F, ._5 }, .{ .F, ._6 }, .{ .G, ._5 }, .{ .G, ._6 } },
        &.{ .{ .H, ._5 }, .{ .H, ._6 }, .{ .I, ._5 } },
        null,
    );
}

test "execute move horizontally with invalid block shape error" {
    var board: Board = .{};

    try board.placePiece(.white, .{ .B, ._5 });
    try board.placePiece(.white, .{ .B, ._6 });
    try board.placePiece(.white, .{ .C, ._5 });

    const move = Move{ .horizontal = .{
        .from_x = .B,
        .to_x = .D,
        .y = ._5,
        .block_height = ._2,
    } };
    try expectError(
        error.InvalidBlockShape,
        board.executeMove(.white, move),
    );

    try expectContent(
        board,
        &.{ .{ .B, ._5 }, .{ .B, ._6 }, .{ .C, ._5 } },
        &.{},
        null,
    );
}

test "execute move horizontally with block cannot move sideways error" {
    var board: Board = .{};

    try board.placePiece(.white, .{ .B, ._5 });
    try board.placePiece(.white, .{ .B, ._6 });

    const move = Move{ .horizontal = .{
        .from_x = .B,
        .to_x = .D,
        .y = ._5,
        .block_height = ._2,
    } };
    try expectError(
        error.BlockCannotMoveSideways,
        board.executeMove(.white, move),
    );

    try expectContent(
        board,
        &.{ .{ .B, ._5 }, .{ .B, ._6 } },
        &.{},
        null,
    );
}

test "execute move vertically with 3x2 block pushing 2 irregular pieces" {
    var board: Board = .{};

    try board.placePiece(.black, .{ .F, ._8 });
    try board.placePiece(.black, .{ .G, ._8 });
    try board.placePiece(.black, .{ .F, ._9 });
    try board.placePiece(.black, .{ .G, ._9 });
    try board.placePiece(.black, .{ .F, ._10 });
    try board.placePiece(.black, .{ .G, ._10 });
    try board.placePiece(.white, .{ .F, ._7 });
    try board.placePiece(.white, .{ .G, ._7 });
    try board.placePiece(.white, .{ .F, ._6 });

    const move = Move{ .vertical = .{
        .from_y = ._10,
        .to_y = ._5,
        .x = .F,
        .block_width = ._2,
    } };
    try board.executeMove(.black, move);

    try expectContent(
        board,
        &.{ .{ .F, ._2 }, .{ .F, ._1 }, .{ .G, ._2 } },
        &.{ .{ .F, ._5 }, .{ .F, ._4 }, .{ .F, ._3 }, .{ .G, ._5 }, .{ .G, ._4 }, .{ .G, ._3 } },
        null,
    );
}

test "execute move vertically with invalid block shape error" {
    var board: Board = .{};

    try board.placePiece(.black, .{ .H, ._8 });
    try board.placePiece(.black, .{ .H, ._9 });
    try board.placePiece(.black, .{ .I, ._9 });

    const move = Move{ .vertical = .{
        .from_y = ._9,
        .to_y = ._6,
        .x = .H,
        .block_width = ._2,
    } };
    try expectError(
        error.InvalidBlockShape,
        board.executeMove(.black, move),
    );

    try expectContent(
        board,
        &.{},
        &.{ .{ .H, ._8 }, .{ .H, ._9 }, .{ .I, ._9 } },
        null,
    );
}

test "execute move vertically with block cannot move sideways error" {
    var board: Board = .{};

    try board.placePiece(.black, .{ .D, ._8 });
    try board.placePiece(.black, .{ .E, ._8 });

    const move = Move{ .vertical = .{
        .from_y = ._8,
        .to_y = ._6,
        .x = .D,
        .block_width = ._2,
    } };
    try expectError(
        error.BlockCannotMoveSideways,
        board.executeMove(.black, move),
    );

    try expectContent(
        board,
        &.{},
        &.{ .{ .D, ._8 }, .{ .E, ._8 } },
        null,
    );
}

test "getPossibleMoves iterates properly" {
    var board: Board = .{};

    try board.placePiece(.white, .{ .B, ._5 });
    try board.placePiece(.white, .{ .C, ._5 });
    try board.placePiece(.black, .{ .C, ._8 });

    var move_iterator = try board.getPossibleMoves(.white);

    const expected_moves = [_]Move{
        // Moves for white piece at B5
        // Vertical moves up
        .{ .vertical = .{ .from_y = ._5, .to_y = ._6, .x = .B, .block_width = .no_block } },
        .{ .vertical = .{ .from_y = ._5, .to_y = ._7, .x = .B, .block_width = .no_block } },
        .{ .vertical = .{ .from_y = ._5, .to_y = ._8, .x = .B, .block_width = .no_block } },
        .{ .vertical = .{ .from_y = ._5, .to_y = ._9, .x = .B, .block_width = .no_block } },
        .{ .vertical = .{ .from_y = ._5, .to_y = ._10, .x = .B, .block_width = .no_block } },
        // Vertical moves down
        .{ .vertical = .{ .from_y = ._5, .to_y = ._4, .x = .B, .block_width = .no_block } },
        .{ .vertical = .{ .from_y = ._5, .to_y = ._3, .x = .B, .block_width = .no_block } },
        .{ .vertical = .{ .from_y = ._5, .to_y = ._2, .x = .B, .block_width = .no_block } },
        .{ .vertical = .{ .from_y = ._5, .to_y = ._1, .x = .B, .block_width = .no_block } },
        // Horizontal moves right
        .{ .horizontal = .{ .from_x = .B, .to_x = .C, .y = ._5, .block_height = .no_block } },
        .{ .horizontal = .{ .from_x = .B, .to_x = .D, .y = ._5, .block_height = .no_block } },
        .{ .horizontal = .{ .from_x = .B, .to_x = .E, .y = ._5, .block_height = .no_block } },
        .{ .horizontal = .{ .from_x = .B, .to_x = .F, .y = ._5, .block_height = .no_block } },
        .{ .horizontal = .{ .from_x = .B, .to_x = .G, .y = ._5, .block_height = .no_block } },
        .{ .horizontal = .{ .from_x = .B, .to_x = .H, .y = ._5, .block_height = .no_block } },
        .{ .horizontal = .{ .from_x = .B, .to_x = .I, .y = ._5, .block_height = .no_block } },
        // No move to J5 because white piece at C5 is pushed there
        // Horizontal moves left
        .{ .horizontal = .{ .from_x = .B, .to_x = .A, .y = ._5, .block_height = .no_block } },

        // Moves for white piece at C5
        // Vertical moves up
        .{ .vertical = .{ .from_y = ._5, .to_y = ._6, .x = .C, .block_width = .no_block } },
        .{ .vertical = .{ .from_y = ._5, .to_y = ._7, .x = .C, .block_width = .no_block } },
        // No move to C8 or higher because black piece there blocks the way
        // Vertical moves down
        .{ .vertical = .{ .from_y = ._5, .to_y = ._4, .x = .C, .block_width = .no_block } },
        .{ .vertical = .{ .from_y = ._5, .to_y = ._3, .x = .C, .block_width = .no_block } },
        .{ .vertical = .{ .from_y = ._5, .to_y = ._2, .x = .C, .block_width = .no_block } },
        .{ .vertical = .{ .from_y = ._5, .to_y = ._1, .x = .C, .block_width = .no_block } },
        // Horizontal moves right
        .{ .horizontal = .{ .from_x = .C, .to_x = .D, .y = ._5, .block_height = .no_block } },
        .{ .horizontal = .{ .from_x = .C, .to_x = .E, .y = ._5, .block_height = .no_block } },
        .{ .horizontal = .{ .from_x = .C, .to_x = .F, .y = ._5, .block_height = .no_block } },
        .{ .horizontal = .{ .from_x = .C, .to_x = .G, .y = ._5, .block_height = .no_block } },
        .{ .horizontal = .{ .from_x = .C, .to_x = .H, .y = ._5, .block_height = .no_block } },
        .{ .horizontal = .{ .from_x = .C, .to_x = .I, .y = ._5, .block_height = .no_block } },
        .{ .horizontal = .{ .from_x = .C, .to_x = .J, .y = ._5, .block_height = .no_block } },
        // Horizontal moves left
        .{ .horizontal = .{ .from_x = .C, .to_x = .B, .y = ._5, .block_height = .no_block } },
        // No move to A5 because white piece at B5 is pushed there
    };

    var move_index: usize = 0;
    while (try move_iterator.next()) |move| {
        try expectEqualDeep(expected_moves[move_index], move);
        move_index += 1;
    }

    try expectEqual(expected_moves.len, move_index);
}

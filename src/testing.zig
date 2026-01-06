const tackle = @import("root.zig");

const std = @import("std");

const Position = tackle.Position;
const Move = tackle.Move;
const GameState = tackle.GameState;
pub const UserInterface = tackle.UserInterface;

/// A UserInterface implementation that simulates user input for testing purposes.
pub fn simulatedUserInterface(placements: []const Position, moves: []const Move) UserInterface {
    const ui = struct {
        var pieces_placed: usize = 0;
        var moves_executed: usize = 0;

        pub const interface: UserInterface = .{
            .getNextPlacement = getNextPlacement,
            .getNextMove = getNextMove,
            .render = render,
        };

        pub fn getNextPlacement() anyerror!Position {
            if (pieces_placed >= placements.len) {
                return error.NoMorePlacements;
            }
            const next_placement = placements[pieces_placed];
            pieces_placed += 1;
            return next_placement;
        }

        pub fn getNextMove(_: GameState) !Move {
            if (moves_executed >= moves.len) {
                return error.NoMoreMoves;
            }
            const next_move = moves[moves_executed];
            moves_executed += 1;
            return next_move;
        }

        pub fn render(_: GameState) !void {}
    };
    return ui.interface;
}

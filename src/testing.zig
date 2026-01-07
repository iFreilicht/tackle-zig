const tackle = @import("root.zig");

const std = @import("std");

const Turn = tackle.Turn;
const Position = tackle.Position;
const Move = tackle.Move;
const GameState = tackle.GameState;
const RecordArgs = tackle.RecordArgs;
pub const UserInterface = tackle.UserInterface;

/// A UserInterface implementation that simulates user input for testing purposes.
pub fn simulatedUserInterface(placements: []const Position, moves: []const Move) UserInterface {
    const ui = struct {
        var pieces_placed: usize = 0;
        var moves_executed: usize = 0;

        var write_buffer: [64]u8 = undefined;
        var writer = std.io.Writer.Discarding.init(&write_buffer);

        pub const interface: UserInterface = .{
            .log_writer = &writer.writer,
            .getNextPlacement = getNextPlacement,
            .getNextMove = getNextMove,
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
    };
    return ui.interface;
}

pub fn simulatedUserInterfaceWithRecording(placements: []const Position, moves: []const Move) UserInterface {
    const base_ui = simulatedUserInterface(placements, moves);

    const ui = struct {
        const interface: UserInterface = .{
            .getNextPlacement = base_ui.getNextPlacement,
            .getNextMove = base_ui.getNextMove,
            .record = record,
            .log_writer = base_ui.log_writer,
        };

        fn record(record_args: RecordArgs, turn: Turn) !void {
            const datafile_ptr = record_args.datafile_ptr;
            switch (turn.action) {
                .place => |pos| {
                    try datafile_ptr.placements.append(record_args.gpa, pos);
                },
                .move => {
                    try datafile_ptr.turns.append(record_args.gpa, turn);
                },
            }

            // Save the updated DataFile back to disk
            try record_args.file_ptr.seekTo(0);
            var write_buffer: [1024]u8 = undefined;
            var datafile_writer = record_args.file_ptr.writer(&write_buffer);
            try datafile_ptr.save(&datafile_writer.interface);
            try datafile_writer.interface.flush();
        }
    };
    return ui.interface;
}

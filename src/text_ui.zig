const tackle = @import("root.zig");

const std = @import("std");

const Turn = tackle.Turn;
const DataFile = tackle.DataFile;
const UserInterface = tackle.UserInterface;
const GameState = tackle.GameState;
const Position = tackle.Position;
const Move = tackle.Move;
const RecordArgs = tackle.RecordArgs;
const Player = tackle.Player;
const PieceColor = tackle.PieceColor;
const Phase = tackle.Phase;
const Action = tackle.Action;
const renderBoard = tackle.TextRenderer.renderBoard;

pub fn record(record_args: RecordArgs, turn: Turn) !void {
    const datafile_ptr = record_args.datafile_ptr;
    try datafile_ptr.turns.append(record_args.gpa, turn);

    // Save the updated DataFile back to disk
    try record_args.file_ptr.seekTo(0);
    var write_buffer: [1024]u8 = undefined;
    var datafile_writer = record_args.file_ptr.writer(&write_buffer);
    try datafile_ptr.save(&datafile_writer.interface);
    try datafile_writer.interface.flush();
}

pub fn textBasedUI() UserInterface {
    const ui = struct {
        const stdin = std.fs.File.stdin();
        var input_buffer: [100]u8 = undefined;
        var reader = stdin.readerStreaming(&input_buffer);

        const stdout = std.fs.File.stdout();
        var output_buffer: [50]u8 = undefined;
        var writer = stdout.writer(&output_buffer);
        const log_writer = &writer.interface;

        const interface: UserInterface = .{
            .log_writer = log_writer,
            .getNextAction = getNextAction,
            .render = render,
            .record = record,
        };

        fn getNextAction(player: Player, phase: Phase) !Action {
            while (true) {
                try log_writer.print("Enter next action:\n", .{});

                var slice: ?[]const u8 = null;
                while (slice == null) {
                    slice = try reader.interface.takeDelimiter('\n');
                }
                var turn_reader = std.io.Reader.fixed(slice orelse unreachable);

                const known_color: PieceColor = switch (player) {
                    .white => .white,
                    .black => if (phase == .place_gold) .gold else .black,
                };

                const turn = tackle.parseTurn(&turn_reader, known_color) catch |err| {
                    try log_writer.print("Error parsing action: {}\n", .{err});
                    try log_writer.print("Please enter a valid action:\n", .{});
                    continue;
                };
                return turn.action;
            }
        }

        fn render(state: GameState) !void {
            try log_writer.print("\n\n", .{});
            try renderBoard(&writer.interface, state.board);
            const player = state.currentPlayer();
            switch (state.phase) {
                .opening => try log_writer.print("Turn {}, {t}'s turn to place a piece.\n", .{ state.turn, player }),
                .place_gold => try log_writer.print("Place the gold piece for black.\n", .{}),
                .main => try log_writer.print("Turn {}, {t}'s turn to move.\n", .{ state.turn, player }),
                .finished => try log_writer.print("Game over. {t} has won!\n", .{player}),
            }
        }
    };
    return ui.interface;
}

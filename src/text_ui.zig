const tackle = @import("root.zig");

const std = @import("std");

const Turn = tackle.Turn;
const DataFile = tackle.DataFile;
const UserInterface = tackle.UserInterface;
const GameState = tackle.GameState;
const Position = tackle.Position;
const Move = tackle.Move;
const RecordArgs = tackle.RecordArgs;
const renderBoard = tackle.TextRenderer.renderBoard;

pub fn textBasedUI() UserInterface {
    const ui = struct {
        const stdin = std.fs.File.stdin();
        var input_buffer: [100]u8 = undefined;
        var reader = stdin.readerStreaming(&input_buffer);

        const stdout = std.fs.File.stdout();
        var output_buffer: [50]u8 = undefined;
        var writer = stdout.writer(&output_buffer);

        const interface: UserInterface = .{
            .log_writer = &writer.interface,
            .getNextPlacement = getNextPlacement,
            .getNextMove = getNextMove,
            .render = render,
            .record = record,
        };

        fn getNextPlacement() !Position {
            while (true) {
                std.debug.print("Enter your piece placement:\n", .{});
                var slice: ?[]const u8 = null;
                while (slice == null) {
                    slice = try reader.interface.takeDelimiter('\n');
                }
                var pos_reader = std.io.Reader.fixed(slice orelse unreachable);

                const position = tackle.parsePosition(&pos_reader) catch |err| {
                    std.debug.print("Error parsing position: {}\n", .{err});
                    std.debug.print("Please enter a valid placement:\n", .{});
                    continue;
                };
                return position;
            }
        }

        fn getNextMove(state: GameState) !Move {
            while (true) {
                std.debug.print("Enter your move:\n", .{});
                var slice: ?[]const u8 = null;
                while (slice == null) {
                    slice = try reader.interface.takeDelimiter('\n');
                }
                var move_reader = std.io.Reader.fixed(slice orelse unreachable);

                const player = state.currentPlayer();
                const turn = tackle.parseTurn(&move_reader, player) catch |err| {
                    std.debug.print("Error parsing move: {}\n", .{err});
                    std.debug.print("Please enter a valid move:\n", .{});
                    continue;
                };
                switch (turn.action) {
                    .place => {
                        std.debug.print("Expected a move, but got a placement. Please enter a valid move:\n", .{});
                        continue;
                    },
                    .move => |move| return move,
                }
            }
        }

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

        fn render(state: GameState) !void {
            std.debug.print("\n\n", .{});
            try renderBoard(&writer.interface, state.board);
            const player = state.currentPlayer();
            switch (state.phase) {
                .opening => std.debug.print("Turn {}, {t}'s turn to place a piece.\n", .{ state.turn, player }),
                .place_gold => std.debug.print("Place the gold piece for black.\n", .{}),
                .main => std.debug.print("Turn {}, {t}'s turn to move.\n", .{ state.turn, player }),
                .finished => std.debug.print("Game over. {t} has won!\n", .{player}),
            }
        }
    };
    return ui.interface;
}

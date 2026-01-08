const tackle = @import("root.zig");

const std = @import("std");

const Action = tackle.Action;
const Turn = tackle.Turn;
const Position = tackle.Position;
const Move = tackle.Move;
const Player = tackle.Player;
const Phase = tackle.Phase;
const GameState = tackle.GameState;
const RecordArgs = tackle.RecordArgs;
const text_ui = tackle.text_ui;
const UserInterface = tackle.UserInterface;

/// A UserInterface implementation that simulates user input for testing purposes.
pub fn simulatedUserInterface(actions: []const Action) UserInterface {
    const ui = struct {
        var actions_executed: usize = 0;

        var write_buffer: [64]u8 = undefined;
        var writer = std.io.Writer.Discarding.init(&write_buffer);

        pub const interface: UserInterface = .{
            .log_writer = &writer.writer,
            .getNextAction = getNextAction,
        };

        pub fn getNextAction(player: Player, phase: Phase) anyerror!Action {
            _, _ = .{ player, phase }; // Unused parameters
            if (actions_executed >= actions.len) {
                return error.NoMoreActions;
            }
            const next_action = actions[actions_executed];
            actions_executed += 1;
            return next_action;
        }
    };
    return ui.interface;
}

pub fn simulatedUserInterfaceWithRecording(actions: []const Action) UserInterface {
    const base_ui = simulatedUserInterface(actions);

    const ui = struct {
        const interface: UserInterface = .{
            .getNextAction = base_ui.getNextAction,
            .record = text_ui.record,
            .log_writer = base_ui.log_writer,
        };
    };
    return ui.interface;
}

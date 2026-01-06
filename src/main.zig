const std = @import("std");
const tackle = @import("root.zig");

const DataFile = tackle.DataFile;
const Job = tackle.Job;
const GameState = tackle.GameState;
const Move = tackle.Move;
const Position = tackle.Position;
const UserInterface = tackle.UserInterface;
const textBasedUI = tackle.text_ui.textBasedUI;
const simulatedUserInterface = tackle.testing.simulatedUserInterface;

const renderBoard = tackle.TextRenderer.renderBoard;

const Mode = enum {
    play,
    load,
    show,
};

const Args = struct {
    mode: Mode,
    job: ?tackle.Job,
    filepath: ?[]const u8,
    verbose: bool,

    const usage =
        \\Usage: tackle [job]
        \\       tackle play [job]          Play a new game with [job]
        \\       tackle load [file]         Continue a saved game
        \\       tackle show [file]         Display a saved game and exit
        \\
    ;

    /// Parse command-line arguments into an Args struct.
    /// I would have liked to use std.process.ArgIterator here,
    /// but it directly accesses os.argv, which makes testing difficult.
    pub fn parse(proc_args: []const []const u8) !Args {
        var mode: Mode = .play;
        var file: ?[]const u8 = null;
        var job: ?tackle.Job = null;
        var verbose: bool = false;

        for (proc_args[1..]) |arg| {
            if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
                return error.InvalidArguments;
            } else if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
                verbose = true;
            } else if (std.mem.eql(u8, arg, "play")) {
                mode = .play;
            } else if (std.mem.eql(u8, arg, "load")) {
                mode = .load;
            } else if (std.mem.eql(u8, arg, "show")) {
                mode = .show;
            } else {
                if (mode == .play) parse_job: {
                    job = Job.fromName(arg) catch {
                        break :parse_job;
                    };
                    continue;
                }
                file = arg;
            }
        }

        return .{
            .mode = mode,
            .job = job,
            .filepath = file,
            .verbose = verbose,
        };
    }
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const argv = try std.process.argsAlloc(allocator);
    defer allocator.free(argv);

    const parsed_args = try Args.parse(argv);

    mainArgs(allocator, parsed_args, textBasedUI()) catch |err| {
        if (err == error.InvalidArguments) {
            std.debug.print("{s}\n", .{Args.usage});
        } else {
            std.debug.print("Error: {}\n", .{err});
        }
        // Print traceback
        if (parsed_args.verbose) {
            return err;
        }
    };
}

pub fn mainArgs(gpa: std.mem.Allocator, args: Args, ui: UserInterface) !void {
    var datafile = if (args.filepath) |filename| df: {
        const file = try std.fs.cwd().openFile(filename, .{});
        defer file.close();

        var read_buffer: [1024]u8 = undefined;
        var reader = file.reader(&read_buffer);

        const result = try DataFile.load(gpa, &reader.interface);
        break :df result;
    } else DataFile{ .job = args.job orelse Job.turm3() };
    defer datafile.deinit(gpa);

    const state = state: switch (args.mode) {
        .show, .load => try datafile.toGameState(),
        .play => {
            if (datafile.placements.items.len == 0 and datafile.turns.items.len == 0) {
                break :state GameState.init(datafile.job);
            } else {
                std.debug.print("File contains a saved game. Please use \"load\" to load it.\n", .{});
                return error.FileContainsSavedGame;
            }
        },
    };

    try ui.render(state);

    if (datafile.job.name) |name| {
        std.debug.print("The job for this game is \"{t}\".\n", .{name});
    } else {
        std.debug.print("The job for this game is a custom job, which the CLI currently can't display.\n", .{});
    }

    if (args.mode == .show) return;

    _ = try tackle.runGameLoop(state, ui);
}

test {
    std.testing.refAllDecls(@This());
}

test "mainArgs loads entire game and exits without errors when the game is already finished" {
    const allocator = std.testing.allocator;
    const args = Args{
        .mode = .load,
        .job = Job.turm3(),
        .filepath = "src/test_data/turm3_testgame.txt",
        .verbose = false,
    };

    const ui = simulatedUserInterface(&.{}, &.{});

    try mainArgs(allocator, args, ui);
}

test "mainArgs starts a new game and exits without errors when no user input is given" {
    const allocator = std.testing.allocator;
    const args = Args{
        .mode = .play,
        .job = Job.turm3(),
        .filepath = null,
        .verbose = false,
    };

    const ui = simulatedUserInterface(&.{}, &.{});

    try mainArgs(allocator, args, ui);
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}

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
const simulatedUserInterfaceWithRecording = tackle.testing.simulatedUserInterfaceWithRecording;

const renderBoard = tackle.TextRenderer.renderBoard;

const Mode = enum {
    play,
    load,
    show,
    discard,
    save,
};

const autosave_filename = ".tackle-autosave.txt";

const Args = struct {
    mode: Mode,
    job: ?tackle.Job,
    filepath: ?[]const u8,
    verbose: bool,

    /// The working directory to use for file operations.
    /// Is set to the current directory by default and only overridden in tests.
    working_dir: std.fs.Dir,

    const usage =
        \\Usage: tackle [file] [job]
        \\       tackle play [file] [job]   Play a new game with [job], saving to [file] if passed
        \\       tackle load [file]         Continue a saved game
        \\       tackle show [file]         Display a saved game and exit
        \\       tackle discard             Discard the current autosave
        \\       tackle save [file]         Save the autosaved game to [file]
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
            } else if (std.mem.eql(u8, arg, "discard")) {
                mode = .discard;
            } else if (std.mem.eql(u8, arg, "save")) {
                mode = .save;
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
            .working_dir = std.fs.cwd(),
        };
    }
};

fn print_job_names() void {
    std.debug.print("Available jobs:\n", .{});
    for (Job.official_jobs) |job| {
        std.debug.print(" - {t}\n", .{job.name.?});
    }
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const argv = try std.process.argsAlloc(allocator);
    defer allocator.free(argv);

    const parsed_args = try Args.parse(argv);

    mainArgs(allocator, parsed_args, textBasedUI()) catch |err| {
        if (err == error.InvalidArguments) {
            std.debug.print("{s}\n", .{Args.usage});
            print_job_names();
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
    if (args.mode == .discard) {
        try args.working_dir.deleteFile(autosave_filename);
        std.debug.print("Autosave file \"{s}\" discarded.\n", .{autosave_filename});
        return;
    }

    const filename = args.filepath orelse autosave_filename;

    if (args.mode == .save) {
        try args.working_dir.rename(autosave_filename, filename);
        std.debug.print(
            "Autosave file \"{s}\" renamed to \"{s}\".\n",
            .{ autosave_filename, filename },
        );
        return;
    }

    // Open or create the file
    var file = try args.working_dir.createFile(
        filename,
        .{ .truncate = false, .read = true, .exclusive = false },
    );
    defer file.close();

    var read_buffer: [1024]u8 = undefined;
    var reader = file.reader(&read_buffer);

    var datafile = try DataFile.load(gpa, &reader.interface);
    defer if (datafile != null) datafile.?.deinit(gpa);
    if (datafile == null) {
        if (args.mode == .load or args.mode == .show) {
            std.debug.print("No saved game found at \"{s}\".\n", .{filename});
            return error.NoSavedGameFound;
        }
        if (args.job == null) {
            std.debug.print("No job specified for new game.\n", .{});
            print_job_names();
            return error.JobRequiredForNewGame;
        }
        datafile = DataFile{ .job = args.job orelse Job.turm3() };
    } else {
        if (args.mode == .play) {
            if (std.mem.eql(u8, filename, autosave_filename)) {
                std.debug.print(
                    \\There is an existing autosave at "{s}".
                    \\If you want to continue the saved game, run "load" instead.
                    \\If you want to start a new game, either run "save" to save the existing
                    \\game to a new file, or delete the autosave with "discard" before 
                    \\running "play" again.
                    \\
                , .{filename});
                return error.SavedGameAlreadyExists;
            } else {
                std.debug.print(
                    \\There is already a saved game at "{s}".
                    \\If you want to continue the saved game, run "load" instead.
                    \\If you want to start a new game, either choose a different filename or
                    \\delete the existing file with "discard" before running "play" again.
                , .{filename});
                return error.SavedGameAlreadyExists;
            }
        }
    }

    const state = try datafile.?.toGameState();

    if (ui.render) |render| try render(state);

    if (datafile.?.job.name) |name| {
        std.debug.print("The job for this game is \"{t}\".\n", .{name});
    } else {
        std.debug.print("The job for this game is a custom job, which the CLI currently can't display.\n", .{});
    }

    if (args.mode == .show) return;

    _ = try tackle.runGameLoop(
        state,
        ui,
        .{
            .gpa = gpa,
            .datafile_ptr = &datafile.?,
            .file_ptr = &file,
        },
    );
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
        .working_dir = std.fs.cwd(),
    };

    const ui = simulatedUserInterface(&.{}, &.{});

    try mainArgs(allocator, args, ui);
}

test "mainArgs starts a new game and exits without errors when no user input is given" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const args = Args{
        .mode = .play,
        .job = Job.turm3(),
        .filepath = null,
        .verbose = false,
        .working_dir = tmp_dir.dir,
    };

    const ui = simulatedUserInterface(&.{}, &.{});

    try mainArgs(allocator, args, ui);
}

test "play -> play fails -> save -> play works" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var args = Args{
        .mode = .play,
        .job = Job.treppe4(),
        .filepath = null,
        .verbose = false,
        .working_dir = tmp_dir.dir,
    };

    const ui = simulatedUserInterfaceWithRecording(
        &.{.{ .A, ._5 }},
        &.{},
    );

    // First play creates the autosave
    try mainArgs(allocator, args, ui);

    // Second play fails because the autosave already exists
    try std.testing.expectError(
        error.SavedGameAlreadyExists,
        mainArgs(allocator, args, ui),
    );

    // Save the autosave to a new file
    args.mode = .save;
    args.filepath = "saved_game.txt";
    try mainArgs(allocator, args, ui);

    // Now play with the original autosave filename should work again
    args.mode = .play;
    args.filepath = null;
    try mainArgs(allocator, args, ui);

    // Discard the autosave to clean up
    args.mode = .discard;
    try mainArgs(allocator, args, ui);

    // Now play with the original autosave filename should work as well
    args.mode = .play;
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

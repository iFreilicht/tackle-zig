//! Implementation of loading and saving data files containing games.
//! The data file format is a simple line-based format where each line
//! represents either a comment, a job, a piece placement, or a turn.
//! Comments start with `# ` and go on for the entire line.
//! The first non-comment line MUST contain the name of the job. Custom jobs
//! are currently not supported.
//! After the job, all subsequent lines will be treated as turns, in the
//! format accepted by `tackle.notation.parseTurn`.
//! Empty lines are ignored. Whitespace at the end of lines is ignored.

const DataFile = @This();

const std = @import("std");

const expectEqual = std.testing.expectEqual;
const expectEqualDeep = std.testing.expectEqualDeep;
const expectError = std.testing.expectError;

const tackle = @import("root.zig");

const ArrayList = std.ArrayList;
const AutoHashMap = std.hash_map.AutoHashMapUnmanaged;
const GameState = tackle.GameState;
const Job = tackle.Job;
const Player = tackle.enums.Player;
const Position = tackle.position.Position;
const notation = tackle.notation;
const Turn = tackle.Turn;

const comment_prefix = "# ";

job: Job,
comments: Comments = Comments.empty,
turns: ArrayList(Turn) = ArrayList(Turn).empty,

const Comments = AutoHashMap(usize, ArrayList(u8));

/// Load a DataFile from the given reader according to the format
/// described in the module documentation.
/// Returns `null` if the file is empty.
pub fn load(gpa: std.mem.Allocator, reader: *std.io.Reader) !?DataFile {
    var comments = Comments.empty;
    errdefer {
        var comments_iter = comments.valueIterator();
        while (comments_iter.next()) |comment| {
            comment.deinit(gpa);
        }
        comments.deinit(gpa);
    }
    var job: ?Job = null;
    var turns = ArrayList(Turn).empty;
    errdefer turns.deinit(gpa);

    // Remember which line we're on so that comments can be
    // written back on the same line when saving.
    var line_number: usize = 1;

    while (true) : (line_number += 1) {
        const line = reader.peekDelimiterExclusive('\n') catch |err| {
            if (err == error.EndOfStream) break;
            return err;
        };
        if (line.len == 0) continue;

        // Ensure that the parsers only see this line without trailing whitespace.
        const line_stripped = std.mem.trimRight(u8, line, " \t\r");
        var line_reader = std.io.Reader.fixed(line_stripped);

        if (line.len >= comment_prefix.len and std.mem.eql(u8, line[0..comment_prefix.len], comment_prefix)) {
            // Comment line
            const comment_text = line[comment_prefix.len..];
            var comment = ArrayList(u8).empty;
            try comment.appendSlice(gpa, comment_text);
            try comments.put(gpa, line_number, comment);
        } else if (job == null) {
            // Job line
            job = try Job.fromName(line);
        } else {
            // Turn line
            const turn = try notation.parseTurn(&line_reader, null);
            try turns.append(gpa, turn);
        }

        _ = try reader.discardDelimiterInclusive('\n');
    }

    if (comments.count() == 0 and job == null and turns.items.len == 0) {
        return null;
    }

    return DataFile{
        .comments = comments,
        .job = job orelse return error.DataFileContainsNoJob,
        .turns = turns,
    };
}

pub fn deinit(self: *DataFile, gpa: std.mem.Allocator) void {
    var comment_iterator = self.comments.iterator();
    while (comment_iterator.next()) |entry| {
        entry.value_ptr.deinit(gpa);
    }
    self.comments.deinit(gpa);
    self.turns.deinit(gpa);
}

/// Save the DataFile to the given writer according to the format
/// described in the module documentation.
pub fn save(self: DataFile, writer: *std.io.Writer) !void {
    var line_number: usize = 1;
    var job_written = false;
    var turns_written: usize = 0;

    while (true) : (line_number += 1) {
        if (self.comments.get(line_number)) |comment| {
            _ = try writer.write(comment_prefix);
            _ = try writer.write(comment.items);
            _ = try writer.write("\n");
        } else if (!job_written) {
            // Job line
            if (self.job.name) |name_enum| {
                _ = try writer.write(@tagName(name_enum));
                _ = try writer.write("\n");
                job_written = true;
            } else {
                return error.CannotSaveCustomJobYet;
            }
        } else if (turns_written < self.turns.items.len) {
            // Turn line
            const turn = self.turns.items[turns_written];
            try writer.print("{f}\n", .{turn});
            turns_written += 1;
        } else {
            break;
        }
    }
}

/// Play back the DataFile into an empty GameState initialized with the DataFile's job.
/// This will validate whether the actions in the DataFile are legal according to the game rules.
pub fn toGameState(self: DataFile) !GameState {
    var game_state = GameState.init(self.job);

    for (self.turns.items) |turn| {
        try game_state.executeTurn(turn);
    }

    return game_state;
}

test "load data file correctly" {
    const allocator = std.testing.allocator;

    const datafile = @embedFile("test_data/turm3_testgame.txt");
    var reader = std.io.Reader.fixed(datafile);

    var loaded_datafile = try DataFile.load(allocator, &reader) orelse unreachable;
    defer loaded_datafile.deinit(allocator);

    try expectEqualDeep(Job.turm3(), loaded_datafile.job);
    try expectEqualDeep(&[_]Turn{
        .{ .color = .white, .action = .{ .place = .{ .A, ._1 } } },
        .{ .color = .black, .action = .{ .place = .{ .B, ._1 } } },
        .{ .color = .white, .action = .{ .place = .{ .F, ._10 } } },
        .{ .color = .black, .action = .{ .place = .{ .B, ._10 } } },
        .{ .color = .white, .action = .{ .place = .{ .J, ._5 } } },
        .{ .color = .black, .action = .{ .place = .{ .A, ._8 } } },
        .{ .color = .white, .action = .{ .place = .{ .F, ._1 } } },
        .{ .color = .black, .action = .{ .place = .{ .G, ._10 } } },
        .{ .color = .white, .action = .{ .place = .{ .A, ._4 } } },
        .{ .color = .black, .action = .{ .place = .{ .J, ._8 } } },
        .{ .color = .gold, .action = .{ .place = .{ .F, ._5 } } },
        .{ .color = .white, .action = .{ .move = .{
            .horizontal = .{ .from_x = .A, .to_x = .B, .y = ._4 },
        } } },
        .{ .color = .black, .action = .{ .move = .{
            .horizontal = .{ .from_x = .J, .to_x = .C, .y = ._8 },
        } } },
        .{ .color = .white, .action = .{ .move = .{
            .diagonal = .{ .from = .bottom_left, .distance = 3 },
        } } },
        .{ .color = .black, .action = .{ .move = .{
            .vertical = .{ .x = .B, .from_y = ._10, .to_y = ._8 },
        } }, .winning = .job_in_one },
        .{ .color = .white, .action = .{ .move = .{
            .vertical = .{ .x = .F, .from_y = ._1, .to_y = ._4 },
        } } },
        .{ .color = .black, .action = .{ .move = .{
            .horizontal = .{ .from_x = .A, .to_x = .B, .y = ._8 },
        } }, .winning = .win },
    }, loaded_datafile.turns.items);

    try expectEqualDeep("This is a comment", loaded_datafile.comments.get(1).?.items);
    try expectEqualDeep("Another comment", loaded_datafile.comments.get(5).?.items);
    try expectEqualDeep("this time accross multiple lines", loaded_datafile.comments.get(6).?.items);
}

test "load and save data file roundtrip" {
    const allocator = std.testing.allocator;

    const datafile = @embedFile("test_data/turm3_testgame.txt");
    var reader = std.io.Reader.fixed(datafile);

    var loaded_datafile = try DataFile.load(allocator, &reader) orelse unreachable;
    defer loaded_datafile.deinit(allocator);

    var buffer: [1024]u8 = undefined;
    var writer = std.io.Writer.fixed(&buffer);

    try loaded_datafile.save(&writer);

    try expectEqualDeep(datafile, writer.buffered());
}

test "no memory leaks when loading errors occur" {
    const allocator = std.testing.allocator;

    const invalid_datafile = @embedFile("test_data/invalid_endofstream.txt");
    var reader = std.io.Reader.fixed(invalid_datafile);

    try expectError(
        error.EndOfStream,
        DataFile.load(allocator, &reader),
    );
}

test "convert to GameState correctly" {
    const allocator = std.testing.allocator;

    const datafile = @embedFile("test_data/turm3_testgame.txt");
    var reader = std.io.Reader.fixed(datafile);

    var loaded_datafile = try DataFile.load(allocator, &reader) orelse unreachable;
    defer loaded_datafile.deinit(allocator);

    const game_state = try loaded_datafile.toGameState();

    try expectEqual(15, game_state.turn);
    try expectEqual(GameState.Phase.finished, game_state.phase);

    try game_state.board.expectContent(
        &.{ .{ .B, ._4 }, .{ .D, ._4 }, .{ .F, ._4 }, .{ .F, ._10 }, .{ .J, ._5 } },
        &.{ .{ .B, ._1 }, .{ .B, ._8 }, .{ .C, ._8 }, .{ .D, ._8 }, .{ .G, ._10 } },
        .{ .F, ._5 },
    );
}

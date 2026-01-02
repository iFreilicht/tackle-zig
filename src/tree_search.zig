const tackle = @import("root.zig");

const std = @import("std");

// Change this alias once unmanaged was made the default
const AutoArrayHashMap = std.AutoArrayHashMapUnmanaged;
const reverseIterator = std.mem.reverseIterator;

const board_size = tackle.constants.board_size;

const Player = tackle.enums.Player;
const Board = tackle.Board;
const Move = tackle.Move;
const Job = tackle.Job;

const TreePlayer = enum(i32) {
    white = 1,
    black = -1,

    pub fn fromPlayer(p: Player) @This() {
        return switch (p) {
            .white => .white,
            .black => .black,
        };
    }

    pub fn toPlayer(self: @This()) Player {
        return switch (self) {
            .white => .white,
            .black => .black,
        };
    }

    pub fn opponent(self: @This()) @This() {
        return switch (self) {
            .white => .black,
            .black => .white,
        };
    }
};

const Node = struct {
    /// The probability of selecting this node from its parent
    prior_probability: f32,

    /// Which player's turn it is at this node
    to_move: TreePlayer,

    /// The Job that needs to be completed in order to win the game
    job: Job,

    /// The move that led to this node (null for root). This move is from the
    /// perspective of the previous player, not the one to move!
    move: ?Move,

    /// The game state at this node (null for unexpanded nodes)
    state: ?Board,
    /// The state vector representation of the board for neural network input
    /// (null for unexpanded nodes)
    state_vector: ?[board_size]f32,

    visit_count: f32,
    /// The total value accumulated from simulations passing through this node
    /// Ranges between 0.0 (definite loss) and 1.0 (definite win)
    total_value: f32,

    children: ChildrenMap,

    const ChildrenMap = AutoArrayHashMap(Move, Node);

    pub fn init(gpa: std.mem.Allocator, to_move: TreePlayer, job: Job, move: Move) !Node {
        return Node{
            .prior_probability = 0.0, // This will be set afterwards, otherwise the value makes no sense
            .to_move = to_move,
            .job = job,
            .move = move,
            .state = null,
            .state_vector = null,
            .visit_count = 0.0,
            .total_value = 0.0,
            .children = try ChildrenMap.init(gpa, &.{}, &.{}),
        };
    }

    pub fn initRoot(gpa: std.mem.Allocator, to_move: TreePlayer, job: Job, state: Board) !Node {
        return Node{
            .prior_probability = 1.0,
            .to_move = to_move,
            .job = job,
            .move = null,
            .state = state,
            .state_vector = stateVectorFromBoard(state, to_move),
            .visit_count = 0.0,
            .total_value = 0.0,
            .children = try ChildrenMap.init(gpa, &.{}, &.{}),
        };
    }

    pub fn deinit(self: *Node, gpa: std.mem.Allocator) void {
        var it = self.children.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(gpa);
        }
        self.children.deinit(gpa);
    }

    fn stateVectorFromBoard(board: Board, to_move: TreePlayer) [board_size]f32 {
        var vector: [board_size]f32 = undefined;

        // Fill the state vector with 1.0 for own pieces, -1.0 for opponent pieces, 0.0 for empty
        for (&vector, board.squares) |*cell_value, square| {
            cell_value.* = switch (square) {
                .empty => 0.0,
                .white => if (to_move == .white) 1.0 else -1.0,
                .black => if (to_move == .black) 1.0 else -1.0,
                .gold => -1.0, // We always treat the gold piece as an opponent's piece
            };
        }

        return vector;
    }

    /// Compute the game state at this node if it hasn't been computed yet
    pub fn computeState(self: *Node, parent_state: Board) !void {
        if (self.state != null) return;

        var new_state = parent_state;
        const previous_player = self.to_move.opponent().toPlayer();
        const move = self.move orelse unreachable;
        try new_state.executeMove(previous_player, move);

        self.state = new_state;
        self.state_vector = stateVectorFromBoard(new_state, self.to_move);
    }

    /// Check if this node is a winning node for the current player
    pub fn isWinningNode(self: Node) bool {
        const state = self.state orelse unreachable;
        return self.job.isFulfilled(state, self.to_move.toPlayer());
    }

    /// Check if this node has been expanded
    pub fn expanded(self: *Node) bool {
        return self.children.count() > 0;
    }

    /// Expand this node by generating all possible child nodes
    pub fn expand(self: *Node, gpa: std.mem.Allocator) !void {
        const state = self.state orelse unreachable;
        const next_player = self.to_move.opponent();
        var possible_moves = try state.getPossibleMoves(self.to_move.toPlayer());

        while (try possible_moves.next()) |move| {
            const child_node = try Node.init(gpa, next_player, self.job, move);
            try self.children.put(gpa, move, child_node);
        }

        // TODO: Determine probability from a policy network instead of uniform distribution
        const num_children: f32 = @floatFromInt(self.children.count());

        var children_iter = self.children.iterator();
        while (children_iter.next()) |entry| {
            entry.value_ptr.prior_probability = 1.0 / num_children;
        }
    }

    pub fn value(self: *Node) f32 {
        if (self.visit_count > 0.0) {
            return self.total_value / self.visit_count;
        } else {
            return 0.0;
        }
    }

    pub fn ucbScore(self: *Node, parent_visit_count: f32) f32 {
        const prior_score = self.prior_probability * std.math.sqrt(parent_visit_count) / (1.0 + self.visit_count);
        return self.value() + prior_score;
    }

    pub fn selectBestChild(self: *Node) *Node {
        std.debug.assert(self.expanded());

        var best_ucb = -std.math.inf(f32);
        var best_child: *Node = undefined;

        var children_iter = self.children.iterator();
        while (children_iter.next()) |entry| {
            const child = entry.value_ptr;
            const ucb_value = child.ucbScore(self.visit_count);
            if (ucb_value > best_ucb) {
                best_ucb = ucb_value;
                best_child = child;
            }
        }

        return best_child;
    }

    /// Run a Monte Carlo simulation starting from this node
    pub fn runMonteCarloSimulation(self: *Node, gpa: std.mem.Allocator, num_simulations: usize) !void {
        try self.expand(gpa);

        var path = std.ArrayList(*Node).empty;
        defer path.deinit(gpa);

        for (0..num_simulations) |_| {
            path.clearRetainingCapacity();
            var current_node = self;
            var parent_node = self;

            // Selection
            while (current_node.expanded()) {
                const best_child = current_node.selectBestChild();
                try path.append(gpa, current_node);
                parent_node = current_node;
                current_node = best_child;
            }

            // Expansion
            try current_node.computeState(parent_node.state.?);
            if (current_node.isWinningNode()) {
                // We won the game with this move, no further moves will be played
                current_node.total_value = 1.0;
            } else {
                try current_node.expand(gpa);
                // TODO: Use a value network to evaluate the position instead of random simulation
                // For now, we just assign a static value
                current_node.total_value = 0.5;
            }

            // Backpropagation
            var current_value: f32 = current_node.total_value;
            var reverse_path_items = reverseIterator(path.items);
            while (reverse_path_items.next()) |node| {
                node.visit_count += 1;
                node.total_value += current_value;
                current_value = -current_value; // Switch perspective for the opponent
            }
        }
    }

    /// Traverse the tree depth-first, calling the visitor function on each node
    pub fn traverse(self: *const Node, visitor: fn (*const Node) void) void {
        visitor(self);
        var iterator = self.children.iterator();
        while (iterator.next()) |child| {
            child.value_ptr.traverse(visitor);
        }
    }
};

test "Node can be created and destroyed without memory leaks" {
    const allocator = std.testing.allocator;

    const board = Board{};
    var node = try Node.initRoot(allocator, .white, board);
    defer node.deinit(allocator);
}

test "State vector is correctly generated from board" {
    var board = Board{};
    try board.placePiece(.white, .{ .B, ._4 });
    try board.placePiece(.black, .{ .E, ._5 });
    try board.placePiece(.gold, .{ .D, ._6 });

    const allocator = std.testing.allocator;

    var node_white = try Node.initRoot(allocator, .white, board);
    defer node_white.deinit(allocator);
    const vector_white = node_white.state_vector orelse unreachable;
    try std.testing.expect(vector_white[Board.index(.{ .B, ._4 })] == 1.0);
    try std.testing.expect(vector_white[Board.index(.{ .E, ._5 })] == -1.0);
    try std.testing.expect(vector_white[Board.index(.{ .D, ._6 })] == -1.0);
    try std.testing.expect(vector_white[Board.index(.{ .F, ._2 })] == 0.0);

    var node_black = try Node.initRoot(allocator, .black, board);
    defer node_black.deinit(allocator);
    const vector_black = node_black.state_vector orelse unreachable;
    try std.testing.expect(vector_black[Board.index(.{ .B, ._4 })] == -1.0);
    try std.testing.expect(vector_black[Board.index(.{ .E, ._5 })] == 1.0);
    try std.testing.expect(vector_black[Board.index(.{ .D, ._6 })] == -1.0);
    try std.testing.expect(vector_black[Board.index(.{ .F, ._2 })] == 0.0);
}

test "Node expansion generates correct number of children" {
    const allocator = std.testing.allocator;

    const job = Job.turm3();
    var board = Board{};
    try board.placePiece(.white, .{ .B, ._4 });
    try board.placePiece(.white, .{ .D, ._7 });
    try board.placePiece(.white, .{ .F, ._2 });
    try board.placePiece(.black, .{ .E, ._5 });

    var node = try Node.initRoot(allocator, .white, job, board);
    defer node.deinit(allocator);

    try node.expand(allocator);

    // There are 9 empty squares in each axis per piece
    const expected_move_count = 9 * 2 * 3;
    try std.testing.expectEqual(expected_move_count, node.children.count());
}

test "Monte Carlo simulation runs without errors and finds winning move" {
    const allocator = std.testing.allocator;

    const job = Job.turm3();
    var board = Board{};
    try board.placePiece(.white, .{ .B, ._6 });
    try board.placePiece(.white, .{ .B, ._7 });
    try board.placePiece(.white, .{ .B, ._2 });
    try board.placePiece(.black, .{ .E, ._5 });

    var root = try Node.initRoot(allocator, .white, job, board);
    defer root.deinit(allocator);

    const num_simulations = 1000;
    try root.runMonteCarloSimulation(allocator, num_simulations);

    // Traverse tree to find if any child has a total value of 1.0 (winning move)
    const visitor = struct {
        var winning_node: ?*const Node = null;

        pub fn visit(node: *const Node) void {
            if (node.total_value == 1.0 and winning_node == null) {
                winning_node = node;
            }
        }
    };
    root.traverse(visitor.visit);
    try std.testing.expect(visitor.winning_node != null);
}

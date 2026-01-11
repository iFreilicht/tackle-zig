# Tackle in Zig

This project has the goal of implementing the board game "Tackle" (http://tackle-game.de) within the following components:

- Core Game Logic: All rules and state of the game as a library to facilitate easy development of Frontends and Analysis Tools for the game
- Text-Based Frontend: Allows playing a game of Tackle on the command line, mostly used for testing
- MCTS-Algorithm for AI opponents: The first (to my knowledge) algorithm that can play a game of Tackle
- Graphical Frontend: An application that allows playing the game against other players or AI opponents

## Current status and TODOs

### Game logic
- ✓ Full representation of the game state in a single stack-allocatable structure
- ✓ Complete parsing and formatting of notation
- ✓ Placements during opening
- ✓ Moves of single pieces
- ✓ Moves of blocks of any breadth and width, including pushing logic
- ✓ Diagonal moves from the four corners
- ✓ Support for all official jobs
- ✓ Support for custom jobs
- ✓ Detection of job completion
- ✓ Automatic removal of gold piece
- ⏳ Worm moves
- ⏳ Allow bypassing the rule that gold has to be placed in the court

The logic engine is limited in some ways to reduce need for heap allocations and allow easier optimization of RAM usage:
- No more than 12 pieces per player are allowed
- As such, a job can't contain more than 10 pieces
- Blocks wider than 3 pieces are not supported (length is only limited by the board size)
- The number of squares in a job can't be more than 25, so the maximum size for a job is 8x3, 6x4 or 5x5

None of these limitations matter for games that adhere to the official rules. The last rule limits the size of custom jobs, but this limit seems reasonable to us. See also [`src/constants.zig`](./src/constants.zig).

### Text-Based Frontend:
- ✓ Graphical output of the board
- ✓ Textual input of the moves in notation form
- ✓ Play a full game of Tackle
- ⏳ Undo functionality
- ✓ Saving and loading games
- ✓ Selecting a job from the list of official jobs 
- ⏳ Playing against an AI opponent

### MCTS-Algorithm
- ⏳ Iteration over possible placements during opening phase
- ✓ Iteration over possible single-piece moves per player
- ⏳ Iteration over all block moves, worm moves and diagonal moves
- ⏳ Exhaustive graph structure for turm3
- ⏳ Find the known guaranteed win sequence for white when playing turm3
- ⏳ Try to find the currently unknown guaranteed win sequence for white when playing treppe3
- ⏳ Play a full game against the algorithm
- ⏳ Generational training of the algorithm against itself

### Graphical Frontend
Stuff for the future, no concrete plans yet.
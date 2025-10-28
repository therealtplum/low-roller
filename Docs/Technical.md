
# LowRoller Technical Documentation

## Table of Contents
- [Overview](#overview)
- [Architecture](#architecture)
- [Core Components](#core-components)
- [Game Engine](#game-engine)
- [User Interface](#user-interface)
- [Data Models](#data-models)
- [AI System](#ai-system)
- [Economy System](#economy-system)
- [Leaderboard System](#leaderboard-system)
- [Analytics](#analytics)
- [API Reference](#api-reference)

---

## Overview

**LowRoller** is a competitive dice game for iOS/macOS where players aim to achieve the lowest possible score. Built with SwiftUI and RealityKit, the game features multiplayer support, AI opponents, persistent leaderboards, and an in-game economy.

### Key Features
- **Multiplayer Support**: Up to 8 players (human or AI)
- **AI Opponents**: Two difficulty levels (Amateur/Pro)
- **Persistent Economy**: Bankroll system with borrowing mechanics
- **Leaderboard System**: Multiple ranking metrics
- **Visual Effects**: Confetti animations and 3D dice rendering
- **Cross-platform**: iOS and macOS support

### Technology Stack
- **Language**: Swift 5.5+
- **UI Framework**: SwiftUI
- **3D Rendering**: RealityKit
- **Data Persistence**: UserDefaults with Codable
- **Architecture Pattern**: MVVM with ObservableObject

---

## Architecture

### High-Level Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                     LowRollerApp                         │
│                    (Main Entry Point)                    │
└─────────────────┬───────────────────────────────────────┘
                  │
      ┌───────────┴────────────┐
      │                        │
┌─────▼──────┐         ┌───────▼────────┐
│PreGameView │         │   GameView     │
│  (Lobby)   │         │ (Active Game)  │
└────┬───────┘         └───────┬────────┘
     │                         │
     │                    ┌────▼────────┐
     │                    │ GameEngine  │◄──────┐
     │                    │ (Core Logic)│       │
     │                    └─────┬───────┘       │
     │                          │                │
     │                    ┌─────▼───────┐       │
     │                    │BotController├───────┘
     │                    └─────────────┘
     │
┌────▼────────────────────────────────────┐
│          Shared Services                 │
│  ┌────────────┐  ┌──────────────────┐  │
│  │EconomyStore│  │LeaderboardStore  │  │
│  └────────────┘  └──────────────────┘  │
└──────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Key Files |
|-----------|---------------|-----------|
| **LowRollerApp** | Application lifecycle, scene management | `LowRollerApp.swift` |
| **PreGameView** | Game setup, player configuration | `PreGameView.swift`, `SetupView.swift` |
| **GameView** | Active game UI, turn management | `GameView.swift`, `HUDView.swift` |
| **GameEngine** | Core game logic, state management | `GameEngine.swift` |
| **BotController** | AI turn automation | `BotController.swift` |
| **EconomyStore** | House bank, borrowing system | `EconomyStore.swift` |
| **LeaderboardStore** | Player statistics, rankings | `LeaderEntry.swift` |

---

## Core Components

### GameEngine

The `GameEngine` is the central game controller managing all game state and logic.

#### Key Responsibilities
- **State Management**: Maintains `GameState` with all game data
- **Turn Logic**: Handles dice rolls, picks, and turn progression
- **Phase Transitions**: Manages Normal → Sudden Death → Double-or-Nothing flow
- **Scoring**: Calculates scores and determines winners
- **Bot AI**: Implements amateur and pro-level decision making

#### State Flow

```
         ┌──────────────┐
         │   SETUP      │
         └──────┬───────┘
                │
         ┌──────▼───────┐
         │   NORMAL     │◄────────┐
         │   PHASE      │         │
         └──────┬───────┘         │
                │                 │
    ┌───────────┴──────────┐     │
    │                      │     │
┌───▼────┐           ┌─────▼──┐  │
│ WINNER │           │ SUDDEN │  │
│ FOUND  │           │ DEATH  ├──┘
└───┬────┘           └────────┘
    │
┌───▼────────────┐
│ AWAIT DOUBLE   │
└───┬────────────┘
    │
┌───▼────────────┐
│   FINISHED     │
└────────────────┘
```

### BotController

Manages automated turns for AI players.

#### Features
- **Async Execution**: Uses DispatchWorkItem for delayed actions
- **Adaptive Timing**: 350ms delay between bot actions
- **Chain Processing**: Automatically continues when multiple bots play consecutively

---

## Game Engine

### Core Methods

#### `roll() -> [Int]`
Generates dice rolls for the current player's turn.

**Process**:
1. Checks if player can afford the roll
2. Generates random faces (1-6) for remaining dice
3. Handles borrowing if bankroll insufficient
4. Returns array of dice faces

#### `pick(face: Int) -> Bool`
Records a player's dice selection.

**Parameters**:
- `face`: The dice value to pick (1-6)

**Returns**:
- `true` if pick was valid
- `false` if face unavailable or already picked

#### `fallbackPick()`
AI decision-making logic for bot turns.

**Amateur Strategy**:
- Picks lowest available face first
- Falls back to random selection

**Pro Strategy**:
- Evaluates risk/reward ratios
- Considers position relative to opponents
- Makes strategic high-value picks when ahead

#### `endTurnIfDone() -> Bool`
Checks if current turn is complete and advances to next player.

**Process**:
1. Verifies all dice have been placed
2. Increments turn counter
3. Checks for phase transitions
4. Returns whether game has ended

---

## User Interface

### View Hierarchy

```
LowRollerApp
├── PreGameView (Lobby)
│   ├── SetupView (Player Configuration)
│   └── LeaderboardList
│
└── GameView (Active Game)
    ├── HUDView (Status Display)
    │   ├── Pot Display
    │   ├── House Bank Display
    │   ├── Timer Display
    │   └── Player Strip (Horizontal Scroll)
    │
    ├── Dice Display Area
    │   └── DiceView (per die)
    │       └── Pip Layout
    │
    ├── Control Buttons
    │   ├── Roll Button
    │   ├── Pick Buttons
    │   └── End Turn Button
    │
    └── ConfettiView (Victory Animation)
```

### Key UI Components

#### HUDView
Displays game status information:
- **Pot Amount**: Current prize pool
- **House Bank**: Economy store balance
- **Timer**: Game duration
- **Player Strip**: Scrollable list showing all players' status

#### DiceView
Custom dice renderer with:
- **Dynamic Sizing**: Adjustable via `size` parameter
- **Selection State**: Yellow border when selected
- **Shake Animation**: Visual feedback on roll
- **Pip Layout**: Accurate dice face representation

#### ConfettiView
UIKit-based particle system for victory celebrations:
- **Multiple Shapes**: Rectangle, circle, triangle, diamond, star
- **Customizable Colors**: 8 default colors
- **Performance Optimized**: CAEmitterLayer implementation

---

## Data Models

### Player Model

```swift
struct Player {
    let id: UUID                  // Unique identifier
    var display: String           // Display name
    var isBot: Bool              // AI-controlled flag
    var botLevel: BotLevel?      // Amateur/Pro for bots
    var wagerCents: Int          // Per-roll wager
    var picks: [Int]             // Selected dice values
    var bankrollCents: Int       // Current balance
}
```

### GameState Model

```swift
struct GameState {
    var players: [Player]              // All participants
    var turnIdx: Int                   // Current player index
    var remainingDice: Int             // Dice left to roll
    var lastFaces: [Int]               // Current roll results
    var potCents: Int                  // Prize pool
    var phase: Phase                   // Game phase
    var winnerIdx: Int?                // Winner index
    var suddenContenders: [Int]?       // Sudden death players
    var doubleCount: Int               // Double-or-nothing count
}
```

### Phase Enum

```swift
enum Phase {
    case normal        // Regular gameplay
    case suddenDeath   // Tiebreaker phase
    case awaitDouble   // Double-or-nothing decision
    case finished      // Game complete
}
```

---

## AI System

### Bot Roster

Pre-defined AI opponents with personality:

#### Amateur Bots (7 total)
- Dicey McRollface
- Bet Midler
- Snake Eyes Sally
- Sir Lose-A-Lot
- Bluffalo Bill
- Risky Biscuit
- Rollin' Stones

#### Pro Bots (7 total)
- High Roller Hank
- Bot Damon
- The Count of Monte Crisco
- Win Diesel
- Lady Luckless
- Pair O'Dice Hilton
- Claude Monetball

### AI Decision Making

#### Amateur Algorithm
```
1. Check available faces
2. Pick lowest value (1, 2, 3)
3. If none available, pick random
```

#### Pro Algorithm
```
1. Evaluate game state
2. Calculate position vs opponents
3. If winning by > 3 points:
   - Take risks with higher values
4. If losing or close:
   - Conservative, pick low values
5. Consider remaining dice count
```

---

## Economy System

### EconomyStore

Singleton managing house bank:

```swift
class EconomyStore: ObservableObject {
    @Published var houseCents: Int
    
    func recordBorrowPenalty(_ cents: Int)
    func resetHouse()
}
```

### Borrowing Mechanics

When a player's bankroll goes negative:
1. **Automatic Loan**: Player can continue playing
2. **House Penalty**: 10% of borrowed amount goes to house
3. **Persistent Debt**: Carried across games
4. **Visual Indicator**: Red balance display

---

## Leaderboard System

### LeaderboardStore

Persistent storage for player statistics:

#### Metrics Tracked
- **Games Won**: Total victories
- **Dollars Won**: Cumulative pot winnings
- **Longest Streak**: Best consecutive wins
- **Current Streak**: Active win streak
- **Current Balance**: Persistent bankroll

#### Key Features
- **Case-Insensitive Matching**: Prevents duplicate entries
- **Automatic Deduplication**: Merges duplicate names
- **House Integration**: Shows casino earnings in balance view
- **Swipe Actions**: Reset balance or remove players

### Data Persistence

Uses UserDefaults with JSON encoding:
- **Key**: `lowroller_leaders_v1`
- **Migration Support**: Handles missing fields gracefully
- **Backward Compatibility**: Defaults for new fields

---

## Analytics

### AnalyticsLogger (Referenced but not included)

The game integrates with an analytics system tracking:
- Match outcomes
- Player performance
- Bot difficulty effectiveness
- Economy metrics

### Events Tracked
- Game start/end
- Turn actions
- Borrowing events
- Double-or-nothing decisions

---

## API Reference

### GameEngine Public Methods

#### `init(players:baseWager:)`
Creates new game engine instance.

**Parameters**:
- `players: [Player]` - Array of participants
- `baseWager: Int` - Per-roll wager in cents

#### `roll() -> [Int]`
Executes dice roll for current player.

**Returns**: Array of dice faces (1-6)

#### `pick(face: Int) -> Bool`
Records player's dice selection.

**Parameters**:
- `face: Int` - Selected dice value

**Returns**: Success status

#### `endTurnIfDone() -> Bool`
Completes turn if all dice placed.

**Returns**: Whether game has ended

#### `handleDoubleOrNothing(accept: Bool)`
Processes double-or-nothing decision.

**Parameters**:
- `accept: Bool` - Player's choice

### LeaderboardStore Public Methods

#### `recordResult(name:didWin:potCents:)`
Records single game outcome.

**Parameters**:
- `name: String` - Player name
- `didWin: Bool` - Victory status
- `potCents: Int` - Pot amount won

#### `updateBankroll(name:bankrollCents:)`
Updates player's persistent balance.

**Parameters**:
- `name: String` - Player name
- `bankrollCents: Int` - New balance

#### `top10(by:) -> [LeaderEntry]`
Retrieves leaderboard rankings.

**Parameters**:
- `by: LeaderMetric` - Sorting criterion

**Returns**: Sorted array of top entries

### NameValidator Public Methods

#### `isValidName(_ name: String) -> Bool`
Checks if name is available.

**Parameters**:
- `name: String` - Proposed name

**Returns**: Availability status

#### `sanitizeName(_ name:fallback:) -> String`
Creates valid version of name.

**Parameters**:
- `name: String` - Original name
- `fallback: String` - Default if invalid

**Returns**: Validated name

---

## Configuration

### Constants

| Constant | Value | Description |
|----------|-------|-------------|
| Starting Bankroll | $100 (10,000¢) | Initial player balance |
| Max Players | 8 | Including human player |
| Dice Count | 7 | Per player per game |
| Bot Delay | 350ms | Between AI actions |
| Turn Timer | Variable | Shown in MM:SS format |
| Borrow Penalty | 10% | House fee on loans |

### Storage Keys

| Key | Purpose |
|-----|---------|
| `lowroller_leaders_v1` | Leaderboard data |
| `lowroller_name_ios` | Stored player name |

---

## Performance Considerations

### Optimization Strategies

1. **Lazy View Loading**: SwiftUI's built-in optimization
2. **Dispatch Queues**: Async bot processing
3. **CAEmitterLayer**: Hardware-accelerated confetti
4. **Codable Migration**: Graceful data updates
5. **Set Operations**: Efficient bot ID tracking

### Memory Management

- **Weak References**: BotController → GameEngine
- **Cancellable WorkItems**: Prevents timer leaks
- **View State Cleanup**: Proper lifecycle handling

---

## Security Considerations

### Name Validation
- Prevents impersonation of system/bot names
- Sanitizes user input
- Reserves casino/house identifiers

### Data Integrity
- UUID-based identification
- Case-insensitive name matching
- Automatic deduplication

---

## Future Enhancements

### Potential Improvements
1. **Network Multiplayer**: Real-time online games
2. **Tournament Mode**: Structured competitions
3. **Achievement System**: Unlockable rewards
4. **Custom Dice Skins**: Visual customization
5. **Statistics Dashboard**: Detailed analytics
6. **Replay System**: Game recording/playback

---

## Version History

Current implementation appears to be version 1.0 based on:
- Creation dates: October 2025
- Storage key: `v1` suffix
- Feature completeness

---

## Support & Maintenance

### Common Issues

1. **Negative Bankroll Display**: Working as intended (debt system)
2. **Bot Name Conflicts**: Handled by NameValidator
3. **Leaderboard Duplicates**: Auto-merged on startup
4. **Sudden Death Ties**: Continues until single winner

### Debug Commands

The game includes notification-based navigation:
- `Notification.Name.lowRollerBackToLobby`: Return to setup screen

---

## Conclusion

LowRoller demonstrates a well-architected iOS/macOS game with:
- Clean separation of concerns
- Robust state management
- Engaging AI opponents
- Persistent player progression
- Polished user experience

The codebase follows Swift best practices with proper use of SwiftUI, Combine, and modern Swift features.

# Coding Wizard 🧙‍♂️

A puzzle platformer where you write GDScript code to solve puzzles and progress through a medieval fantasy world. Learn programming concepts while having fun!

## About

**Coding Wizard** is an educational puzzle platformer that teaches programming through gameplay. Players write actual GDScript code to manipulate the game environment, spawn platforms, change gravity, and solve increasingly complex puzzles.

### Features

- 🪄 **Learn by Doing**: Write real GDScript code to solve puzzles
- 📜 **Progressive Learning**: Start with visual blocks, graduate to full coding
- 🧩 **Puzzle Platforming & Action Adventure**: Cross gaps, avoid hazards, fight enemies and explore the world!
- 🏰 **Medieval Fantasy Theme**: Play as a wizard learning spells to progress through the world and increase their experience
- 🎮 **Desktop Support**: Windows, Linux, macOS

## Getting Started

### Prerequisites

- **Godot 4.7+**: Download from [godotengine.org](https://godotengine.org/download/windows/)
- **VS Code** (Recommended): With [Godot Tools extension](https://marketplace.visualstudio.com/items?itemName=geequlim.godot-tools)

### Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/LawrenceLS/code-adventure.git
   cd code-adventure
   ```

2. Open the project in Godot:
   - Launch Godot 4.7
   - Click "Import" and select the `project.godot` file
   - Or open Godot and use "Scan" to find the project

3. Configure VS Code (Optional but recommended):
   - Open the project folder in VS Code
   - Install the Godot Tools extension
   - See `SETUPINSTRUCTIONS.md` for detailed instructions

4. Run the game:
   - Press `F5` or click the play button in Godot
   - The game will open in the connected world, starting at Zone 1 "The Awakening"

## How to Play

### Controls

| Action | Input |
|--------|-------|
| Move | Arrow Keys / WASD |
| Jump | Space / Up Arrow |
| Open Code Editor | `Tab` or `E` |
| Execute Code | `Ctrl+Enter` / `F5` |

### Gameplay

1. **Explore** the level as the wizard character
2. **Open the Code Editor** when you reach a puzzle
3. **Write GDScript code** to solve the puzzle (e.g., spawn platforms)
4. **Execute** your code and watch it happen in real-time
5. **Reach the goal** to complete the level

### Example Code

```gdscript
# Spawn a bridge of platforms
for i in range(5):
	spawn_platform(200 + i * 100, 300)

# Change gravity to float upward
change_gravity(-500)

# Teleport to safety
teleport_player(400, 200)
```

## Project Structure

```
code-adventure/
├── Assets/                 # Sprites, audio, fonts
├── Resources/              # Godot resources
│   ├── api_tiers/          # API whitelists per tier
│   └── levels/             # Level configurations
├── Scenes/                 # Game scenes
│   ├── Levels/             # Playable levels
│   ├── Player/             # Player character
│   └── UI/                 # User interface
├── Scripts/                # GDScript code
│   ├── Core/               # Sandbox, API, progression
│   ├── Levels/             # Level logic
│   ├── Player/             # Player controller
│   └── UI/                 # UI logic
└── project.godot           # Godot project file
```

## Core Systems

### CodeSandbox
Safely executes player-written GDScript with:
- API whitelisting per level tier
- Execution timeouts
- Statement limits
- Forbidden pattern detection

### WizardAPI
Defines allowed functions per progression tier:
- **Apprentice**: `spawn_platform()`, `change_gravity()`, `teleport_player()`, conditionals
- **Journeyman**: Loops, functions, `match`, `tween_property()`, `get_node()`
- **Master**: `instantiate_scene()`, `connect_signal()`, `physics_raycast()` (full sandbox with limits)

### ProgressionManager
Tracks your progress:
- Unlocked API tiers
- Completed levels
- Saved code solutions

## Development

### Tech Stack

- **Engine**: Godot 4.7
- **Language**: GDScript
- **Renderer**: GL Compatibility
- **Physics**: Jolt Physics

### Building from Source

1. Clone the repo
2. Open in Godot 4.7
3. Press `F5` to run

### Exporting

The project is configured for desktop exports (Windows/Linux/macOS). See Godot documentation for export presets.

## Roadmap

- [x] **Phase 1**: Core sandbox, Apprentice tier, MVP level
- [x] **Phase 1.5**: Journeyman & Master tiers, crash guards
- [x] **Phase 2**: Single connected world stage with 4 puzzle zones
- [ ] **Phase 3**: Respawn checkpoints, visual block palette, dedicated HUD scene
- [ ] **Phase 4**: Polish, sound design, tutorial levels

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Open a pull request

## License

See [LICENSE](LICENSE) for details.

## Acknowledgments

- [Godot Engine](https://godotengine.org/) - Amazing game engine
- [GDScript](https://docs.godotengine.org/) - Fun to write with
- All the aspiring wizards who will play this game!

---

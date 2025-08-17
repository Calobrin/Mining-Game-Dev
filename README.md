May as well make a README eventually so uh, here we go.

This Github Repository is to track the progress of my development of my game. 
I am making a Mining Game in Godot that will allow players to go into a mines and dig up shiny crystals, rocks, or other valuable minerals just for fun. 
I am inspired by games like Webfishing (and a bit of Atlyss) to make a fairly mindless but chill game just about gathering shiny things in the ground.

## Style Guide (Concise)

- **Naming**
  - Scenes: `PascalCase` (e.g., `MiningMinigame.tscn`)
  - Script files: `snake_case.gd` (e.g., `mining_minigame.gd`)
  - Classes: `PascalCase` via `class_name` (e.g., `class_name MiningMinigame`)
  - Signals: `snake_case` describing event (e.g., `item_collected`)

- **Types & Exports**
  - Use typed GDScript for vars, function params, and return types.
  - Prefer `@export` for inspector-configurable values.

- **Paths & Globals**
  - Prefer `class_name` classes and Autoload singletons over hardcoded paths.
  - Use `Constants.Paths` for shared resource paths (e.g., `Constants.Paths.MINING_ITEMS_JSON`).
  - Global signals live in `Signals` autoload.

- **Folders (light organization)**
  - `Scenes/world/`, `Scenes/minigame/`
  - `Scripts/minigame/`, `Scripts/generation/`, `Scripts/data/`

- **Signals usage**
  - Emit: `Signals.item_collected.emit(item_id)`
  - Connect: `Signals.item_collected.connect(_on_item_collected)`

## Autoloads

- `Global` (existing)
- `MiningItemDatabase` (existing data system; loads JSON)
- `Constants` (new): shared constants and paths
- `Signals` (new): global signals hub

In branch 0.02 I set up an interactable 3DSprite/label with an Area3D to detect when the player enters its radius and enables the "E" interact key. When interacting with this sprite it will scene swap into the actual Mines level 1 scene. 
I also set up the interactable sprite to exist within the mines so the player can then leave and return to "town".
Which then caused the obvious problem of appearing at the default player node location so I set up a spawnpoint node that I can name to allow multiple "landing spots" when tranporting from various scenes into town.

I set up a global.gd script that I can use to keep track of the current scene, made a script to attach to town which will detect what scene the player is coming from and move the players location 
to that of the spawnpoint nodes I created that match to what scene they were coming from

Still learning a lot and there is likely a better way to do what I am doing, but hey I am slowly making progress.

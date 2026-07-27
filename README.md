THS IS THE README FOR MY YUGIOH FAN GAME PROJECT

# YGOStoryGame

YGOStoryGame is an unfinished Yu-Gi-Oh! JRPG prototype built in Godot. The idea was to combine classic RPG systems like exploration, quests, NPC dialogue, cutscenes, shops, money, unlocks, maps, music, and progression with a Pokemon-like structure: instead of walking into battles with monsters, the player walks into story duels using Yu-Gi-Oh! decks.

The duel engine is EDOPro, an open-source Yu-Gi-Oh! simulator. I chose to integrate EDOPro instead of building a full duel engine from scratch because Yu-Gi-Oh! rules, card effects, chains, timings, deck legality, summoning rules, and thousands of card scripts would be far too large for a solo prototype. The hardest engineering challenge became making the Godot RPG and the external EDOPro/WindBot runtime behave like one game.

## Status

This project is currently paused and does not have a ready public release package.

The main blocker was not the RPG systems or the Godot-to-EDOPro launch flow. The project stopped because enemy AI was not viable at the quality level I wanted. In WindBot, strong AI behavior requires custom executor code for each deck. In this setup those executors are compiled C#/.NET AI modules that decide how the bot uses cards, combos, priorities, and win conditions. Writing and maintaining a reliable executor for every story opponent would take a tremendous amount of time, even with the tools available, so the project was paused in its current form.

## Demo

No public build is available yet. The best way to review the project is through a short gameplay/integration video plus selected code samples. A future demo video should show the story scene, NPC duel trigger, EDOPro launch, WindBot joining, duel result handling, and reward application back in Godot.

## Game Concept

The player explores a JRPG-style world, talks to NPCs, completes quests, earns currency, unlocks cards, buys from card shops, opens packs, and progresses through story events. When a story duel starts, the game hands off the actual duel to EDOPro, then reads the result back into Godot so the story can continue.

In simple terms:

```text
Pokemon-style RPG exploration
  + Yu-Gi-Oh! deck progression
  + EDOPro as the duel engine
  + WindBot as the enemy duelist
```

## What I Built

- A Godot 4 JRPG launcher with explorable maps, interiors, NPCs, dialogue, cutscenes, shops, save slots, quests, flags, unlocks, rewards, music, and SFX.
- A card shop and pack/unlock system where the player spends in-game currency to unlock cards and expand their available deck pool.
- A data-driven `GameData` structure for NPCs, dialogue, duel sessions, packs, shops, quests, maps, music, SFX, save templates, and generated card pack data.
- A Python toolchain that bridges the Godot launcher with EDOPro and WindBot.
- A duel startup pipeline that prepares a WindBot session, validates player decks, launches EDOPro, waits for the LAN room, launches WindBot, and restores WindBot files afterward.
- A progression sync layer so Godot card unlocks affect what the player is allowed to use in EDOPro.
- A duel result pipeline that reads duel results back into the Godot save system and applies story rewards.
- Modified EDOPro/WindBot runtime folders with custom decks, custom executor DLLs, card databases, scripts, lflists, and runtime configuration.
-Multiple fully explorable and ready Maps and areas with other explorable sub areas

## High-Level Architecture for Dueling/Battle Gameplay

```text
Godot story scene
  -> duel prompt
  -> Python session preparation
  -> deck validation against unlocked cards and EDOPro card databases
  -> EDOPro.exe launch
  -> WindBot.exe launch with selected AI deck
  -> duel result JSON
  -> post-duel validation
  -> reward application
  -> Godot save/story state continues
```

## Key Systems

### Godot Launcher

The Godot project lives in:

```text
Launcher/ygo-story-launcher
```

Important systems include:

- `SaveManager` for save slots, autosaves, backups, world state, inventory, flags, quests, relationships, ranks, and progression data.
- `UnlockManager` for unlocked cards and regenerated story banlists.
- `RewardManager`, `ConditionManager`, and `DialogueManager` for story progression.
- Player movement, area transitions, NPC spawning, map/interior scenes, cutscene playback, music, SFX, shops, and area configuration loaded from JSON data.

### Python Bridge

The Python tools live in:

```text
Launcher/ygo-story-launcher/Tools
```

Important tools include:

- `prepare_windbot_session.py` - loads a duel session config, backs up WindBot files, rewrites `bots.json`, and selects the correct AI deck.
- `pre_duel_validate.py` - checks player decks against unlocked cards and EDOPro `.cdb` databases before a duel can start.
- `launch_windbot_from_session.py` - starts WindBot with the selected deck and LAN room settings.
- `post_duel_validate.py` - checks the duel result before rewards are allowed.
- `apply_duel_rewards.py` - applies duel rewards back into the active Godot save.
- `generate_story_banlist.py` - regenerates the story banlist from the player's unlocked card pool.

### EDOPro and WindBot Integration

The modified runtime folders live in:

```text
EDOPro
EDOPro/WindBot
```

This project uses EDOPro as the duel engine and WindBot as the AI opponent. The Godot launcher does not simulate card gameplay itself. Instead, it prepares the story context, validates decks, launches the duel runtime, and consumes the duel result afterward.

The difficult part was keeping the external duel simulator synchronized with the RPG. Godot tracks player progress, unlocked cards, currency, quests, and story flags. EDOPro is a separate application with its own decks, card databases, scripts, and banlists. I had to create helper tools that translate Godot progression into EDOPro-compatible behavior.

Examples:

- If the player unlocks cards in Godot, those cards become part of the allowed card pool.
- If the player tries to duel with locked cards, the Python validation step blocks the duel before EDOPro starts.
- The story banlist can be regenerated from the player's unlocked card pool.
- WindBot is temporarily configured with the correct enemy deck for the selected story duel.
- After the duel closes, WindBot files are restored and the result is checked before rewards are applied.

## Current Release State

A downloadable `YGOStoryGame-Setup.exe` is not ready yet.

Before a tester-friendly release can be made, the project needs:

- Portable paths instead of development-machine paths such as `C:/Users/...` or `C:/YGOStoryGame`.
- A bundled runtime solution so testers do not need to install Godot, Python, Visual Studio, or development tools.
- A Godot Windows export preset and release build.
- A cleaned release folder containing the exported Godot game plus only the required EDOPro/WindBot runtime files.
- A decision on whether to ship Python scripts, replace them with Godot/C#, or compile them into a helper executable.
- A reliable solution for WindBot executor AI per opponent deck.

## Why The Project Stopped

The project reached the point where the technical bridge between systems was possible, but the AI design problem became the limiting factor. For the game to feel good, each story opponent needs an AI that understands its deck's combos, priorities, and win conditions.

WindBot can play decks well only when it has strong executor logic. A generic enemy AI did not produce good enough duel behavior, and writing a custom executor for every deck was too slow and unreliable for a solo project. Rather than ship a story game where many duels felt broken, random, or unfair, I stopped the project after documenting the integration work and the release blockers.

## Code Worth Highlighting

These are the strongest areas to show in a public portfolio version:

| Area | Files | Why it matters |
| --- | --- | --- |
| Duel orchestration | `Launcher/ygo-story-launcher/Scripts/duel_prompt_prototype.gd` | Shows Godot launching external processes, waiting for EDOPro, calling Python tools, and managing duel state. |
| Save/progression system | `Launcher/ygo-story-launcher/Scripts/save_manager.gd` | Shows structured save data, backups, world state, inventory, quests, flags, and reward persistence. |
| Card unlock pipeline | `Launcher/ygo-story-launcher/Scripts/unlock_manager.gd`, `Launcher/ygo-story-launcher/Tools/generate_story_banlist.py` | Shows how unlocked cards affect deck legality and story progression. |
| WindBot session prep | `Launcher/ygo-story-launcher/Tools/prepare_windbot_session.py` | Shows backup/restore safety, session-driven bot selection, and runtime file preparation. |
| Deck validation | `Launcher/ygo-story-launcher/Tools/pre_duel_validate.py` | Shows SQLite `.cdb` scanning, `.ydk` parsing, and validation against player unlock state. |
| Reward application | `Launcher/ygo-story-launcher/Tools/post_duel_validate.py`, `Launcher/ygo-story-launcher/Tools/apply_duel_rewards.py` | Shows the result-to-reward bridge after external duels finish. |
| Data-driven content | `Launcher/ygo-story-launcher/GameData/configs` | Shows that NPCs, dialogue, duels, packs, shops, and quests were designed as editable JSON data. |

## Suggested Portfolio Demo

A short demo video would explain this project better than asking someone to install it.

Recommended video structure:

1. Start in the Godot launcher.
2. Talk to an NPC.
3. Trigger a duel session.
4. Show pre-duel validation.
5. Launch EDOPro.
6. Show WindBot joining with the selected deck.
7. Finish or simulate the duel result.
8. Return to Godot and show rewards/story state changing.

Keep the video under two minutes for recruiters.

## Repository Notes

This repository is best treated as a prototype/work-in-progress, not a polished end-user product. A public portfolio version should avoid shipping development-only folders, local runtime files, logs, crash dumps, generated debug reports, private paths, and editable Godot source files unless intentionally sharing code samples.

For a public recruiter-facing version, I would include:

- This README.
- A short demo video or GIF.
- Screenshots.
- Selected Godot and Python code samples.
- A trimmed architecture document.
- A clear note that the release package is not currently available.

I would avoid including:

- Full editable Godot project files unless source sharing is intended.
- Personal save/runtime data.
- Local logs and crash dumps.
- Development caches such as `.godot`.
- Backup binaries and old test outputs.
- Any third-party assets or binaries that cannot be redistributed safely.

## Lessons Learned

- Cross-application game integration needs strict control over process launch, working directories, file handoff, and failure recovery.
- A playable prototype can be blocked by AI quality even when the surrounding game systems work.
- Data-driven JSON content made it easier to create many NPCs, duel sessions, packs, and story conditions.
- Reusing a proven simulator can be the right technical decision when the domain rules are too complex to recreate from scratch.
- Releasing a Windows game requires a different layer of engineering than building it locally: portable paths, installer layout, runtime dependencies, source protection, and clean test environments.
- For portfolio purposes, a clear README, short video, architecture summary, and selected code samples may communicate the work better than an unfinished installer.

## Disclaimer

This is a personal fan/prototype project and is not affiliated with or endorsed by Konami, Yu-Gi-Oh!, EDOPro, or WindBot. Third-party tools, assets, card data, and binaries may have their own licenses and redistribution rules. A public release would require additional licensing and packaging review.

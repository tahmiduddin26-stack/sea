# Polish pass plan (from playtest notes)

Every note from the playtest is one line below, grouped into phases. Tick them off as they land.
Rule for all UI work: one **ship theme** (wood planks, brass rivets, rope trim, parchment bodies, porthole close
button) built once in `client/UI.luau`, so every menu picks it up and stays consistent.

## Phase 1: Ship world (server/WorldBuilder.luau, client/FittingView.luau)
- [x] 1.1 Cannons reachable: mount them on the deck rail (not outside the hull) with a "Load Cannonball" prompt;
      a loaded cannon shows a ball and fires at the start of your next battle, an empty one does not.
- [x] 1.2 Locked floors really locked: side walls along both sides of the Floor 2 and Floor 3 stairs so nobody can
      jump onto the stairs around the barrier (rails stay, gate opens when bought).
- [x] 1.3 Safe swim area: invisible wall ring around the water so nobody swims out to nowhere.
- [x] 1.4 Climb back: ladders/stairs from the water onto the ship, and from the fight-viewing spot back up to the deck.
- [x] 1.5 Signs: shorten the wooden posts so they don't overlap the sign face ("Pick who fights", etc.).

## Phase 2: UI theme kit (client/UI.luau, Hud toasts)
- [x] 2.1 Ship theme in `UI.luau`: timber outlines, parchment panels, `UI.window` (plank frame, rivets, hanging title sign,
      porthole close), `UI.plank`, `UI.rivet`. Every `Menus.window` uses it. (built, not play-tested)
- [x] 2.2 Toasts and errors always on top: toast holder moved to the screen with ZIndex 1000 (was under menus).
- [x] 2.3 Currency clarity: tap the pearl/coin chip (or its "?") for a card: what it is, where to get it, what it buys.
      Egg Shop footer lists pearl sources; Tide Festival text now says shells come from Free Gifts/Daily Chest
      (the old text wrongly said battles drop them); Free Gifts cards show their bonus shells.

## Phase 3: Restyle every menu (client/Menus.luau + views)
- [x] 3.1 Team: "Pick who fights" gets the new frame, warm cards and a DMG/s sticker on every monster
- [x] 3.2 Free Gifts / Daily Chest: new frame, warm cards, bonus shells shown
- [x] 3.3 Missions: plank header, parchment rows, "N coins + N pearls" rewards
- [x] 3.4 Spellbook: new frame and 19 Blender spell icons mapped to all 34 spells (`Config.SPELL_ICON`)
- [x] 3.5 Egg Shop: pearl-source footer; Golden Egg 180 -> 400 pearls (it is x2 stats, better than the 260 Epic at x1.6)
- [x] 3.6 Treasure Shop: Elemental Bundle card says "1 egg of each element"; the world sign says "4 eggs: Tide, Coral,
      Storm, Abyss | R$199"
- [x] 3.7 Power Shrine / Tide Powers: new frame (the content layout is unchanged)
- [x] 3.8 Tide Festival: new frame, truthful shells text
- [x] 3.9 Leaderboard board redrawn: rank | name (cut with ...) | depth in separate columns on plank rows
- [x] 3.10 Abyss Crate stutter: NPC rigs now move in one `BulkMoveTo` per rig at 30 Hz and only when visible; crate
      point lights cut from three big to three small. (cause not profiled in Studio: check it)

## Phase 4: Gameplay readouts and fuse flow
- [x] 4.1 Damage sticker on every nest nameplate, in the Team cards, and "DAMAGE N / sec" on the hatch/fuse reveal card.
- [x] 4.2 Fuse tray (`FuseView.luau`): the Fuse button / E on a monster opens a bottom plank tray with two slots; the
      monster flies into its slot; FUSE! lights up when both are filled.

## Phase 5: Effects
- [x] 5.1 Spell cast effect (`Hud.spellCast`): colour flash, spinning rays, rings, sparkles, big icon + name, then the
      icon flies to the buff row. Drawn above every menu (the old splash hid behind the Spellbook).
- [x] 5.2 Spell icons rendered in Blender (`assets/icons/build_spell_icons.py`) and uploaded to the group; the Pearls
      icon was still in moderation when uploaded, so check it shows in game.

## First five minutes playtest

Fresh-profile Studio run with keyboard and mouse, reviewed from the perspective of players ages 9–15. The run covered the intro, two hatches, the first fight, the first fuse, and a second fight. The starter lost at Depth 1. After fusing, the next fight beat three enemies and reached Depth 2.

| What could confuse a new player | Change |
| --- | --- |
| The crate countdown covered the fishing instruction and advertised an unrelated activity. | Hold crate announcements until the tutorial ends. Show that the hook is bringing up an egg during the cast. |
| Turning toward the arena made the guide vanish. TAKE also used coins without saying so in the guide. | Keep the guide visible from any angle on deck and show the price in the TAKE instruction. |
| The nest showed a paid Hatch Now prompt while the tutorial wanted the player to wait. | Show the countdown and name the OPEN action. Hide the paid shortcut during the tutorial. |
| The first goal said to beat a mini-boss. The starter lost at Depth 1, and the result gave no specific next action. | Explain that monsters fight automatically, hold the first arena view longer, and show Go Fish on the first result. Keep Fight out of the way until the first fuse is complete. |
| After the fuse and next battle, the player could see their team resting but had no suggested action. | Tell the player they can fish while the team rests. Give a clear next goal when the fuse reveal ends. |

## Next onboarding simplification pass

1. Give players one next action after the first fuse. Point to Fight first, then offer “Fish while your monster rests” after the result. Check that players recover from a loss without help.
2. Keep the first harbour trip focused. Lead new players to Captain Coral and let them choose one destination. Suggested choices are the Egg Shop, the Dockyard, and Crab Cove.
3. Introduce extra systems when they become useful. Explain spells when the first card drops, team slots when the team fills up, and flag design when the player visits the mast.
4. Playtest on a phone with new players ages 9–12 and 13–15. Give them five minutes with no coaching. Note any pause over ten seconds, wrong button presses, and whether they can explain how to get another egg or improve their team.

## Fusion balance check

Fusion now preserves at least the parents’ combined regular-hit DPS, sustained DPS including energy attacks, and total HP. The floor uses the actual parents, including their finishes, permanent Powers, and earlier fusion bonuses. Natural stats can still exceed it. The displayed DPS is a neutral sustained average. Enemy matchups, perks, and combat buffs can change what happens in a fight.

The audit checked 36 species and 20,378 fusion outcomes across sampled level bands, including 2-, 3-, and 4-parent inputs, Divine pairs, Golden and Rainbow finishes, and previously fused parents. Three regular level-3 Splashfins combine for 31,200 sustained DPS. A natural level-4 Splashfin gives 16,640, while this fusion now gives 31,200.

Boss and mob HP stayed at their existing values. In a neutral damage-only estimate with six common fusions at the available level cap, bosses at stages 2, 10, and 20 take roughly 13, 22, and 44 seconds respectively. That estimate assumes every fighter stays alive and does not replace late-game playtesting.

## Notes
- Edit `src/` only with the Edit tool (sed/perl crash Rojo).
- Nothing in this pass changes balance except 3.5 (if the price review says so).

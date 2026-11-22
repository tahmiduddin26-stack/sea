# Merge Sea Monsters — Design Doc (formerly "Tide Tamers" / "Sea Monster Arena")

A merge-and-battle idle game on Roblox. Players roll monster eggs, hatch sea monsters, **merge two into one stronger
hybrid**, and send their team to auto-fight endless waves in an arena on their own island plot.

Built from hands-on research of a top dragon game (see `research/dragon-arena-notes.md`). We keep its **proven
loop and kid-friendly UI patterns**, but all art, names, creatures, story and numbers are our own.

---

## 1. Pillars

1. **Readable in 3 seconds.** One big button per action, one yellow keyword per instruction, arrows on the ground.
   A 7-year-old on a phone must never wonder what to do next.
2. **Merge surprise.** Every merge is a mini gacha reveal: two creatures go in, one *unknown* stronger hybrid comes out.
3. **Numbers go up, always.** Every run pays out, even a loss. Best Depth is shown publicly over your island.
4. **Idle-friendly.** Fights are automatic; monsters keep fighting offline.

---

## 2. Story hook

Intro cutscene (first join only, skippable after first view):

1. "Merge your Monsters!": two baby sea monsters play on the player's island.
2. Camera pans across the harbour hub, past a glowing mystery egg.
3. The villain **Maw, the Abyss King** (giant anglerfish-kraken) rises from the water and drags one of the player's monsters
   under: *"Want your friend back? Come find me at **Depth 240**!"*
4. Black card: **"Reach DEPTH 240 to rescue your monster..."**

We use **Depth** instead of "Wave": every wave is one level deeper, and the arena's water darkens as you go down.

---

## 3. Elements and creatures

Four base elements. Each base element has one starter species; hybrids come from merging two different elements.

| Element | Icon | Starter monster | Feel |
|---|---|---|---|
| Tide | water drop | **Splashfin** (baby sea serpent) | balanced |
| Coral | pink coral | **Reefback** (turtle) | tank, high HP |
| Storm | lightning | **Zapjelly** (jellyfish) | fast attacks |
| Abyss | purple eye | **Gloomeel** (eel) | high damage, low HP |

**Hybrids** (6 pairs; each pair has 2–3 possible species so merges stay surprising), e.g.:
- Tide + Storm: Thunderwhale
- Coral + Abyss: Bonereef
- Tide + Coral: Kelpdragon
- Storm + Abyss: Voidray

**Stars (1–5)** = rarity tier within a level. Higher stars = better stat multiplier and a fancier model and colour.
5-star monsters are rare chase items.

Monster stats: `HP`, `Attack`, `Attack Speed`, plus one element ability that fills an energy bar
(the blue bar under HP) and fires automatically.
**Element advantage** (a simple loop, shown on the enemy nameplate):
**Tide beats Abyss, Abyss beats Coral, Coral beats Storm, Storm beats Tide**
(+50% damage, shown as a big "SUPER!" popup). This is our addition; the research game didn't show counters this early.

---

## 4. Core loop

```
Roll egg at Clam Lever  ->  buy with coins  ->  carry to a Shell Nest  ->  hatch timer  ->  tap to open
        ^                                                                                        |
        |                                                                                        v
  spend coins on upgrades  <-  coins + pearls + boss eggs  <-  FIGHT (auto waves)  <-  MERGE two same-level monsters
```

### 4.1 Roll
- A **Clam Lever** on your island. Hold E, or tap on mobile, and a random egg pops onto a pedestal showing **element icon,
  name, level, coin price** (e.g. "Storm Egg Lv.1 — 800").
- Walk into the egg to buy it; it's carried overhead and appears in the hotbar.
- Upgrades: **Roll Luck** (better star odds), **Extra Pedestals** (roll 2, then 3 eggs at once, pick which to buy).

### 4.2 Hatch
- Walk to an empty **Shell Nest**; an "E Place" prompt appears. Egg sits in the nest with a countdown.
- At "Ready!" tap the egg for an element-themed burst (bubbles, sparks, ink cloud) and a reveal card with name, stars and level.
- Prompt "E Skip" pays Pearls to finish the timer instantly.
- Start with **3 nests**; buy more around the island edge (price tag floats over each locked nest).

### 4.3 Merge ("Breeding" in the research game, here called **Fuse**)
- Big **Fuse!** button bottom-centre (pink heart-shell icon).
- Panel: `[Monster A] + [Monster B] = Lv N+1`, timer, row of **possible outcomes with %**, big **Fuse!** button.
- Must be the **same level**. Both parents are **consumed**: they swim into one nest with bubbles and hearts, a timer runs,
  then a **silhouette reveal** shows ONE new monster at the next level.
- Fusing is free (coins), costs only time. Luck can be boosted (Robux).
- "Total Fuses" counter gates island upgrades (see 4.5).

### 4.4 Fight
- **FIGHT!** button top-centre + "Team Power: N".
- Team swims or flies to the **Reef Ring** arena in the middle of the island; nests show "IN FIGHT!".
- Enemies spawn one at a time. Fully automatic.
- **Depth tracker** (top): "Depth N", 15 dots per stage, green = cleared, skull = mini-boss (dot 8),
  horned skull = boss (dot 15). Controls: restart, speed toggle (x1/x2), Retreat.
- **Boss** every 15 depths: letterbox cutscene "BOSS: <name>", HP bar **plus countdown timer** (~20s). Beat it before the
  timer runs out or the run ends.
- Bosses drop a **higher-level egg** (e.g. Lv.3), which feeds straight back into the merge loop.
- Kills drop coins and sometimes pearls that fly to the HUD.
- When all monsters fall: **"Dive Over!"** panel with Depth reached, Coins Earned, Monsters Defeated, plus
  "Revive & Continue" (Robux) / "No Thanks". Losing still pays.
- **Offline fighting:** on rejoin, show "While you were away your team reached Depth X and earned Y coins".

### 4.5 Island evolution
Physical upgrade boards beside the island (the **Shop** button teleports you there):
- Roll Luck: +0% to +50% … (coins)
- Extra Pedestals: 1 to 2 to 3 (coins)
- Extra Nest slots (coins, rising price)
- **Unlock Floor 2 + Lighthouse (Boosts)**: requires **Total Fuses 20** AND 30K coins. Each floor adds nests and a
  new feature building (Lighthouse = boosts, Shipwreck = Powers, Aquarium = Index display...).

### 4.6 Powers (unlocks at Depth 30)
"Tide Powers": a spin wheel that grants a random passive buff to one monster (e.g. +20% attack speed). Spins cost
pearls; promo codes and group join give free spins.

---

## 5. Enemies (per stage theme)

| Stage | Depth | Theme | Normal mobs | Mini-boss | Boss |
|---|---|---|---|---|---|
| 1 | 1–15 | Sunny Shallows | Crab, Puffer, Seagull | Big Crab | **Captain Clawbeard** (pirate crab) |
| 2 | 16–30 | Kelp Forest | Urchin, Eel, Starfish | Kelp Lurker | **Mother Urchin** |
| 3 | 31–45 | Shipwreck | Skeleton Fish, Barnacle | Cannon Crab | **Ghost Captain** |
| 4 | 46–60 | Twilight Zone | Lanternfish, Squid | Glow Squid | **Siren Queen** |
| … | … | repeat themes with recolours and higher stats | | | |
| final | 240 | The Trench | — | — | **Maw, the Abyss King** |

---

## 6. Numbers (starting tunables — all in one shared `Config` module)

| Thing | Start value | Notes |
|---|---|---|
| Starting coins | 2,500 | enough for ~2 cheap eggs |
| Lv.1 egg price | 300–2,000 by element/roll | research game: 300–1,900 |
| First hatch timer | 6 s | later eggs scale with level |
| Fuse timer | 5 s at Lv.1, x1.5 per level | |
| Starting nests | 3 | extra nests from 1,500 coins, x1.6 each |
| Enemy HP | `base * 1.18^depth`, x5 jump at each new stage | research: 13 HP @ wave 12 to 81 HP @ wave 17 |
| Boss timer | 20 s | |
| Coins per kill | `10 + depth * 2` (approx.) | research: +16..+25 early |
| Pearls | ~1 per 3 kills + bonus at run end | research: ~100 at run end |
| Monster stats per level | x1.6 | Lv2 hybrid had ~1.4x HP of Lv1 |
| Stars multiplier | 1★ 1.0 / 2★ 1.25 / 3★ 1.6 / 4★ 2.1 / 5★ 3.0 | |

Tuning target: a new player loses around **Depth 7** solo, clears the **first boss after their first merge**, and reaches
**~Depth 25** in the first 10 minutes.

---

## 7. UI layout (keep these patterns — proven easy for kids)

All UI is big, rounded, thick dark outlines, bold chunky font, bright colours, icon + one word.

```
┌──────────────────────────────────────────────────────────────┐
│ [Roblox] [menu]          [ FIGHT! ]  / Depth bar        [⚙] │
│                       Team Power: 252                        │
│                                                              │
│ [Shop]      "Pull the lever to roll an EGG!"     [Starter  ] │
│ [Event ②]   (top banner, YELLOW keyword)         [Pack R$  ] │
│ [Index ④]                                        [Rotating ] │
│ [Team 0/3]          (3D world)                   [ offer   ] │
│                                                              │
│ [pearl] 20                                                   │
│ [coin] 4.8K           [ ♥ Fuse! ]   [hotbar]                 │
└──────────────────────────────────────────────────────────────┘
```

- **Left column:** Shop, Event, Index, Team. Red number badges for new things.
- **Right column:** Starter Pack + one rotating offer slot (cycles every ~30s).
- **Bottom-left:** currencies (Pearls above Coins), with "+N" popups when gained; abbreviate 1.5K / 2.3M.
- **Bottom-centre:** big Fuse! button + small hotbar for carried eggs/items.
- **Top-centre:** FIGHT! button when idle. When fighting it becomes the Depth bar, enemy name and HP bar, speed toggle and Retreat.
- **Tutorial:** one instruction at a time in the top banner with a yellow keyword; **red chevron arrows on the ground**
  lead to the target; a **pointing-hand icon** bobs over it. The next step only appears when the current one is done.
- **World billboards:** element icon + "Name Lv.N" + star row over every monster/egg; "Your Island" + "Best Depth: N" over plots.
- **Reveal moments** (hatch, fuse, boss): dim the screen, letterbox, silhouette, then pop with a particle burst.
- Mobile: every world action also works by tapping the object; all buttons ≥ 64 px.

### Tutorial script
1. "Pull the lever to roll an **EGG**!"
2. "Buy your first **EGG**!"
3. "Place your egg in a **NEST**!"
4. "Open your egg when it's **READY**!"
5. "Try to beat the **MINI BOSS**!" (they will lose around Depth 7)
6. "You need **MORE MONSTERS**!" (roll and hatch a second)
7. "Fuse your **2 MONSTERS**!"
8. "Buy a **TIDE EGG**!" (guaranteed cheap third monster) → auto-fight, beat the first boss → full HUD unlocks.

---

## 8. Monetization (Robux)

Same shapes the research game uses, priced on our own terms:

| Product | Type | Example price |
|---|---|---|
| Starter Pack (2 hybrids + pearls) | dev product, one-time | R$69 |
| VIP Club (+coins, chat tag, exclusive nest) | gamepass | R$349 |
| x2 Coins | gamepass | R$219 |
| x2 Fuse Speed | gamepass | R$299 |
| x2 Fight Speed | gamepass | R$59 |
| Fuse Luck / Insane Fuse Luck | dev product (timed) | R$119 / R$399 |
| Revive & Continue | dev product | scales with depth |
| Skip hatch / fuse timer | pearls (soft) or Robux | — |
| Limited monster rolls | event currency + Robux | odds always shown |

Rules: never sell power that can't also be earned slowly; always show roll odds; no purchase prompts during the tutorial.

---

## 9. Social and retention

- Up to 6 players per server, each with their own island around a shared harbour hub; Best Depth billboard visible to all.
- Group join = free egg. Promo codes = free Power spins.
- Daily login reward, timed events (seasonal limited monster + event currency), global Best Depth leaderboard.
- Index (collection book) with a reward for each new species discovered.
- Join the group (Gift Chest button) = a free 2-star egg + 2 Power spins, once.
- Friends in your server: +10% battle coins each (up to 3); Invite Friends button on the Gift Chest.
- One favourite prompt after the tutorial ends. Badges for first hatch, fuse, boss, a Legendary, Depth 50/100 and Maw.
- VIP Captain: gold nests, a gold "VIP CAPTAIN" tag over your head and [VIP] in chat.

### Analytics (Creator Dashboard, `server/Analytics.luau`)
- **Onboarding funnel:** step 1 joined, then one step per tutorial step.
- **Store funnel** per item: prompted, then purchased. **Vendor funnel** per vendor: opened, then used.
- **Economy:** every coin and pearl source and sink, tagged Shop / IAP / TimedReward / Onboarding / Gameplay.
- **Progression:** each dive start, stage clear and end. **Custom:** Hatch, Fuse, SpellDrop, SpellCast, DailyClaim, GiftClaim, Code, BestDepth.

### Controls
| Action | PC | Console | Mobile |
|---|---|---|---|
| Interact (winch, egg, nest, vendor, fuse pick) | E | X (prompt) | tap the prompt |
| Fight / Retreat | FIGHT button | X (when no prompt is up) | FIGHT button |
| How to fuse | heart button | Y | heart button |
| Robux shop | right-side offers | LB | right-side offers |
| Close menu | X button | B | X button |
| Reach HUD buttons | mouse | Select (menu cursor) | tap |

---

## 10. Build order (MVP first)

1. **Config + data:** shared Config, ProfileService-style save (coins, pearls, monsters, nests, best depth, total fuses).
2. **Island plot:** assign plot on join, nests, Clam Lever, Reef Ring arena (code-built).
3. **Roll → buy → carry → place → hatch** with timers.
4. **Fuse** with outcome table and reveal.
5. **Auto-combat** with depth bar, enemy scaling, mini-boss and boss timer, coin drops, run-end panel.
6. **HUD + tutorial** (arrows, banner, pointing hand).
7. Upgrade boards and island Floor 2.
8. Index, Team, Powers, offline progress.
9. Monetization products and events.

Server-authoritative throughout: client only sends intents (roll, buy, place, open, fuse, fight); the server owns all
timers, odds, combat and currency.

---

## 11. Open questions

- Team size limit (research game showed "Team 0/3"). Is it a cap on fighters, with the rest staying home?
- Does a lost run restart at Depth 1 or at the last boss checkpoint? (Recommend: last boss checkpoint.)
- What exactly fills the Index / Team / Event screens? (Not yet observed in research.)
- Late-game scaling past Depth 50 not yet observed.

## 11. Fishing, Ship Workshop and coin balance (latest)
- **Egg rod:** the old winch is a fishing rod. One cast = one egg. The cast (wind-up, whip, camera) is a Blender animation baked to `src/shared/RodAnim.luau` (`assets/fishing/build_rod_anim.py`); the dive is code. The hook dives a trench off the port side through 5 zones (`Config.FISH_ZONES`: Shallows/Tide, Kelp/Coral, Reef/Storm, Wreck/Abyss, Abyss/hybrids). The server rolls the stop zone (Egg Luck pushes deeper), the hook pulls ONE black egg out of a rock nest, and the pedestal shows only the egg TYPE; rarity is revealed at hatch. A cast takes about 9.5-13.5 s; the Fast Reel upgrade/pass/spells shorten it.
- **Egg cost:** most fished eggs are free; about 30% are Treasure Eggs (a level higher, for coins). Never every egg on one cast.
- **Ship Workshop:** fittings (Cannons +5% dmg, Hull Plating +5% hp, Crow's Nest +2 s boss timer, Lucky Figurehead +5% egg luck, 5 levels each; Blender rigs in `assets/monsters/spec.py`) and paint (sail + hull stripe colours).
- **Price rule:** every coin sink costs about N minutes of battle income at the stage it is meant for (`Stats.stagePrice`), so prices keep pace with income (nests, Egg Luck, Fast Reel, fittings, Floor 2, team slots; the Shipwright and Floor 3 already worked this way). A new player has about 11K coins after 10 minutes.
- **Offline:** 10% of the live coin rate, 8 h cap (`Config.OFFLINE_RATE`).
- **Rewards:** no reward for joining the group (Roblox rule); friends in the server give +10% coins each, max +30%.
- **Deep Rod (retention after ~20 min):** a second rod on the starboard rail (`Config.DEEP_ROD`). Unlocks after 20 minutes of play, casts once every 10 minutes, dives its own 10-zone trench (`Config.DEEP_ZONES`, Ice and Lava Vents looks added) with x1.5 rarity luck, and its eggs are always free. Each catch may carry one of 5 **perks** (`Config.PERKS`: Frost freeze, Venom poison, Bubble shield, Leech heal, Lucky coins). Perks add no hit damage; a fused child keeps one parent's perk. The sign over the rod counts down the unlock and cooldown.
- **Sounds (ElevenLabs, `assets/audio`):** Cannon, ZoneChime, EggPop, Cast, Upgrade (uploaded to the group; moderation was still reviewing them).

## 12. Dockyard and the bigger harbour
- **Dockyard:** a vendor in town (inner ring, blue pier shed with a ship's wheel, anchor and a Shipwright NPC). It sells Egg Luck, Fast Reel and the Shipwright tiers (server action `Upgrade`, client `Menus.dockyard`) and opens the Ship Workshop. A red "!" floats over it when you can afford a level. These boards are no longer on the deck; only the Floor board, Team board, Gift Chest and the Fuse Luck sign stay on the ship.
- **Island:** `HUB_RADIUS` 78 -> 96, `SHIP_RING_RADIUS` 206 -> 236, `SWIM_RADIUS` 410. Vendor slots, palms, towers, lamps, paths and flowers scale with `TOWN_K = HUB_RADIUS / 78` in `WorldBuilder.buildHub`.
- **Tutorial:** the ship's upgrade signs (and the Dockyard purchases) work from tutorial step 10 (`Config.SIGNS_UNLOCK_STEP`); the Fuse step hint is a tag beside the Fuse button, not the top banner.
- **NPC clearance:** NPCs are 1.15x scale (about 9.6 studs tall with a hat). Keep a roof at least 10 above the feet, or lower the NPC `scale` (Pirate 1.0, Festival Host 0.9) so hats never poke through a roof.

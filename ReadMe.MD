# SRL - Smart Raiding Lua

EverQuest bot automation framework for Macroquest. Runs a utility AI scoring engine where every module scores itself each tick and the highest scorer executes.

---

## Starting the script

```
/lua run srl
```

---

## Slash Commands

All commands use the unified `/srl <subcommand>` format.

> Broadcast commands are ignored by bots if the sender is not in the same zone or beyond `General.DistanceSetting` units away (default 250).

### Quick Reference

| Command | Description |
|---|---|
| `/srl assiston` | Assist on current target |
| `/srl assiston weaponset=<name>` | Assist and swap melee weapons to named set |
| `/srl swapweapons <name>` | Swap melee weapons to named set mid-fight |
| `/srl saveweaponset <name>` | Save currently equipped weapons to named set in YAML |
| `/srl backoff` | Stop combat, clear target |
| `/srl debuffon` | Command debuff current target (uses `DebuffOnCommand` spells) |
| `/srl debuffoff` | Clear command debuff |
| `/srl aeon` | Enable AE spells |
| `/srl aeoff` | Disable AE spells |
| `/srl follow` | All bots follow you |
| `/srl follow id=<id>` | Follow a specific spawn by ID |
| `/srl stop` | Stop following |
| `/srl move` | Emergency move to you |
| `/srl navfollow` | Nav-follow you |
| `/srl mtt` | Navigate to your current target |
| `/srl medon` | Force all bots into med mode |
| `/srl medoff` | Take all bots out of med mode |
| `/srl moveon [seconds]` | Suppress med mode for N seconds (default 60) |
| `/srl mount` | Mount all bots |
| `/srl stickpoint <point>` | Set melee stick point (Behind/Front/etc.) |
| `/srl stickdist <dist>` | Set melee stick distance |
| `/srl quickburn` | Activate quick burn |
| `/srl longburn` | Activate long burn |
| `/srl fullburn` | Activate full burn |
| `/srl epicburn` | Click epics |
| `/srl lesson` | Activate Lesson of the Devoted |
| `/srl intensity` | Activate Intensity of the Resolute |
| `/srl armor` | Activate Armor of Experience |
| `/srl staunch` | Activate Staunch Recovery |
| `/srl expedient` | Activate Expedient Recovery |
| `/srl throne` | Activate Throne of Heroes |
| `/srl infusion` | Activate Infusion of the Faithful |
| `/srl fellowship` | Use Fellowship Registration Insignia |
| `/srl melody <name>` | Start bard melody |
| `/srl stopmelody` | Stop bard melody |
| `/srl buffme` | Request all bots buff the sender |
| `/srl clickitem <item> [id=<id>]` | Click item on target (defaults to current target) |
| `/srl set <name>` | Switch spell set |
| `/srl maxmobs <n>` | Override max tanked mobs |
| `/srl addnomez` | Add current target to no-mez list |
| `/srl fi <item>` | Find item in bags |
| `/srl fmi <item>` | Find missing item |
| `/srl status [threshold]` | Report unspent AAs |
| `/srl turnin <item>` | Turn in item to targeted NPC |
| `/srl say <phrase>` | Say phrase at staggered intervals |
| `/srl castcombatbuffs` | Force-cast combat buffs on all bots immediately |
| `/srl reload` | Reload YAML config |
| `/srl restart` | Restart all bots |
| `/srl debug` | Toggle debug window (local) |
| `/srl puller` | Toggle puller mode (local) |
| `/srl count` | Show bot zone status (local) |
| `/srl help [topic]` | Show in-game help |

---

### Combat

```
/srl assiston                           # target the mob first
/srl assiston weaponset=Piercing        # assist and swap to the named weapon set
/srl backoff
/srl debuffon                           # target the mob first — uses DebuffOnCommand spells, scores above heals
/srl debuffoff                          # clear command debuff manually (also clears when mob dies)
/srl aeon                               # enable AE spells (disabled by default)
/srl aeoff
```

> `assiston` only commits if the target is an NPC that is actively aggressive.
>
> `debuffon` targets the mob you currently have selected and broadcasts to all bots. Only bots with `Debuff.DebuffOnCommand` populated will act. Clears automatically when the mob dies.

---

### Movement

```
/srl follow
/srl stop
/srl move
/srl navfollow
/srl mtt
/srl mtt include=Plate
```

---

### Burns & AAs

```
/srl quickburn
/srl longburn
/srl fullburn
/srl epicburn
/srl lesson
/srl intensity
/srl armor
/srl staunch
/srl expedient
/srl throne
/srl infusion
/srl fellowship
/srl fellowship include=Group
```

> All burn and AA commands support `include=`, `exclude=`, and `include=Group` filters.

---

### Spell Set

```
/srl set Main
/srl set Fire
/srl set Ice
```

Falls back to `Main` if the named set has no entries for a category. Also reloads the matching `GemSwap` set — use this to load cure gems for specific encounters.

---

### Crowd Control

```
/srl maxmobs 0    # mez everything except the assist target
/srl maxmobs 1    # leave 1 mob for an off-tank (default)
/srl maxmobs 2    # two off-tanks
```

Override is in-memory only — reverts to the YAML value on restart.

---

### Bard Melody

```
/srl melody dps
/srl melody mana
/srl stopmelody
```

---

### Item Search

```
/srl fi Commemorative Coin
/srl fi coin include=Plate
/srl fmi Commemorative Coin
```

`fi` — each bot that has the item reports which bag/slot via `/dgt all`. Partial match supported.
`fmi` — each bot that does **not** have the item reports it.

---

### Turn In

```
/srl turnin Bone Chips
/srl turnin coin amount=4
```

Target the NPC first. Bots search their bags (partial match) and give the item directly to the NPC at staggered intervals.

---

### Say

```
/srl say Welcome_to_the_guild_%t
/srl say Good_fight include=Group
```

Bots target your current target and `/say` the phrase at staggered random intervals (500 ms – 20 s). Spaces must be underscores. `%t` is replaced with the target's name.

---

### Status

```
/srl status         # all bots report unspent AAs
/srl status 25      # only bots with 25+ unspent AAs report
```

---

### Admin

```
/srl reload         # reload YAML config on all bots
/srl restart        # restart all bots
/srl debug          # toggle debug overlay (local only)
/srl puller         # toggle puller mode (local only)
```

> `puller` state is in-memory only — resets on script restart.

---

### Count

```
/srl count
```

Local command. Displays all DanNet peers grouped by zone status with distance for in-zone bots, sorted nearest to farthest.

```
[SRL] === Bot Count: 3 in zone | 2 out of zone ===
[SRL] In Zone:
[SRL]   MyTank1               12 units
[SRL]   MyHealer1             18 units
[SRL]   MyDPS1                34 units
[SRL] Out of Zone:
[SRL]   MyBot1
[SRL]   MyBot2
```

---

## Include / Exclude Filters

Most commands support `include=` and `exclude=` filters to target specific bots.

**Tokens:** character name, class short name (`CLR`, `BRD`, `SHM`...), armor type (`Silk`, `Leather`, `Chain`, `Plate`), or `Group`.

```
/srl quickburn include=Plate         # only plate wearers
/srl assiston exclude=MyHealer1      # everyone except MyHealer1
/srl follow include=Group            # only group members
```

---

## Internal Command Bus

The underlying event system uses `/srlevent` to pass commands and key=value payloads between characters. You generally do not call this directly.

**Format:**
```
/srlevent <Command> key=value key=value ...
```

**Commands dispatched internally:**

| Command | Payload | Description |
|---|---|---|
| `Assist` | `id`, `generation`, `sender` | Set assist target |
| `BackOff` | `sender` | Stop combat, clear target |
| `DebuffOn` | `id`, `sender` | Command debuff spawn `id` using `DebuffOnCommand` spells |
| `DebuffOff` | `sender` | Clear command debuff |
| `AEOn` | `sender` | Enable AE spells |
| `AEOff` | `sender` | Disable AE spells |
| `Follow` | `id`, `sender` | Begin following spawn ID |
| `Stop` | `sender` | Stop following |
| `Move` | `id`, `sender` | Emergency move to spawn ID |
| `NavFollow` | `sender` | Nav-follow sender |
| `MoveToTarget` | `id`, `sender` | Navigate to spawn ID and stop |
| `MedOn` | `sender` | Force med mode on |
| `MedOff` | `sender` | Force med mode off |
| `SuppressMed` | `seconds`, `sender` | Suppress med mode for N seconds |
| `Mount` | `sender` | Mount up |
| `StickPoint` | `point`, `sender` | Set melee stick point |
| `StickDist` | `dist`, `sender` | Set melee stick distance |
| `QuickBurn` / `LongBurn` / `FullBurn` | `sender` | Activate burn rotation |
| `EpicBurn` | `sender` | Click epic |
| `SetSpellSet` | `set`, `sender` | Switch active spell set |
| `CCMaxMobs` | `n`, `sender` | Override max tanked mobs |
| `AddNoMez` | `id`, `name`, `sender` | Add NPC to no-mez list |
| `BuffMe` | `sender` | Cast BotBuff spells on sender |
| `ClickItem` | `item`, `id`, `sender` | Click item on spawn `id` and announce |
| `Fellowship` | `sender` | Use Fellowship Registration Insignia |
| `FindItem` | `item`, `sender` | Report item location |
| `FindMissingItem` | `item`, `sender` | Report if item is missing |
| `Status` | `threshold`, `sender` | Report unspent AAs |
| `PlayMelody` | `name`, `sender` | Start melody |
| `StopMelody` | `sender` | Stop melody |
| `ReloadConfig` | `sender` | Reload YAML |
| `ToggleDebug` | _(none)_ | Toggle debug window |
| `CastCombatBuffs` | `sender` | Force-cast combat buffs immediately |
| `NeedCure` | `targetId`, `targetName`, `types`, `buffs` | Request a cure for the named target; any bot with a matching cure spell will respond |
| `ClaimCure` | `id` | Claim a cure target so other bots don't double-cure (7s expiry) |
| `COMBAT_ENDED` | _(none)_ | Clear combat state, resume follow |
| `TellBuff` | `target`, `sender` | Cast all `Buffs.BotBuff` entries on `target`; only the receiving bot sends the acknowledgement tell |
| `TellSpell` | `trigger`, `target`, `sender` | Cast the spell mapped to `trigger` in `GroupBuffs.Aliases` on `target` |
| `TellTL` | `target`, `sender` | Cast the configured `Translocate.Spell` on `target` |
| `SayPhrase` | `id`, `msg`, `sender` | Target spawn `id` and `/say msg` after a random 500–20000 ms delay |
| `TurnIn` | `id`, `item`, `sender` | Turn in item to NPC spawn `id` |

---

## YAML Configuration

Each character has a config file at:
```
srl/config/bot_yaml/<CharacterName>_<Server>.yaml
```

A default file is generated on first run. Key sections:

| Section | Description |
|---|---|
| `AssistSettings.type` | `melee`, `ranged`, or `off` |
| `Heals.Spells` | Heal spells by role (tank/important/normal) with threshold and gem |
| `Heals.Tanks` | Character names considered tanks for heal priority |
| `Heals.ImportantBots` | Character names with elevated heal priority |
| `Debuff.DebuffOnAssist.Main` | Debuffs to cast on the assist target |
| `Debuff.DebuffOnCommand.Main` | Debuffs cast when `/srl debuffon` is used — scores 115, fires before heals |
| `Debuff.DebuffOnXTar.Main` | Debuffs to cast on aggressive XTarget mobs |
| `Debuff.DebuffTargetsOnXTarEnabled` | `true`/`false` — enable XTarget debuffing |
| `Debuff.MinimumAmountToStartDebuffOnXTar` | Minimum aggressive mobs before XTarget debuffing starts |
| `AE.Spells` | AE spells/discs/AAs — enabled via `/srl aeon`, disabled by default |
| `Buffs.GroupBuff` | Buffs swept across all raid members every 10 minutes |
| `RaidBuff.MinManaPct` | Mana % below which the raid buff sweep is deferred 2 minutes (default 20) |
| `Nukes.Main` | Nuke spells with gem. Additional sets: `Nukes.Fire`, `Nukes.Ice`, etc. |
| `Jolts.Main` | Aggro-reduction spells with `aggroThreshold` per spell. Jolts never change with `/srl set`. |
| `CrowdControl.Enabled` | `true`/`false` |
| `CrowdControl.Spells` | Mez spells with gem, priority, and optional `ae: true` for AE mez |
| `CrowdControl.RecastBuffer` | Seconds before mez expires to recast (default 10) |
| `Buffs.SelfBuff` | Buffs to keep on yourself |
| `Buffs.BotBuff` | Buffs to cast on other characters, out of combat only |
| `Buffs.CombatBuff` | Buffs to cast only during combat |
| `Abilities` | Combat abilities/discs/AAs/items to use automatically |
| `Taunt` | Taunt abilities for tank classes |
| `Cures` | Cure spells/AAs to use on debuffed group members |
| `Aura` | Aura spell/AA/disc to maintain automatically |
| `UseItems.Shrink` | Shrink spell/item configuration |
| `Burn.QuickBurn` | Abilities fired by `/quickburn` |
| `Burn.FullBurn` | Abilities fired by `/fullburn` |
| `Burn.LongBurn` | Abilities fired by `/longburn` |
| `Jolts.JoltThreshold` | Aggro % to start using jolts (default 80) |
| `Jolts.LockoutThreshold` | Aggro % to stop nuking entirely (default 100) |
| `Heals.GroupThreshold` | Average group HP% to trigger a group heal |
| `Heals.GroupSpell` | Group heal spell and gem |
| `Cleric.EpicPct` | Tank HP% to click the cleric epic (default 35) |
| `Cleric.EpicName` | Name of the cleric epic item |
| `Cleric.DivineArbitrationPct` | Tank HP% to use Divine Arbitration (default 35) |
| `Cleric.DonorMinPct` | Avg non-tank HP% required before DA/epic fires (default 60) |
| `GiftOfMana` | Spell to cast when Gift of Mana procs |
| `Bard.Melodies` | Named melody gem sequences for `/playmelody` |
| `Epic.name` | Override the default epic item name for burn clicks |
| `General.DistanceSetting` | Max distance (units) sender must be within for commands to apply (default 250) |
| `General.debugLevel` | `off` or `on` |
| `GemSwap` | Named gem loadout sets; the active set's gems are restored automatically after a buff borrows them. Switched with `/srl set` |

---

## YAML Field Reference

### AssistSettings

```yaml
AssistSettings:
  type: melee        # melee | ranged | off
  enabled: true
  meleeStickDistance: 15
  meleeStickPoint: Behind
  rangedDistance: 100
  AutoAssistEngagePercent: 98
```

---

### Buffs

All buff categories share the same entry format:

```yaml
Buffs:
  SelfBuff:                      # cast on yourself, out of combat only
    - spell: Yaulp VI
      gem: 3

  BotBuff:                       # cast on other characters, out of combat only
    - spell: My Group Buff Rk. III
      gem: 2
      buffName: My Group Buff    # optional: buff name to check on target if different from spell name
      alwaysCheck: true          # optional: also cast during combat
      charactersToBuff:
        - MyTank1
        - MyBot1

  CombatBuff:                    # cast on others during combat only
    - spell: My Combat Buff Rk. II
      gem: 1
      charactersToBuff:
        - MyTank1
```

> `alwaysCheck: true` on a BotBuff entry makes it fire in and out of combat.
>
> `buffName` overrides what is checked on the target when the spell name differs from the buff it applies (e.g. `spell: Improved Familiar` lands as `Improved Familiar VII`). Rank suffixes (`Rk. III` etc.) are always stripped automatically — only use `buffName` when the name is genuinely different.
>
> Group buffs listed under `charactersToBuff` are cast once and allowed to land before re-checking other targets — the bot will not spam the cast once per target.

---

### Heals

```yaml
Heals:
  Tanks:
    - MyTank1
  ImportantBots:
    - MyHealer1
  GroupThreshold: 65             # cast group heal when avg HP% falls below this
  GroupSpell:
    spell: Word of Restoration Rk. III
    gem: 7
    minInjured: 4              # optional: minimum members below threshold before group heal fires (default 4)
  Spells:
    tank:
      - spell: My Big Heal Rk. III
        threshold: 70            # cast when target HP% is at or below this
        gem: 1
    important:
      - spell: My Big Heal Rk. III
        threshold: 70
        gem: 1
    normal:
      - spell: My Small Heal Rk. II
        threshold: 60
        gem: 2
```

---

### Heals — HoTs & Promised Heals

```yaml
Heals:
  HoTSpells:
    tank:
      - spell: Healing over Time Rk. III
        threshold: 90          # cast when target HP% is at or below this
        gem: 3
    important:
      - spell: Healing over Time Rk. II
        threshold: 85
        gem: 3
    normal:
      - spell: Healing over Time Rk. II
        threshold: 80
        gem: 3

  PromisedSpells:
    tank:
      - spell: Promised Healing Rk. III
        threshold: 85          # cast when target HP% is at or below this
        gem: 4
        buffer: 3              # optional: seconds to wait after buff expires before recasting (default 3)
    normal:
      - spell: Promised Healing Rk. II
        threshold: 75
        gem: 4
```

> **HoT spells** fire at score 92 (below Cure at 95, above Assist at 90). They check whether the HoT buff is already present before casting — no spam.
>
> **Promised heals** fire their heal when the buff expires, so the bot waits for it to fall off naturally. After it drops, the bot waits `buffer` seconds (default 3) to let the heal land before casting the next one.
>
> Both work in and out of combat. Target priority mirrors the main heal system: tanks first, then important bots, then normal group/raid members. Lowest HP within each tier wins.

---

### Nukes, Jolts & Spell Sets

```yaml
Nukes:
  Main:
    - spell: My Nuke Rk. III
      gem: 5
  Fire:
    - spell: My Fire Nuke Rk. III
      gem: 5
  Ice:
    - spell: My Ice Nuke Rk. III
      gem: 5

Jolts:
  JoltThreshold: 80              # start jolting above this aggro %
  LockoutThreshold: 100          # stop nuking entirely at this aggro %
  Main:
    - spell: My Jolt Rk. III
      gem: 7
      aggroThreshold: 95         # optional: only use this jolt above 95%
```

> Switch active nuke set with `/srl set Fire`. Jolts never change with `/srl set`. If a named set has no entries for a category, that category keeps using `Main`.

---

### Abilities

```yaml
Abilities:
  - Ability: Flying Kick
    type: ability              # ability | disc | aa | item
  - Ability: Boastful Bellow
    type: aa
    stacks: true               # track recast via timer — won't recast until buff expires
    duration: 22               # optional: override spell duration (seconds) if TLO is wrong
  - Ability: My Debuff Disc
    type: disc
    debuff: true               # skip if effect already on target
  - Ability: Staunch Recovery
    type: aa
    reagent: Flowing Black Silk Sash   # skip if item not in inventory
  - Ability: My Clicky Item
    type: item
  - Ability: Feign Death
    type: ability
    aggroThreshold: 80         # only fire when your aggro% is at or above this value
```

> `stacks: true` uses a recast timer (duration + 1s) instead of buff polling, preventing early recasts on stacking DoT abilities.
>
> `aggroThreshold` gates any ability type behind your current aggro percentage — useful for hate-reduction abilities like Feign Death.
>
> Only one disc fires per decision cycle, with a 3 s guard between activations to prevent the "too distracted" error. Regular abilities have a 1.5 s guard.

---

### Taunt

Tank classes only (WAR / SHD / PAL). The bot taunts when the assist mob's target-of-target is a non-tank PC.

```yaml
Taunt:
  Enabled: true
  Abilities:
    - name: Taunt
      type: ability            # ability | aa | disc
    - name: Bash
      type: ability
```

> Only fires when the mob is the bot's current target. Each tank independently taunts off its own assist target, so two tanks on different mobs won't interfere with each other.

---

### Cures

```yaml
Cures:
  Spells:
    - name: Radiant Cure      # AA group cure — no gem needed
      type: Poison,Disease,Curse
      spelltype: aa
      minInjured: 3           # optional: only use if 3+ unclaimed targets need this cure type
    - name: My Cure Spell Rk. III
      gem: 6
      type: Poison,Disease
    - name: My Curse Cure Rk. II
      gem: 8
      type: Curse
  IgnoreList:                 # global — these debuffs are never cured (defined in settings.yaml)
    - Bloodeye's Curse
```

> `type` is a comma-separated list of conditions cured: `Poison`, `Disease`, `Curse`, `Corruption`. `spelltype: aa` uses `/alt activate` instead of a gem slot.
>
> `minInjured` on AE/group cures: the spell is skipped unless that many unclaimed targets are queued for the same cure type. Falls through to the next spell in the list (e.g. a single-target cure). Use this to avoid wasting group cures on a single person.
>
> `IgnoreList` lives in `settings.yaml` so it applies to all bots. Debuffs on this list are never broadcast as needing a cure.

---

### Aura

```yaml
Aura:
  CastAura: true
  Aura:
    spell: My Aura
    type: aa          # aa | disc | spell
    gem: 8            # only needed if type is spell
```

> Aura is cast out of combat only. Bards automatically stop twisting before casting and resume afterward.

---

### Shrink

```yaml
UseItems:
  Shrink:
    spell: Smaller Friends Rk. III   # or an item name
    type: spell                       # spell | item | aa
    gem: 4                            # only needed if type is spell
    threshold: 3.0                    # shrink group members with Height above this
```

> Shrinks group members within spell/item range who are above the height threshold. Only fires out of combat.

---

### Burn

```yaml
Burn:
  QuickBurn:
    - name: My Combat Disc
      type: disc
    - name: Intensity of the Resolute
      type: aa
    - name: My Clicky
      type: item
  FullBurn:
    - name: My Combat Disc
      type: disc
  LongBurn:
    - name: Intensity of the Resolute
      type: aa
```

> Abilities fire top to bottom. Discs are skipped if one is already active. Epic is always clicked automatically.

---

### Weapon Swap

Declares named weapon loadouts per character. Melee-only — bots without `SwapItems` configured silently skip all swap commands.

```yaml
SwapItems:
  Default:
    Main: Transcended Fistwraps of Immortality
    Off:                         # leave blank for classes with no offhand (e.g. BER)
  Piercing:
    Main: Some Piercing Weapon
    Off:
  DS:
    Main: Fishing Pole
    Off: Blade of Vesagran
```

**Commands:**

```
/srl saveweaponset Default       # save currently equipped weapons into the Default set (local only)
/srl saveweaponset Piercing      # save into Piercing set
/srl swapweapons Default         # all bots swap to Default set
/srl swapweapons Piercing        # all bots swap to Piercing set
/srl assiston weaponset=Piercing # assist + swap to Piercing in one command
```

> `saveweaponset` is local-only — each bot saves its own equipped weapons. Run it on each bot individually.
>
> Uses MQ2Exchange (`/exchange "Item Name" mainhand/offhand`). Polls the slot until the item appears, up to 2 seconds.

---

### GemSwap

Declares the "permanent" combat spell for one or more gem slots, grouped into named sets. When a buff borrows one of these gem slots, `MemSwapDecision` restores it back to the declared spell as soon as the buff job clears the queue. Switching sets with `/srl set` also switches the active GemSwap loadout.

```yaml
GemSwap:
  Main:                          # default — active unless another set is selected
    - gem: 2
      name: Balance of Discord
    - gem: 8
      name: My AE Slow Rk. III
  Seru:                          # loaded when you run: /srl set Seru
    - gem: 2
      name: Balance of Discord
    - gem: 7
      name: Expunge Corruption Rk. III
    - gem: 9
      name: Remove Greater Curse
```

> Leave `Main` empty (or omit it) if you do not need enforced gems in the default loadout.
>
> Cure gems are a common use case: declare them only in the encounter-specific set so they are not memmed during normal play.
>
> `/srl set Main` clears encounter-specific gems and restores the default loadout.

---

### Crowd Control

```yaml
CrowdControl:
  Enabled: true
  RecastBuffer: 10             # seconds before mez expires to recast
  MaxTankedMobs: 1             # leave this many mobs for tanks, mez the rest
  Spells:
    - spell: My AE Mez Rk. III
      gem: 4
      ae: true                 # AE mez
      aeMinTargets: 2          # minimum mobs before using AE mez
      maxLevel: 78             # optional: skip if target level exceeds this
    - spell: My Single Mez Rk. II
      gem: 5
```

---

### Debuff

```yaml
Debuff:
  DebuffOnAssist:
    Main:
      - spell: My Malo Rk. III
        gem: 3
      - spell: My Slow Rk. III
        gem: 2
        group: slow             # group entries: only one per group fires per target
        checkBuff: My Slow      # skip this entry if buff already present (string or list)
        priority: 1             # sort order within the spell list (lower = higher priority)
        highPriority: true      # score 115 — fires before heals (use for slows/critical debuffs)
      - spell: My Backup Slow Rk. II
        gem: 4
        group: slow
        checkBuff:              # list form — skip if any of these are present
          - My Slow
          - My Backup Slow
        priority: 2
  DebuffOnCommand:              # triggered by /srl debuffon — same flags as DebuffOnAssist
    Main:
      - spell: My Slow Rk. III
        gem: 2
        group: slow
        checkBuff: My Slow
        priority: 1
      - spell: My Backup Slow Rk. II
        gem: 4
        group: slow
        checkBuff: My Slow
        priority: 2
      - spell: My Malo Rk. III
        gem: 3
  DebuffTargetsOnXTarEnabled: true
  MinimumAmountToStartDebuffOnXTar: 2
  DebuffOnXTar:
    Main:
      - spell: My Malo Rk. III
        gem: 3
```

> **Groups:** Entries with the same `group` value compete — `checkBuff` blocks the entire group if any listed buff is present. Only the first ready entry in a group fires. Entries without a group are independent and always considered.
>
> **`priority: true`** (boolean) raises the decision score to 115, above all heals. Use this on critical debuffs like slows. Numeric `priority` controls sort order within the list — these are separate fields.
>
> **`DebuffOnCommand`** uses all the same flags (`group`, `checkBuff`, `priority`) as `DebuffOnAssist`. Triggered by `/srl debuffon` and scores 115 regardless of `priority: true`.
>
> **Spell sets:** Like nukes, debuff sets can be named (`DebuffOnAssist.Fire`, etc.) and switched with `/srl set`.

---

### DoTs

```yaml
Dots:
  DotsOnAssist:
    Main:
      - spell: My DoT Rk. III
        gem: 3
        checkBuff: My DoT       # skip if buff already on target
      - spell: My Other DoT Rk. II
        gem: 4
        checkBuff: My Other DoT
```

> DoTs score 79 — below debuffs (80) but above burns. Like debuffs, they check whether the DoT is already active before recasting to avoid refreshing unnecessarily. Supports the same `group`, `checkBuff`, and `priority` flags as `Debuff`.

---

### AE Spells

```yaml
AE:
  Spells:
    - name: My AE Slow Rk. III
      type: spell               # spell | disc | aa
      gem: 4
      threshold: 3              # minimum aggressive mobs in radius before casting
      debuff: true              # score 115 — fires before heals (use for AE slows)
    - name: My AE Nuke Rk. III
      type: spell
      gem: 5
      threshold: 4              # won't fire unless 4+ aggressive mobs in range
```

> AE spells are disabled by default. Enable/disable with `/srl aeon` / `/srl aeoff` (in-memory, resets on restart). Set `AE.Enabled: true` in YAML to default to enabled on startup.
>
> Radius is read from the spell's own `AERange` TLO (falls back to `Range`). No radius config needed.
>
> `debuff: true` scores 115 (above heals). Without it, AE spells score 82. Use `debuff: true` for AE slows and crowd-reducing debuffs, not nukes.
>
> Each ability tracks its own recast timer — won't fire again until the spell's recast time has passed (minimum 2s).

---

### GroupBuff / RaidBuff

```yaml
Buffs:
  GroupBuff:                    # swept across all raid members every 10 minutes
    - spell: My Group Buff Rk. III
      gem: 2
    - spell: My Other Buff Rk. II
      gem: 3

RaidBuff:
  MinManaPct: 20                # skip raid sweep and retry in 2 minutes if mana is below this
```

> `GroupBuff` entries are polled via the actor bus just like `BotBuff` — the bot asks each raid member if they have the buff before casting. Only fires out of combat, only when in a raid.
>
> The sweep runs every 10 minutes. If mana is below `MinManaPct` (default 20%), it retries in 2 minutes instead.

---

### Cleric

```yaml
Cleric:
  EpicPct: 35                  # tank HP% to click epic
  EpicName: Aegis of Superior Divinity
  DonorMinPct: 60              # avg non-tank HP% required before DA/epic fires
  DivineArbitrationPct: 35     # tank HP% to use Divine Arbitration
  AutoYaulp: false
  YaulpSpell:
```

---

### Gift of Mana

```yaml
GiftOfMana:
  spell: My Big Nuke Rk. III
  gem: 5
  target: assist               # assist | self (default: assist)
```

> Fires when the Gift of Mana proc is active. Cast your highest-mana-cost spell here.

---

### Bard Melodies

```yaml
Bard:
  Melodies:
    dps:
      - 1
      - 2
      - 3
      - 4
    mana:
      - 5
      - 6
```

> Gem slot numbers in twist order. Activated with `/playmelody dps`, stopped with `/stopmelody`.

---

### Epic

```yaml
Epic:
  name: My Epic Item Name
```

> Overrides the hardcoded class epic. Leave blank to use the default. Clicked automatically on every burn.

---

### General

```yaml
General:
  debugLevel: off              # off | on
  DistanceSetting: 250         # max distance sender must be within for commands to apply
  medStart: 10                 # mana % to enter med mode (casters/healers)
  medStop: 100                 # mana % to exit med mode
```

---

## Global Settings (settings.yaml)

Shared settings that apply to **all** bots live in:
```
srl/config/settings.yaml
```

Character YAML is deep-merged on top, so any character-level value overrides the global default.

### GroupBuffs — tell-based buff system

Players send a tell with a trigger word to any bot to request buffs. DanNet peers are automatically trusted. Non-peers must be on the whitelist.

```yaml
GroupBuffs:
  Whitelist:
    - FriendlyPlayer        # non-DanNet characters allowed to request buffs
  TellTrigger: buffs        # "/tell MyBot1 buffs" → all bots cast their configured spells on the requester
  Aliases:                  # individual spell triggers
    haste:
      - My Haste Spell Rk. III
    clarity:
      - My Clarity Spell Rk. III
    ds:
      - My Damage Shield Rk. II
    sow:
      - Spirit of Wolf
```

Each bot's `GroupBuffs.Spells` list (per-character YAML) defines what it casts when `TellTrigger` is received. `Aliases` are resolved against each bot's configured spells — bots that don't have the spell skip it silently.

The bot that receives the tell sends one acknowledgement reply to the requester:
> `Buffs incoming, please stand still.`

### Translocate

```yaml
Translocate:
  Trigger: tl               # "/tell MyBot1 tl" → TL bot casts the configured spell on requester
  Spell:
    spell: My Translocate Spell Rk. II
    gem: 6
```

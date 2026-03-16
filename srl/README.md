# SRL - Smart Raiding Lua

EverQuest bot automation framework for MQNext. Runs a utility AI scoring engine where every module scores itself each tick and the highest scorer executes.

---

## Starting the script

```
/lua run srl
```

---

## Slash Commands

All commands below are typed on the **main (leader) character**. They broadcast to all bots via DanNet (`/dgae`).

> Commands are ignored by bots if the sender is not in the same zone or is more than 250 units away.

### `/assiston`
Broadcasts an assist command to all bots. Bots will target and attack whoever the main character currently has targeted.

**Usage:**
1. Target the mob you want to kill
2. Type `/assiston`

---

### `/followme`
All bots follow the main character.

**Usage:**
```
/followme
```
Bots will stick within 5 yards of the main character. Follow is suspended during combat and resumes automatically when combat ends.

---

### `/srlstop`
All bots stop following.

**Usage:**
```
/srlstop
```

---

### `/lesson`
All bots activate **Lesson of the Devoted**.

### `/intensity`
All bots activate **Intensity of the Resolute**.

### `/armor`
All bots activate **Armor of Experience**.

### `/staunch`
All bots activate **Staunch Recovery**.

### `/expedient`
All bots activate **Expedient Recovery**.

> All AA commands support `include=`, `exclude=`, and `include=Group` filters.

---

### `/srlbackoff`
All bots immediately stop attacking, turn off auto-attack, and clear the assist target.

```
/srlbackoff
```

> Use this when you need to abort a fight — bots will disengage and won't re-engage until the next `/assiston`.

---

### `/srlmaxmobs <n>`
Overrides `CrowdControl.MaxTankedMobs` at runtime on all bots. Sets how many non-assist mobs to leave for tanks — everything beyond that count gets mezzed.

```
/srlmaxmobs 0    # mez everything except the assist target
/srlmaxmobs 1    # leave 1 mob for an off-tank (default)
/srlmaxmobs 2    # two off-tanks
```

Override is in-memory only — reverts to the YAML value on script restart.

---

### `/srlmove`
Emergency movement command. Bots immediately drop what they are doing (interrupts any active cast) and move to the main character. Works during combat.

**Usage:**
```
/srlmove
```

> Use this when repositioning mid-fight — bots will interrupt casts, turn off attack, and stick to you.

---

### `/quickburn` `/fullburn` `/longburn`
Activates the corresponding burn rotation on all bots. Each bot fires their configured burn abilities in order, then clicks their epic.

```
/quickburn
/fullburn
/longburn
```

---

### `/srlreload`
Reloads the YAML config on all bots without restarting the script.

```
/srlreload
```

---

### `/playmelody <name>`
Bard-only. Starts the named melody twist sequence.

```
/playmelody dps
/playmelody mana
```

### `/stopmelody`
Stops the active melody.

---

## Include / Exclude Filters

Most commands support `include=` and `exclude=` filters to target specific bots.

**Tokens:** character name, class short name (`CLR`, `BRD`, `SHM`...), armor type (`Silk`, `Leather`, `Chain`, `Plate`), or `Group`.

```
/quickburn include=Plate         # only plate wearers
/assiston exclude=Kaedy          # everyone except Kaedy
/followme include=Group          # only group members
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
| `Follow` | `id`, `sender` | Begin following spawn ID |
| `Stop` | `sender` | Stop following |
| `Move` | `id`, `sender` | Emergency move to spawn ID |
| `COMBAT_ENDED` | _(none)_ | Clear combat state, resume follow |

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
| `Debuff.DebuffOnXTar.Main` | Debuffs to cast on aggressive XTarget mobs |
| `Debuff.DebuffTargetsOnXTarEnabled` | `true`/`false` — enable XTarget debuffing |
| `Debuff.MinimumAmountToStartDebuffOnXTar` | Minimum aggressive mobs before XTarget debuffing starts |
| `Nukes.Main` | Nuke spells with gem, and optional conditions |
| `Jolts.Main` | Aggro-reduction spells with `aggroThreshold` per spell |
| `CrowdControl.Enabled` | `true`/`false` |
| `CrowdControl.Spells` | Mez spells with gem, priority, and optional `ae: true` for AE mez |
| `CrowdControl.RecastBuffer` | Seconds before mez expires to recast (default 10) |
| `Buffs.SelfBuff` | Buffs to keep on yourself |
| `Buffs.BotBuff` | Buffs to cast on other group members |
| `Buffs.CombatBuff` | Buffs to cast only during combat |
| `Abilities` | Combat abilities/discs/AAs/items to use automatically |
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
| `AutoRez.Enabled` | `true`/`false` — enable auto-rez |
| `AutoRez.Spells` | Rez spells/AAs/items tried in order |
| `GiftOfMana` | Spell to cast when Gift of Mana procs |
| `Bard.Melodies` | Named melody gem sequences for `/playmelody` |
| `Epic.name` | Override the default epic item name for burn clicks |
| `General.debugLevel` | `off` or `on` |

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
    - spell: Talisman of the Dire Rk. III
      gem: 2
      alwaysCheck: true          # optional: also cast during combat
      charactersToBuff:
        - Taloneri
        - Muser

  CombatBuff:                    # cast on others during combat only
    - spell: Champion
      gem: 1
      charactersToBuff:
        - Taloneri
```

> `alwaysCheck: true` on a BotBuff entry makes it fire in and out of combat — useful for long-duration buffs that double as combat buffs.

---

### Heals

```yaml
Heals:
  Tanks:
    - Taloneri
  ImportantBots:
    - Kaedy
  GroupThreshold: 65             # cast group heal when avg HP% falls below this
  GroupSpell:
    spell: Word of Restoration Rk. III
    gem: 7
  Spells:
    tank:
      - spell: Sacred Light III
        threshold: 70            # cast when target HP% is at or below this
        gem: 1
    important:
      - spell: Sacred Light III
        threshold: 70
        gem: 1
    normal:
      - spell: Sacred Light III
        threshold: 70
        gem: 1
```

---

### Nukes & Jolts

```yaml
Nukes:
  Main:
    - spell: Ethereal Combustion Rk. III
      gem: 5
    - spell: Rimeblast Rk. III
      gem: 6

Jolts:
  JoltThreshold: 80              # start jolting above this aggro %
  LockoutThreshold: 100          # stop nuking entirely at this aggro %
  Main:
    - spell: Concussive Burst Rk. III
      gem: 7
      aggroThreshold: 95         # optional: only use this jolt above 95%
```

> Nukes cycle in order. Jolts fire when aggro exceeds `JoltThreshold`, replacing nukes. At `LockoutThreshold` only jolts fire.

---

### Abilities

```yaml
Abilities:
  - Ability: Flying Kick
    type: ability              # ability | disc | aa | item
  - Ability: Clawstriker's Flurry Rk. III
    type: disc
  - Ability: Boastful Bellow
    type: disc
    debuff: true               # skip if effect already on target
    stacks: true               # stacking: only skip if YOUR version is on target
  - Ability: Staunch Recovery
    type: aa
    reagent: Flowing Black Silk Sash   # optional: skip if item not in inventory
  - Ability: Cloak of Scale Spines
    type: item
```

---

### Burn

```yaml
Burn:
  QuickBurn:
    - name: Speed Focus Discipline
      type: disc
    - name: Intensity of the Resolute
      type: aa
    - name: Some Clicky
      type: item
  FullBurn:
    - name: Speed Focus Discipline
      type: disc
  LongBurn:
    - name: Intensity of the Resolute
      type: aa
```

> Abilities fire top to bottom. Discs are skipped if one is already active. Epic is always clicked automatically.

---

### Crowd Control

```yaml
CrowdControl:
  Enabled: true
  RecastBuffer: 10             # seconds before mez expires to recast
  MaxTankedMobs: 1             # leave this many mobs for tanks, mez the rest
  Spells:
    - spell: Bewildering Wave Rk. III
      gem: 4
      ae: true                 # AE mez
    - spell: Mesmerization
      gem: 5
```

---

### Debuff

```yaml
Debuff:
  DebuffOnAssist:
    Main:
      - spell: Malosinise
        gem: 3
  DebuffOnCommand:
    Main:
      - spell: Balance of Discord
        gem: 2
  DebuffTargetsOnXTarEnabled: true
  MinimumAmountToStartDebuffOnXTar: 2
  DebuffOnXTar:
    Main:
      - spell: Malosinise
        gem: 3
```

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

### Auto Rez (Clerics)

```yaml
AutoRez:
  Enabled: true
  Spells:
    - name: Reviviscence Rk. III
      type: spell
      gem: 5
    - name: Blessing of Resurrection
      type: aa
    - name: Some Rez Clicky
      type: item
```

> Tries each rez option in order, skipping those on cooldown. Only rezzes DanNet peers within 100 units.

---

### Gift of Mana

```yaml
GiftOfMana:
  spell: Ethereal Combustion Rk. III
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
  name: Transcended Fistwraps of Immortality
```

> Overrides the hardcoded class epic. Leave blank to use the default. Clicked automatically on every burn.

---

### General

```yaml
General:
  debugLevel: off              # off | on
```

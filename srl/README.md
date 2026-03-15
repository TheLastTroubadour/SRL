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
| `Abilities.Ability` | Combat abilities/discs/AAs to use automatically |

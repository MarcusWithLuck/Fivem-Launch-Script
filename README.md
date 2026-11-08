# Fivem Launch Script (esx_launchcontrol)

Launch control (2-step), line-lock burnouts and rolling anti-lag for FiveM / ESX.
Boost builds while you wait on the limiter and is already there when you release.

## Install
1. Put this folder in `resources/` (renaming it to `esx_launchcontrol` is recommended).
2. Add `ensure esx_launchcontrol` to `server.cfg` **after** `es_extended`.
3. OneSync needs to be on (it is by default) for the flame and pop sync.

No items are needed.

## Commands
| Command | |
|---|---|
| `/launch` | Arm launch control (turns burnout mode off) |
| `/burnout` | Burnout mode (turns launch control off) |
| `/antilag` | Anti-lag on/off (needs the turbo upgrade) |
| `/launchrpm 5000` | Launch RPM |
| `/lcstatus` | What's on |

## Controls
| | Keyboard | PlayStation | Xbox |
|---|---|---|---|
| Launch control: hold | Space + W | R1 + R2 | RB + RT |
| Launch: release | let go of Space | let go of R1 | let go of RB |
| Burnout | Space + W | R1 + R2 | RB + RT |
| Rolling anti-lag | Left Shift + W | D-pad ↓ + R2 | D-pad ↓ + RT |

To rebind the rolling button, go to *Settings > Key Bindings > FiveM > Rolling anti-lag*.

## How it feels
- **Staging:** the engine bounces on the limiter and the body rocks with every cut. The camera and controller vibrate harder as boost builds. With anti-lag on, the exhaust crackles and spits flames.
- **Boost builds:** with anti-lag on, the 2-step keeps the turbo lit, so it reaches full boost in about 3 seconds. Without anti-lag you only get a little boost. Without a turbo you only get the RPM hold.
- **Release:** the boost is already in the turbo, so power arrives with no spool delay. The nose lifts and the controller thumps. If the tyres spin, the rear steps around and traction control trims the power. The stored boost then bleeds into the turbo's normal spool over about 2 seconds.
- **Rolling anti-lag:** the ignition cut holds your speed and the turbo stays lit. Count three and let go.
- **Lifting off with anti-lag on:** the turbo stays spooled and crackles, and the boost is there the instant you're back on the throttle. With anti-lag off, the turbo dumps pressure as normal.
- **Abuse:** sitting on the limiter heats the turbo. When it's hot the engine stumbles and misfires. When it overheats, boost is capped and the engine takes damage until it cools. It never damages below the configured minimum, so the engine won't explode.
- **Sound:** the real turbo pressure is held up, so your vehicle sound mods play their own spool, whistle and flutter. The extra pop samples are a quiet layer on top; turn them off with `Config.Sound.Enabled = false`.

## UI
A small PSI number and a thin line sit at the bottom centre, only while boost is built. A second, orange line appears once the turbo gets hot and turns red when it overheats. Nothing is shown otherwise.

## Tuning (`config.lua`)
- `Config.Turbo`: build time, extra power, bleed time, max PSI
- `Config.Feel`: body shudder, launch squat, squirm, camera shake, rumble
- `Config.Heat`: heat rates, misfire and overheat thresholds, engine damage
- `Config.Controls`: default rolling buttons
- `Config.Access.AllowedJobs`: optional job lock

## Security
- **No secrets:** no API keys, tokens, webhooks or outside HTTP calls.
- **No NUI callbacks:** the UI has no NUI callbacks and never takes mouse or keyboard focus.
- **Nothing server-side changes:** the script never touches money, items, jobs or the database. Everything it does to a vehicle (RPM, turbo pressure, power, engine health) runs on the driver's own client and only affects the car they're driving.
- **One server event:** `esx_launchcontrol:pop`, the flame and pop sync. It:
  - only accepts a whole-number network ID; a NaN size is thrown out and every size is clamped to 0.2-2.0;
  - only relays if the sender is actually driving that vehicle;
  - is rate-limited per player;
  - only forwards to players in range.
- **Job lock is a convenience, not anti-cheat:** `Config.Access.AllowedJobs` is enforced when a player types a command. Since the effects run on the player's own client, a player running a cheat menu could switch them on for themselves. This is true of any client-side vehicle script. It cannot affect other players' vehicles or the server.
- **Anti-cheat:** the script uses `SetVehicleCheatPowerIncrease` for the extra power while boost is being released. If your anti-cheat flags this native, whitelist this resource or set `Config.Turbo.ExtraPower = 0` (you keep the turbo pressure and all the effects).

## License
MIT. See `LICENSE`.

# Raycer

Raycer is a lightweight arcade car library. Each car is a single rigid body held up by one raycast spring per wheel, with tire forces computed in code. It uses the same model layout as A-Chassis, so existing A-Chassis-style cars work with it.

Raycer is built for games that prioritize fun driving over realism, like kart racers, party games, etc.

It is not a 1:1 replacement for A-Chassis!

## Why Raycer?

- **Small.** One module of about 400 lines and a config, with no plugins, GUIs or legacy body movers.
- **Predictable grip.** Tires don't depend on Roblox contact friction, so cars don't slide out in corners or catch on seams between floor parts.
- **Tuned in real units.** Top speed in studs/s, grip in g, suspension as a bounce frequency. No torque curves or gear ratios.
- **One assembly.** The car is welded into a single body, so network ownership is one call and there are no joints to break.
- **Input for free.** Raycer reads the `VehicleSeat`'s `ThrottleFloat` and `SteerFloat`, which Roblox's default controls already fill for keyboard, gamepad and touch.
- **Per-car tuning.** Each car points at its own config, which only needs the values it changes.
- **No legacy/deprecated code.** Other popular car libraries, such as `A-Chassis`, use deprecated legacy methods such as `:MakeJoints`, which do not work well with modern features. Raycer uses only modern APIs.

### What it doesn't do

- **Exactly four wheels.** No three-wheelers, bikes or trucks with extra axles.
- **No drifting or handbrake.** Tires cancel sliding, which keeps cars controllable but means no oversteer.
- **No gearbox or engine simulation.** The engine sound's pitch follows speed.
- **Only driven cars are simulated.** With nobody in the seat, the car rests on its collision hull.

## Car layout

The required layout for Raycer is the following:

```
📦 Car (Model)
├── 💺 DriveSeat (VehicleSeat)
├── 📁 Wheels
│   ├── FL (BasePart)
│   ├── FR (BasePart)
│   ├── RL (BasePart)
│   └── RR (BasePart)
├── 📁 Body (optional, any parts)
└── 🔗 Config (ObjectValue, optional, points at a config ModuleScript)
```

- The wheels can be any shape. They're only visual and get animated for spin, steering and suspension travel.
- Raycer builds an invisible collision hull from the `Body`'s footprint, sitting just above the ground, so walls and other cars bounce off it. Wheels are made non-collidable. `Body` parts keep their `CanCollide` setting, so turn it off unless you want them colliding too.
- The `DriveSeat` doesn't need to be level. Raycer works out "forward" and "up" from the wheel positions.

## Usage

### Server

```lua
local Raycer = require(ReplicatedStorage.Raycer)

local car = workspace.Car
local chassis = Raycer.new(car)
chassis:Init() -- Welds the car, builds its hull and hands physics to whoever sits in the DriveSeat

-- Later, when the car is removed
chassis:Destroy()
```

`Raycer.new(car, config)` also accepts a config ModuleScript, which replaces whatever the car's `Config` ObjectValue points at.

### Client

Call `initClient` once per client, from a LocalScript. It drives the local player's car and animates every car's wheels and engine sound.

```lua
local Raycer = require(ReplicatedStorage.Raycer)

Raycer.initClient()
```

#### Collision groups

If your cars use a collision group, pass it in:

```lua
Raycer.initClient({ collisionGroup = "Cars" })
```

The suspension rays then follow the same collision rules as the cars. For example, if characters don't collide with `Cars`, cars drive straight over players instead of bumping up onto them. Without it, the rays hit anything with `CanCollide` enabled except the car itself.

## Configuration

Every car uses `Raycer.DefaultConfig` unless its `Config` ObjectValue points at another ModuleScript. That module only needs the values it changes:

```lua
--!strict
return {
	MAX_SPEED = 110,
	GRIP = 2.2,
}
```

Misspelled keys print a warning, and a config that fails to load falls back to the default.

| Key                      | Default                  | What it does                                                                                       |
| ------------------------ | ------------------------ | -------------------------------------------------------------------------------------------------- |
| `MAX_SPEED`              | `90`                     | Top speed, in studs/s.                                                                             |
| `REVERSE_SPEED`          | `35`                     | Top reversing speed, in studs/s.                                                                   |
| `ACCELERATION`           | `60`                     | Acceleration, in studs/s².                                                                         |
| `BRAKE_DECELERATION`     | `130`                    | Braking when holding the opposite direction, in studs/s².                                          |
| `COAST_DECELERATION`     | `20`                     | Slowdown with no throttle, in studs/s².                                                            |
| `STEER_ANGLE`            | `30`                     | Front wheel angle at full lock when stopped, in degrees.                                           |
| `HIGH_SPEED_STEER_ANGLE` | `10`                     | Front wheel angle at full lock at `MAX_SPEED`, in degrees.                                         |
| `STEER_SPEED`            | `5`                      | How fast the steering moves, in full locks per second.                                             |
| `GRIP`                   | `1.8`                    | Max tire force, in multiples of the load on that wheel. Higher means tighter turns before sliding. |
| `SLIP_RATE`              | `25`                     | How fast tires cancel sideways sliding, per second. Lower feels looser.                            |
| `SUSPENSION_TRAVEL`      | `0.4`                    | Wheel travel each way from rest, in studs.                                                         |
| `SUSPENSION_FREQUENCY`   | `3`                      | Suspension bounce speed, in Hz. Higher is stiffer.                                                 |
| `SUSPENSION_DAMPING`     | `0.7`                    | `1` stops bouncing as fast as possible; lower bounces more.                                        |
| `FLIP_DELAY`             | `2`                      | Seconds upside down before the car flips itself back over.                                         |
| `ENGINE_SOUND_ID`        | `rbxassetid://358130654` | Looping engine sound.                                                                              |
| `ENGINE_VOLUME`          | `0.35`                   | Engine sound volume.                                                                               |
| `ENGINE_IDLE_PITCH`      | `0.17`                   | Engine sound `PlaybackSpeed` when stopped.                                                         |
| `ENGINE_MAX_PITCH`       | `1.42`                   | Engine sound `PlaybackSpeed` at `MAX_SPEED`.                                                       |

## Get started

This project uses [Azul](https://github.com/Ransomwave/azul), the easiest two-way sync tool.

Use `azul push` to get the library into your Roblox project:

```ps1
azul push -s .\sync\ReplicatedStorage -d ReplicatedStorage --from-sourcemap .\raycer.sourcemap.json
```

This pushes Raycer to `ReplicatedStorage`. It needs to be somewhere both the server and clients can require it.

## License

[MIT](LICENSE)

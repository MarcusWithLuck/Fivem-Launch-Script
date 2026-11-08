Config = {}

-- GTA stores RPM as 0.0 - 1.0 (1.0 = redline). This is the real RPM that 1.0
-- maps to, so players can type /launchrpm 5500.
Config.RedlineRPM = 8000

-- Remember each player's toggles and launch RPM between sessions.
Config.SavePreferences = true

---------------------------------------------------------------------------
-- Access (no item needed). Optional job lock.
---------------------------------------------------------------------------
Config.Access = {
    Group       = 'user', -- ESX group needed for the commands ('user' = everyone)
    AllowedJobs = nil,    -- e.g. { 'mechanic' } or nil for everyone
}

-- Vehicle classes that can't use the system: 13 cycles, 14 boats, 15 helis, 16 planes, 21 trains
Config.BlacklistedClasses = { [13] = true, [14] = true, [15] = true, [16] = true, [21] = true }

---------------------------------------------------------------------------
-- Controls
--   Launch control : HANDBRAKE + THROTTLE   (keyboard Space + W, pad R1 + R2)
--   Burnout        : HANDBRAKE + THROTTLE   (same buttons, while /burnout mode is on)
--   Rolling ALS    : ROLLING KEY + THROTTLE (keyboard Left Shift + W, pad D-pad Down + R2)
-- Players can rebind the rolling key in Settings > Key Bindings > FiveM.
---------------------------------------------------------------------------
Config.Controls = {
    RollingKeyboard = 'LSHIFT',
    RollingPad      = 'LDOWN_INDEX', -- D-pad down. Others: L1_INDEX, L3_INDEX, RLEFT_INDEX (Square), ...
}

---------------------------------------------------------------------------
-- Rev limiter bounce (the brap-brap while you're held on the limiter)
---------------------------------------------------------------------------
Config.Limiter = {
    RevRate  = 2.4,   -- how fast RPM climbs to the limit (GTA rpm units/sec)
    CutDrop  = 0.09,  -- RPM drop on each ignition cut
    CutTime  = 50,    -- ms ignition is cut
    HoldTime = 65,    -- ms on the limit between cuts
}

---------------------------------------------------------------------------
-- Turbo / boost model
-- On the 2-step (or rolling ALS) the anti-lag keeps the turbo lit, so boost
-- BUILDS while you wait. Release and the boost is already there:
-- no spool delay. The stored boost then bleeds into the natural spool.
-- Without a turbo there is no boost, only the RPM hold.
---------------------------------------------------------------------------
Config.Turbo = {
    RequireTurbo   = true,  -- anti-lag and boost need the turbo upgrade (mod slot 18)
    BuildTime      = 3.0,   -- seconds on the limiter with ALS to reach full boost (the "count of three")
    NoAlsCap       = 0.35,  -- 2-step WITHOUT anti-lag builds only a little boost
    NoAlsBuildTime = 4.0,
    ExtraPower     = 0.30,  -- extra power at full stored boost, on top of GTA's own turbo
    BleedTime      = 2.2,   -- seconds the stored boost takes to bleed off once you send it
    LiftBleedTime  = 6.0,   -- with ALS, how slowly boost leaks while you're off the throttle
    MaxPsi         = 28,    -- what full boost reads on the gauge
}

---------------------------------------------------------------------------
-- Launch control (/launch)
---------------------------------------------------------------------------
Config.Launch = {
    DefaultRPM      = 0.62,
    MinRPM          = 0.30,
    MaxRPM          = 0.95,
    TractionControl = true, -- trims the stored-boost power while the driven wheels are spinning
    MaxSlip         = 3.0,  -- m/s of wheelspin before TC starts trimming
}

---------------------------------------------------------------------------
-- Burnout mode (/burnout). Uses the same handbrake + throttle hold as launch
-- control, so turning one on turns the other off.
-- Hold R1+R2 / Space+W: fronts lock, rears light up. Let go of R1 to leave.
---------------------------------------------------------------------------
Config.Burnout = {
    RPM        = 0.82,
    MaxTime    = 0,     -- ms before the tyres let go (0 = never)
    BurstTyres = false,
}

---------------------------------------------------------------------------
-- Anti-lag (/antilag)
---------------------------------------------------------------------------
Config.AntiLag = {
    MinRPM      = 0.55, -- RPM needed when lifting off for pops
    LiftWindow  = 1500, -- ms of crackle after lifting off
    PopMinDelay = 60,
    PopMaxDelay = 240,
    ShiftPops   = true,
    FlameScale  = 1.0,
}

Config.Rolling = {
    RPM      = 0.72,
    MinSpeed = 3.0,   -- m/s (~7 mph)
    MaxSpeed = 31.0,  -- m/s (~70 mph)
}

---------------------------------------------------------------------------
-- Heat: sitting on the 2-step / rolling ALS / burnout heats the turbo.
-- Hot = misfires and stumbles. Overheated = boost is capped and the engine
-- takes damage until it cools down.
---------------------------------------------------------------------------
Config.Heat = {
    Enabled          = true,
    StageRate        = 0.045, -- heat per second on the 2-step with ALS
    RollingRate      = 0.07,
    BurnoutRate      = 0.06,
    NoAlsFactor      = 0.35,  -- 2-step without ALS heats much slower
    CoolRate         = 0.03,  -- per second while idle / normal driving
    CoolSpeedBonus   = 0.0015,-- extra cooling per m/s of airflow
    MisfireAt        = 0.70,
    OverheatAt       = 0.90,
    OverheatBoostCap = 0.40,
    EngineDamage     = 30.0,  -- engine health lost per second while overheated and still abusing it
    MinEngineHealth  = 150.0, -- never damages below this (no explosions)
}

---------------------------------------------------------------------------
-- Feel: the car should get a little wild
---------------------------------------------------------------------------
Config.Feel = {
    BodyShudder = 0.05,  -- body rocks on each limiter cut (torque reaction)
    LaunchSquat = 0.22,  -- nose lifts when you dump it (scaled by stored boost)
    Squirm      = 0.07,  -- rear steps around when the tyres are spinning
    CamShake    = 0.18,  -- camera vibration while on the limiter (0 = off)
    PopShake    = true,  -- tiny camera jolt on big pops
    Rumble      = true,  -- controller vibration
}

---------------------------------------------------------------------------
-- Sync: nearby players see the flames and hear the pops (OneSync)
---------------------------------------------------------------------------
Config.Sync = {
    Enabled           = true,
    Range             = 80.0,
    ClientMinInterval = 60,
    ServerMinInterval = 45,
}

-- Extra pop sounds on top of the car's own sound mod. The car's sound mod
-- already handles spool and blow-off from the turbo pressure. Turn this off
-- if your sound mods have their own backfires.
Config.Sound = {
    Enabled = true,
    Volume  = 0.45,
    Files   = { 'pop1.wav', 'pop2.wav', 'pop3.wav', 'pop4.wav' },
}

-- Minimal boost gauge: shows only while boost is built / held, then fades out.
Config.Hud = {
    Enabled = true,
}

Config.Locale = {
    launch_on   = 'Launch control ~g~armed',
    launch_off  = 'Launch control ~r~off',
    burnout_on  = 'Burnout mode ~g~on',
    burnout_off = 'Burnout mode ~r~off',
    antilag_on  = 'Anti-lag ~g~on',
    antilag_off = 'Anti-lag ~r~off',
    no_turbo    = '~y~No turbo fitted~s~ - anti-lag needs a turbo',
    overheat    = '~r~Turbo overheating',
    rpm_set     = 'Launch RPM ~y~%d',
    rpm_invalid = '~r~Use %d - %d rpm',
    no_access   = '~r~You are not allowed to use this.',
    status      = 'LC %s  ALS %s  Burnout %s  %d rpm',
}

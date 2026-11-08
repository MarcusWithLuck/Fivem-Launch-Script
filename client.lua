local ESX = exports['es_extended']:getSharedObject()

---------------------------------------------------------------------------
-- Player settings
---------------------------------------------------------------------------
local mode = {
    launch    = false,
    burnout   = false,
    antilag   = false,
    launchRpm = Config.Launch.DefaultRPM,
}

-- Game controls (same index on keyboard and gamepad)
local CTRL_THROTTLE  = 71 -- W  / R2
local CTRL_BRAKE     = 72 -- S  / L2 (blocked while staged so it can't reverse)
local CTRL_HANDBRAKE = 76 -- Space / R1

---------------------------------------------------------------------------
-- Runtime state
---------------------------------------------------------------------------
local phase         = nil   -- 'stage' | 'burnout' | 'rolling' | nil
local phaseStart    = 0
local rollingHeld   = false
local rollingSpeed  = 0.0
local burnoutLocked = false

local stored     = 0.0   -- boost (0-1) the anti-lag is holding in the turbo
local unleashing = false -- stored boost is being sent to the wheels
local alsUntil, nextPop = 0, 0
local lastPopLocal, lastPopSent, nextSquirm = 0, 0, 0
local lastThrottle, lastRpm, lastGear = 0.0, 0.0, 0
local currentVeh = 0
local camShaking = false
local overheatWarned = false
local hudVisible, lastHudSend = false, 0

local lim = { rpm = 0.2, cutUntil = 0, nextCut = 0 }
local heat = {} -- [vehicle] = { v = 0-1, t = lastUpdateMs }

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function notify(msg) ESX.ShowNotification(msg) end
local function clamp(v, lo, hi) return v < lo and lo or (v > hi and hi or v) end
local function toRealRpm(v) return math.floor(v * Config.RedlineRPM + 0.5) end

local function savePrefs()
    if not Config.SavePreferences then return end
    SetResourceKvpInt('lc_launch', mode.launch and 1 or 0)
    SetResourceKvpInt('lc_burnout', mode.burnout and 1 or 0)
    SetResourceKvpInt('lc_antilag', mode.antilag and 1 or 0)
    SetResourceKvpFloat('lc_rpm', mode.launchRpm)
end

local function loadPrefs()
    if not Config.SavePreferences then return end
    mode.launch  = GetResourceKvpInt('lc_launch') == 1
    mode.burnout = GetResourceKvpInt('lc_burnout') == 1 and not mode.launch
    mode.antilag = GetResourceKvpInt('lc_antilag') == 1
    local rpm = GetResourceKvpFloat('lc_rpm')
    if rpm and rpm >= Config.Launch.MinRPM and rpm <= Config.Launch.MaxRPM then
        mode.launchRpm = rpm
    end
end

local modelCache = {}
local function modelInfo(veh)
    local model = GetEntityModel(veh)
    local info = modelCache[model]
    if info then return info end

    info = {
        bias  = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fDriveBiasFront'), -- 0 RWD, 1 FWD
        mass  = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fMass'),
        bones = {},
    }
    for i = 1, 16 do
        local idx = GetEntityBoneIndexByName(veh, i == 1 and 'exhaust' or ('exhaust_' .. i))
        if idx ~= -1 then info.bones[#info.bones + 1] = idx end
    end
    modelCache[model] = info
    return info
end

local function hasTurbo(veh) return IsToggleModOn(veh, 18) end

local function alsActive(veh)
    return mode.antilag and (not Config.Turbo.RequireTurbo or hasTurbo(veh))
end

local function isUsableVehicle(veh)
    if veh == 0 or not DoesEntityExist(veh) then return false end
    if Config.BlacklistedClasses[GetVehicleClass(veh)] then return false end
    return GetPedInVehicleSeat(veh, -1) == PlayerPedId()
end

local function wheelSlip(veh, groundSpeed)
    local bias = modelInfo(veh).bias
    local maxWheel = 0.0
    for i = 0, GetVehicleNumberOfWheels(veh) - 1 do
        local front = i < 2
        if (front and bias > 0.0) or (not front and bias < 1.0) then
            local ws = math.abs(GetVehicleWheelSpeed(veh, i))
            if ws > maxWheel then maxWheel = ws end
        end
    end
    return maxWheel - groundSpeed
end

---------------------------------------------------------------------------
-- Heat (per vehicle, cools down even while you're out of the car)
---------------------------------------------------------------------------
local function getHeat(veh)
    local h = heat[veh]
    local now = GetGameTimer()
    if not h then
        h = { v = 0.0, t = now }
        heat[veh] = h
    elseif now - h.t > 1000 then
        -- catch up on cooling that happened while we weren't updating it
        h.v = math.max(0.0, h.v - Config.Heat.CoolRate * (now - h.t) / 1000)
    end
    h.t = now
    return h
end

---------------------------------------------------------------------------
-- Physical feel
---------------------------------------------------------------------------
-- Pure rotational nudge: equal and opposite impulses at two offsets.
-- axis 'roll' rocks side to side, 'pitch' lifts the nose, 'yaw' steps the rear out.
local function nudge(veh, axis, amount)
    if amount == 0 then return end
    local j = modelInfo(veh).mass * amount
    if axis == 'roll' then
        ApplyForceToEntity(veh, 1, 0.0, 0.0,  j,  0.9, 0.0, 0.0, 0, true, false, false, false, true)
        ApplyForceToEntity(veh, 1, 0.0, 0.0, -j, -0.9, 0.0, 0.0, 0, true, false, false, false, true)
    elseif axis == 'pitch' then
        ApplyForceToEntity(veh, 1, 0.0, 0.0,  j, 0.0,  1.5, 0.0, 0, true, false, false, false, true)
        ApplyForceToEntity(veh, 1, 0.0, 0.0, -j, 0.0, -1.5, 0.0, 0, true, false, false, false, true)
    elseif axis == 'yaw' then
        ApplyForceToEntity(veh, 1,  j, 0.0, 0.0, 0.0, -1.6, 0.0, 0, true, false, false, false, true)
    end
end

local function rumble(ms, strength)
    if Config.Feel.Rumble then SetPadShake(0, ms, clamp(math.floor(strength), 0, 255)) end
end

local function startCamShake()
    if Config.Feel.CamShake > 0 and not camShaking then
        ShakeGameplayCam('ROAD_VIBRATION_SHAKE', Config.Feel.CamShake)
        camShaking = true
    end
end

local function stopCamShake()
    if camShaking then
        StopGameplayCamShaking(false)
        camShaking = false
    end
end

---------------------------------------------------------------------------
-- Rev limiter
---------------------------------------------------------------------------
local function limiterReset(veh)
    lim.rpm = GetVehicleCurrentRpm(veh)
    lim.cutUntil, lim.nextCut = 0, 0
end

-- Holds the engine on `target`, bouncing on the cut. Returns true on a cut.
local function holdRpm(veh, target, dt)
    local L = Config.Limiter
    local now = GetGameTimer()
    local cut = false

    if now < lim.cutUntil then
        lim.rpm = target - L.CutDrop
    else
        lim.rpm = math.min(target, lim.rpm + L.RevRate * dt)
        if lim.rpm >= target and now >= lim.nextCut then
            lim.cutUntil = now + L.CutTime + math.random(0, 15)
            lim.nextCut  = lim.cutUntil + L.HoldTime + math.random(0, 20)
            lim.rpm = target - L.CutDrop
            cut = true
        end
    end

    SetVehicleCurrentRpm(veh, lim.rpm)
    return cut
end

local function misfire(dur)
    lim.cutUntil = GetGameTimer() + dur
    lim.nextCut = lim.cutUntil + Config.Limiter.HoldTime
end

---------------------------------------------------------------------------
-- Pops & flames
---------------------------------------------------------------------------
local function playPopFx(veh, volume, size)
    if HasNamedPtfxAssetLoaded('core') then
        local scale = size * Config.AntiLag.FlameScale
        for _, bone in ipairs(modelInfo(veh).bones) do
            UseParticleFxAssetNextCall('core')
            StartParticleFxNonLoopedOnEntityBone('veh_backfire', veh,
                0.0, 0.0, 0.0, 0.0, 0.0, 0.0, bone, scale, false, false, false)
        end
    end

    if Config.Sound.Enabled and volume > 0.01 then
        local files = Config.Sound.Files
        SendNUIMessage({
            action = 'pop',
            file   = files[math.random(#files)],
            volume = math.min(1.0, volume * Config.Sound.Volume * (0.7 + size * 0.3)),
        })
    end
end

local function pop(veh, size)
    local now = GetGameTimer()
    if now - lastPopLocal < 35 then return end
    lastPopLocal = now

    playPopFx(veh, 1.0, size)
    if size >= 1.1 and Config.Feel.PopShake and not camShaking then ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.03 * size) end
    rumble(60, 90 * size)

    if Config.Sync.Enabled and now - lastPopSent >= Config.Sync.ClientMinInterval
        and NetworkGetEntityIsNetworked(veh) then
        lastPopSent = now
        TriggerServerEvent('esx_launchcontrol:pop', VehToNet(veh), size)
    end
end

RegisterNetEvent('esx_launchcontrol:pop', function(netId, size)
    if type(netId) ~= 'number' or netId ~= netId then return end
    if type(size) ~= 'number' or size ~= size then size = 1.0 end
    size = clamp(size, 0.2, 2.0)
    if not NetworkDoesNetworkIdExist(netId) then return end
    local veh = NetToVeh(netId)
    if veh == 0 or not DoesEntityExist(veh) then return end

    local dist = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(veh))
    local range = Config.Sync.Range
    if dist > range then return end

    local falloff = 1.0 - (dist / range)
    playPopFx(veh, falloff * falloff, size)
end)

---------------------------------------------------------------------------
-- Boost
---------------------------------------------------------------------------
local function buildBoost(veh, dt, als, h)
    local T = Config.Turbo
    if not hasTurbo(veh) then stored = 0.0 return end

    local cap  = als and 1.0 or T.NoAlsCap
    local time = als and T.BuildTime or T.NoAlsBuildTime
    if Config.Heat.Enabled and h.v >= Config.Heat.OverheatAt then
        cap = math.min(cap, Config.Heat.OverheatBoostCap)
    end

    if stored < cap then
        stored = math.min(cap, stored + dt / time)
    else
        stored = math.max(cap, stored - dt)
    end
end

-- Keep the real turbo pressure at least as high as the boost we're holding,
-- so the car's sound mod hears a lit turbo and power is there instantly.
local function applyPressure(veh)
    if stored > 0.01 and hasTurbo(veh) then
        SetVehicleTurboPressure(veh, math.max(GetVehicleTurboPressure(veh), stored))
    end
end

local function unleash(veh, squat)
    if stored < 0.05 then return end
    unleashing = true
    SetVehicleTurboPressure(veh, stored)
    if squat and IsVehicleOnAllWheels(veh) then
        nudge(veh, 'pitch', Config.Feel.LaunchSquat * stored)
    end
    rumble(380, 140 + 115 * stored)
    if alsActive(veh) then pop(veh, 1.0 + stored * 0.6) end
end

---------------------------------------------------------------------------
-- Commands (registered through ESX on the server, routed here)
---------------------------------------------------------------------------
RegisterNetEvent('esx_launchcontrol:command', function(cmd, arg)
    local L = Config.Locale

    if cmd == 'launch' then
        mode.launch = not mode.launch
        if mode.launch and mode.burnout then mode.burnout = false end
        notify(mode.launch and L.launch_on or L.launch_off)
    elseif cmd == 'burnout' then
        mode.burnout = not mode.burnout
        if mode.burnout and mode.launch then mode.launch = false end
        notify(mode.burnout and L.burnout_on or L.burnout_off)
    elseif cmd == 'antilag' then
        mode.antilag = not mode.antilag
        notify(mode.antilag and L.antilag_on or L.antilag_off)
        local veh = GetVehiclePedIsIn(PlayerPedId(), false)
        if mode.antilag and Config.Turbo.RequireTurbo and veh ~= 0 and not hasTurbo(veh) then
            notify(L.no_turbo)
        end
    elseif cmd == 'rpm' then
        local value = tonumber(arg)
        if not value or value ~= value then return end -- reject nil / NaN
        local gta = value > 1.0 and (value / Config.RedlineRPM) or value
        if gta < Config.Launch.MinRPM or gta > Config.Launch.MaxRPM then
            notify(L.rpm_invalid:format(toRealRpm(Config.Launch.MinRPM), toRealRpm(Config.Launch.MaxRPM)))
            return
        end
        mode.launchRpm = gta
        notify(L.rpm_set:format(toRealRpm(gta)))
    elseif cmd == 'status' then
        local function onoff(b) return b and '~g~on~s~' or '~r~off~s~' end
        notify(L.status:format(onoff(mode.launch), onoff(mode.antilag), onoff(mode.burnout), toRealRpm(mode.launchRpm)))
        return
    end

    savePrefs()
end)

-- Rolling anti-lag button: one mapping for keyboard, one for gamepad.
-- Both can be rebound in Settings > Key Bindings > FiveM.
RegisterCommand('+lc_rolling', function() rollingHeld = true end, false)
RegisterCommand('-lc_rolling', function() rollingHeld = false end, false)
RegisterKeyMapping('+lc_rolling', 'Rolling anti-lag (hold)', 'keyboard', Config.Controls.RollingKeyboard)

RegisterCommand('+lc_rolling_pad', function() rollingHeld = true end, false)
RegisterCommand('-lc_rolling_pad', function() rollingHeld = false end, false)
RegisterKeyMapping('+lc_rolling_pad', 'Rolling anti-lag (hold, controller)', 'pad_digitalbutton', Config.Controls.RollingPad)

---------------------------------------------------------------------------
-- Minimal HUD (NUI boost gauge)
---------------------------------------------------------------------------
local function updateHud(veh, h, now)
    if not Config.Hud.Enabled then return end

    local pressure = hasTurbo(veh) and math.max(0.0, GetVehicleTurboPressure(veh)) or 0.0
    local boost = math.max(stored, phase and pressure or 0.0)
    local show = (phase ~= nil and hasTurbo(veh)) or stored > 0.03 or now < alsUntil or h.v > 0.5

    if not show and not hudVisible then return end
    if now - lastHudSend < 50 and show == hudVisible then return end
    lastHudSend, hudVisible = now, show

    SendNUIMessage({
        action = 'hud',
        show   = show,
        psi    = math.floor(clamp(boost, 0, 1) * Config.Turbo.MaxPsi + 0.5),
        boost  = clamp(boost, 0, 1),
        heat   = Config.Heat.Enabled and h.v or 0,
    })
end

local function hideHud()
    if hudVisible then
        hudVisible = false
        SendNUIMessage({ action = 'hud', show = false })
    end
end

---------------------------------------------------------------------------
-- Phase transitions
---------------------------------------------------------------------------
local function exitPhase(veh, throttle)
    local old = phase
    phase = nil
    stopCamShake()
    if veh == 0 or not DoesEntityExist(veh) then return end

    if old == 'stage' then
        SetVehicleHandbrake(veh, false)
        if throttle > 0.5 then
            SetVehicleCurrentRpm(veh, mode.launchRpm)
            unleash(veh, true)
        end
    elseif old == 'burnout' then
        SetVehicleBurnout(veh, false)
        if throttle > 0.5 then unleash(veh, true) end
    elseif old == 'rolling' then
        if throttle > 0.5 then unleash(veh, false) end
    end
end

local function enterPhase(veh, newPhase, speed)
    phase = newPhase
    phaseStart = GetGameTimer()
    limiterReset(veh)
    if newPhase == 'rolling' then rollingSpeed = speed end
    startCamShake()
end

local function resetAll(veh)
    if phase then exitPhase(veh, 0.0) end
    if veh ~= 0 and DoesEntityExist(veh) then
        SetVehicleHandbrake(veh, false)
        SetVehicleBurnout(veh, false)
        SetVehicleCheatPowerIncrease(veh, 1.0)
    end
    stored, unleashing, alsUntil = 0.0, false, 0
    burnoutLocked, lastGear = false, 0
    stopCamShake()
    hideHud()
end

---------------------------------------------------------------------------
-- Main loop
---------------------------------------------------------------------------
CreateThread(function()
    loadPrefs()
    RequestNamedPtfxAsset('core')

    while true do
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)

        if veh ~= currentVeh then
            resetAll(currentVeh)
            currentVeh = veh
        end

        if not (mode.launch or mode.burnout or mode.antilag) or not isUsableVehicle(veh) then
            if phase or unleashing or stored > 0 then resetAll(veh) end
            Wait(500)
        else
            Wait(0)

            local now      = GetGameTimer()
            local dt       = GetFrameTime()
            local speed    = GetEntitySpeed(veh)
            local throttle = GetDisabledControlNormal(0, CTRL_THROTTLE)
            local hbrake   = IsDisabledControlPressed(0, CTRL_HANDBRAKE)
            local als      = alsActive(veh)
            local h        = getHeat(veh)
            local HC       = Config.Heat

            if burnoutLocked and not hbrake then burnoutLocked = false end

            -----------------------------------------------------------------
            -- Which phase do the inputs ask for?
            -----------------------------------------------------------------
            local want = nil
            local pinned = throttle > 0.5

            if mode.launch and hbrake and pinned and (phase == 'stage' or speed < 0.5) then
                want = 'stage'
            elseif mode.burnout and hbrake and pinned and not burnoutLocked
                and (phase == 'burnout' or speed < 1.0) then
                want = 'burnout'
            elseif als and rollingHeld and pinned and (phase == 'rolling'
                or (speed >= Config.Rolling.MinSpeed and speed <= Config.Rolling.MaxSpeed)) then
                want = 'rolling'
            end

            if want ~= phase then
                if phase then exitPhase(veh, throttle) end
                if want then enterPhase(veh, want, speed) end
            end

            -----------------------------------------------------------------
            -- Run the active phase
            -----------------------------------------------------------------
            local cut, heatRate = false, 0.0

            if phase == 'stage' then
                -- 2-step: handbrake on, engine held on the launch RPM, boost builds
                DisableControlAction(0, CTRL_THROTTLE, true)
                DisableControlAction(0, CTRL_BRAKE, true)
                SetVehicleHandbrake(veh, true)
                cut = holdRpm(veh, mode.launchRpm, dt)
                buildBoost(veh, dt, als, h)
                heatRate = HC.StageRate * (als and 1.0 or HC.NoAlsFactor)
                if cut and als and math.random() < 0.35 + stored * 0.5 then
                    pop(veh, 0.7 + stored * 0.6)
                end

            elseif phase == 'burnout' then
                -- Line lock: handbrake button is used as the hold, rears spin free
                DisableControlAction(0, CTRL_HANDBRAKE, true)
                SetVehicleHandbrake(veh, false)
                SetVehicleBurnout(veh, true)
                cut = holdRpm(veh, Config.Burnout.RPM, dt)
                buildBoost(veh, dt, als, h)
                heatRate = HC.BurnoutRate * (als and 1.0 or HC.NoAlsFactor)
                if cut and als and math.random() < 0.3 then pop(veh, 0.8) end

                local B = Config.Burnout
                if B.MaxTime > 0 and now - phaseStart > B.MaxTime then
                    if B.BurstTyres then
                        local bias = modelInfo(veh).bias
                        if bias < 1.0 then
                            SetVehicleTyreBurst(veh, 4, true, 1000.0)
                            SetVehicleTyreBurst(veh, 5, true, 1000.0)
                        end
                        if bias > 0.0 then
                            SetVehicleTyreBurst(veh, 0, true, 1000.0)
                            SetVehicleTyreBurst(veh, 1, true, 1000.0)
                        end
                    end
                    burnoutLocked = true
                    exitPhase(veh, 0.0)
                end

            elseif phase == 'rolling' then
                -- Rolling anti-lag: ignition cut holds the speed, the turbo stays lit
                if speed > rollingSpeed + 0.25 then
                    DisableControlAction(0, CTRL_THROTTLE, true)
                end
                cut = holdRpm(veh, Config.Rolling.RPM, dt)
                buildBoost(veh, dt, true, h)
                heatRate = HC.RollingRate
                if cut and math.random() < 0.55 + stored * 0.4 then
                    pop(veh, 0.8 + stored * 0.5)
                end
            end

            if phase then
                applyPressure(veh)

                -- Limiter feel: body rocks with the engine, pad buzzes, cam vibrates harder as boost builds
                if cut then
                    nudge(veh, 'roll', Config.Feel.BodyShudder * (0.6 + math.random() * 0.8))
                    rumble(45, 60 + stored * 120)
                end
                if camShaking then
                    SetGameplayCamShakeAmplitude(Config.Feel.CamShake * (0.5 + stored))
                end

                -- Heat-soaked: stumbles and misfires
                if HC.Enabled and h.v >= HC.MisfireAt and math.random() < dt * (1.5 + h.v * 3.0) then
                    misfire(math.random(110, 220))
                    nudge(veh, 'roll', Config.Feel.BodyShudder * 1.6)
                    if als then pop(veh, 1.2) end
                end
            end

            -----------------------------------------------------------------
            -- Normal driving with anti-lag: lift-off crackle holds the boost,
            -- shift pops, back on the throttle = boost is already there
            -----------------------------------------------------------------
            if not phase then
                if als then
                    local A = Config.AntiLag
                    if lastThrottle > 0.6 and throttle < 0.2 and lastRpm > A.MinRPM and speed > 2.0 then
                        alsUntil = now + A.LiftWindow
                        nextPop = now + math.random(0, 50)
                        unleashing = false
                        if hasTurbo(veh) then
                            -- the turbo was lit when you lifted: ALS keeps that pressure in it
                            local spool = clamp((lastRpm - 0.3) / 0.6, 0.0, 1.0) * lastThrottle
                            stored = math.max(stored, clamp(GetVehicleTurboPressure(veh), 0.0, 1.0), spool)
                        end
                    end

                    if now < alsUntil then
                        if throttle > 0.5 then
                            alsUntil = 0
                            unleash(veh, false)
                        else
                            stored = math.max(0.0, stored - dt / Config.Turbo.LiftBleedTime)
                            applyPressure(veh)
                            heatRate = 0.01
                            if now >= nextPop then
                                pop(veh, 0.6 + math.random() * 0.6)
                                nextPop = now + math.random(A.PopMinDelay, A.PopMaxDelay)
                            end
                        end
                    elseif not unleashing and stored > 0 then
                        stored = math.max(0.0, stored - dt / Config.Turbo.BleedTime)
                    end

                    if A.ShiftPops then
                        local gear = GetVehicleCurrentGear(veh)
                        if lastGear > 0 and gear > lastGear and throttle > 0.5 and lastRpm > A.MinRPM then
                            pop(veh, 1.0)
                            applyPressure(veh)
                        end
                        lastGear = gear
                    end
                elseif not unleashing and stored > 0 then
                    stored = math.max(0.0, stored - dt / Config.Turbo.BleedTime)
                end
            end

            -----------------------------------------------------------------
            -- Unleash: stored boost goes to the wheels with no spool delay,
            -- then bleeds into the turbo's natural spool
            -----------------------------------------------------------------
            if unleashing then
                if throttle > 0.3 and stored > 0.01 and not phase then
                    local gain = Config.Turbo.ExtraPower * stored
                    local slip = wheelSlip(veh, speed)

                    if slip > Config.Launch.MaxSlip then
                        if Config.Launch.TractionControl then
                            gain = gain * clamp(1.0 - (slip - Config.Launch.MaxSlip) / 6.0, 0.0, 1.0)
                        end
                        -- tyres are lit: let the rear step around a bit
                        if now >= nextSquirm then
                            local s = (math.random() < 0.5 and -1 or 1) * Config.Feel.Squirm * clamp(slip / 8.0, 0.3, 1.0)
                            nudge(veh, 'yaw', s)
                            rumble(90, 120)
                            nextSquirm = now + math.random(120, 260)
                        end
                    end

                    SetVehicleCheatPowerIncrease(veh, 1.0 + gain)
                    applyPressure(veh)
                    stored = math.max(0.0, stored - dt / Config.Turbo.BleedTime)
                else
                    unleashing = false
                    SetVehicleCheatPowerIncrease(veh, 1.0)
                end
            end

            -----------------------------------------------------------------
            -- Heat
            -----------------------------------------------------------------
            if HC.Enabled then
                if heatRate > 0 then
                    h.v = math.min(1.0, h.v + heatRate * dt)
                else
                    h.v = math.max(0.0, h.v - (HC.CoolRate + speed * HC.CoolSpeedBonus) * dt)
                end

                if h.v >= HC.OverheatAt then
                    if phase then
                        local hp = GetVehicleEngineHealth(veh)
                        if hp > HC.MinEngineHealth then
                            SetVehicleEngineHealth(veh, math.max(HC.MinEngineHealth, hp - HC.EngineDamage * dt))
                        end
                    end
                    if not overheatWarned then
                        overheatWarned = true
                        notify(Config.Locale.overheat)
                    end
                elseif h.v < HC.MisfireAt then
                    overheatWarned = false
                end
            end

            updateHud(veh, h, now)

            lastThrottle = throttle
            lastRpm = GetVehicleCurrentRpm(veh)
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then resetAll(currentVeh) end
end)

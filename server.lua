local ESX = exports['es_extended']:getSharedObject()

---------------------------------------------------------------------------
-- Access checks
---------------------------------------------------------------------------
local function hasAccess(xPlayer)
    local access = Config.Access

    if access.AllowedJobs then
        local job = xPlayer.getJob() and xPlayer.getJob().name
        local ok = false
        for _, name in ipairs(access.AllowedJobs) do
            if name == job then ok = true break end
        end
        if not ok then
            xPlayer.showNotification(Config.Locale.no_access)
            return false
        end
    end

    return true
end

local function register(name, help, args, handler)
    ESX.RegisterCommand(name, Config.Access.Group, function(xPlayer, parsed, showError)
        if not hasAccess(xPlayer) then return end
        handler(xPlayer, parsed, showError)
    end, false, { help = help, arguments = args })
end

---------------------------------------------------------------------------
-- Chat commands
---------------------------------------------------------------------------
register('launch', 'Toggle launch control (2-step)', nil, function(xPlayer)
    TriggerClientEvent('esx_launchcontrol:command', xPlayer.source, 'launch')
end)

register('antilag', 'Toggle anti-lag (pops, flames, rolling anti-lag)', nil, function(xPlayer)
    TriggerClientEvent('esx_launchcontrol:command', xPlayer.source, 'antilag')
end)

register('burnout', 'Toggle burnout mode', nil, function(xPlayer)
    TriggerClientEvent('esx_launchcontrol:command', xPlayer.source, 'burnout')
end)

register('launchrpm', 'Set launch control RPM', {
    { name = 'rpm', help = ('RPM (e.g. 5500, redline is %d)'):format(Config.RedlineRPM), type = 'number' },
}, function(xPlayer, parsed)
    TriggerClientEvent('esx_launchcontrol:command', xPlayer.source, 'rpm', parsed.rpm)
end)

register('lcstatus', 'Show launch control / anti-lag status', nil, function(xPlayer)
    TriggerClientEvent('esx_launchcontrol:command', xPlayer.source, 'status')
end)

---------------------------------------------------------------------------
-- Pop / flame sync relay (OneSync). Only forwards to players in range and
-- only when the sender is actually driving the vehicle.
---------------------------------------------------------------------------
local lastPop = {}

RegisterNetEvent('esx_launchcontrol:pop', function(netId, size)
    if not Config.Sync.Enabled then return end
    local src = source
    local now = GetGameTimer()

    if lastPop[src] and now - lastPop[src] < Config.Sync.ServerMinInterval then return end
    lastPop[src] = now

    -- Never trust client input: netId must be a positive whole number,
    -- size must be a finite number (NaN / inf are rejected, not clamped).
    if type(netId) ~= 'number' or netId ~= netId or netId < 1 or netId > 65535
        or math.floor(netId) ~= netId then return end
    if type(size) ~= 'number' or size ~= size then size = 1.0 end
    size = math.max(0.2, math.min(2.0, size))

    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end

    local ped = GetPlayerPed(src)
    if GetVehiclePedIsIn(ped, false) ~= veh then return end

    local origin = GetEntityCoords(veh)
    local range = Config.Sync.Range

    for _, id in ipairs(GetPlayers()) do
        local target = tonumber(id)
        if target ~= src then
            local tPed = GetPlayerPed(target)
            if tPed and tPed ~= 0 and #(GetEntityCoords(tPed) - origin) <= range then
                TriggerClientEvent('esx_launchcontrol:pop', target, netId, size)
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    lastPop[source] = nil
end)

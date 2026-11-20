AddEventHandler('onClientResourceStart', function(resource)
    if GetCurrentResourceName() == resource then
        if pr_lib.framework.IsPlayerLoaded() then
            Radio:Init()
            Radio.playerLoaded = true
            TriggerServerEvent('mm_radio:server:createdefaultjammer')
        end
    end
end)

AddEventHandler('onClientResourceStop', function(resource)
    if GetCurrentResourceName() == resource then
        Radio:toggleRadioAnimation(false)
        Radio:RemoveJammerZone()
        if Radio.onRadio then
            Radio:leaveradio()
        end
    end
end)

RegisterNetEvent('mm_radio:client:use', function(slot)
    if not Radio.playerLoaded or Radio.PlayerDead or IsPedFatallyInjured(pr_lib.cache.ped) then return end
    if not Radio.identifier then Radio:Init() end
    local userdata = Radio.identifier and Radio.userData[Radio.identifier]
    if not userdata then return end
    local battery, radioId = pr_lib.callback.await('mm_radio:server:getradiodata', false, slot)
    -- Character/session/death may change while the callback is pending.
    if not Radio.playerLoaded or Radio.PlayerDead or not radioId or Radio.userData[Radio.identifier] ~= userdata then return end
    Radio.usingRadio = true
    SetNuiFocus(true, true)
    Radio:toggleRadioAnimation(true)
    Radio:SendSvelteMessage("setRadioVisible", {
        radioId = radioId,
        onRadio = Radio.onRadio,
        channel = Radio.RadioChannel,
        volume = Radio.Volume,
        favourite = Radio.favourite,
        recomended = Radio.recomended,
        userData = userdata,
        time = Radio:CalculateTimeToDisplay(),
        street = Radio:getCrossroads(),
        maxChannel = Shared.MaxFrequency,
        locale = Radio.locale,
        channelName = Shared.RadioNames,
        insideJammerZone = Radio.signalJammed,
        battery = battery,
        overlay = Shared.Overlay
    })
    UpdateTime()
    if userdata.allowMovement then
        SetNuiFocusKeepInput(true)
        DisableControls()
    end
end)

RegisterNetEvent('mm_radio:client:usejammer', function()
    if not Shared.Jammer.state then return end
    if not Shared.Jammer.permission or not (pr_lib.table.contains(Shared.Jammer.permission, Radio.PlayerJob) or pr_lib.table.contains(Shared.Jammer.permission, Radio.PlayerGang)) then
        pr_lib.Notify({
            title = locale('jammer.permission'),
            type = 'error'
        })
        return
    end
    local plyCoords = GetEntityCoords(pr_lib.cache.ped)
    local forward = GetEntityForwardVector(pr_lib.cache.ped)
    local x, y, z = table.unpack(plyCoords + forward * 1.0)
    local id = math.random(1000, 9999)
    TriggerServerEvent('mm_radio:server:spawnobject', {
        coords = vec4(x, y, z - 1.0, GetEntityHeading(pr_lib.cache.ped)),
        id = id,
        range = Shared.Jammer.range.default,
        allowedChannels = {},
        canRemove = true,
        canDamage = true
    })
end)

RegisterNetEvent('mm_radio:client:syncobject', function(data)
    -- Hydration and live broadcasts can overlap; replace, never duplicate a zone.
    TriggerEvent('mm_radio:client:removejammer', data.id)
    local entity = NetworkGetEntityFromNetworkId(data.object)
    if entity ~= 0 then SetEntityCanBeDamaged(entity, data.canDamage) end
    Radio.jammer[#Radio.jammer+1] = {
        id = data.id,
        entity = entity,
        object = data.object,
        coords = data.coords,
        allowedChannels = data.allowedChannels,
        range = data.range,
        enable = data.enable,
        canRemove = data.canRemove,
        canDamage = data.canDamage,
        zone = pr_lib.zones.sphere({
            coords = data.coords,
            radius = data.range,
            debug = Shared.Debug,
            jammerid = data.id,
            entity = entity,
            object = data.object,
            onEnter = OnEnterJammerZone,
            onExit = OnExitJammerZone
        }),
        zoneJammer = pr_lib.zones.sphere({
            coords = data.coords,
            radius = 2.5,
            debug = Shared.Debug,
            jammerid = data.id,
            entity = entity,
            object = data.object,
            onEnter = OnEnterJammer,
            onExit = OnExitJammer
        })
    }
end)

RegisterNetEvent('mm_radio:client:changeJammerRange', function(id, range)
    for i=1, #Radio.jammer do
        local entity = Radio.jammer[i]
        if entity.id == id then
            entity.zone:remove()
            entity.range = range
            entity.zone = pr_lib.zones.sphere({
                coords = entity.coords,
                radius = range,
                debug = Shared.Debug,
                jammerid = id,
                entity = entity.entity,
                object = entity.object,
                onEnter = OnEnterJammerZone,
                onExit = OnExitJammerZone
            })
            break
        end
    end
end)

RegisterNetEvent('mm_radio:client:removeallowedchannel', function(id, allowedChannels)
    for i=1, #Radio.jammer do
        local entity = Radio.jammer[i]
        if entity.id == id then
            entity.allowedChannels = allowedChannels
            Radio:UpdateJammerZone(id, allowedChannels)
            break
        end
    end
end)

RegisterNetEvent('mm_radio:client:addallowedchannel', function(id, allowedChannels)
    for i=1, #Radio.jammer do
        local entity = Radio.jammer[i]
        if entity.id == id then
            entity.allowedChannels = allowedChannels
            Radio:UpdateJammerZone(id, allowedChannels)
            break
        end
    end
end)

RegisterNetEvent('mm_radio:client:togglejammer', function(id, state)
    for i=1, #Radio.jammer do
        local entity = Radio.jammer[i]
        if entity.id == id then
            entity.zone:remove()
            entity.enable = state
            if state then
                entity.zone = pr_lib.zones.sphere({
                    coords = entity.coords,
                    radius = entity.range,
                    debug = Shared.Debug,
                    jammerid = id,
                    entity = entity.entity,
                    object = entity.object,
                    onEnter = OnEnterJammerZone,
                    onExit = OnExitJammerZone
                })

            else
                entity.zone:remove()
                Radio:UpdateJammerRemove(id)
            end
            break
        end
    end
end)

RegisterNetEvent('mm_radio:client:removejammer', function(id)
    for i=1, #Radio.jammer do
        local entity = Radio.jammer[i]
        if entity.id == id then
            entity.zone:remove()
            entity.zoneJammer:remove()
            Radio:UpdateJammerRemove(id)
            table.remove(Radio.jammer, i)
        end
    end
end)

RegisterNetEvent('mm_radio:client:remove', function()
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    Radio:toggleRadioAnimation(false)
    Radio:SendSvelteMessage("setRadioHide", nil)
    Radio.usingRadio = false
end)

RegisterNetEvent('mm_radio:client:radioListUpdate', function(players, channel)
    if Radio.RadioChannel == channel then
        Radio:SendSvelteMessage("updateRadioList", players)
    end
end)

RegisterNetEvent('mm_radio:client:nocharge', function()
    Radio:leaveradio()
end)

RegisterNetEvent("mm_radio:client:recharge", function()
    TriggerServerEvent('mm_radio:server:rechargeBattery')
end)

RegisterNetEvent("pma-voice:radioActive", function(talkingState)
    Radio:SendSvelteMessage("updateRadioTalking", {
        radioId = tostring(Radio.playerServerID),
        radioTalking = talkingState
    })
end)

RegisterNetEvent("pma-voice:setTalkingOnRadio", function(source, talkingState)
    Radio:SendSvelteMessage("updateRadioTalking", {
        radioId = tostring(source),
        radioTalking = talkingState
    })
end)

AddEventHandler('pr_bridge:client:OnPlayerLoaded', function()
    Radio.playerLoaded = true
    Radio:Init()
    TriggerServerEvent('mm_radio:server:createdefaultjammer')
    local jammer = pr_lib.callback.await('mm_radio:server:getjammer', false)
    for i = 1, #(jammer or {}) do
        TriggerEvent('mm_radio:client:syncobject', jammer[i])
    end
end)

AddEventHandler('pr_bridge:client:OnPlayerUnloaded', function()
    if Radio.usingRadio then TriggerEvent('mm_radio:client:remove') end
    Radio.hasRadio = false
    Radio:leaveradio()
    Radio.playerLoaded = false
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
    local player = QBX.PlayerData
    player.job = job
    Radio:Init(player)
end)

RegisterNetEvent('QBCore:Player:SetPlayerData', function(val)
    if Radio.playerLoaded then
        Radio:doRadioCheck()
    end
end)

RegisterNetEvent('QBCore:Client:OnGangUpdate', function(gang)
    local player = QBX.PlayerData
    player.gang = gang
    Radio:Init(player)
end)

RegisterNetEvent("QBCore:Client:SetDuty", function(newDuty)
    Radio.PlayerDuty = newDuty
    local restricted=Shared.RestrictedChannels[math.floor(Radio.RadioChannel)]
    if Radio.onRadio and restricted and RadioConfig.requiresDuty(restricted) and not newDuty then Radio:leaveradio() end
end)

RegisterNetEvent("ND:updateCharacter", function(character)
    Radio.PlayerDead = character.metadata.dead
end)

AddEventHandler('ox_inventory:updateInventory', function()
    Radio:doRadioCheck()
end)

AddEventHandler('gameEventTriggered', function(event, data)
    if event == "CEventNetworkEntityDamage" then
        if not IsEntityAPed(data[1]) then return end
        if data[4] and NetworkGetPlayerIndexFromPed(data[1]) == pr_lib.cache.playerId and IsEntityDead(pr_lib.cache.ped) then
            if Radio.usingRadio then
                TriggerEvent('mm_radio:client:remove')
            end
            if Radio.playerLoaded and Radio.onRadio and Radio.hasRadio and Radio.RadioChannel ~= 0 then
                Radio:leaveradio()
            end
        end
    end
end)

local function refreshDead()
    -- Cache expiry is swept periodically. Invalidate before reading a changed
    -- character status so a previous false/true cannot survive this event.
    pr_lib.cache.clear('metadata:self:isdead')
    pr_lib.cache.clear('metadata:self:inlaststand')
    Radio.PlayerDead=pr_lib.cache.GetMetadata('isdead',0)==true or pr_lib.cache.GetMetadata('inlaststand',0)==true or pr_lib.cache.get('dead',false)==true
    if Radio.PlayerDead then
        if Radio.usingRadio then TriggerEvent('mm_radio:client:remove') end
        if Radio.onRadio or Radio.RadioChannel ~= 0 then Radio:leaveradio() end
    end
end
pr_lib.cache.onChange('dead',refreshDead)
AddEventHandler('pr_bridge:client:OnInventoryChanged',refreshDead)
AddEventHandler('pr_bridge:client:OnPlayerLoaded',refreshDead)
-- Defer until the framework cache has processed its own data/status handlers.
RegisterNetEvent('QBCore:Player:SetPlayerData',function() SetTimeout(0,refreshDead) end)
RegisterNetEvent('qbx_core:client:onSetMetaData',function(key)
    if key=='isdead' or key=='inlaststand' then SetTimeout(0,refreshDead) end
end)
AddEventHandler('qbx_core:client:statusChanged',function() SetTimeout(0,refreshDead) end)
RegisterNetEvent('mm_radio:client:batteryUpdated',function()
    if Radio.usingRadio then Radio:update() end
end)
AddEventHandler('pr_bridge:client:OnPlayerUnloaded',function()
    Radio.PlayerDead=false
    pr_lib.cache.clear('mm_radio:character')
end)
refreshDead()
AddEventHandler('mm_radio:configChanged',function()
    if not Radio.playerLoaded then return end
    Radio:Init()
    local restricted=Shared.RestrictedChannels[math.floor(Radio.RadioChannel)]
    local permitted=not restricted or (restricted.type=='job' and (not RadioConfig.requiresDuty(restricted) or Radio.PlayerDuty) and pr_lib.table.contains(restricted.name,Radio.PlayerJob))
        or (restricted.type=='gang' and pr_lib.table.contains(restricted.name,Radio.PlayerGang))
    if Radio.onRadio and (Radio.RadioChannel>Shared.MaxFrequency or not permitted) then Radio:leaveradio() end
    if not Shared.Jammer.state and Radio.signalJammed then
        Radio.insideJammer,Radio.signalJammed,Radio.insideJammerZone=false,false,0
        Radio:SendSvelteMessage('insideJammer',false)
        if Radio.onRadio then exports['pma-voice']:setRadioChannel(Radio.RadioChannel) end
    end
    if Radio.usingRadio then Radio:update() end
end)

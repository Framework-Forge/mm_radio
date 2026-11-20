local channels, jammer, batteryData = {}, {}, {}
local spawnedDefaultJammer, nextJammerId, radioSequence = false, 1000000, 0
local jammerGeneration = 0
local inventory = pr_lib.inventory

local function finite(value, minimum, maximum)
    return type(value) == 'number' and value == value and value >= minimum and value <= maximum
end

local function playerData(src)
    local player = pr_lib.cache.GetPlayer(src, 0)
    return player and (player.PlayerData or player)
end

local function ready(src)
    if pr_lib.cache.get('mm_radio:session:' .. src) == false then return end
    local data = src > 0 and playerData(src)
    return data and data.citizenid and data
end

local function throttle(src, action, milliseconds)
    local key = ('mm_radio:request:%s:%s'):format(src, action)
    local now = GetGameTimer()
    local last = pr_lib.cache.get(key)
    if last and now >= last and now - last < milliseconds then return false end
    pr_lib.cache.set(key, now)
    return true
end

local function ownedRadio(src, slot)
    if type(slot) == 'table' then
        slot = slot.slot
        if slot == nil then return end
    end
    if slot ~= nil then
        if not finite(slot, 1, 100000) or slot % 1 ~= 0 then return end
        local item = inventory.GetSlot(src, slot)
        if item and pr_lib.table.contains(Shared.RadioItem, item.name) then return item end
        return
    end
    for _, name in ipairs(Shared.RadioItem) do
        local item = inventory.GetSlotWithItem(src, name)
        if item then return item end
    end
end

local function radioId(src, item)
    local metadata = RadioConfig.copy(item.metadata or {})
    if type(metadata.radioId) == 'string' and #metadata.radioId > 0 and #metadata.radioId <= 200 then return metadata.radioId end
    local data = ready(src)
    if not data then return end
    radioSequence = radioSequence + 1
    local id = ('%s:%s:%s:%s'):format(data.citizenid, os.time(), GetGameTimer(), radioSequence)
    local info = data.charinfo or {}
    metadata.radioId = id
    metadata.name = metadata.name or ((info.firstname or '') .. ' ' .. (info.lastname or ''))
    inventory.SetMetadata(src, item.slot, metadata)
    -- Do not issue an ID unless it actually belongs to the current inventory slot.
    local updated = inventory.GetSlot(src, item.slot)
    if not updated or not updated.metadata or updated.metadata.radioId ~= id then return end
    return id
end

pr_lib.callback.register('mm_radio:server:getradiodata', function(src, slot)
    if not ready(src) then return 0, nil end
    local item = ownedRadio(src, slot)
    if not item then return 0, nil end
    local id = radioId(src, item)
    if not id then return 0, nil end
    if not Shared.Battery.state then return 100, id end
    local tickKey = 'mm_radio:battery:tick:' .. id
    if not pr_lib.cache.get(tickKey) then pr_lib.cache.set(tickKey, GetGameTimer()) end
    return batteryData[id] or 100, id
end)

-- Battery consumption is server-owned: a client cannot drain another radio,
-- accelerate consumption by replaying events, or stop depletion by omitting events.
local function consumeBattery(src)
    if not Shared.Battery.state or not ready(src) then return end
    local seen, now = {}, GetGameTimer()
    for _, name in ipairs(Shared.RadioItem) do
        local items = inventory.Search(src, 'slots', name) or {}
        for _, item in pairs(items) do
            local id = radioId(src, item)
            if id and not seen[id] then
                seen[id] = true
                local key = 'mm_radio:battery:tick:' .. id
                local last = pr_lib.cache.get(key)
                local presentKey = 'mm_radio:battery:present:' .. id
                local present = pr_lib.cache.get(presentKey)
                local owner = ready(src).citizenid
                -- No offline depletion; transferring the device keeps its charge.
                if not present or present.owner ~= owner or now-present.time > 2500 then last=nil end
                pr_lib.cache.set(presentKey,{owner=owner,time=now})
                local interval = Shared.Battery.depletionTime * 60000
                if last and now >= last then
                    local periods = math.floor((now - last) / interval)
                    if periods > 0 then
                        local oldCharge = batteryData[id] or 100
                        batteryData[id] = math.max(oldCharge - periods * Shared.Battery.consume, 0)
                        pr_lib.cache.set(key, last + periods * interval)
                        if oldCharge > 0 and batteryData[id] == 0 then TriggerClientEvent('mm_radio:client:nocharge', src) end
                    end
                else
                    pr_lib.cache.set(key, now)
                end
            end
        end
    end
end
-- Kept for compatibility with older clients; payload IDs are deliberately ignored.
RegisterNetEvent('mm_radio:server:consumeBattery', function()
    if throttle(source, 'battery', 1000) then consumeBattery(source) end
end)
CreateThread(function()
    while true do
        Wait(1000)
        if Shared.Battery.state then
            for _, id in ipairs(GetPlayers()) do consumeBattery(tonumber(id)) end
        end
    end
end)

RegisterNetEvent('mm_radio:server:rechargeBattery', function()
    local src = source
    if not Shared.Battery.state or not ready(src) or not throttle(src, 'recharge', 1000) then return end
    local item = ownedRadio(src)
    local id = item and radioId(src, item)
    if not id or not inventory.RemoveItem(src, 'radiocell', 1) then return end
    batteryData[id] = 100
    pr_lib.cache.set('mm_radio:battery:tick:' .. id, GetGameTimer())
    TriggerClientEvent('mm_radio:client:batteryUpdated', src)
end)

local function jammerPermission(src)
    local data = ready(src)
    if not data then return false end
    local metadata = data.metadata or {}
    if metadata.isdead or metadata.inlaststand then return false end
    return pr_lib.table.contains(Shared.Jammer.permission, (data.job or {}).name)
        or pr_lib.table.contains(Shared.Jammer.permission, (data.gang or {}).name)
end

local function coordinates(value)
    local kind = type(value)
    if kind ~= 'table' and kind ~= 'vector4' and kind ~= 'vector3' then return end
    if not finite(value.x, -100000, 100000) or not finite(value.y, -100000, 100000)
        or not finite(value.z, -100000, 100000) or not finite(value.w or 0, -360, 360) then return end
    return { x = value.x, y = value.y, z = value.z, w = value.w or 0 }
end

local function nearby(src, coords)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local current = GetEntityCoords(ped)
    return (current.x-coords.x)^2 + (current.y-coords.y)^2 + (current.z-coords.z)^2 <= 16
end

local function jammerPacket(entry)
    return { enable=entry.enable, object=entry.object, coords=RadioConfig.copy(entry.coords),
        id=entry.id, range=entry.range, allowedChannels=RadioConfig.copy(entry.allowedChannels),
        canRemove=entry.canRemove, canDamage=entry.canDamage }
end

local function spawnJammer(data, src, owner)
    local generation = jammerGeneration
    local entity = CreateObject(joaat(Shared.Jammer.model), data.coords.x, data.coords.y, data.coords.z, true, true, false)
    local elapsed = 0
    while not DoesEntityExist(entity) and elapsed < 5000 do Wait(50); elapsed=elapsed+50 end
    if not DoesEntityExist(entity) or generation ~= jammerGeneration or not Shared.Jammer.state
        or (src and (not ready(src) or ready(src).citizenid ~= owner or not jammerPermission(src) or not nearby(src,data.coords))) then
        if DoesEntityExist(entity) then DeleteEntity(entity) end
        return false
    end
    -- Consume only after spawning and checking that this is still the same character.
    if src and not inventory.RemoveItem(src, 'jammer', 1) then DeleteEntity(entity); return false end
    if src then SetEntityRoutingBucket(entity,GetPlayerRoutingBucket(src)) end
    SetEntityHeading(entity, data.coords.w)
    data.entity, data.object, data.owner = entity, NetworkGetNetworkIdFromEntity(entity), owner
    data.enable = data.enable ~= false
    jammer[#jammer+1] = data
    TriggerClientEvent('mm_radio:client:syncobject', -1, jammerPacket(data))
    return true
end

RegisterNetEvent('mm_radio:server:spawnobject', function(data)
    local src = source
    if not Shared.Jammer.state or not jammerPermission(src) or not throttle(src, 'spawn', 2000) then return end
    local coords = type(data)=='table' and coordinates(data.coords)
    if not coords or not nearby(src, coords) or #jammer >= 200 or inventory.GetItemCount(src,'jammer') < 1 then return end
    local owner = ready(src).citizenid
    nextJammerId = nextJammerId+1
    local entry={coords=coords,id=nextJammerId,range=Shared.Jammer.range.default,
        allowedChannels={},canRemove=true,canDamage=true}
    CreateThread(function() spawnJammer(entry, src, owner) end)
end)

local function editableJammer(src, id)
    if not Shared.Jammer.state or not finite(id, 1, 2147483647) or id%1~=0
        or not jammerPermission(src) or not throttle(src, 'edit', 250) then return end
    for index, entry in ipairs(jammer) do
        if entry.id==id and nearby(src,entry.coords) and DoesEntityExist(entry.entity)
            and (not GetPlayerRoutingBucket or GetPlayerRoutingBucket(src)==GetEntityRoutingBucket(entry.entity)) then
            if not entry.removing then return entry,index end
        end
    end
end

RegisterNetEvent('mm_radio:server:togglejammer', function(id)
    local entry=editableJammer(source,id)
    if not entry then return end
    entry.enable=not entry.enable
    TriggerClientEvent('mm_radio:client:togglejammer',-1,id,entry.enable)
end)
RegisterNetEvent('mm_radio:server:removejammer', function(id)
    local src=source
    local entry=editableJammer(src,id)
    if not entry or not entry.canRemove then return end
    entry.removing=true
    -- Trust server entity health, never the client's "isDamaged" flag.
    if GetEntityHealth(entry.entity)>0 and not inventory.AddItem(src,'jammer',1) then entry.removing=nil; return end
    -- Inventory adapters may yield; another jammer can move this array's indices.
    for index,current in ipairs(jammer) do
        if current==entry then table.remove(jammer,index); break end
    end
    DeleteEntity(entry.entity)
    TriggerClientEvent('mm_radio:client:removejammer',-1,id)
end)
RegisterNetEvent('mm_radio:server:changeJammerRange', function(id,range)
    if not finite(range,Shared.Jammer.range.min,Shared.Jammer.range.max) then return end
    local entry=editableJammer(source,id)
    if not entry then return end
    entry.range=range
    TriggerClientEvent('mm_radio:client:changeJammerRange',-1,id,range)
end)

local function updateAllowed(id, allowedChannels, event)
    if type(allowedChannels)~='table' then return end
    local list,seen={},{}
    for key,channel in pairs(allowedChannels) do
        if not finite(key,1,100) or key%1~=0 or not finite(channel,1,Shared.MaxFrequency) then return end
        if not seen[channel] then list[#list+1]=channel; seen[channel]=true end
    end
    local entry=editableJammer(source,id)
    if not entry then return end
    entry.allowedChannels=list
    TriggerClientEvent(event,-1,id,list)
end
RegisterNetEvent('mm_radio:server:removeallowedchannel',function(id,list) updateAllowed(id,list,'mm_radio:client:removeallowedchannel') end)
RegisterNetEvent('mm_radio:server:addallowedchannel',function(id,list) updateAllowed(id,list,'mm_radio:client:addallowedchannel') end)

RegisterNetEvent('mm_radio:server:addToRadioChannel', function(channel, username)
    local src=source
    if not ready(src) or not finite(channel,1,Shared.MaxFrequency) or type(username)~='string'
        or #username==0 or #username>100 or not throttle(src,'roster',250) then return end
    local voice=exports['pma-voice']:GetVoiceState(src)
    if not voice or voice.radioChannel~=channel then return end
    channels[channel]=channels[channel] or {}
    channels[channel][tostring(src)]={name=username,isTalking=false}
    TriggerClientEvent('mm_radio:client:radioListUpdate',-1,channels[channel],channel)
end)
RegisterNetEvent('mm_radio:server:removeFromRadioChannel', function(channel)
    if not finite(channel,1,Shared.MaxFrequency) or not channels[channel] then return end
    channels[channel][tostring(source)]=nil
    TriggerClientEvent('mm_radio:client:radioListUpdate',-1,channels[channel],channel)
    if not next(channels[channel]) then channels[channel]=nil end
end)

local function cleanupPlayer(src)
    pr_lib.cache.set('mm_radio:session:' .. src, false)
    pr_lib.cache.clear('player:' .. src)
    for id, list in pairs(channels) do
        if list[tostring(src)] then
            list[tostring(src)]=nil
            TriggerClientEvent('mm_radio:client:radioListUpdate',-1,list,id)
            if not next(list) then channels[id]=nil end
        end
    end
    for _,action in ipairs({'battery','recharge','spawn','edit','roster'}) do
        pr_lib.cache.clear(('mm_radio:request:%s:%s'):format(src,action))
    end
end
AddEventHandler('playerDropped',function() cleanupPlayer(source) end)
AddEventHandler('pr_bridge:server:OnPlayerUnloaded',cleanupPlayer)
AddEventHandler('pr_bridge:server:OnPlayerLoaded',function(src)
    pr_lib.cache.clear('player:' .. src)
    pr_lib.cache.set('mm_radio:session:' .. src, true)
end)

local function createDefaultJammers()
    if not Shared.Jammer.state or spawnedDefaultJammer then return end
    spawnedDefaultJammer=true
    for _, value in ipairs(Shared.Jammer.default) do
        local entry=RadioConfig.copy(value)
        entry.coords=coordinates(entry.coords)
        entry.canRemove=false
        CreateThread(function() spawnJammer(entry) end)
    end
end
-- Clients may request hydration, but cannot supply or manufacture fixed jammers.
RegisterNetEvent('mm_radio:server:createdefaultjammer',createDefaultJammers)
pr_lib.callback.register('mm_radio:server:getjammer',function(src)
    if not ready(src) then return {} end
    local snapshot={}
    for _,entry in ipairs(jammer) do snapshot[#snapshot+1]=jammerPacket(entry) end
    return snapshot
end)

AddEventHandler('onResourceStart',function(resource)
    if resource~=GetCurrentResourceName() then return end
    local raw=LoadResourceFile(resource,'battery.json')
    local ok,value=pcall(json.decode,raw or '{}')
    if ok and type(value)=='table' then
        for id,charge in pairs(value) do if type(id)=='string' and finite(charge,0,100) then batteryData[id]=charge end end
    end
    createDefaultJammers()
end)
AddEventHandler('onResourceStop',function(resource)
    if resource~=GetCurrentResourceName() then return end
    for _,entry in ipairs(jammer) do DeleteEntity(entry.entity) end
    SaveResourceFile(resource,'battery.json',json.encode(batteryData),-1)
end)
AddEventHandler('mm_radio:server:configChanged',function()
    jammerGeneration=jammerGeneration+1
    for i=#jammer,1,-1 do
        local entry=jammer[i]
        if not entry.canRemove then
            DeleteEntity(entry.entity); table.remove(jammer,i)
            TriggerClientEvent('mm_radio:client:removejammer',-1,entry.id)
        elseif not Shared.Jammer.state then
            entry.enable=false
            TriggerClientEvent('mm_radio:client:togglejammer',-1,entry.id,false)
        end
    end
    spawnedDefaultJammer=false
    createDefaultJammers()
end)

if Shared.Ready then
    pr_lib.addCommand('radio',{help=locale('commands.radio'),params={}},function(src)
        if Shared.UseCommand then TriggerClientEvent('mm_radio:client:use',src) end
    end)
    pr_lib.addCommand('jammer',{help=locale('commands.jammer'),params={}},function(src)
        if Shared.UseCommand then TriggerClientEvent('mm_radio:client:usejammer',src) end
    end)
    pr_lib.addCommand('rechargeradio',{help=locale('commands.recharge'),params={}},function(src)
        if Shared.UseCommand then TriggerClientEvent('mm_radio:client:recharge',src) end
    end)
end
pr_lib.addCommand('remradiodata',{help=locale('commands.reset'),params={}},function(src)
    TriggerClientEvent('mm_radio:client:removedata',src)
end)

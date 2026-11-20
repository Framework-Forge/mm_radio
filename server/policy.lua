local function canJoin(src,channel)
    if type(channel)~='number' or channel~=channel or channel<1 or channel>Shared.MaxFrequency then return false end
    if pr_lib.cache.get('mm_radio:session:' .. src)==false then return false end
    local player=pr_lib.cache.GetPlayer(tonumber(src),0)
    local data=player and (player.PlayerData or player) or {}
    if not data.citizenid or (data.metadata or {}).isdead or (data.metadata or {}).inlaststand then return false end
    local restriction=Shared.RestrictedChannels[math.floor(channel)]
    if not restriction then return true end
    local group=data[restriction.type] or {}
    return pr_lib.table.contains(restriction.name,group.name) and (not RadioConfig.requiresDuty(restriction) or group.onduty==true)
end
exports('CanJoinChannel',canJoin)
local function register() exports['pma-voice']:setRadioPolicy(canJoin) end
CreateThread(register)
AddEventHandler('onResourceStart',function(resource) if resource=='pma-voice' then register() end end)
AddEventHandler('mm_radio:server:configChanged',function()
    for _,playerSource in ipairs(GetPlayers()) do
        local src=tonumber(playerSource)
        local state=exports['pma-voice']:GetVoiceState(src)
        if state.radioChannel and state.radioChannel~=0 and not canJoin(src,state.radioChannel) then
            exports['pma-voice']:setPlayerRadio(src,0)
        end
    end
end)
AddEventHandler('qbx_core:server:onSetMetaData',function(key,_,value,src)
    if (key=='isdead' or key=='inlaststand') and value==true then
        exports['pma-voice']:setPlayerRadio(src,0)
    end
end)
-- Framework events are local server events. Never accept duty claims from NUI.
local function recheck(src)
    src=tonumber(src)
    if not src then return end
    pr_lib.cache.clear('player:'..src)
    local state=exports['pma-voice']:GetVoiceState(src)
    if state.radioChannel and state.radioChannel~=0 and not canJoin(src,state.radioChannel) then
        exports['pma-voice']:setPlayerRadio(src,0)
    end
end
AddEventHandler('QBCore:Server:SetDuty',recheck)
AddEventHandler('QBCore:Server:OnJobUpdate',recheck)
AddEventHandler('QBCore:Server:OnGangUpdate',recheck)

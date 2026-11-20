local revision,generation=0,os.time()+GetGameTimer()/1000
local raw=LoadResourceFile(GetCurrentResourceName(),'settings.json')
if raw then
    local ok,value=pcall(json.decode,raw)
    if not ok or not RadioConfig.apply(value) then print('[mm_radio] Invalid settings.json; using shared defaults.') end
else
    SaveResourceFile(GetCurrentResourceName(),'settings.json',json.encode(RadioConfig.current()),-1)
end
local function packet() return {generation=generation,revision=revision,settings=RadioConfig.current()} end
function RadioConfig.isAdmin(src)
    if not src or src<=0 then return false end
    if IsPlayerAceAllowed(src,'mm_radio.admin') or IsPlayerAceAllowed(src,'pr_bridge.admin') then return true end
    if type(GetResourceState)=='function' and GetResourceState('forge-core')=='started' then
        local ok,allowed=pcall(function() return exports['forge-core']:CanManageServerSettings(src) end)
        if ok and allowed==true then return true end
    end
    return false
end
pr_lib.callback.register('mm_radio:getSettings',function() return packet() end)
pr_lib.callback.register('mm_radio:admin:get',function(src)
    if not RadioConfig.isAdmin(src) then return nil end
    return packet()
end)
-- Use the authoritative bridge catalog, not player assignments or a QBX export.
pr_lib.callback.register('mm_radio:admin:groups',function(src,kind)
    if not RadioConfig.isAdmin(src) or (kind~='job' and kind~='gang') then return nil end
    local getter=kind=='job' and pr_lib.framework.GetFrameworkJobs or pr_lib.framework.GetFrameworkGangs
    if type(getter)~='function' then return nil end
    local ok,groups=pcall(getter)
    if not ok or type(groups)~='table' then return nil end
    local options={}
    for name,group in pairs(groups) do
        if type(name)=='string' and name~='' and #name<=100 and type(group)=='table' then
            local label=type(group.label)=='string' and group.label or name
            options[#options+1]={value=name,label=label..' ('..name..')'}
        end
    end
    table.sort(options,function(a,b) return a.label==b.label and a.value<b.value or a.label<b.label end)
    return options
end)
pr_lib.callback.register('mm_radio:admin:save',function(src,value,expectedRevision)
    if not RadioConfig.isAdmin(src) then return {ok=false,error='forbidden'} end
    if expectedRevision~=revision then return {ok=false,error='conflict'} end
    local valid=RadioConfig.validate(value)
    if not valid then return {ok=false,error='invalid'} end
    if not SaveResourceFile(GetCurrentResourceName(),'settings.json',json.encode(valid),-1) then return {ok=false,error='save_failed'} end
    local old=RadioConfig.current()
    RadioConfig.apply(valid); revision=revision+1
    TriggerClientEvent('mm_radio:configSync',-1,packet())
    TriggerEvent('mm_radio:server:configChanged',old,RadioConfig.current())
    return {ok=true,packet=packet()}
end)
pr_lib.addCommand('radioadmin',{help=locale('admin.title'),params={}},function(src)
    if RadioConfig.isAdmin(src) then TriggerClientEvent('mm_radio:admin:open',src) end
end)

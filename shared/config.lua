VersionCheck = true

RadioConfig = {}
local keys = {'UseCommand','Debug','Overlay','MaxFrequency','Jammer','RadioItem','Battery','RadioNames','RestrictedChannels'}
function RadioConfig.copy(value)
    if type(value)~='table' then return value end
    local result={}; for key,item in pairs(value) do result[key]=RadioConfig.copy(item) end
    return result
end
function RadioConfig.current()
    local result={}; for _,key in ipairs(keys) do result[key]=RadioConfig.copy(Shared[key]) end
    return result
end
RadioConfig.defaults=RadioConfig.current()
-- Missing flags preserve the legacy job policy; gangs do not have a duty state.
function RadioConfig.requiresDuty(entry)
    return entry.type=='job' and entry.requireDuty~=false
end
local function finite(v,min,max) return type(v)=='number' and v==v and v>=min and v<=max end
local function stringList(value,limit)
    if type(value)~='table' or #value>limit then return nil end
    local result={}
    for i,item in ipairs(value) do
        if type(item)~='string' or #item==0 or #item>100 then return nil end
        result[i]=item
    end
    return result
end
function RadioConfig.validate(input)
    if type(input)~='table' then return nil end
    local result={}
    for _,key in ipairs(keys) do if input[key]==nil then return nil end; result[key]=RadioConfig.copy(input[key]) end
    if type(result.UseCommand)~='boolean' or type(result.Debug)~='boolean' then return nil end
    if result.Overlay~='default' and result.Overlay~='always' and result.Overlay~='never' then return nil end
    if not finite(result.MaxFrequency,1,10000) then return nil end
    if not stringList(result.RadioItem,30) or #result.RadioItem==0 then return nil end
    local b,j=result.Battery,result.Jammer
    if type(b)~='table' or type(b.state)~='boolean' or not finite(b.consume,1,100) or not finite(b.depletionTime,0.1,1440) then return nil end
    if type(j)~='table' or type(j.state)~='boolean' or type(j.model)~='string' or #j.model<1 or #j.model>100 or not stringList(j.permission,100) then return nil end
    local r=j.range
    if type(r)~='table' or not finite(r.min,1,1000) or not finite(r.max,r.min,1000) or not finite(r.default,r.min,r.max) or not finite(r.step,0.1,100) then return nil end
    if type(result.RadioNames)~='table' or type(result.RestrictedChannels)~='table' or type(j.default)~='table' or #j.default>100 then return nil end
    for key,value in pairs(result.RadioNames) do
        if type(key)~='string' or #key>32 or type(value)~='string' or #value>100 then return nil end
    end
    local restricted={}
    for frequency,entry in pairs(result.RestrictedChannels) do
        local channel=tonumber(frequency)
        if not channel or not finite(channel,1,result.MaxFrequency) or channel%1~=0 or type(entry)~='table' then return nil end
        if entry.type~='job' and entry.type~='gang' then return nil end
        if not stringList(entry.name,100) or #entry.name==0 then return nil end
        if entry.requireDuty~=nil and type(entry.requireDuty)~='boolean' then return nil end
        restricted[channel]={type=entry.type,name=RadioConfig.copy(entry.name),requireDuty=RadioConfig.requiresDuty(entry)}
    end
    result.RestrictedChannels=restricted
    for _,entry in ipairs(j.default) do
        if type(entry)~='table' or type(entry.coords)~='table' or not finite(entry.range,r.min,r.max) or type(entry.canDamage)~='boolean' then return nil end
        for _,axis in ipairs({'x','y','z','w'}) do if not finite(entry.coords[axis],-100000,100000) then return nil end end
        if not finite(entry.id,1,1000000) or type(entry.allowedChannels)~='table' or #entry.allowedChannels>100 then return nil end
        for _,channel in ipairs(entry.allowedChannels) do if not finite(channel,1,result.MaxFrequency) then return nil end end
    end
    return result
end
function RadioConfig.apply(value)
    local settings=RadioConfig.validate(value); if not settings then return false end
    for _,key in ipairs(keys) do Shared[key]=settings[key] end
    pr_lib.cache.set('mm_radio:settings',RadioConfig.copy(settings))
    return true
end
if not IsDuplicityVersion() then
    local generation,revision=nil,-1
    local function apply(packet)
        if type(packet)~='table' or type(packet.generation)~='number' or type(packet.revision)~='number' then return false end
        if generation and (packet.generation<generation or (packet.generation==generation and packet.revision<=revision)) then return true end
        if not RadioConfig.apply(packet.settings) then return false end
        generation,revision=packet.generation,packet.revision
        TriggerEvent('mm_radio:configChanged')
        return true
    end
    RegisterNetEvent('mm_radio:configSync',function(packet) if source==65535 then apply(packet) end end)
    CreateThread(function()
        while true do
            local ok,packet=pcall(pr_lib.callback.await,'mm_radio:getSettings',false)
            if ok and apply(packet) then break end
            Wait(2000)
        end
    end)
end

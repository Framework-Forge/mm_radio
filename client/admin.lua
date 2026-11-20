local draft,revision,parentMenu,parentResource
local function t(key,...) return locale('admin.'..key,...) end
local function notify(key) pr_lib.Notify({title=t('title'),description=t(key),type='error'}) end
local function split(value)
    local result={}; for token in tostring(value or ''):gmatch('[^,;]+') do
        local item=token:match('^%s*(.-)%s*$'); if item~='' then result[#result+1]=item end
    end
    return result
end
local function slider(label,value,min,max,step)
    return {type='slider',label=t(label),default=value,min=min,max=max,step=step or 1,required=true}
end
local function input(label,value)
    return {type='input',label=t(label),default=value,required=true}
end
local function check(label,value) return {type='checkbox',label=t(label),checked=value} end
local function menu(id,title,options,parent)
    pr_lib.registerContext({id='mm_radio:admin:'..id,title=t(title),menu=parent and 'mm_radio:admin:'..parent or parentMenu,
        menuResource=not parent and parentResource or nil,options=options})
    pr_lib.showContext('mm_radio:admin:'..id)
end
local root
local function save()
    local result=pr_lib.callback.await('mm_radio:admin:save',false,draft,revision)
    if not result or not result.ok then notify(result and result.error or 'save_failed'); return end
    revision=result.packet.revision; draft=RadioConfig.copy(result.packet.settings)
    pr_lib.Notify({title=t('title'),description=t('saved'),type='success'})
    root()
end
local function general()
    local values=pr_lib.inputDialog(t('general'),{
        check('commands',draft.UseCommand),check('debug',draft.Debug),
        {type='select',label=t('overlay'),default=draft.Overlay,required=true,options={
            {value='default',label=t('overlay_default')},{value='always',label=t('overlay_always')},{value='never',label=t('overlay_never')}
        }},slider('max_frequency',draft.MaxFrequency,1,10000,0.01),input('radio_items',table.concat(draft.RadioItem,', ')),
    })
    if values then
        draft.UseCommand,draft.Debug,draft.Overlay,draft.MaxFrequency=values[1],values[2],values[3],values[4]
        draft.RadioItem=split(values[5])
    end
    root()
end
local function battery()
    local b=draft.Battery
    local values=pr_lib.inputDialog(t('battery'),{check('enabled',b.state),slider('consume',b.consume,1,100),slider('depletion',b.depletionTime,0.1,1440,0.1)})
    if values then b.state,b.consume,b.depletionTime=values[1],values[2],values[3] end
    root()
end
local restricted
local function restriction(channel)
    local entry=draft.RestrictedChannels[channel] or {type='job',name={}}
    local values=pr_lib.inputDialog(t('restricted'),{
        slider('channel',channel or 1,1,math.floor(draft.MaxFrequency)),
        {type='select',label=t('group_type'),default=entry.type,required=true,options={{value='job',label=t('jobs')},{value='gang',label=t('gangs')}}},
    })
    if values then
        local kind=values[2]
        local ok,options=pcall(pr_lib.callback.await,'mm_radio:admin:groups',false,kind)
        if not ok or type(options)~='table' or #options==0 then notify('catalog_unavailable'); restricted(); return end
        local known,selected={},{}
        for _,option in ipairs(options) do known[option.value]=true end
        if kind==entry.type then
            for _,name in ipairs(entry.name) do if known[name] then selected[#selected+1]=name end end
        end
        local fields={{type='multi-select',label=t('groups'),default=selected,options=options,
            tags=true,searchable=true,searchPlaceholder=t(kind=='job' and 'search_jobs' or 'search_gangs'),
            required=true,minSelectedValues=1,maxSelectedValues=100}}
        if kind=='job' then fields[#fields+1]=check('require_duty',kind~=entry.type or RadioConfig.requiresDuty(entry)) end
        local groups=pr_lib.inputDialog(t('restricted'),fields)
        if groups then
            if type(groups[1])~='table' or #groups[1]==0 then notify('invalid'); restricted(); return end
            for _,name in ipairs(groups[1]) do
                if not known[name] then notify('invalid'); restricted(); return end
            end
            if channel then draft.RestrictedChannels[channel]=nil end
            draft.RestrictedChannels[values[1]]={type=kind,name=RadioConfig.copy(groups[1]),requireDuty=kind=='job' and groups[2]==true}
        end
    end
    restricted()
end
restricted=function()
    local options={{title=t('add'),icon='plus',onSelect=function() restriction() end}}
    local channels={}; for channel in pairs(draft.RestrictedChannels) do channels[#channels+1]=channel end; table.sort(channels)
    for _,channel in ipairs(channels) do
        local entry=draft.RestrictedChannels[channel]
        local description=t(entry.type=='job' and 'jobs' or 'gangs')..': '..table.concat(entry.name,', ')
        if entry.type=='job' then description=description..' — '..t(RadioConfig.requiresDuty(entry) and 'duty_required' or 'duty_optional') end
        options[#options+1]={title=t('channel')..' '..channel,description=description,onSelect=function()
            menu('restriction','restricted',{
                {title=t('edit'),onSelect=function() restriction(channel) end},
                {title=t('remove'),onSelect=function() draft.RestrictedChannels[channel]=nil; restricted() end},
            },'restricted')
        end}
    end
    menu('restricted','restricted',options,'root')
end
local names
local function editName(key)
    local values=pr_lib.inputDialog(t('names'),{input('pattern',key or ''),input('name',key and draft.RadioNames[key] or '')})
    if values then if key then draft.RadioNames[key]=nil end; draft.RadioNames[values[1]]=values[2] end
    names()
end
names=function()
    local options={{title=t('add'),onSelect=function() editName() end}}
    local keys={}; for key in pairs(draft.RadioNames) do keys[#keys+1]=key end; table.sort(keys)
    for _,key in ipairs(keys) do
        options[#options+1]={title=key..' — '..draft.RadioNames[key],onSelect=function()
            menu('name','names',{{title=t('edit'),onSelect=function() editName(key) end},{title=t('remove'),onSelect=function() draft.RadioNames[key]=nil; names() end}},'names')
        end}
    end
    menu('names','names',options,'root')
end
local defaults
local function location(index)
    local entry=index and draft.Jammer.default[index]
    local coords=entry and entry.coords
    local values=pr_lib.inputDialog(t('locations'),{
        check('current_position',not entry),slider('range',entry and entry.range or draft.Jammer.range.default,draft.Jammer.range.min,draft.Jammer.range.max,draft.Jammer.range.step),
        check('damage',entry and entry.canDamage or false),{type='input',label=t('allowed_channels'),default=entry and table.concat(entry.allowedChannels,', ') or ''},
    })
    if values then
        if values[1] or not coords then
            local ped=pr_lib.cache.ped; local point=GetEntityCoords(ped)
            coords={x=point.x,y=point.y,z=point.z-1,w=GetEntityHeading(ped)}
        end
        local allowed={}; for _,item in ipairs(split(values[4])) do local channel=tonumber(item); if channel then allowed[#allowed+1]=channel end end
        local id=entry and entry.id or 1
        if not entry then for _,item in ipairs(draft.Jammer.default) do id=math.max(id,item.id+1) end end
        draft.Jammer.default[index or (#draft.Jammer.default+1)]={id=id,coords=coords,range=values[2],canDamage=values[3],allowedChannels=allowed}
    end
    defaults()
end
defaults=function()
    local options={{title=t('add_here'),onSelect=function() location() end}}
    for index,entry in ipairs(draft.Jammer.default) do
        options[#options+1]={title=t('location')..' '..entry.id,description=('%.2f, %.2f, %.2f | %.1f m'):format(entry.coords.x,entry.coords.y,entry.coords.z,entry.range),onSelect=function()
            menu('location','locations',{{title=t('edit'),onSelect=function() location(index) end},{title=t('remove'),onSelect=function() table.remove(draft.Jammer.default,index); defaults() end}},'locations')
        end}
    end
    menu('locations','locations',options,'jammer')
end
local function jammer()
    local j=draft.Jammer
    local assets=pr_lib.fivem.blips
    local image=assets.getPropImageUrl(j.model)
    menu('jammer','jammer',{
        {title=t('jammer_options'),description=j.model,image=image,metadata={{label=t('model'),value=j.model}},onSelect=function()
            local values=pr_lib.inputDialog(t('jammer_options'),{
                check('enabled',j.state),input('model',j.model),{type='input',label=t('permissions'),default=table.concat(j.permission,', ')},
                slider('min_range',j.range.min,1,1000,0.1),slider('max_range',j.range.max,1,1000,0.1),
                slider('default_range',j.range.default,1,1000,0.1),slider('step',j.range.step,0.1,100,0.1),
            })
            if values then
                if not IsModelInCdimage(joaat(values[2])) or not IsModelValid(joaat(values[2])) then notify('invalid_model'); jammer(); return end
                j.state,j.model,j.permission=values[1],values[2],split(values[3])
                j.range={min=values[4],max=values[5],default=values[6],step=values[7]}
            end
            jammer()
        end},
        {title=t('locations'),icon='location-dot',onSelect=defaults},
    },'root')
end
root=function()
    menu('root','title',{
        {title=t('general'),icon='gear',onSelect=general},
        {title=t('battery'),icon='battery-half',onSelect=battery},
        {title=t('restricted'),icon='lock',onSelect=restricted},
        {title=t('names'),icon='list',onSelect=names},
        {title=t('jammer'),icon='tower-broadcast',onSelect=jammer},
        {title=t('save'),description=t('save_description'),icon='floppy-disk',onSelect=save},
    })
end
local function openAdmin(parent,resource)
    local packet=pr_lib.callback.await('mm_radio:admin:get',false)
    if not packet then notify('forbidden'); return false end
    parentMenu=type(parent)=='string' and parent or nil
    parentResource=parentMenu and (type(resource)=='string' and resource or GetInvokingResource()) or nil
    draft,revision=RadioConfig.copy(packet.settings),packet.revision
    root()
    return true
end
RegisterNetEvent('mm_radio:admin:open',function() openAdmin() end)
exports('OpenAdminMenu',openAdmin)

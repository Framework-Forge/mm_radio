local insideJammer = false

function IsJammerAllowed(id, channel)
    for i=1, #Radio.jammer do
        local entity = Radio.jammer[i]
        if entity.id == id then
            return pr_lib.table.contains(entity.allowedChannels, channel)
        end
    end
end

function Radio:Notify(msg, duration)
    self:SendSvelteMessage("notify", {msg = msg, duration = duration or 5000})
end

function Radio:connectSound()
    PlaySoundFrontend(-1, 'Retune_High', 'MP_RADIO_SFX', true)
end

function Radio:closeEvent()
    PlaySoundFrontend(-1, 'Off_High', 'MP_RADIO_SFX', true)
end

function Radio:SplitStr(inputstr, sep)
    if sep == nil then
        sep = "%s"
    end
    local t = {}
    for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
        t[#t+1] = str
    end
    return t
end

function Radio:getCrossroads()
    local player = pr_lib.cache.ped
    local pos = GetEntityCoords(player)
    local street1, street2 = GetStreetNameAtCoord(pos.x, pos.y, pos.z)
    if street2 == 0 then
        return GetStreetNameFromHashKey(street1)
    else
        return GetStreetNameFromHashKey(street2)
    end
end

function Radio:SetDefaultData(cid)
    self.userData[cid] = {
        favourite = {},
        name = nil,
        overlaySizeMultiplier = 50,
        radioSizeMultiplier = 50,
        allowMovement = false,
        enableClicks = true,
        playerlist = {
            show = false,
            coords = {
                x = 15.0,
                y = 40.0
            }
        },
        radio = {
            coords = {
                x = 10,
                y = 15,
            },
        }
    }
    SetResourceKvp('radioSettings2', json.encode(self.userData))
end

function Radio:Init(data)
    -- QBX's playerdata module is the existing complete character cache; the
    -- bridge GetPlayer() currently returns a reduced display-name record.
    local player = data or QBX.PlayerData or {}
    self.identifier = player.citizenid or player.cid
    if not self.identifier or not player.job or not player.gang or not player.charinfo then return false end
    pr_lib.cache.set('mm_radio:character', self.identifier)
    self.PlayerJob = player.job.name
    self.PlayerDuty = player.job.onduty
    self.PlayerGang = player.gang.name
    if not self.userData[self.identifier] then self:SetDefaultData(self.identifier) end
    self.userData[self.identifier].name = self.userData[self.identifier].name or player.charinfo.firstname .. " " .. player.charinfo.lastname
    local rec = {}
    for k, v in pairs(Shared.RestrictedChannels) do
        if v.type == 'job' and pr_lib.table.contains(v.name, self.PlayerJob) then
            rec[#rec+1] = k
        elseif v.type == 'gang' and pr_lib.table.contains(v.name, self.PlayerGang) then
            rec[#rec+1] = k
        end
    end
    self.favourite = rec
    for _, val in ipairs(self.userData[self.identifier].favourite) do
        if not pr_lib.table.contains(self.favourite, val) then
            self.favourite[#self.favourite+1] = val
        end
    end

    local preferences=self.userData[self.identifier]
    if preferences.enableClicks==nil then
        preferences.enableClicks=true
        SetResourceKvp('radioSettings2',json.encode(self.userData))
    end
    -- Always apply the current character's preference, including re-enabling it.
    exports['pma-voice']:setVoiceProperty('micClicks', preferences.enableClicks==true)

    self:doRadioCheck()
end

function Radio:connecttoradio(channel)
    if self.RadioChannel ~= 0 then
        TriggerServerEvent('mm_radio:server:removeFromRadioChannel', self.RadioChannel)
    end
    self.RadioChannel = channel
    if not Radio.onRadio then
        Radio.onRadio = true
        exports["pma-voice"]:setVoiceProperty("radioEnabled", true)
    end
    exports["pma-voice"]:setRadioChannel(channel)
    TriggerServerEvent('mm_radio:server:addToRadioChannel', self.RadioChannel, self.userData[self.identifier].name)
    self:connectSound()
    self:Notify(locale('join_notify_description', channel))
    if not pr_lib.table.contains(Radio.recomended, channel) then
        Radio.recomended[#Radio.recomended+1] = channel
    end
    if self.insideJammer then
        Radio.signalJammed = false
        Radio:SendSvelteMessage("insideJammer", false)
    end
end

function Radio:doRadioCheck(_)
    self.batteryData = {}
    self.hasRadio = false
    -- Search one item at a time: multi-item searches return a nested dictionary.
    for _, name in ipairs(Shared.RadioItem) do
        local playerItems = pr_lib.inventory.Search('slots', name) or {}
        for _, item in pairs(playerItems) do
            if item.name == name then
                self.hasRadio = true
                local id = (item.metadata or item.info or {}).radioId
                if id then self.batteryData[#self.batteryData+1] = id end
            end
        end
    end
    if not self.hasRadio and self.onRadio then
        Radio:leaveradio()
    end
end

function Radio:leaveradio()
    self:closeEvent()
    TriggerServerEvent('mm_radio:server:removeFromRadioChannel', self.RadioChannel)
    self.RadioChannel = 0
    self.onRadio = false
    exports["pma-voice"]:setRadioChannel(0)
    exports["pma-voice"]:setVoiceProperty("radioEnabled", false)
    self:update()
end

function Radio:update()
    local battery, radioId = pr_lib.callback.await('mm_radio:server:getradiodata', false)
    self:SendSvelteMessage("updateRadio", {
        radioId = radioId,
        onRadio = Radio.onRadio,
        channel = Radio.RadioChannel,
        volume = Radio.Volume,
        favourite = Radio.favourite,
        recomended = Radio.recomended,
        userData = Radio.userData[self.identifier],
        time = self:CalculateTimeToDisplay(),
        street = self:getCrossroads(),
        locale = self.locale,
        channelName = Shared.RadioNames,
        insideJammerZone = self.signalJammed,
        battery = battery,
        overlay = Shared.Overlay
    })
end

function Radio:toggleRadioAnimation(pState)
    pr_lib.requestAnimDict('cellphone@')
	if pState then
		TriggerEvent("attachItemRadio", "radio01")
		TaskPlayAnim(pr_lib.cache.ped, "cellphone@", "cellphone_text_read_base", 2.0, 3.0, -1, 49, 0, false, false, false)
		self.radioProp = CreateObject(joaat('prop_cs_hand_radio'), 1.0, 1.0, 1.0, true, true, false)
		AttachEntityToEntity(self.radioProp, pr_lib.cache.ped, GetPedBoneIndex(pr_lib.cache.ped, 57005), 0.14, 0.01, -0.02, 110.0, 120.0, -15.0, true, false, false, false, 2, true)
	else
		StopAnimTask(pr_lib.cache.ped, "cellphone@", "cellphone_text_read_base", 1.0)
		ClearPedTasks(pr_lib.cache.ped)
		if self.radioProp ~= 0 then
			DeleteObject(self.radioProp)
			self.radioProp = 0
		end
	end
end

function Radio:CalculateTimeToDisplay()
	local hour = GetClockHours()
    local minute = GetClockMinutes()
    local second = GetClockSeconds()

    local obj = ""

	if minute <= 9 then
		minute = "0" .. minute
    end

    obj = hour..":"..minute

    return obj, (60 - second)
end

function Radio:RemoveJammerZone()
    for i=1, #self.jammer do
        self.jammer[i].zone:remove()
        self.jammer[i].zoneJammer:remove()
    end
end

function Radio:OpenJammerConfig(id)
    for i=1, #Radio.jammer do
        if Radio.jammer[i].id == id then
            local isDamaged = GetEntityHealth(Radio.jammer[i].entity) <= 0
            pr_lib.registerContext({
                id = 'jammer_menu',
                title = locale('jammer.title'),
                onExit = function ()
                    if insideJammer then pr_lib.showTextUI(locale('jammer.prompt')) end
                end,
                options = {
                    {
                        title = locale('jammer.toggle'),
                        description = locale('jammer.toggle_description', Radio.jammer[i].enable and locale('jammer.enabled') or locale('jammer.disabled')),
                        disabled = isDamaged,
                        icon = 'fa-toggle-on',
                        onSelect = function ()
                            TriggerServerEvent('mm_radio:server:togglejammer', Radio.jammer[i].id)
                            pr_lib.showTextUI(locale('jammer.prompt'))
                        end
                    },
                    {
                        title = locale('jammer.remove'),
                        description = locale('jammer.remove_description'),
                        icon = 'fa-trash',
                        disabled = not Radio.jammer[i].canRemove,
                        onSelect = function ()
                            TriggerServerEvent('mm_radio:server:removejammer', Radio.jammer[i].id, isDamaged)
                        end
                    },
                    {
                        title = locale('jammer.range'),
                        description = locale('jammer.range_description'),
                        icon = 'fa-ruler',
                        disabled = isDamaged,
                        onSelect = function ()
                            local input = pr_lib.inputDialog(locale('jammer.title'), {
                                {
                                    type = 'slider',
                                    label = locale('jammer.range'),
                                    description = locale('jammer.range_description'),
                                    icon = 'fa-ruler',
                                    min = Shared.Jammer.range.min,
                                    max = Shared.Jammer.range.max,
                                    step = Shared.Jammer.range.step,
                                    default = Radio.jammer[i].range,
                                },
                            })
                            if not input then return end
                            TriggerServerEvent('mm_radio:server:changeJammerRange', Radio.jammer[i].id, input[1])
                            pr_lib.showTextUI(locale('jammer.prompt'))
                        end
                    },
                    {
                        title = locale('jammer.allowed'),
                        description = locale('jammer.allowed_description'),
                        icon = 'fa-circle-check',
                        disabled = isDamaged,
                        onSelect = function ()
                            local allowedChannels = {
                                id = 'jammer_allowed_channel',
                                title = locale('jammer.allowed'),
                                menu = 'jammer_menu',
                                options = {}
                            }
                            for j=1, #Radio.jammer[i].allowedChannels do
                                allowedChannels.options[#allowedChannels.options+1] = {
                                    title = locale('jammer.channel', Radio.jammer[i].allowedChannels[j]),
                                    description = locale('jammer.remove_channel'),
                                    icon = 'fa-trash',
                                    onSelect = function ()
                                        table.remove(Radio.jammer[i].allowedChannels, j)
                                        TriggerServerEvent('mm_radio:server:removeallowedchannel', Radio.jammer[i].id, Radio.jammer[i].allowedChannels)
                                        pr_lib.showTextUI(locale('jammer.prompt'))
                                    end
                                }
                            end
                            allowedChannels.options[#allowedChannels.options+1] = {
                                title = locale('jammer.add_channel'),
                                description = locale('jammer.add_channel_description'),
                                icon = 'fa-circle-plus',
                                onSelect = function ()
                                    local input = pr_lib.inputDialog(locale('jammer.add_channel'), {
                                        {type = 'slider', label = locale('jammer.frequency'), description = locale('jammer.frequency_description'), icon = 'fa-wifi', min = 1, max = Shared.MaxFrequency, step = 0.01, default = 1},
                                    })
                                    if not input then return end
                                    table.insert(Radio.jammer[i].allowedChannels, input[1])
                                    TriggerServerEvent('mm_radio:server:addallowedchannel', Radio.jammer[i].id, Radio.jammer[i].allowedChannels)
                                    pr_lib.showTextUI(locale('jammer.prompt'))
                                end
                            }
                            pr_lib.registerContext(allowedChannels)
                            pr_lib.showContext('jammer_allowed_channel')
                        end
                    }
                }
            })
            pr_lib.showContext('jammer_menu')
            break
        end
    end
end

function Radio:UpdateJammerZone(id, allowedChannels)
    if not self.insideJammer then return end
    local containChannel = pr_lib.table.contains(allowedChannels, self.RadioChannel)
    self.insideJammerZone = id
    if not containChannel then
        self.signalJammed = true
        self:SendSvelteMessage("insideJammer", true)
        exports["pma-voice"]:setRadioChannel(0)
    else
        self.signalJammed = false
        self:SendSvelteMessage("insideJammer", false)
        exports["pma-voice"]:setRadioChannel(self.RadioChannel)
    end
end

function Radio:UpdateJammerRemove(id)
    if self.insideJammerZone == id then
        self.insideJammer = false
        if IsJammerAllowed(id, self.RadioChannel) then return end
        self.insideJammerZone = 0
        self.signalJammed = false
        self:SendSvelteMessage("insideJammer", false)
        exports["pma-voice"]:setRadioChannel(self.RadioChannel)
    end
end

function UpdateTime()
    CreateThread(function()
        while Radio.usingRadio do
            local currentTime, nextUpdate = Radio:CalculateTimeToDisplay()
            Radio:SendSvelteMessage("UpdateTime", currentTime)
            Wait(nextUpdate*1000)
        end
    end)
end

function DisableControls()
    CreateThread(function()
        while Radio.usingRadio and Radio.userData[Radio.identifier].allowMovement do
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 106, true)
            DisableControlAction(0, 199, true)
            DisableControlAction(0, 200, true)
            DisablePlayerFiring(pr_lib.cache.playerId, true)
            Wait(5)
        end
    end)
end

function OnInsideJammerZone(data)
    CreateThread(function()
        while Radio.insideJammer and Radio.insideJammerZone == data.jammerid do
            local isDamaged = GetEntityHealth(data.entity) <= 0
            if isDamaged then
                for i=1, #Radio.jammer do
                    local entity = Radio.jammer[i]
                    if entity.id == data.jammerid then
                        Radio:UpdateJammerRemove(data.jammerid)
                        entity.zone:remove()
                    end
                end
            end
            Wait(5000)
        end
    end)
end

function OnEnterJammerZone(self)
    local record
    for _, entry in ipairs(Radio.jammer) do if entry.id==self.jammerid then record=entry; break end end
    if not Shared.Jammer.state or not record or not record.enable then return end
    -- Network objects may not have streamed in when a far-away zone was created.
    local entity=NetworkGetEntityFromNetworkId(record.object)
    if entity==0 then return end
    self.entity,record.entity=entity,entity
    SetEntityCanBeDamaged(entity,record.canDamage)
    if GetEntityHealth(self.entity) <= 0 then return end
    Radio.insideJammer = true
    Radio.insideJammerZone = self.jammerid
    OnInsideJammerZone(self)
    if IsJammerAllowed(self.jammerid, Radio.RadioChannel) then return end
    Radio.signalJammed = true
    Radio:SendSvelteMessage("insideJammer", true)
    exports["pma-voice"]:setRadioChannel(0)
end

function OnExitJammerZone(self)
    Radio.insideJammer = false
    Radio.insideJammerZone = 0
    if IsJammerAllowed(self.jammerid, Radio.RadioChannel) then return end
    Radio.signalJammed = false
    Radio:SendSvelteMessage("insideJammer", false)
    exports["pma-voice"]:setRadioChannel(Radio.RadioChannel)
end

function OnEnterJammer(self)
    if not Shared.Jammer.permission or not (pr_lib.table.contains(Shared.Jammer.permission, Radio.PlayerJob) or pr_lib.table.contains(Shared.Jammer.permission, Radio.PlayerGang)) then
        return
    end
    pr_lib.showTextUI(locale('jammer.prompt'))
    insideJammer = true
    CreateThread(function()
        while insideJammer do
            if IsControlJustPressed(0, 38) then
                Radio:OpenJammerConfig(self.jammerid)
                pr_lib.hideTextUI()
            end
            Wait(5)
        end
    end)
end

function OnExitJammer()
    pr_lib.hideTextUI()
    insideJammer = false
end

function JoinRadio(channel)
    if not Radio.playerLoaded or Radio.PlayerDead or not Radio.hasRadio then return end
    if type(channel) ~= 'number' or channel ~= channel then return end
    if Radio.insideJammer and not IsJammerAllowed(Radio.insideJammerZone, channel) then
        return Radio:Notify(locale('jammer_notify_description', channel), 10000)
    end
    if not channel or channel > Shared.MaxFrequency or channel < 1 then
        return Radio:Notify(locale('invalid_notify_description', channel))
    end
    if channel == Radio.RadioChannel then
        return Radio:Notify(locale('already_notify_description', channel), 10000)
    end
    local connectChannel = math.floor(channel)
    if Shared.RestrictedChannels[connectChannel] then
        local type = Shared.RestrictedChannels[connectChannel].type
        local name = Shared.RestrictedChannels[connectChannel].name
        if type == 'job' and pr_lib.table.contains(name, Radio.PlayerJob)
            and (not RadioConfig.requiresDuty(Shared.RestrictedChannels[connectChannel]) or Radio.PlayerDuty) then
            Radio:connecttoradio(channel)
            Radio:update()
        elseif type == 'gang' and pr_lib.table.contains(name, Radio.PlayerGang) then
            Radio:connecttoradio(channel)
            Radio:update()
        else
            Radio:Notify(locale('restricted_notify_description', channel), 10000)
        end
    else
        Radio:connecttoradio(channel)
        Radio:update()
    end
end

exports('JoinRadio', JoinRadio)

local function LeaveRadio()
    Radio:leaveradio()
end

exports('LeaveRadio', LeaveRadio)

pr_lib.addKeybind({
    name = 'radio',
    description = locale('keybind.open'),
    defaultKey = 'EQUALS',
    onPressed = function()
        if not Radio.usingRadio then
            if Radio.hasRadio then
                TriggerEvent('mm_radio:client:use')
            end
        end
    end
})

pr_lib.addKeybind({
    name = '+channel',
    description = locale('keybind.next'),
    defaultKey = 'PERIOD',
    onPressed = function()
        if not Radio.onRadio then return end
        local currentChannel = Radio.RadioChannel
        JoinRadio(currentChannel + 1)
    end
})

pr_lib.addKeybind({
    name = '-channel',
    description = locale('keybind.previous'),
    defaultKey = 'COMMA',
    onPressed = function()
        if not Radio.onRadio then return end
        local currentChannel = Radio.RadioChannel
        JoinRadio(currentChannel - 1)
    end
})

-- Battery timing and inventory ownership are managed by the server.

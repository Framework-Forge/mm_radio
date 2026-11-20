Radio = {
	identifier = nil,
	playerServerID = GetPlayerServerId(PlayerId()),
	PlayerJob = 'civilian',
	PlayerGang = 'none',
	PlayerDuty = false,
	hasRadio = false,
	onRadio = false,
	usingRadio = false,
	RadioChannel = 0,
	radioProp = 0,
	Volume = 30,
	favourite = {},
	recomended = {},
	street = "Unknown",
	talkingList = {},
	locale = locale:getAll(),
	jammer = {},
	batteryData = {},
	insideJammerZone = 0,
	insideJammer = false,
	signalJammed = false,
	allowedChannelInsideJammer = {},
	userData = json.decode(GetResourceKvpString('radioSettings2')) or {}
}

setmetatable(Radio, {
    __index = function(_, key)
        if key == 'playerLoaded' then return pr_lib.framework.IsPlayerLoaded() end
        if key == 'PlayerDead' then return pr_lib.cache.get('mm_radio:dead', false) end
    end,
    __newindex = function(self, key, value)
        if key == 'playerLoaded' then pr_lib.cache.set('mm_radio:loaded', value)
        elseif key == 'PlayerDead' then pr_lib.cache.set('mm_radio:dead', value)
        else rawset(self,key,value) end
    end,
})

RegisterNetEvent('mm_radio:client:removedata', function()
	DeleteResourceKvp('radioSettings2')
	Radio.userData = {}
	SetResourceKvp('radioSettings2', json.encode(Radio.userData))
	if pr_lib.framework.IsPlayerLoaded() then
		Radio:Init()
	end
end)

if not Shared.Ready then
	return error('Cannot Start Resource, MISSING DEPENDENCIES', 0)
end

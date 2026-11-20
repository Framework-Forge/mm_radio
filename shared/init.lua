Shared = {}

---@class Shared
---@field Ready boolean
---@field UseCommand boolean
---@field Debug boolean
---@field Overlay 'default'|'always'|'never'

---@type Shared
Shared = {
    Ready = true,
    UseCommand = true,
    Debug = false,
    Overlay = 'default' -- default, always, never
}

if not LoadResourceFile(GetCurrentResourceName(), 'build/index.html') then
    Shared.Ready = false
    warn('UI has not been built, refer to the readme or download a release build.\n	^3https://github.com/Qbox-project/mm_radio/releases/')
end


locale = pr_lib.locale()
-- Keep existing languages, falling back to English only for newly added keys.
local english=json.decode(LoadResourceFile(GetCurrentResourceName(),'locales/en.json'))
local function flatten(value,prefix,result)
    for key,item in pairs(value) do
        local name=prefix and (prefix..'.'..key) or key
        if type(item)=='table' then flatten(item,name,result) else result[name]=item end
    end
end
local fallback={}; flatten(english,nil,fallback)
local missing={}; for key,value in pairs(fallback) do if not locale:has(key) then missing[key]=value end end
locale:extend(missing)

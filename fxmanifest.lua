fx_version 'cerulean'
game 'gta5'

author 'Master Mind'
version '0.2.3'
description 'A beautiful Radio Resource for FiveM'
repository 'https://github.com/SOH69/mm_radio'

lua54 'yes'

ui_page 'build/index.html'
-- ui_page 'http://localhost:3000/' --for dev

shared_script {
    '@pr_bridge/init.lua',
    'shared/init.lua',
    'shared/shared.lua',
    'shared/config.lua'
}

client_script {
    '@pr_bridge/bridge/compat/qbx/entries/playerdata.lua',
    'client/interface.lua',
    'client/function.lua',
    'client/event.lua',
    'client/nui.lua',
    'client/admin.lua'
}

server_script {
    'server/config.lua',
    'server/main.lua',
    'server/policy.lua',
}

files {
    'build/**',
    'locales/*.json'
}

dependencies {
    'pma-voice',
    'pr_bridge',
    '/onesync'
}

server_script 'server/version.lua'

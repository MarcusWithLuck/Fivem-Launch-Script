fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'esx_launchcontrol'
description 'Launch control (2-step), burnout mode and rolling anti-lag for ESX'
version '1.0.0'

shared_script 'config.lua'
client_script 'client.lua'
server_script 'server.lua'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/sounds/*.wav',
}

dependency 'es_extended'

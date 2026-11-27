fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

description 'w_medic - the doctors and the hospital'
version '1.0.11'
lua54 'yes'

shared_scripts {
	'@w_lib/init.lua',
	'config.lua'
}

client_scripts {
	'client/main.lua',
	'client/wounding.lua',
	'client/laststand.lua',
	'client/job.lua',
	'client/jobs_center.lua',  -- the jobs centre at gw-medic's desk (hire / rank / dismiss)
	'client/dead.lua'
}

server_scripts {
	'@oxmysql/lib/MySQL.lua',
	'server/main.lua'
}

files {
	'locales/*.json'
}

-- The library loads locales/<key>.json (ar/en) at start on both sides
w_lib {
	'locale'
}

-- w_lib provides the dictionary. w_core too: its core object is fetched at load
-- (w.framework:getCoreObject()). When w_store is running and Config.Pharmacy.useStore is true,
-- the cabinet can use a w_store shelf; otherwise it uses w_inventory's built-in shop.
dependencies { 'w_lib' }

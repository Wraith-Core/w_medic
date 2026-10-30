fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

description 'w_medic - the doctors and the hospital'
version '1.0.5'
lua54 'yes'

shared_scripts {
	'@w_lib/init.lua',
	'config.lua'
}

client_scripts {
	'c/wcore_shim.lua',        -- the Wraith Core client API on VORP / RSG / QBR (through w_lib): before the job's files
	'client/main.lua',
	'client/wounding.lua',
	'client/laststand.lua',
	'client/job.lua',
	'client/jobs_center.lua',  -- the jobs centre at gw-medic's desk (hire / rank / dismiss)
	'client/dead.lua'
}

server_scripts {
	'@oxmysql/lib/MySQL.lua',
	'server/wcore_shim.lua',   -- the Wraith Core server API on VORP / RSG / QBR (through w_lib): before main.lua
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
-- (w.framework:getCoreObject()). w_store is the pharmacy shelf: the cabinet is a real
-- government store row when it is running (see Config.Pharmacy.useStore and server/main.lua).
dependencies { 'w_lib', 'w_store' }

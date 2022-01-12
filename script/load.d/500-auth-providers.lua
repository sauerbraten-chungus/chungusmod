--[[
    Allow players to authenticate with authkeys hosted on additional masterservers (auth providers), 
    and give them the specified privilege upon successful auth completion.

    auth.domains["authkey_domain"] = auth.create_provider("provider_host", provider_port, privilege)

    Auth-on-connect: table.insert(auth.preauths, "authkey_domain")
]]

local auth = require"std.auth"

-- p1x.pw
auth.domains["p1x.pw"] = auth.create_provider("p1x.pw", 28787, server.PRIV_NONE)

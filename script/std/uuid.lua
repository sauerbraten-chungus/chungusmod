--[[

  Generate an unique identifier for each connection.

]]--

local uuid, fp, L = require"uuid", require"utils.fp", require"utils.lambda"
local fold, last = fp.fold, fp.last

-- Define a random bytes generator using /dev/urandom
local function random_bytes(n)
    local urandom, err = io.open("/dev/urandom", "rb")
    if not urandom then
        -- Fallback to math.random if /dev/urandom is unavailable
        math.randomseed(os.time())
        local bytes = {}
        for i = 1, n do
            bytes[i] = string.char(math.random(0, 255))
        end
        return table.concat(bytes)
    end
    local bytes = urandom:read(n)
    urandom:close()
    if not bytes or #bytes ~= n then
        error("Failed to read enough random bytes from /dev/urandom")
    end
    return bytes
end

-- Set the RNG function for the uuid module
uuid.set_rng(random_bytes)

local function adduuid(info)
    info.ci.extra.uuid = uuid()
    print("Assigned UUID to client = ".. info.ci.clientnum .. ": " .. info.ci.extra.uuid)
 end
spaghetti.addhook("clientconnect", adduuid, true)
spaghetti.addhook("botjoin", adduuid, true)

return { find = function(ciuuid)
    local l1, l2 = server.clients, server.connects
    for i = 0, l1:length() - 1 do if l1[i].extra.uuid == ciuuid then return l1[i] end end
    for i = 0, l2:length() - 1 do if l2[i].extra.uuid == ciuuid then return l2[i] end end
end }

local H=game:GetService("HttpService")
local T=game:GetService("TeleportService")
local P=game:GetService("Players").LocalPlayer

local PID=tostring(game.PlaceId)
local JID=game.JobId

local SERVERS_URL="https://raw.githubusercontent.com/Shuzinho/farm-system/main/servers.json"
local USED_FILE="used_servers.json"
local STATE_FILE="hop_state.json"
local PROTECT=180

local function fexists(n)
    local ok=pcall(function() return readfile(n) end)
    return ok
end

local function jload(n)
    if not readfile or not writefile then return {} end
    if not fexists(n) then
        writefile(n,"{}")
        return {}
    end
    local ok,d=pcall(function() return H:JSONDecode(readfile(n)) end)
    return ok and type(d)=="table" and d or {}
end

local function jsave(n,d)
    if writefile then
        writefile(n,H:JSONEncode(d))
    end
end

local function loadServers()
    local ok,r=pcall(function() return game:HttpGet(SERVERS_URL) end)
    if not ok then return nil end
    local ok2,d=pcall(function() return H:JSONDecode(r) end)
    if not ok2 then return nil end
    return d
end

local function justHoppedHere()
    local s=jload(STATE_FILE)
    if not s.last_target_jobid then return false end
    if s.last_target_jobid~=JID then return false end
    if not s.last_hop_time then return false end
    return (os.time()-s.last_hop_time)<=PROTECT
end

local function isUsed(id, used)
    for _,x in ipairs(used) do
        if x==id then return true end
    end
    return false
end

local function getServer()
    local all=loadServers()
    if not all or not all[PID] then return nil end

    local list=all[PID]
    local usedData=jload(USED_FILE)
    local used=usedData[PID] or {}

    if #list==0 then return nil end

    local start=(P.UserId % #list)+1

    for i=0,#list-1 do
        local idx=((start+i-1)%#list)+1
        local id=list[idx].jobId
        if id~=JID and not isUsed(id, used) then
            return id
        end
    end

    return nil
end

local function markUsed(id)
    local used=jload(USED_FILE)
    used[PID]=used[PID] or {}
    table.insert(used[PID],id)
    jsave(USED_FILE,used)
end

local function markTarget(id)
    jsave(STATE_FILE,{
        last_target_jobid=id,
        last_hop_time=os.time()
    })
end

if justHoppedHere() then
    return
end

local id=getServer()
if not id then
    return
end

markTarget(id)
markUsed(id)
T:TeleportToPlaceInstance(tonumber(PID),id,P)

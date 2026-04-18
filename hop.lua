local H=game:GetService("HttpService")
local T=game:GetService("TeleportService")
local P=game:GetService("Players").LocalPlayer
local Players=game:GetService("Players")

local PID=tostring(game.PlaceId)
local JID=game.JobId

local BLUE_LOCK_ID="18668065416"

local SERVERS_URL="https://raw.githubusercontent.com/Shuzinho/farm-system/main/servers.json"
local ACCOUNTS_URL="https://raw.githubusercontent.com/Shuzinho/farm-system/main/accounts.json"
local PRIORITY_URL="https://raw.githubusercontent.com/Shuzinho/farm-system/main/accounts_priority.json"

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
    if not ok then
        warn("Erro ao carregar servers.json")
        return nil
    end

    local ok2,d=pcall(function() return H:JSONDecode(r) end)
    if not ok2 then
        warn("JSON inválido em servers.json")
        return nil
    end

    return d
end

local function loadAccounts()
    local ok,r=pcall(function() return game:HttpGet(ACCOUNTS_URL) end)
    if not ok then return {} end
    local ok2,d=pcall(function() return H:JSONDecode(r) end)
    if not ok2 then return {} end
    return d
end

local function loadPriority()
    local ok,r=pcall(function() return game:HttpGet(PRIORITY_URL) end)
    if not ok then return {} end
    local ok2,d=pcall(function() return H:JSONDecode(r) end)
    if not ok2 then return {} end
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
        if x==id then
            return true
        end
    end
    return false
end

local function getQueueStartIndex(list, priority)
    if #list == 0 then
        return 1
    end

    local myPriority = priority[P.Name]

    if myPriority and type(myPriority) == "number" then
        return ((myPriority - 1) % #list) + 1
    end

    return ((P.UserId % #list) + 1)
end

local function getServer()
    local all=loadServers()
    if not all or not all[PID] then
        return nil,nil
    end

    local list=all[PID]
    local usedData=jload(USED_FILE)
    local used=usedData[PID] or {}
    local priority=loadPriority()

    if #list==0 then
        return nil,nil
    end

    local start=getQueueStartIndex(list, priority)

    for i=0,#list-1 do
        local idx=((start+i-1)%#list)+1
        local server=list[idx]
        local id=server.jobId
        local game_id=server.game_id or tonumber(PID)

        -- segurança extra: só aceita servidor do place atual
        if tostring(game_id)==PID and id~=JID and not isUsed(id, used) then
            return id,game_id
        end
    end

    return nil,nil
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

local function goNewServer()
    local id,game_id=getServer()

    if not id or not game_id then
        print("❌ Nenhum servidor disponível")
        return
    end

    print("🚀 Indo para novo servidor:",id,"place:",game_id)
    markTarget(id)
    markUsed(id)
    T:TeleportToPlaceInstance(tonumber(game_id),id,P)
end

local function detectMyAccounts()
    task.wait(10)

    local accounts=loadAccounts()
    local priority=loadPriority()
    local players=Players:GetPlayers()

    local myAccountsHere={}

    for _,plr in ipairs(players) do
        if accounts[plr.Name] then
            table.insert(myAccountsHere,plr.Name)
        end
    end

    if #myAccountsHere<=1 then
        print("✅ Nenhuma conta duplicada aqui")
        return false
    end

    table.sort(myAccountsHere,function(a,b)
        local pa=priority[a] or 999999
        local pb=priority[b] or 999999
        if pa==pb then
            return a<b
        end
        return pa<pb
    end)

    local keeper=myAccountsHere[1]
    local myName=P.Name

    if myName~=keeper then
        print("⚠️ Outra conta minha detectada, prioridade menor, vou trocar de servidor...")
        return true
    else
        print("✅ Sou a conta de maior prioridade, vou ficar")
        return false
    end
end

if PID==BLUE_LOCK_ID then
    print("🔵 Modo Blue Lock ativo")

    if justHoppedHere() then
        print("⛔ Anti-loop ativo no Blue Lock")
        return
    end

    local needHop=detectMyAccounts()

    if needHop then
        goNewServer()
    else
        print("✅ Ficando no servidor. BananaHub cuida do hop da partida.")
    end

    return
end

if justHoppedHere() then
    print("⛔ Anti-loop ativo, ficando no servidor")
    return
end

goNewServer()

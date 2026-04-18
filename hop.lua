local H=game:GetService("HttpService")
local T=game:GetService("TeleportService")
local P=game:GetService("Players").LocalPlayer
local Players=game:GetService("Players")

local PID=tostring(game.PlaceId)
local JID=game.JobId

local BLUE_LOCK_ID="18668065416"

local SERVERS_URL="https://raw.githubusercontent.com/Shuzinho/farm-system/main/servers.json"
local ACCOUNTS_URL="https://raw.githubusercontent.com/Shuzinho/farm-system/main/accounts.json"

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

local function loadAccounts()
    local ok,r=pcall(function() return game:HttpGet(ACCOUNTS_URL) end)
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

local function removeUsed(id)
    local used=jload(USED_FILE)
    if used[PID] then
        for i,v in ipairs(used[PID]) do
            if v==id then
                table.remove(used[PID],i)
                break
            end
        end
        jsave(USED_FILE,used)
    end
end

local function goNewServer()
    local maxAttempts=5
    local attempts=0

    while attempts<maxAttempts do
        local id=getServer()
        if not id then
            print("❌ Nenhum servidor disponível")
            return
        end

        attempts=attempts+1
        print("🚀 Tentativa "..attempts.."/"..maxAttempts.." - Indo para servidor:",id)
        markTarget(id)
        markUsed(id)

        local ok,err=pcall(function()
            game:GetService("ReplicatedStorage").__ServerBrowser:InvokeServer("teleport", id)
        end)

        if ok then
            print("✅ Teleporte iniciado com sucesso!")
            return
        else
            print("❌ Teleporte falhou:",tostring(err))
            removeUsed(id)

            if attempts<maxAttempts then
                print("⏳ Tentando próximo servidor em 2 segundos...")
                task.wait(2)
            end
        end
    end

    print("❌ Máximo de tentativas atingido. Aguardando antes de tentar novamente...")
end

local function detectMyAccounts()
    task.wait(10)

    local accounts=loadAccounts()
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

    table.sort(myAccountsHere)

    local keeper=myAccountsHere[1]
    local myName=P.Name

    if myName~=keeper then
        print("⚠️ Outra conta minha detectada, vou trocar de servidor...")
        return true
    else
        print("✅ Sou a conta que vai ficar")
        return false
    end
end

-- Blue Lock:
-- BananaHub faz o hop no fim da partida.
-- Nosso script só corrige colisão de contas.
if PID==BLUE_LOCK_ID then
    print("🔵 Modo Blue Lock ativo")

    if justHoppedHere() then
        print("⛔ Anti-loop ativo no Blue Lock")
        return
    end

    local needHop=detectMyAccounts()
    if needHop then
        goNewServerAsync()
    else
        print("✅ Ficando no servidor. BananaHub cuida do hop da partida.")
    end

    return
end

-- Outros jogos:
if justHoppedHere() then
    print("⛔ Anti-loop ativo, ficando no servidor")
    return
end

-- Handler para falhas de teleporte
local isTeleporting=false
local teleportFailed=false

T.TeleportInitFailed:Connect(function(player,resultEnum,errorMessage,placeId,instanceId)
    if player~=P then return end
    isTeleporting=false
    teleportFailed=true
    print("❌ Teleporte falhou (evento):",tostring(resultEnum),tostring(errorMessage))

    -- Limpar o servidor que falhou da lista
    if instanceId then
        removeUsed(instanceId)
        print("🗑️ Servidor removido da lista:",instanceId)
    end
end)

-- Função melhorada com retry assíncrono
local function goNewServerAsync()
    local maxAttempts=5
    local attempts=0

    while attempts<maxAttempts do
        local id=getServer()
        if not id then
            print("❌ Nenhum servidor disponível")
            return
        end

        attempts=attempts+1
        print("🚀 Tentativa "..attempts.."/"..maxAttempts.." - Indo para servidor:",id)
        markTarget(id)
        markUsed(id)

        isTeleporting=true
        teleportFailed=false

        -- Tentar teleporte
        local ok,err=pcall(function()
            game:GetService("ReplicatedStorage").__ServerBrowser:InvokeServer("teleport", id)
        end)

        if not ok then
            print("❌ Erro imediato:",tostring(err))
            removeUsed(id)
            isTeleporting=false

            if attempts<maxAttempts then
                print("⏳ Tentando próximo em 3 segundos...")
                task.wait(3)
            end
        else
            -- Aguardar resultado por até 5 segundos
            local waited=0
            while isTeleporting and waited<50 do
                task.wait(0.1)
                waited=waited+1

                if teleportFailed then
                    break
                end
            end

            if not teleportFailed then
                print("✅ Teleporte aceito!")
                return
            end

            -- Falhou, tentar próximo
            if attempts<maxAttempts then
                print("⏳ Tentando próximo servidor em 3 segundos...")
                task.wait(3)
            end
        end
    end

    print("❌ Máximo de tentativas atingido.")
end

goNewServerAsync()

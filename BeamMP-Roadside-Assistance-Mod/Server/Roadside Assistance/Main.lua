-- Requests are session-only. Restarting/reloading the plugin clears the job board.
local REQUEST_COOLDOWN = 30 -- Seconds between successful requests per player.
local jobs, requestedBy, assignedTo, pending, lastRequest = {}, {}, {}, {}, {}
local nextJob, nextToken = 0, 0
local subscribers, uiRate = {}, {}

local function reply(pid, text)
    MP.SendChatMessage(pid, "[Roadside] " .. text)
    if subscribers[pid] then MP.TriggerClientEvent(pid, "RoadsideAssistNotice", Util.JsonEncode({text = text})) end
end
local function name(pid)
    return (MP.GetPlayerName(pid) or ("Player " .. pid)):gsub("%c", " "):gsub("%^%d", "")
end
local function number(text)
    if type(text) ~= "string" or not text:match("^%d+$") then return nil end
    local value = tonumber(text)
    if value and value <= 2147483647 then return value end
end
local function ownsVehicle(pid, vid)
    local vehicles = MP.GetPlayerVehicles(pid)
    return type(vehicles) == "table" and vehicles[vid] ~= nil
end
local function summary(job)
    return "Job #" .. job.id .. " - " .. job.name .. " (Player " .. job.owner .. ", vehicle " .. job.vehicle .. ")"
end
local function jobView(job)
    if not job then return nil end
    return {id = job.id, owner = job.owner, name = job.name, vehicle = job.vehicle,
        helper = job.helper, helperName = job.helper ~= nil and name(job.helper) or nil}
end
local function sendState(pid)
    local open = {}
    for _, job in pairs(jobs) do
        if job.helper == nil then table.insert(open, jobView(job)) end
    end
    table.sort(open, function(a, b) return a.id < b.id end)
    MP.TriggerClientEvent(pid, "RoadsideAssistState", Util.JsonEncode({
        connected = true, playerId = pid, openJobs = open,
        request = jobView(jobs[requestedBy[pid]]), assignment = jobView(jobs[assignedTo[pid]]),
        selecting = pending[pid] ~= nil and pending[pid].expires >= os.time(),
        cooldown = math.max(0, REQUEST_COOLDOWN - (os.time() - (lastRequest[pid] or 0)))
    }))
end
local function publishState()
    local players = MP.GetPlayers()
    for pid in pairs(subscribers) do
        if players[pid] ~= nil then sendState(pid) else subscribers[pid] = nil end
    end
end
local function clearMarker(pid)
    MP.TriggerClientEvent(pid, "RoadsideAssistClear", "")
end
local function locate(pid, job)
    local sent = MP.TriggerClientEvent(pid, "RoadsideAssistLocate", Util.JsonEncode({
        serverVehicleID = job.owner .. "-" .. job.vehicle,
        label = summary(job)
    }))
    if not sent then reply(pid, "Could not send the locator. Try /assist locate again.") end
end
local function finish(job, reason, disconnected)
    jobs[job.id], requestedBy[job.owner] = nil, nil
    if job.helper ~= nil then
        assignedTo[job.helper] = nil
        if job.helper ~= disconnected then
            clearMarker(job.helper)
            reply(job.helper, "Job #" .. job.id .. " " .. reason)
        end
    end
    if job.owner ~= disconnected then reply(job.owner, "Job #" .. job.id .. " " .. reason) end
end
local function release(job, disconnected)
    local helper = job.helper
    assignedTo[helper], job.helper = nil, nil
    if helper ~= disconnected then
        clearMarker(helper)
        reply(helper, "Released job #" .. job.id .. ".")
    end
    reply(job.owner, "Your helper is no longer assigned. Your request is open again.")
    reply(-1, summary(job) .. " is open again. /assist accept " .. job.id)
end
local function mayRequest(pid)
    if requestedBy[pid] then reply(pid, "You already have a request. Use /assist status or /assist cancel."); return false end
    if assignedTo[pid] then reply(pid, "Complete or release your current job before requesting help."); return false end
    local wait = REQUEST_COOLDOWN - (os.time() - (lastRequest[pid] or 0))
    if wait > 0 then reply(pid, "Please wait " .. wait .. " seconds before requesting again."); return false end
    return true
end
local function createRequest(pid, vid)
    if not mayRequest(pid) then return end
    if not ownsVehicle(pid, vid) then reply(pid, "That vehicle does not belong to you. Use /assist vehicles."); return end
    nextJob = nextJob + 1
    local job = { id = nextJob, owner = pid, vehicle = vid, name = name(pid) }
    jobs[job.id], requestedBy[pid], lastRequest[pid] = job, job.id, os.time()
    reply(pid, "Request #" .. job.id .. " created for vehicle " .. vid .. ". Use /assist cancel if help is no longer needed.")
    reply(-1, summary(job) .. " needs towing/recovery. /assist accept " .. job.id)
end

-- The event sender is supplied by BeamMP; only a pending request for that sender is accepted.
local function handleSelected(pid, raw)
    local request = pending[pid]
    if not request or os.time() > request.expires or type(raw) ~= "string" or #raw > 1024 then return end
    local ok, data = pcall(Util.JsonDecode, raw)
    if not ok or type(data) ~= "table" or data.token ~= request.token then return end
    pending[pid] = nil
    if type(data.serverVehicleID) ~= "string" then
        reply(pid, "Enter your own vehicle, then use /assist. Or use /assist vehicles and /assist <vehicle_id>.")
        return
    end
    local owner, vehicle = data.serverVehicleID:match("^(%d+)%-(%d+)$")
    local vid = number(vehicle)
    if number(owner) ~= pid or not vid then reply(pid, "You can only request assistance for your own vehicle."); return end
    createRequest(pid, vid)
end

local function handleChat(pid, sender, message)
    if type(message) ~= "string" then return 0 end
    local command, args = message:match("^(%S+)%s*(.-)%s*$")
    if not command or command:lower() ~= "/assist" then return 0 end
    local action, rest = args:match("^(%S+)%s*(.-)%s*$")
    action = action and action:lower() or ""
    rest = rest or ""
    if action == "" then
        if not mayRequest(pid) then return 1 end
        if pending[pid] and pending[pid].expires >= os.time() then
            reply(pid, "Waiting for your client. If needed, use /assist vehicles and /assist <vehicle_id>.")
            return 1
        end
        nextToken = nextToken + 1
        pending[pid] = { token = tostring(nextToken), expires = os.time() + 15 }
        local sent = MP.TriggerClientEvent(pid, "RoadsideAssistSelect", Util.JsonEncode({token = tostring(nextToken)}))
        if not sent then pending[pid] = nil; reply(pid, "Could not contact your client. Use /assist <vehicle_id> instead.")
        else reply(pid, "Selecting your current vehicle. If no request appears, install the client ZIP or use /assist <vehicle_id>.") end
    elseif action == "help" and rest == "" then
        reply(pid, "/assist - request help for your current vehicle. /assist <vehicle_id> - choose your own vehicle explicitly.")
        reply(pid, "/assist vehicles | list | status - view your vehicle IDs, open jobs, or your current job.")
        reply(pid, "/assist accept <job_id> - take a job. /assist locate - refresh its marker.")
        reply(pid, "/assist complete - finish your accepted job. /assist release - return it to the board.")
        reply(pid, "/assist cancel - cancel your own request. Use your tow truck's normal controls for recovery.")
    elseif action == "vehicles" and rest == "" then
        local ids = {}
        for vid in pairs(MP.GetPlayerVehicles(pid) or {}) do table.insert(ids, vid) end
        table.sort(ids)
        if #ids == 0 then reply(pid, "You have no vehicles spawned.") end
        for _, vid in ipairs(ids) do reply(pid, "Vehicle ID " .. vid .. " - request help: /assist " .. vid) end
    elseif action == "list" and rest == "" then
        local ids = {}
        for id, job in pairs(jobs) do if job.helper == nil then table.insert(ids, id) end end
        table.sort(ids)
        if #ids == 0 then reply(pid, "No open requests.") end
        for _, id in ipairs(ids) do reply(pid, summary(jobs[id]) .. " - /assist accept " .. id) end
    elseif action == "status" and rest == "" then
        local job = jobs[requestedBy[pid] or assignedTo[pid]]
        if not job then reply(pid, "You have no active job or request.")
        else reply(pid, summary(job) .. (job.helper and (" | Helper: " .. name(job.helper)) or " | Waiting for a helper")) end
    elseif action == "accept" and number(rest) then
        local job = jobs[number(rest)]
        if requestedBy[pid] or assignedTo[pid] then reply(pid, "You already have a request or assignment.")
        elseif not job then reply(pid, "That request does not exist.")
        elseif job.owner == pid then reply(pid, "You cannot accept your own request.")
        elseif job.helper ~= nil then reply(pid, "Another helper has already accepted that job.")
        elseif not ownsVehicle(job.owner, job.vehicle) then finish(job, "cancelled: vehicle no longer exists.")
        else
            pending[pid] = nil
            job.helper, assignedTo[pid] = pid, job.id
            reply(job.owner, name(pid) .. " accepted your request and is on their way.")
            reply(pid, "Accepted " .. summary(job) .. ". Use your tow truck to recover it, then /assist complete.")
            locate(pid, job)
        end
    elseif action == "cancel" and rest == "" then
        pending[pid] = nil
        local job = jobs[requestedBy[pid]]
        if job then finish(job, "cancelled by the requesting player.") else reply(pid, "No active request. Any pending vehicle selection was cancelled.") end
    elseif (action == "complete" or action == "release" or action == "locate") and rest == "" then
        local job = jobs[assignedTo[pid]]
        if not job then reply(pid, "You have no accepted job.")
        elseif action == "complete" then finish(job, "completed. Thanks for helping!")
        elseif action == "release" then release(job)
        elseif not ownsVehicle(job.owner, job.vehicle) then finish(job, "cancelled: vehicle no longer exists.")
        else locate(pid, job); reply(pid, "Locator requested. Apply queued vehicles if the target is not spawned locally.") end
    elseif number(action) and rest == "" then
        pending[pid] = nil
        createRequest(pid, number(action))
    else reply(pid, "Unknown command or extra arguments. Use /assist help.") end
    return 1
end

function RoadsideAssistChat(pid, sender, message)
    local result = handleChat(pid, sender, message)
    if result == 1 then publishState() end
    return result
end

function RoadsideAssistSelected(pid, raw)
    handleSelected(pid, raw)
    publishState()
end

-- UI payloads select a fixed command, never an arbitrary command or player identity.
function RoadsideAssistUI(pid, raw)
    if MP.GetPlayers()[pid] == nil or type(raw) ~= "string" or #raw > 512 then return end
    local ok, data = pcall(Util.JsonDecode, raw)
    if not ok or type(data) ~= "table" or type(data.action) ~= "string" then return end
    local allowed = {refresh = true, request = true, accept = true, cancel = true,
        complete = true, release = true, locate = true, unsubscribe = true}
    if not allowed[data.action] then return end
    if data.action == "unsubscribe" then subscribers[pid] = nil; uiRate[pid] = nil; return end
    local now = os.time()
    local rate = uiRate[pid]
    if not rate or rate.time ~= now then rate = {time = now, count = 0}; uiRate[pid] = rate end
    if rate.count >= 8 then return end
    rate.count = rate.count + 1
    subscribers[pid] = true
    if data.action == "refresh" then sendState(pid); return end
    local command = data.action
    if command == "request" then command = ""
    elseif command == "accept" then
        if type(data.jobId) ~= "number" or data.jobId < 1 or data.jobId > 2147483647 or data.jobId % 1 ~= 0 then return end
        command = "accept " .. string.format("%.0f", data.jobId)
    end
    RoadsideAssistChat(pid, name(pid), "/assist " .. command)
end

function RoadsideAssistDisconnect(pid)
    subscribers[pid], uiRate[pid] = nil, nil
    pending[pid], lastRequest[pid] = nil, nil
    local requested = jobs[requestedBy[pid]]
    if requested then finish(requested, "cancelled: requesting player disconnected.", pid) end
    local assigned = jobs[assignedTo[pid]]
    if assigned then release(assigned, pid) end
    publishState()
end

function RoadsideAssistVehicleDeleted(pid, vid)
    local job = jobs[requestedBy[pid]]
    if job and job.vehicle == vid then finish(job, "cancelled: stranded vehicle was removed."); publishState() end
end

-- Also catch removals performed by other plugins that do not emit deletion hooks.
function RoadsideAssistMaintenance()
    local players = MP.GetPlayers()
    for pid, selection in pairs(pending) do
        if selection.expires < os.time() then pending[pid] = nil end
    end
    local ids = {}
    for id in pairs(jobs) do table.insert(ids, id) end
    for _, id in ipairs(ids) do
        local job = jobs[id]
        if players[job.owner] == nil then RoadsideAssistDisconnect(job.owner)
        elseif not ownsVehicle(job.owner, job.vehicle) then finish(job, "cancelled: stranded vehicle was removed.")
        elseif job.helper ~= nil and players[job.helper] == nil then release(job, job.helper) end
    end
    publishState()
end

MP.RegisterEvent("onChatMessage", "RoadsideAssistChat")
MP.RegisterEvent("RoadsideAssistSelected", "RoadsideAssistSelected")
MP.RegisterEvent("RoadsideAssistUI", "RoadsideAssistUI")
MP.RegisterEvent("onPlayerDisconnect", "RoadsideAssistDisconnect")
MP.RegisterEvent("onVehicleDeleted", "RoadsideAssistVehicleDeleted")
MP.RegisterEvent("RoadsideAssistMaintenance", "RoadsideAssistMaintenance")
MP.CreateEventTimer("RoadsideAssistMaintenance", 5000)
-- A hot reload resets the board, so clear markers from any previous plugin state.
MP.TriggerClientEvent(-1, "RoadsideAssistClear", "")
print("[Roadside] Player-operated roadside assistance loaded. /assist help")

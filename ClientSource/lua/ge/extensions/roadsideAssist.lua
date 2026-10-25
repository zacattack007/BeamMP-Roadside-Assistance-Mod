local M = {}
local target
local registeredWith
local handlerName = "beammpRoadsideAssistance"
local uiListening = false

local function uiHook(event, data)
    if guihooks then guihooks.trigger(event, data) end
end

local function notify(text)
    if ui_message then ui_message(text, 6, "roadsideAssist") end
    uiHook("RoadsideAssistAppNotice", {text = text})
end

local function receiveState(raw)
    if type(raw) ~= "string" then return end
    local ok, data = pcall(jsonDecode, raw)
    if ok and type(data) == "table" then uiHook("RoadsideAssistAppState", data) end
end

local function receiveNotice(raw)
    if type(raw) ~= "string" or #raw > 4096 then return end
    local ok, data = pcall(jsonDecode, raw)
    if ok and type(data) == "table" and type(data.text) == "string" then
        uiHook("RoadsideAssistAppNotice", {text = data.text})
    end
end

local function clear(reason)
    target = nil
    if reason then notify(reason) end
end

local function receiveShow(raw)
    if type(raw) ~= "string" or #raw > 4096 then return end
    local ok, data = pcall(jsonDecode, raw)
    if not ok or type(data) ~= "table" or type(data.serverVehicleID) ~= "string"
        or not data.serverVehicleID:match("^%d+%-%d+$") or type(data.label) ~= "string" then return end
    target = {
        id = data.serverVehicleID,
        label = data.label:gsub("%c", " "):gsub("%^%d", ""):sub(1, 240),
        -- Fixed client lifetime prevents malformed events from leaving permanent markers.
        remaining = 600,
        missingTime = 0
    }
    notify("Locating " .. target.label .. ". Look for the orange marker; /assist locate refreshes it.")
end

local function receiveClear()
    clear("Roadside job marker cleared.")
end

local function receiveSelection(raw)
    if type(raw) ~= "string" or #raw > 1024 then return end
    local ok, data = pcall(jsonDecode, raw)
    if not ok or type(data) ~= "table" or type(data.token) ~= "string"
        or not data.token:match("^%d+$") or #data.token > 32 then return end
    local response = { token = data.token }
    local vehicle = getPlayerVehicle(0)
    local network = extensions.MPVehicleGE or MPVehicleGE
    if vehicle and network then
        response.serverVehicleID = network.getServerVehicleID(vehicle:getID())
    end
    TriggerServerEvent("RoadsideAssistSelected", jsonEncode(response))
end

local function registerHandlers()
    if type(AddEventHandler) == "function" and registeredWith ~= AddEventHandler then
        AddEventHandler("RoadsideAssistSelect", receiveSelection, handlerName)
        AddEventHandler("RoadsideAssistLocate", receiveShow, handlerName)
        AddEventHandler("RoadsideAssistClear", receiveClear, handlerName)
        AddEventHandler("RoadsideAssistState", receiveState, handlerName)
        AddEventHandler("RoadsideAssistNotice", receiveNotice, handlerName)
        registeredWith = AddEventHandler
    end
end

local function uiAction(action, jobId)
    local allowed = {refresh = true, request = true, accept = true, cancel = true,
        complete = true, release = true, locate = true, unsubscribe = true}
    if not allowed[action] then return end
    if not MPCoreNetwork or not MPCoreNetwork.isMPSession() or type(TriggerServerEvent) ~= "function" then
        uiHook("RoadsideAssistAppState", {connected = false})
        return
    end
    if action == "accept" and (type(jobId) ~= "number" or jobId < 1 or jobId > 2147483647 or jobId % 1 ~= 0) then return end
    uiListening = action ~= "unsubscribe"
    registerHandlers()
    TriggerServerEvent("RoadsideAssistUI", jsonEncode({action = action, jobId = jobId}))
end

local function onUpdate(dtReal)
    -- The mod may mount before BeamMP's event functions are ready.
    registerHandlers()
    if not target then return end
    local dt = math.max(0, tonumber(dtReal) or 0)
    target.remaining = target.remaining - dt
    if target.remaining <= 0 then clear("Job marker expired. Use /assist locate to refresh it."); return end

    local vehicles = extensions.MPVehicleGE or MPVehicleGE
    local entry = vehicles and vehicles.getVehicleByServerID(target.id)
    if target.entry and target.entry ~= entry then
        clear("Located vehicle was removed or replaced.")
        return
    end
    if entry then target.entry = entry end
    local vehicle = entry and entry.gameVehicleID and be:getObjectByID(entry.gameVehicleID)
    if not vehicle then
        target.missingTime = target.missingTime + dt
        if target.missingTime >= 5 then
            clear("Vehicle is not spawned on your client. Apply queued vehicles, then run /assist locate again.")
        end
        return
    end
    target.missingTime = 0

    local position = vehicle:getPosition()
    local beacon = position + vec3(0, 0, 8)
    local distance = (position - getCameraPosition()):length()
    local label = target.label .. string.format(" | %.0f m from camera", distance)
    debugDrawer:drawCylinder(position, beacon, 0.18, ColorF(1, 0.45, 0, 0.55))
    debugDrawer:drawSphere(position + vec3(0, 0, 2), 0.5, ColorF(1, 0.65, 0, 0.8))
    -- Last argument disables depth testing so the label can be seen behind scenery.
    debugDrawer:drawTextAdvanced(beacon, String(label), ColorF(1, 0.8, 0.2, 1), true, false, ColorI(0, 0, 0, 190), false, false)
end

local function onExtensionUnloaded()
    clear()
    if uiListening and type(TriggerServerEvent) == "function" and MPCoreNetwork and MPCoreNetwork.isMPSession() then
        TriggerServerEvent("RoadsideAssistUI", jsonEncode({action = "unsubscribe"}))
    end
    uiListening = false
    if registeredWith and type(RemoveEventHandler) == "function" then
        RemoveEventHandler("RoadsideAssistSelect", handlerName)
        RemoveEventHandler("RoadsideAssistLocate", handlerName)
        RemoveEventHandler("RoadsideAssistClear", handlerName)
        RemoveEventHandler("RoadsideAssistState", handlerName)
        RemoveEventHandler("RoadsideAssistNotice", handlerName)
    end
    registeredWith = nil
    uiHook("RoadsideAssistAppState", {connected = false})
end

M.onExtensionLoaded = registerHandlers
M.onUpdate = onUpdate
M.onClientEndMission = function() clear(); uiHook("RoadsideAssistAppState", {connected = false}) end
M.onExtensionUnloaded = onExtensionUnloaded
M.uiAction = uiAction
return M

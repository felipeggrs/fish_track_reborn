local api = require("api")

local fish_track = {
	name = "fish_track_reborn",
	author = "Wagasez",
	version = "1.4",
	desc = "Track Buff For Fishing. Inspired by Usb's work."
}

local fishBuffIdsToAlert = {
	[5715] = "Strength Contest",
	[5264] = "Stand Firm Right",
	[5265] = "Stand Firm Left",
	[5266] = "Reel In",
	[5267] = "Give Slack",
	[5508] = "Big Reel In"
}

local actionBuffs = {
	[5264] = true,
	[5265] = true,
	[5266] = true,
	[5267] = true,
	[5508] = true
}

local fishNamesToAlert = {
	-- English
	["Marlin"] = true, ["Blue Marlin"] = true, ["Tuna"] = true, ["Blue Tuna"] = true, ["Bluefin Tuna"] = true, ["Sunfish"] = true,
	["Sailfish"] = true, ["Sturgeon"] = true, ["Pink Pufferfish"] = true,
	["Carp"] = true, ["Arowana"] = true, ["Pufferfish"] = true, ["Eel"] = true,
	["Pink Marlin"] = true, ["Treasure Mimic"] = true,
	-- Korean
	["철갑상어"] = true,  -- Sturgeon
	["청새치"] = true,  -- Blue Marlin
	["참다랑어"] = true,  -- Tuna
	["돛새치"] = true,  -- Sailfish
}

local fishTrackerCanvas, fishBuffAlertCanvas, fishBuffAlertLabel, fishBuffAlertIcon, fishBuffTimeLeftLabel, targetFishIcon
local strengthContestIcon, strengthContestTimeLabel

local previousBuffTimeRemaining = 0
local previousXYZ = "0,0,0"
local previousFish
local settings

local MARKED_FISH_TIMER = 150000
local markedFishData = {}
local markedFishUI = {}

local DEBUG_MODE = false  -- Set to true to log target unit info
local lastLoggedFishId = nil

local function OnUpdate(dt)
    local currentTime = api.Time:GetUiMsec()

    for markerIndex = 1, 6 do
        local markerUnitId = api.Unit:GetOverHeadMarkerUnitId(markerIndex)

        if markerUnitId ~= nil then
            local markerUnitInfo = api.Unit:GetUnitInfoById(markerUnitId)
            if markerUnitInfo ~= nil and fishNamesToAlert[markerUnitInfo.name] then
                if markedFishData[markerIndex] == nil then
                    markedFishData[markerIndex] = {}
                end
                if markedFishData[markerIndex].unitId ~= markerUnitId then
                    markedFishData[markerIndex].unitId = markerUnitId
                    markedFishData[markerIndex].deathTime = nil
                end
            end
        else
            if markedFishData[markerIndex] ~= nil then
                markedFishData[markerIndex].unitId = nil
                markedFishData[markerIndex].deathTime = nil
            end
            if markedFishUI[markerIndex] ~= nil then
                markedFishUI[markerIndex].canvas:Show(false)
            end
        end
    end

    local activeTimerCount = 0
    for markerIndex = 1, 6 do
        local data = markedFishData[markerIndex]
        local ui = markedFishUI[markerIndex]

        if data ~= nil and data.unitId ~= nil and data.deathTime ~= nil and ui ~= nil then
            local elapsed = currentTime - data.deathTime
            local remaining = MARKED_FISH_TIMER - elapsed

            if remaining > 0 then
                local xOffset = (activeTimerCount * 50) - 125
                ui.canvas:AddAnchor("TOP", "UIParent", "CENTER", xOffset, 200)
                ui.canvas:Show(true)
                F_SLOT.SetIconBackGround(ui.icon, api.Ability:GetBuffTooltip(4832, 1).path)
                ui.timeLabel:SetText(string.format("%.0fs", remaining / 1000))
                ui.markerLabel:SetText(tostring(markerIndex))
                activeTimerCount = activeTimerCount + 1
            else
                ui.canvas:Show(false)
                data.deathTime = nil
            end
        end
    end

    local currentFish = api.Unit:GetUnitId("target")
    local currentFishName
    local currentFishInfo
    if (currentFish ~= nil) then
        currentFishInfo = api.Unit:GetUnitInfoById(currentFish)
        currentFishName = currentFishInfo.name

        -- Debug: Log target name to file for collecting fish names
        if DEBUG_MODE and currentFish ~= lastLoggedFishId then
            lastLoggedFishId = currentFish
            local logData = api.File:Read("fish_track_reborn/debug_log.lua") or {names = {}}
            logData.names[currentFishName] = true
            api.File:Write("fish_track_reborn/debug_log.lua", logData)
            api.Log:Info("[FishTrack] Logged: " .. tostring(currentFishName))
        end
    else
        lastLoggedFishId = nil
    end

    local x, y, z = api.Unit:GetUnitScreenPosition("target")

    if (currentFish ~= previousFish) then
        fishTrackerCanvas:Show(false)
        fishBuffAlertCanvas:Show(false)
    end

    if (currentFish == nil) then
        fishTrackerCanvas:Show(false)
        fishBuffAlertCanvas:Show(false)
        return
    end

    if (previousXYZ ~= (x .. "," .. y .. "," .. z)) then
        fishTrackerCanvas:AddAnchor("TOP", "UIParent", "TOPLEFT", x - 42, y + 5)
        previousXYZ = x .. "," .. y .. "," .. z
    end

    local fishHealth = api.Unit:UnitHealth("target")
    if (fishHealth ~= nil and fishHealth <= 0) then
        fishBuffAlertCanvas:Show(false)
        strengthContestIcon:Show(false)
        strengthContestTimeLabel:SetText("")
        fishTrackerCanvas:AddAnchor("TOP", "UIParent", "TOPLEFT", x - 20, y + 5)
        if (fishNamesToAlert[currentFishName] ~= nil) then
            fishTrackerCanvas:Show(true)
        end
        F_SLOT.SetIconBackGround(targetFishIcon, api.Ability:GetBuffTooltip(4832, 1).path)
        fishBuffTimeLeftLabel:SetText("")

        for markerIndex = 1, 6 do
            local data = markedFishData[markerIndex]
            if data ~= nil and data.unitId == currentFish and data.deathTime == nil then
                data.deathTime = api.Time:GetUiMsec()
            end
        end
        return
    end

    local buffCount = api.Unit:UnitBuffCount("target")
    if buffCount == nil or buffCount == 0 then
        fishBuffAlertCanvas:Show(false)
        if (fishNamesToAlert[currentFishName] ~= nil) then
            fishTrackerCanvas:Show(true)
        end
        F_SLOT.SetIconBackGround(targetFishIcon, api.Ability:GetBuffTooltip(4832, 1).path)
        fishBuffTimeLeftLabel:SetText("Waiting")
        return
    end

    local actionBuff = nil
    local strengthContestBuff = nil

    for i = 1, buffCount do
        local buff = api.Unit:UnitBuff("target", i)
        if buff ~= nil and fishBuffIdsToAlert[buff.buff_id] ~= nil then
            if actionBuffs[buff.buff_id] then
                actionBuff = buff
                break
            elseif buff.buff_id == 5715 then
                strengthContestBuff = buff
            end
        end
    end

    if (actionBuff ~= nil) then
        previousFish = currentFish

        if (settings.ShowBuffsOnTarget == true) then
            F_SLOT.SetIconBackGround(targetFishIcon, actionBuff.path)
        else
            F_SLOT.SetIconBackGround(targetFishIcon, api.Ability:GetBuffTooltip(actionBuff.buff_id, 1).path)
        end

        if (fishNamesToAlert[currentFishName] ~= nil) then
            fishTrackerCanvas:Show(true)
        end

        if (settings.ShowTimers == true) then
            local currentTime = actionBuff.timeLeft / 1000
            fishBuffTimeLeftLabel:SetText(string.format("%.1fs", currentTime))
        else
            fishBuffTimeLeftLabel:SetText("")
        end
    else
        if (fishNamesToAlert[currentFishName] ~= nil and strengthContestBuff == nil) then
            fishTrackerCanvas:Show(true)
            F_SLOT.SetIconBackGround(targetFishIcon, api.Ability:GetBuffTooltip(3710, 1).path)
            fishBuffTimeLeftLabel:SetText("Waiting")
        elseif strengthContestBuff == nil then
            fishTrackerCanvas:Show(false)
        end
    end

    if (strengthContestBuff ~= nil) then
        if (fishNamesToAlert[currentFishName] ~= nil) then
            fishTrackerCanvas:Show(true)
        end

        F_SLOT.SetIconBackGround(strengthContestIcon, api.Ability:GetBuffTooltip(5715, 1).path)
        strengthContestIcon:Show(true)

        if (settings.ShowTimers == true) then
            local currentTime = strengthContestBuff.timeLeft / 1000
            strengthContestTimeLabel:SetText(string.format("%.1fs", currentTime))
        else
            strengthContestTimeLabel:SetText("")
        end
    else
        if strengthContestIcon ~= nil then
            strengthContestIcon:Show(false)
        end
    end

    fishBuffAlertCanvas:Show(false)
end

local function OnLoad()
	settings = api.GetSettings(fish_track.name)
	local needsFirstSave = false
	if (settings.ShowBuffsOnTarget == nil) then
		settings.ShowBuffsOnTarget = false
		needsFirstSave = true
	end
	if (settings.ShowWait == nil) then
		settings.ShowWait = true
		needsFirstSave = true
	end
	if (settings.ShowTimers == nil) then
		settings.ShowTimers = true
		needsFirstSave = true
	end
	if (needsFirstSave == true) then
		api.SaveSettings()
	end

	fishBuffAlertCanvas = api.Interface:CreateEmptyWindow("fishBuffAlertCanvas")
	fishBuffAlertCanvas:AddAnchor("CENTER", "UIParent", 0, -300)
	fishBuffAlertCanvas:Show(false)

	fishBuffAlertLabel = fishBuffAlertCanvas:CreateChildWidget("label", "fishBuffAlertLabel", 0, true)
	fishBuffAlertLabel:SetText("fish_track")
	fishBuffAlertLabel:AddAnchor("TOPLEFT", fishBuffAlertCanvas, "TOPLEFT", 0, 22)
	fishBuffAlertLabel.style:SetFontSize(44)
	fishBuffAlertLabel.style:SetAlign(ALIGN_LEFT)
	fishBuffAlertLabel.style:SetShadow(true)

	fishBuffAlertIcon = CreateItemIconButton("fishBuffAlertIcon", fishBuffAlertCanvas)
	fishBuffAlertIcon:Show(true)
	F_SLOT.ApplySlotSkin(fishBuffAlertIcon, fishBuffAlertIcon.back, SLOT_STYLE.DEFAULT)
	fishBuffAlertIcon:AddAnchor("TOPLEFT", fishBuffAlertCanvas, "TOPLEFT", -24, -60)

	fishTrackerCanvas = api.Interface:CreateEmptyWindow("fishTarget")
	fishTrackerCanvas:Show(false)

	targetFishIcon = CreateItemIconButton("targetFishIcon", fishTrackerCanvas)
	targetFishIcon:AddAnchor("TOPLEFT", fishTrackerCanvas, "TOPLEFT", 0, 0)
	targetFishIcon:Show(true)
	F_SLOT.ApplySlotSkin(targetFishIcon, targetFishIcon.back, SLOT_STYLE.DEFAULT)

	fishBuffTimeLeftLabel = fishTrackerCanvas:CreateChildWidget("label", "fishBuffTimeLeftLabel", 0, true)
	fishBuffTimeLeftLabel:SetText("")
	fishBuffTimeLeftLabel:AddAnchor("TOP", targetFishIcon, "BOTTOM", 0, 2)
	fishBuffTimeLeftLabel.style:SetFontSize(18)
	fishBuffTimeLeftLabel.style:SetAlign(ALIGN_CENTER)
	fishBuffTimeLeftLabel.style:SetShadow(true)
	fishBuffTimeLeftLabel.style:SetColor(0, 1, 0, 1)

	strengthContestIcon = CreateItemIconButton("strengthContestIcon", fishTrackerCanvas)
	strengthContestIcon:AddAnchor("LEFT", targetFishIcon, "RIGHT", 5, 0)
	strengthContestIcon:Show(false)
	F_SLOT.ApplySlotSkin(strengthContestIcon, strengthContestIcon.back, SLOT_STYLE.DEFAULT)

	strengthContestTimeLabel = fishTrackerCanvas:CreateChildWidget("label", "strengthContestTimeLabel", 0, true)
	strengthContestTimeLabel:SetText("")
	strengthContestTimeLabel:AddAnchor("TOP", strengthContestIcon, "BOTTOM", 0, 2)
	strengthContestTimeLabel.style:SetFontSize(18)
	strengthContestTimeLabel.style:SetAlign(ALIGN_CENTER)
	strengthContestTimeLabel.style:SetShadow(true)
	strengthContestTimeLabel.style:SetColor(1, 1, 0, 1)

	for i = 1, 6 do
		local canvas = api.Interface:CreateEmptyWindow("markedFishTarget" .. i)
		canvas:Show(false)

		local icon = CreateItemIconButton("markedFishIcon" .. i, canvas)
		icon:AddAnchor("TOPLEFT", canvas, "TOPLEFT", 0, 0)
		icon:Show(true)
		F_SLOT.ApplySlotSkin(icon, icon.back, SLOT_STYLE.DEFAULT)

		local markerLabel = canvas:CreateChildWidget("label", "markedFishMarkerLabel" .. i, 0, true)
		markerLabel:SetText("")
		markerLabel:AddAnchor("BOTTOM", icon, "TOP", 0, 2)
		markerLabel.style:SetFontSize(22)
		markerLabel.style:SetAlign(ALIGN_CENTER)
		markerLabel.style:SetShadow(true)
		markerLabel.style:SetColor(1, 1, 1, 1)

		local timeLabel = canvas:CreateChildWidget("label", "markedFishTimeLabel" .. i, 0, true)
		timeLabel:SetText("")
		timeLabel:AddAnchor("TOP", icon, "BOTTOM", 0, 2)
		timeLabel.style:SetFontSize(18)
		timeLabel.style:SetAlign(ALIGN_CENTER)
		timeLabel.style:SetShadow(true)
		timeLabel.style:SetColor(1, 0.5, 0, 1)

		markedFishUI[i] = {
			canvas = canvas,
			icon = icon,
			timeLabel = timeLabel,
			markerLabel = markerLabel
		}
	end

	api.On("UPDATE", OnUpdate)
end

local function OnUnload()
	if fishBuffAlertCanvas ~= nil then
		fishBuffAlertCanvas:Show(false)
		fishBuffAlertCanvas = nil
	end
	if fishTrackerCanvas ~= nil then
		fishTrackerCanvas:Show(false)
		fishTrackerCanvas = nil
	end
	for i = 1, 6 do
		if markedFishUI[i] ~= nil and markedFishUI[i].canvas ~= nil then
			markedFishUI[i].canvas:Show(false)
			markedFishUI[i].canvas = nil
		end
	end
	markedFishUI = {}
	markedFishData = {}
end

fish_track.OnLoad = OnLoad
fish_track.OnUnload = OnUnload

return fish_track

-- ============================================================
-- CONFIGURATION & DEFAULT POSITIONS
-- ============================================================
local DEFAULT_ALLY_COLOR = { r = 0.3, g = 0.7, b = 1 }
local DEFAULT_HORDE_COLOR = { r = 1, g = 0.3, b = 0.3 }

local DEFAULT_POS = {
    ally =  { xPct = 0.534, yPct = 0.985 },
    horde = { xPct = 0.534, yPct = 0.963 }
}

local lastChatAnnounceTime = 0
local CHAT_ANNOUNCE_COOLDOWN = 3 -- Seconds between health spam prevention

-- ============================================================
-- HELPER: Get Class Color of Player from Raid Roster
-- ============================================================
local function GetClassColorOfPlayer(playerName)
    if not playerName or playerName == "" then return nil end

    local cleanName = string.split("-", playerName)

    local numGroupMembers = GetNumGroupMembers()
    if numGroupMembers > 0 then
        for i = 1, numGroupMembers do
            local name, _, _, _, _, fileName = GetRaidRosterInfo(i)
            if name then
                local unitCleanName = string.split("-", name)
                -- Note: string.lower() only normalizes ASCII bytes; for names
                -- with accented characters (ä, ö, ü, ß, etc.) we fall back to a
                -- raw byte comparison if the lowercase comparison doesn't match,
                -- so correctly-cased UTF-8 names still match.
                if unitCleanName:lower() == cleanName:lower() or unitCleanName == cleanName then
                    if fileName and RAID_CLASS_COLORS[fileName] then
                        return RAID_CLASS_COLORS[fileName]
                    end
                end
            end
        end
    end
    return nil
end

-- ============================================================
-- CREATE FRAMES & TEXT STRINGS
-- ============================================================
local allyFrame = CreateFrame("Frame", "WSG_AllyFrame", UIParent)
allyFrame:SetSize(140, 20)

local allyText = allyFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
allyText:SetPoint("LEFT", allyFrame, "LEFT", 0, 0)

local hordeFrame = CreateFrame("Frame", "WSG_HordeFrame", UIParent)
hordeFrame:SetSize(140, 20)

local hordeText = hordeFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
hordeText:SetPoint("LEFT", hordeFrame, "LEFT", 0, 0)

-- ============================================================
-- STATE VARIABLES AND DISPLAY UPDATE
-- ============================================================
local allyCarrier = nil
local hordeCarrier = nil

local function ApplyPercentPosition(f, posTable)
    local screenWidth = GetScreenWidth()
    local screenHeight = GetScreenHeight()

    if screenWidth > 0 and screenHeight > 0 then
        local pixelX = screenWidth * posTable.xPct
        local pixelY = screenHeight * posTable.yPct

        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pixelX, pixelY)
    end
end

local function LoadPositions()
    ApplyPercentPosition(allyFrame, DEFAULT_POS.ally)
    ApplyPercentPosition(hordeFrame, DEFAULT_POS.horde)
end

local function UpdateDisplay()
    -- Alliance Carrier
    if allyCarrier then
        allyText:SetText(allyCarrier)
        local color = GetClassColorOfPlayer(allyCarrier) or DEFAULT_ALLY_COLOR
        allyText:SetTextColor(color.r, color.g, color.b)
    else
        allyText:SetText("")
    end

    -- Horde Carrier
    if hordeCarrier then
        hordeText:SetText(hordeCarrier)
        local color = GetClassColorOfPlayer(hordeCarrier) or DEFAULT_HORDE_COLOR
        hordeText:SetTextColor(color.r, color.g, color.b)
    else
        hordeText:SetText("")
    end
end

-- ============================================================
-- HELPER: Check and Announce EFC Health on Attack / Target
-- ============================================================
local function CheckAndAnnounceEFCHealth()
    if not UnitExists("target") or UnitIsDead("target") then return end

    local myFaction = UnitFactionGroup("player")
    local enemyFC = (myFaction == "Alliance") and hordeCarrier or allyCarrier

    if not enemyFC or enemyFC == "" then return end

    local targetName = UnitName("target")
    if targetName then
        local cleanTargetName = string.split("-", targetName)
        local cleanEnemyFC = string.split("-", enemyFC)

        -- Same UTF-8-safe comparison as GetClassColorOfPlayer: try
        -- lowercase first, then fall back to a raw match so accented
        -- names still resolve correctly.
        if cleanTargetName:lower() == cleanEnemyFC:lower() or cleanTargetName == cleanEnemyFC then
            local maxHealth = UnitHealthMax("target")
            if maxHealth and maxHealth > 0 then
                local currentHealth = UnitHealth("target")
                local healthPct = math.floor((currentHealth / maxHealth) * 100)

                local currentTime = GetTime()
                if (currentTime - lastChatAnnounceTime) >= CHAT_ANNOUNCE_COOLDOWN then
                    local chatType = "SAY"
                    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
                        chatType = "INSTANCE_CHAT"
                    elseif IsInGroup() and GetNumGroupMembers() > 0 then
                        chatType = "RAID"
                    end

                    SendChatMessage(string.format(">>> ENEMY FC %d%% <<<", healthPct), chatType)
                    lastChatAnnounceTime = currentTime
                end
            end
        end
    end
end

-- ============================================================
-- EVENT HANDLING
-- ============================================================
local eventHandler = CreateFrame("Frame")
eventHandler:RegisterEvent("PLAYER_ENTERING_WORLD")
eventHandler:RegisterEvent("CHAT_MSG_BG_SYSTEM_ALLIANCE")
eventHandler:RegisterEvent("CHAT_MSG_BG_SYSTEM_HORDE")
eventHandler:RegisterEvent("CHAT_MSG_BG_SYSTEM_NEUTRAL")
eventHandler:RegisterEvent("PLAYER_TARGET_CHANGED")
eventHandler:RegisterEvent("UNIT_HEALTH")

eventHandler:SetScript("OnEvent", function(self, event, msg, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        LoadPositions()
        UpdateDisplay()
        return
    elseif event == "PLAYER_TARGET_CHANGED" then
        CheckAndAnnounceEFCHealth()
        return
    elseif event == "UNIT_HEALTH" then
        local unit = msg
        if unit == "target" then
            CheckAndAnnounceEFCHealth()
        end
        return
    end

    if not msg then return end

    -- FIX: the previous pattern "by ([%w%s%-]+)" relied on Lua's %w
    -- character class, which only recognizes plain ASCII letters/digits.
    -- Names containing German (or other) accented characters such as
    -- ä, ö, ü, ß, é, etc. are UTF-8 multi-byte sequences whose
    -- continuation bytes don't match %w, so the old pattern truncated
    -- those names (e.g. "Müller" -> "M").
    --
    -- The new pattern captures everything after "by " up to the next
    -- "!" or "." (or end of string), which is byte-agnostic and works
    -- correctly for any UTF-8 name.
    local name = string.match(msg, "by ([^!%.]+)")

    if name then
        name = name:gsub("[!%.]", "")
        name = strtrim(name)

        if string.find(msg, "Alliance") or string.find(msg, "alliance") then
            if string.find(msg, "picked up") or string.find(msg, "was picked") then
                hordeCarrier = name
            elseif string.find(msg, "dropped") then
                if hordeCarrier == name then hordeCarrier = nil end
            end
        elseif string.find(msg, "Horde") or string.find(msg, "horde") then
            if string.find(msg, "picked up") or string.find(msg, "was picked") then
                allyCarrier = name
            elseif string.find(msg, "dropped") then
                if allyCarrier == name then allyCarrier = nil end
            end
        end
    end

    if string.find(msg, "captured") or string.find(msg, "returned") then
        if string.find(msg, "Alliance") or string.find(msg, "alliance") then hordeCarrier = nil end
        if string.find(msg, "Horde") or string.find(msg, "horde") then allyCarrier = nil end
    end

    UpdateDisplay()
end)
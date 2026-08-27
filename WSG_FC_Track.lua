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
-- CLASS COLOR CACHE
-- Stores the class file name for any player we've seen (target,
-- mouseover, focus, nameplate) so that we can still resolve their
-- class color later even if they're no longer in view when the
-- flag pickup message arrives.
-- ============================================================
local classColorCache = {}

local function CacheUnitClass(unit)
    if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return end
    local name = UnitName(unit)
    if not name then return end

    -- Strip the realm name (e.g. "Player-Ragnaros" -> "player")
    local cleanName = string.match(name, "^([^%-]+)") or name
    cleanName = strtrim(cleanName):lower()

    local _, classFileName = UnitClass(unit)
    if classFileName and RAID_CLASS_COLORS[classFileName] then
        classColorCache[cleanName] = classFileName
    end
end

local function ScanAllVisibleUnits()
    CacheUnitClass("target")
    CacheUnitClass("mouseover")
    CacheUnitClass("focus")
    for i = 1, 40 do
        CacheUnitClass("nameplate" .. i)
    end
end

-- ============================================================
-- BATTLEGROUND SCOREBOARD SCAN
-- The built-in BG scoreboard (GetBattlefieldScoreInfo) contains the
-- name and class of every player in the battleground, on both
-- factions, regardless of whether we can currently see them.
-- This is by far the most reliable source for the class cache.
-- ============================================================
local function ScanBattlefieldScores()
    local numScores = GetNumBattlefieldScores and GetNumBattlefieldScores() or 0
    if not numScores or numScores == 0 then return end

    for i = 1, numScores do
        local classToken, name

        if C_PvP and C_PvP.GetScoreInfo then
            -- Newer API (Dragonflight+ / some newer Classic versions):
            -- C_PvP.GetScoreInfo returns a table with a classToken field.
            local info = C_PvP.GetScoreInfo(i)
            if info then
                name = info.name
                classToken = info.classToken
            end
        elseif GetBattlefieldScoreInfo then
            -- Older API. Some clients return a table, others return
            -- plain values, so handle both.
            local info = GetBattlefieldScoreInfo(i)
            if type(info) == "table" then
                name = info.name
                classToken = info.classToken
            else
                -- Plain-value return, roughly:
                -- name, killingBlows, honorableKills, deaths, honorGained,
                -- faction, rank, race, class, classToken, damageDone, healingDone
                local a1, a2, a3, a4, a5, a6, a7, a8, a9, a10 = GetBattlefieldScoreInfo(i)
                name = a1
                classToken = a10 or a9 -- classToken position varies by client version
            end
        end

        if name and classToken and RAID_CLASS_COLORS[classToken] then
            local cleanName = string.match(name, "^([^%-]+)") or name
            cleanName = strtrim(cleanName):lower()
            classColorCache[cleanName] = classToken
        end
    end
end

-- ============================================================
-- HELPER: Get class color of a player (own raid AND enemy)
-- ============================================================
local function GetClassColorOfPlayer(playerName)
    if not playerName or playerName == "" then return nil end

    -- Clean the name: strip the realm suffix (e.g. "Player-Ragnaros" -> "player")
    local cleanTarget = string.match(playerName, "^([^%-]+)") or playerName
    cleanTarget = strtrim(cleanTarget):lower()

    -- 0. CACHE: a previously seen player's class (check this first,
    --    it's the most reliable source since it doesn't depend on
    --    the player being visible right now)
    if classColorCache[cleanTarget] then
        return RAID_CLASS_COLORS[classColorCache[cleanTarget]]
    end

    -- 1. OWN TEAM: if it's a teammate, look them up in the raid roster
    local numGroupMembers = GetNumGroupMembers()
    if numGroupMembers > 0 then
        for i = 1, numGroupMembers do
            local name, _, _, _, _, fileName = GetRaidRosterInfo(i)
            if name then
                local cleanUnit = string.match(name, "^([^%-]+)") or name
                if strtrim(cleanUnit):lower() == cleanTarget then
                    if fileName and RAID_CLASS_COLORS[fileName] then
                        return RAID_CLASS_COLORS[fileName]
                    end
                end
            end
        end
    end

    -- 2. ENEMY: if it's an enemy player, query it from visible units
    local unitsToScan = { "target", "mouseover", "focus" }

    -- Also add nameplates to the list
    for i = 1, 40 do
        table.insert(unitsToScan, "nameplate" .. i)
    end

    for _, unit in ipairs(unitsToScan) do
        if UnitExists(unit) then
            local uName = UnitName(unit)
            if uName then
                local cleanUName = string.match(uName, "^([^%-]+)") or uName
                if strtrim(cleanUName):lower() == cleanTarget then
                    local _, classFileName = UnitClass(unit)
                    if classFileName and RAID_CLASS_COLORS[classFileName] then
                        -- Also cache it while we're here
                        classColorCache[cleanTarget] = classFileName
                        return RAID_CLASS_COLORS[classFileName]
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
eventHandler:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
eventHandler:RegisterEvent("NAME_PLATE_UNIT_ADDED")
eventHandler:RegisterEvent("UPDATE_BATTLEFIELD_SCORE")

-- Periodically ask the server for fresh scoreboard data so the class
-- cache stays populated even for players we've never targeted.
local scoreTicker = CreateFrame("Frame")
local scoreTickerElapsed = 0
scoreTicker:SetScript("OnUpdate", function(self, elapsed)
    scoreTickerElapsed = scoreTickerElapsed + elapsed
    if scoreTickerElapsed >= 15 then -- every 15 seconds
        scoreTickerElapsed = 0
        if IsActiveBattlefieldArena and IsActiveBattlefieldArena() then
            -- skip arenas, this addon is for battlegrounds
        else
            RequestBattlefieldScoreData()
        end
    end
end)

eventHandler:SetScript("OnEvent", function(self, event, msg, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        LoadPositions()
        UpdateDisplay()
        RequestBattlefieldScoreData()
        return
    elseif event == "UPDATE_BATTLEFIELD_SCORE" then
        ScanBattlefieldScores()
        UpdateDisplay()
        return
    elseif event == "PLAYER_TARGET_CHANGED" then
        -- Cache the class of whatever we just targeted, then refresh
        -- the display in case this was the flag carrier.
        CacheUnitClass("target")
        UpdateDisplay()
        CheckAndAnnounceEFCHealth()
        return
    elseif event == "UNIT_HEALTH" then
        local unit = msg
        if unit == "target" then
            CheckAndAnnounceEFCHealth()
        end
        return
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        CacheUnitClass("mouseover")
        UpdateDisplay()
        return
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        -- msg is the unitId for this event, e.g. "nameplate3"
        CacheUnitClass(msg)
        UpdateDisplay()
        return
    end

    if not msg then return end

    -- FIX: the previous pattern "by ([%w%s%-]+)" relied on Lua's %w
    -- character class, which only recognizes plain ASCII letters/digits.
    -- Names containing accented characters (e.g. German umlauts, accents)
    -- are UTF-8 multi-byte sequences whose continuation bytes don't
    -- match %w, so the old pattern truncated those names
    -- (e.g. "Muller" with an umlaut -> just "M").
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

    -- Try to catch the carrier's class immediately in case they're
    -- currently our target/mouseover/on a nameplate.
    ScanAllVisibleUnits()

    UpdateDisplay()
end)
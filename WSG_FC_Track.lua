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
local CHAT_ANNOUNCE_COOLDOWN = 3

-- ============================================================
-- CLASS COLOR CACHE
-- Populated exclusively from the battleground scoreboard
-- (GetBattlefieldScore), which lists every player in the BG on
-- both factions regardless of visibility.
-- ============================================================
local classColorCache = {}

-- Scoreboard names only include the realm suffix for players from a
-- different realm than yours (e.g. "Cheeto-Firemaw"); same-realm
-- players show up as just "Cheeto". Chat messages follow the same
-- rule. Stripping everything after the first "-" normalizes both
-- cases to the same key.
local function CleanName(name)
    if not name or name == "" then return "" end
    local dashPos = string.find(name, "-")
    if dashPos then
        name = string.sub(name, 1, dashPos - 1)
    end
    name = name:gsub("[!%.]", "")
    name = strtrim(name)
    return name
end

-- ============================================================
-- BATTLEGROUND SCOREBOARD SCAN
-- ============================================================
local function ScanBattlefieldScores()
    local numScores = GetNumBattlefieldScores and GetNumBattlefieldScores() or 0
    if not numScores or numScores == 0 then return end

    for i = 1, numScores do
        local name, _, _, _, _, _, _, _, classToken = GetBattlefieldScore(i)

        -- This client returns classToken capitalized like "Druid"
        -- instead of the usual uppercase file token "DRUID", so it
        -- has to be upper-cased before indexing RAID_CLASS_COLORS.
        if classToken then
            classToken = string.upper(classToken)
        end

        if name and classToken and RAID_CLASS_COLORS[classToken] then
            classColorCache[CleanName(name)] = classToken
        end
    end
end

local function GetClassColorOfPlayer(playerName)
    if not playerName or playerName == "" then return nil end

    local cleanTarget = CleanName(playerName)

    if classColorCache[cleanTarget] then
        return RAID_CLASS_COLORS[classColorCache[cleanTarget]]
    end

    local numScores = GetNumBattlefieldScores and GetNumBattlefieldScores() or 0
    for i = 1, numScores do
        local name, _, _, _, _, _, _, _, classToken = GetBattlefieldScore(i)
        if classToken then
            classToken = string.upper(classToken)
        end
        if name and classToken and RAID_CLASS_COLORS[classToken] then
            local cleanName = CleanName(name)
            if cleanName == cleanTarget then
                classColorCache[cleanTarget] = classToken
                return RAID_CLASS_COLORS[classToken]
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
    if allyCarrier then
        allyText:SetText(allyCarrier)
        local color = GetClassColorOfPlayer(allyCarrier) or DEFAULT_ALLY_COLOR
        allyText:SetTextColor(color.r, color.g, color.b)
    else
        allyText:SetText("")
    end

    if hordeCarrier then
        hordeText:SetText(hordeCarrier)
        local color = GetClassColorOfPlayer(hordeCarrier) or DEFAULT_HORDE_COLOR
        hordeText:SetTextColor(color.r, color.g, color.b)
    else
        hordeText:SetText("")
    end
end

-- Called when we detect we've actually left the battleground
-- (PLAYER_ENTERING_WORLD with instanceType ~= "pvp"), so a stale
-- carrier name/color doesn't linger into the next zone.
local function ResetCarrierState()
    allyCarrier = nil
    hordeCarrier = nil
    classColorCache = {}
    UpdateDisplay()
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
        local cleanTargetName = CleanName(targetName)
        local cleanEnemyFC = CleanName(enemyFC)

        if cleanTargetName == cleanEnemyFC then
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
eventHandler:RegisterEvent("UPDATE_BATTLEFIELD_SCORE")

-- Periodic fallback in case UPDATE_BATTLEFIELD_SCORE doesn't fire
-- promptly after a flag pickup (server-side throttling).
local scoreTicker = CreateFrame("Frame")
local scoreTickerElapsed = 0
scoreTicker:SetScript("OnUpdate", function(self, elapsed)
    scoreTickerElapsed = scoreTickerElapsed + elapsed
    if scoreTickerElapsed >= 5 then
        scoreTickerElapsed = 0
        if not (IsActiveBattlefieldArena and IsActiveBattlefieldArena()) then
            RequestBattlefieldScoreData()
        end
    end
end)

eventHandler:SetScript("OnEvent", function(self, event, msg, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        LoadPositions()
        local _, instanceType = GetInstanceInfo()
        if instanceType ~= "pvp" then
            ResetCarrierState()
        else
            UpdateDisplay()
            RequestBattlefieldScoreData()
        end
        return
    elseif event == "UPDATE_BATTLEFIELD_SCORE" then
        ScanBattlefieldScores()
        UpdateDisplay()
        return
    elseif event == "PLAYER_TARGET_CHANGED" then
        CheckAndAnnounceEFCHealth()
        return
    elseif event == "UNIT_HEALTH" then
        if msg == "target" then
            CheckAndAnnounceEFCHealth()
        end
        return
    end

    if not msg then return end

    local name = string.match(msg, "by ([^!%.]+)")

    if name then
        name = CleanName(name)

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

    if not (IsActiveBattlefieldArena and IsActiveBattlefieldArena()) then
        RequestBattlefieldScoreData()
    end

    UpdateDisplay()
end)
-- Maelstrom Tracker: a tiny WeakAura-style display for Maelstrom Weapon stacks.
--
-- WoW Forever blocks addons from reading auras in combat ("secret" auras).
-- So we use two sources:
--   1. The aura itself, whenever the game allows reading it (out of combat).
--   2. Lightning Bolt's cast time: each Maelstrom stack cuts it by 20%,
--      so at 5 stacks it is 0 (instant). Spell info isn't aura data.

local ADDON = ...
local MAX_STACKS = 5
local SIZE = 48
local PER_STACK = 0.20

-- Maelstrom Weapon buff IDs: Forever 408505, Wrath 53817, retail 344179.
local SPELL_IDS = { 408505, 53817, 344179 }
local FALLBACK_ICON = 237584

-- Spells Maelstrom makes faster; the first one the player knows is the probe.
local PROBE_SPELLS = { 403, 421, 331, 8004, 1064 } -- LB, CL, HW, LHW, CH

local _, playerClass = UnitClass("player")
if playerClass ~= "SHAMAN" then return end

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return GetSpellInfo and (GetSpellInfo(id))
end

local buffName = SpellName(408505) or SpellName(53817)

---------------------------------------------------------------------------
-- Source 1: the aura (only when not secret)
---------------------------------------------------------------------------
local function AurasLocked()
    return C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() == true
end

-- Returns aura (or false if none) when readable; nil when the game blocks it.
local function ReadAura()
    if AurasLocked() then return nil end
    for _, id in ipairs(SPELL_IDS) do
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
        if not ok then return nil end
        if aura then return aura end
    end
    if buffName and C_UnitAuras.GetAuraDataBySpellName then
        local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", buffName, "HELPFUL")
        if not ok then return nil end
        if aura then return aura end
    end
    return false
end

---------------------------------------------------------------------------
-- Source 2: Lightning Bolt cast time
---------------------------------------------------------------------------
local baseCast -- cast time (ms) of the probe spell with 0 stacks
local talentRank, talentMax -- Maelstrom Weapon talent points (nil if unknown)
local learnedPerStack       -- fallback: per-stack reduction observed from the aura

-- Find the Maelstrom Weapon talent in the talent trees (classic-style API).
local function UpdateTalent()
    talentRank, talentMax = nil, nil
    if not (GetNumTalentTabs and GetNumTalents and GetTalentInfo and buffName) then return end
    local ok = pcall(function()
        for tab = 1, GetNumTalentTabs() do
            for i = 1, GetNumTalents(tab) do
                local name, _, _, _, rank, maxRank = GetTalentInfo(tab, i)
                if name == buffName then
                    talentRank, talentMax = rank or 0, maxRank or 5
                    return
                end
            end
        end
    end)
    if not ok then talentRank, talentMax = nil, nil end
end

-- Cast-time reduction per stack: 20% at full talent, scaled by points spent.
local function PerStack()
    if talentRank and talentMax and talentMax > 0 then
        return PER_STACK * talentRank / talentMax
    end
    return learnedPerStack or PER_STACK
end

local function ProbeCastTime()
    for _, id in ipairs(PROBE_SPELLS) do
        local name = SpellName(id)
        if name then
            -- Looking up by name returns the player's highest known rank.
            local ok, info = pcall(C_Spell.GetSpellInfo, name)
            if ok and info and info.castTime ~= nil and not IsSecret(info.castTime) then
                return info.castTime
            end
        end
    end
end

-- Calibration: real cast-time ratios (cast / 0-stack cast) observed per stack
-- count while the aura is readable, saved per talent rank.
local function CalibTable()
    if not MaelstromTrackerDB then return nil end
    MaelstromTrackerDB.calib = MaelstromTrackerDB.calib or {}
    local key = tostring(talentRank or "unknown")
    MaelstromTrackerDB.calib[key] = MaelstromTrackerDB.calib[key] or {}
    return MaelstromTrackerDB.calib[key]
end

local function ExpectedRatio(s)
    if s == 0 then return 1 end
    local t = CalibTable()
    if t and t[s] then return t[s] end
    return 1 - PerStack() * s
end

local function StacksFromCastTime()
    local cast = ProbeCastTime()
    if not cast or not baseCast or baseCast <= 0 then return nil end
    if PerStack() <= 0 and not (CalibTable() or {})[1] then return nil end
    local ratio = cast / baseCast
    -- Pick the stack count whose expected ratio is closest to what we see.
    local best, bestDiff = 0, math.huge
    for s = 0, MAX_STACKS do
        local d = math.abs(ratio - ExpectedRatio(s))
        if d < bestDiff then best, bestDiff = s, d end
    end
    return best
end

-- While the aura is readable: learn the 0-stack cast time (handles haste)
-- and record the real ratio for the current stack count.
local zeroStackBase -- base measured directly with no stacks up
local function LearnBaseCast(stacks)
    local cast = ProbeCastTime()
    if not cast then return end
    if stacks == 0 then
        if cast > 0 then baseCast, zeroStackBase = cast, cast end
        return
    end
    if zeroStackBase and zeroStackBase > 0 then
        local ratio = cast / zeroStackBase
        local t = CalibTable()
        if t and stacks <= MAX_STACKS then t[stacks] = ratio end
        if not talentRank then
            local per = (1 - ratio) / stacks
            if per > 0 then learnedPerStack = per end
        end
        baseCast = zeroStackBase
    else
        local factor = ExpectedRatio(stacks)
        if factor > 0.01 and cast > 0 then baseCast = cast / factor end
    end
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------
local f = CreateFrame("Frame", "MaelstromTrackerFrame", UIParent)
f:SetSize(SIZE, SIZE)
f:SetFrameStrata("MEDIUM")
f:SetClampedToScreen(true)
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")

-- Visuals live on a child frame; opacity is applied to f.
local body = CreateFrame("Frame", nil, f)
body:SetAllPoints()

f.border = body:CreateTexture(nil, "BACKGROUND")
f.border:SetPoint("TOPLEFT", -2, 2)
f.border:SetPoint("BOTTOMRIGHT", 2, -2)
f.border:SetColorTexture(0, 0, 0, 1)

f.icon = body:CreateTexture(nil, "ARTWORK")
f.icon:SetAllPoints()
f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
f.icon:SetTexture(FALLBACK_ICON)

f.cd = CreateFrame("Cooldown", nil, body, "CooldownFrameTemplate")
f.cd:SetAllPoints()
f.cd:SetDrawEdge(false)
f.cd:SetHideCountdownNumbers(true)

local overlay = CreateFrame("Frame", nil, body)
overlay:SetAllPoints()
overlay:SetFrameLevel(f.cd:GetFrameLevel() + 2)

f.count = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalHuge")
f.count:SetPoint("CENTER")

-- 5-stack glow: custom texture (Media/glow.tga, made by tools/make_glow.py).
-- The icon fills the centre half of the texture, so draw it at 2x icon size.
f.glow = overlay:CreateTexture(nil, "OVERLAY")
f.glow:SetTexture("Interface\\AddOns\\MaelstromTracker\\Media\\glow.tga")
f.glow:SetPoint("CENTER")
f.glow:SetSize(SIZE * 2, SIZE * 2)
f.glow:Hide()

-- Slow blink on the glow only; the icon itself stays solid.
local blink = f.glow:CreateAnimationGroup()
blink:SetLooping("BOUNCE")
local fade = blink:CreateAnimation("Alpha")
fade:SetFromAlpha(1)
fade:SetToAlpha(0.2)
fade:SetDuration(0.8)
fade:SetSmoothing("IN_OUT")
blink:SetScript("OnStop", function() f.glow:SetAlpha(1) end)

---------------------------------------------------------------------------
-- Screen edge glow: gradient strips along each screen edge. Each strip spans
-- the full edge, so they overlap in the corners instead of leaving gaps.
---------------------------------------------------------------------------
local screenGlow = CreateFrame("Frame", "MaelstromTrackerScreenGlow", UIParent)
screenGlow:SetAllPoints(UIParent)
screenGlow:SetFrameStrata("BACKGROUND")
screenGlow:EnableMouse(false)
screenGlow:Hide()

-- opaqueAtMin: gradient runs min -> max (left->right, bottom->top).
local edges = {}
local function EdgeStrip(orientation, opaqueAtMin, a1, a2, horizontal)
    local t = screenGlow:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(1, 1, 1, 1)
    t:SetPoint(a1); t:SetPoint(a2)
    edges[#edges + 1] = { tex = t, orientation = orientation,
                          opaqueAtMin = opaqueAtMin, horizontal = horizontal }
end
EdgeStrip("VERTICAL", false, "TOPLEFT", "TOPRIGHT", true)        -- top
EdgeStrip("VERTICAL", true, "BOTTOMLEFT", "BOTTOMRIGHT", true)   -- bottom
EdgeStrip("HORIZONTAL", true, "TOPLEFT", "BOTTOMLEFT", false)    -- left
EdgeStrip("HORIZONTAL", false, "TOPRIGHT", "BOTTOMRIGHT", false) -- right

-- Apply colors, depth and strength from the saved settings.
local function ApplyLooks()
    local db = MaelstromTrackerDB
    local c = db.glowColor
    f.glow:SetVertexColor(c.r, c.g, c.b)
    local s = db.screenColor
    local solid = CreateColor(s.r, s.g, s.b, db.screenStrength)
    local clear = CreateColor(s.r, s.g, s.b, 0)
    for _, e in ipairs(edges) do
        if e.opaqueAtMin then e.tex:SetGradient(e.orientation, solid, clear)
        else e.tex:SetGradient(e.orientation, clear, solid) end
        if e.horizontal then e.tex:SetHeight(db.screenDepth) else e.tex:SetWidth(db.screenDepth) end
    end
end

local screenBlink = screenGlow:CreateAnimationGroup()
screenBlink:SetLooping("BOUNCE")
local sFade = screenBlink:CreateAnimation("Alpha")
sFade:SetFromAlpha(1)
sFade:SetToAlpha(0.2)
sFade:SetDuration(0.8)
sFade:SetSmoothing("IN_OUT")
screenBlink:SetScript("OnStop", function() screenGlow:SetAlpha(1) end)

local DEFAULTS = { showEmpty = true, opacity = 1, glow = true, locked = false,
                   screenGlow = false, scale = 1,
                   screenDepth = 90, screenStrength = 0.55,
                   glowColor = { r = 0.8, g = 1, b = 1 },
                   screenColor = { r = 0.8, g = 1, b = 1 } }
local settingsOpen = false -- always show the icon while positioning in settings

---------------------------------------------------------------------------
-- Position
---------------------------------------------------------------------------
f:SetScript("OnDragStart", function(self)
    if not MaelstromTrackerDB.locked then self:StartMoving() end
end)
f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    MaelstromTrackerDB.pos = { point, relPoint, x, y }
end)

local function RestorePosition()
    f:ClearAllPoints()
    local p = MaelstromTrackerDB.pos
    if p then
        f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, -150 / f:GetScale())
    end
end

-- Change scale while keeping the icon's centre in the same spot on screen.
local function SetScale(scale)
    local cx, cy = f:GetCenter()
    local old = f:GetScale()
    f:SetScale(scale)
    MaelstromTrackerDB.scale = scale
    if cx and MaelstromTrackerDB.pos then
        local x, y = cx * old / scale, cy * old / scale
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
        MaelstromTrackerDB.pos = { "CENTER", "BOTTOMLEFT", x, y }
    else
        RestorePosition()
    end
end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------
local lastSource = "none"

local function Update()
    local stacks, aura
    local readAura = ReadAura()

    if readAura ~= nil then
        aura = readAura or nil
        stacks = aura and (aura.applications or 0) or 0
        if aura and stacks == 0 then stacks = 1 end
        LearnBaseCast(stacks)
        lastSource = "aura"
    else
        stacks = StacksFromCastTime()
        lastSource = stacks and "cast time" or "none"
    end

    if aura and aura.icon then f.icon:SetTexture(aura.icon) end

    if stacks and stacks > 0 then
        f.count:SetText(stacks)
        f.icon:SetDesaturated(false)
        f.icon:SetAlpha(1)
    else
        f.count:SetText("")
        f.icon:SetDesaturated(true)
        f.icon:SetAlpha(0.4)
    end

    -- Duration swipe only when we can actually read the aura.
    if aura and aura.duration and aura.duration > 0 then
        f.cd:SetCooldown(aura.expirationTime - aura.duration, aura.duration)
    elseif readAura ~= nil then
        f.cd:Clear()
    end
    if not stacks or stacks == 0 then f.cd:Clear() end

    local db = MaelstromTrackerDB or DEFAULTS
    f:SetShown((stacks and stacks > 0) or db.showEmpty or settingsOpen)
    f:SetAlpha(db.opacity)

    local atMax = stacks and stacks >= MAX_STACKS
    f.count:SetTextColor(atMax and 0.4 or 1, atMax and 0.9 or 1, 1)

    -- Glows show at max stacks, or as a preview while settings are open.
    local glowOn = (atMax or settingsOpen) and db.glow
    f.glow:SetShown(glowOn)
    if glowOn and not blink:IsPlaying() then blink:Play() end
    if not glowOn and blink:IsPlaying() then blink:Stop() end

    local edge = (atMax or settingsOpen) and db.screenGlow
    screenGlow:SetShown(edge)
    if edge and not screenBlink:IsPlaying() then screenBlink:Play() end
    if not edge and screenBlink:IsPlaying() then screenBlink:Stop() end
end

f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterUnitEvent("UNIT_AURA", "player")
for _, e in ipairs({ "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "SPELLS_CHANGED" }) do
    pcall(f.RegisterEvent, f, e)
end
f:SetScript("OnEvent", function(self, event, arg1)
    if event ~= "UNIT_AURA" and event ~= "ADDON_LOADED" then
        UpdateTalent()
    end
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        MaelstromTrackerDB = MaelstromTrackerDB or {}
        for k, v in pairs(DEFAULTS) do
            if MaelstromTrackerDB[k] == nil then
                MaelstromTrackerDB[k] = type(v) == "table" and CopyTable(v) or v
            end
        end
        ApplyLooks()
        if MaelstromTrackerDB.locked then f:EnableMouse(false) end
        f:SetScale(MaelstromTrackerDB.scale)
        RestorePosition()
        self:UnregisterEvent("ADDON_LOADED")
        -- Poll too: cast time changes don't fire UNIT_AURA we can read.
        C_Timer.NewTicker(0.1, Update)
    end
    Update()
end)

---------------------------------------------------------------------------
-- Settings window
---------------------------------------------------------------------------
local function SetLocked(locked)
    MaelstromTrackerDB.locked = locked
    f:EnableMouse(not locked)
end

local settings
local function CreateSettings()
    local ok, win = pcall(CreateFrame, "Frame", "MaelstromTrackerSettings", UIParent, "BasicFrameTemplateWithInset")
    if not ok then
        win = CreateFrame("Frame", "MaelstromTrackerSettings", UIParent)
        local bg = win:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.05, 0.05, 0.08, 0.92)
        local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 2, 2)
    end
    win:SetSize(500, 330)
    win:SetPoint("CENTER")
    win:SetFrameStrata("HIGH") -- below the color picker (DIALOG)
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:Hide()
    tinsert(UISpecialFrames, "MaelstromTrackerSettings") -- Esc closes it

    local title = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -5)
    title:SetText("Maelstrom Tracker")

    -- Layout cursor: x = column, y = next row.
    local x, y = 0, 0
    local function Column(colX, heading)
        x, y = colX, -34
        local h = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        h:SetPoint("TOPLEFT", x + 18, y)
        h:SetText(heading)
        y = y - 20
    end

    local function Checkbox(label, key, onChange)
        local cb = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
        cb:SetSize(26, 26)
        cb:SetPoint("TOPLEFT", x + 14, y)
        local text = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("LEFT", cb, "RIGHT", 4, 1)
        text:SetText(label)
        cb:SetScript("OnShow", function(self) self:SetChecked(MaelstromTrackerDB[key]) end)
        cb:SetScript("OnClick", function(self)
            local v = self:GetChecked() and true or false
            if onChange then onChange(v) else MaelstromTrackerDB[key] = v end
            Update()
        end)
        y = y - 30
        return cb
    end

    -- Sliders built by hand; slider templates differ between clients.
    -- mult: how the value is shown (100 = percent, 1 = raw).
    local function Slider(fmt, key, min, max, step, onChange, mult)
        mult = mult or 100
        local label = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", x + 18, y - 6)
        local slider = CreateFrame("Slider", nil, win)
        slider:SetOrientation("HORIZONTAL")
        slider:SetSize(200, 16)
        slider:SetPoint("TOPLEFT", x + 22, y - 26)
        slider:SetMinMaxValues(min, max)
        slider:SetValueStep(step)
        slider:SetObeyStepOnDrag(true)
        slider:EnableMouse(true)
        local track = slider:CreateTexture(nil, "BACKGROUND")
        track:SetPoint("LEFT")
        track:SetPoint("RIGHT")
        track:SetHeight(6)
        track:SetColorTexture(0.25, 0.25, 0.3, 1)
        slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        local ready = false -- ignore the SetValue fired from OnShow
        slider:SetScript("OnValueChanged", function(self, v)
            v = math.floor(v / step + 0.5) * step
            label:SetText(fmt:format(v * mult))
            if not ready then return end
            if onChange then onChange(v) else MaelstromTrackerDB[key] = v end
            Update()
        end)
        slider:SetScript("OnShow", function(self)
            ready = false
            self:SetValue(MaelstromTrackerDB[key])
            label:SetText(fmt:format(MaelstromTrackerDB[key] * mult))
            ready = true
        end)
        y = y - 50
    end

    -- Color swatch that opens Blizzard's color picker.
    local function OpenColorPicker(c, onChange)
        local prev = { r = c.r, g = c.g, b = c.b }
        local function apply(r, g, b) c.r, c.g, c.b = r, g, b; onChange() end
        local function picked() apply(ColorPickerFrame:GetColorRGB()) end
        local function cancel() apply(prev.r, prev.g, prev.b) end
        if ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow({ r = c.r, g = c.g, b = c.b,
                hasOpacity = false, swatchFunc = picked, cancelFunc = cancel })
        else -- older API
            ColorPickerFrame.hasOpacity = false
            ColorPickerFrame.previousValues = prev
            ColorPickerFrame.func, ColorPickerFrame.cancelFunc = picked, cancel
            ColorPickerFrame:SetColorRGB(c.r, c.g, c.b)
            ColorPickerFrame:Hide()
            ColorPickerFrame:Show()
        end
    end

    local function ColorSwatch(label, key)
        local btn = CreateFrame("Button", nil, win)
        btn:SetSize(22, 22)
        btn:SetPoint("TOPLEFT", x + 18, y - 2)
        local edge = btn:CreateTexture(nil, "BACKGROUND")
        edge:SetAllPoints()
        edge:SetColorTexture(0.8, 0.8, 0.8, 1)
        local fill = btn:CreateTexture(nil, "ARTWORK")
        fill:SetPoint("TOPLEFT", 2, -2)
        fill:SetPoint("BOTTOMRIGHT", -2, 2)
        local text = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("LEFT", btn, "RIGHT", 8, 0)
        text:SetText(label)
        local function refresh()
            local c = MaelstromTrackerDB[key]
            fill:SetColorTexture(c.r, c.g, c.b, 1)
        end
        btn:SetScript("OnShow", refresh)
        btn:SetScript("OnClick", function()
            OpenColorPicker(MaelstromTrackerDB[key], function()
                refresh(); ApplyLooks(); Update()
            end)
        end)
        y = y - 30
    end

    local function Looks(key) return function(v) MaelstromTrackerDB[key] = v; ApplyLooks() end end

    Column(0, "Icon")
    Checkbox("Show with no stacks", "showEmpty")
    Checkbox("Lock position", "locked", SetLocked)
    Checkbox("Glow at 5 stacks", "glow")
    ColorSwatch("Glow color", "glowColor")
    Slider("Opacity: %d%%", "opacity", 0.1, 1, 0.05)
    Slider("Scale: %d%%", "scale", 0.5, 2.5, 0.05, SetScale)

    Column(250, "Screen edge glow")
    Checkbox("Enable at 5 stacks", "screenGlow")
    ColorSwatch("Color", "screenColor")
    Slider("Depth: %d px", "screenDepth", 20, 300, 5, Looks("screenDepth"), 1)
    Slider("Strength: %d%%", "screenStrength", 0.05, 1, 0.05, Looks("screenStrength"))

    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", x + 18, y - 4)
    hint:SetWidth(220)
    hint:SetJustifyH("LEFT")
    hint:SetText("Enabled glows are previewed while this window is open.")

    local reset = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    reset:SetSize(120, 22)
    reset:SetPoint("BOTTOM", 0, 12)
    reset:SetText("Reset position")
    reset:SetScript("OnClick", function()
        MaelstromTrackerDB.pos = nil
        RestorePosition()
    end)

    win:SetScript("OnShow", function() settingsOpen = true; Update() end)
    win:SetScript("OnHide", function() settingsOpen = false; Update() end)
    return win
end

local function ToggleSettings()
    settings = settings or CreateSettings()
    settings:SetShown(not settings:IsShown())
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function P(...) print("|cff33ccffMaelstrom Tracker|r", ...) end
local function Show(v) return IsSecret(v) and "<secret>" or tostring(v) end

SLASH_MAELSTROMTRACKER1 = "/mwt"
SlashCmdList.MAELSTROMTRACKER = function(msg)
    msg = strtrim((msg or ""):lower())
    if msg == "" or msg == "config" or msg == "options" then
        ToggleSettings()
    elseif msg == "lock" then
        SetLocked(true)
        P("locked.")
    elseif msg == "unlock" then
        SetLocked(false)
        P("unlocked - drag to move.")
    elseif msg == "reset" then
        MaelstromTrackerDB.pos = nil
        RestorePosition()
        P("position reset.")
    elseif msg == "debug" then
        local a = ReadAura()
        P("debug")
        print("  in combat:", tostring(InCombatLockdown()), " auras locked:", tostring(AurasLocked()))
        if a == nil then
            print("  aura: blocked by game")
        elseif a == false then
            print("  aura: not found")
        else
            print("  aura: id=" .. Show(a.spellId), "stacks=" .. Show(a.applications))
        end
        print("  probe cast time:", Show(ProbeCastTime()), " base:", tostring(baseCast))
        print("  cast-time stacks:", tostring(StacksFromCastTime()), " source used:", lastSource)
        print("  talent:", talentRank and (talentRank .. "/" .. talentMax) or "not found",
              " per stack:", ("%.0f%%"):format(PerStack() * 100),
              talentRank and "" or (learnedPerStack and "(learned)" or "(default)"))
        local cast = ProbeCastTime()
        if cast and baseCast then print(("  ratio now: %.3f"):format(cast / baseCast)) end
        local t, parts = CalibTable() or {}, {}
        for s = 1, MAX_STACKS do
            parts[#parts + 1] = s .. "=" .. (t[s] and ("%.3f"):format(t[s]) or ("~%.3f"):format(ExpectedRatio(s)))
        end
        print("  expected ratios (~ = formula, not yet measured):", table.concat(parts, " "))
    elseif msg == "recalibrate" then
        if MaelstromTrackerDB then MaelstromTrackerDB.calib = nil end
        P("calibration cleared.")
    else
        P("/mwt (settings) | lock | unlock | reset | debug | recalibrate")
    end
end

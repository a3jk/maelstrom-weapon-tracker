-- Maelstrom Tracker: a tiny WeakAura-style display for Maelstrom Weapon stacks.
--
-- WoW Forever hides aura data from addons in combat ("secret" values), so we
-- never read the stack count ourselves. Instead we hand our widgets to the
-- game's own aura display (CustomAuraContainerTemplate, Blizzard_AuraContainer)
-- and let it fill them in:
--   * the icon, the duration sweep and the stack count text;
--   * an "application bar" with a minimum of 5 stacks, which the game hides
--     below 5. The 5-stack glows are children of such bars, so they only show
--     at 5 stacks, in combat too.
-- Our own code only touches these widgets out of combat.

local ADDON = ...
local MAX_STACKS = 5
local SIZE = 48
local MAX_COLOR = "|cff66e6ff" -- stack count color at 5 stacks

-- Maelstrom Weapon buff IDs: Forever 408505, Wrath 53817, retail 344179.
local SPELL_IDS = { 408505, 53817, 344179 }
local FALLBACK_ICON = 237584
local GLOW_TEXTURE = "Interface\\AddOns\\MaelstromTracker\\Media\\glow.tga"

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

local function AurasLocked()
    return C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() == true
end

-- Only used out of combat (icon texture) and by /mwt debug.
-- Returns the aura, or false if the buff isn't up, or nil if the game blocks it.
local function ReadAura()
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

local function Border(parent)
    local t = parent:CreateTexture(nil, "BACKGROUND")
    t:SetPoint("TOPLEFT", -2, 2)
    t:SetPoint("BOTTOMRIGHT", 2, -2)
    t:SetColorTexture(0, 0, 0, 1)
end

-- Shown when the buff is down (if "show with no stacks" is on); the game's
-- aura button covers it while the buff is up.
local empty = CreateFrame("Frame", nil, body)
empty:SetAllPoints()
Border(empty)
f.icon = empty:CreateTexture(nil, "ARTWORK")
f.icon:SetAllPoints()
f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
f.icon:SetTexture(FALLBACK_ICON)
f.icon:SetDesaturated(true)
f.icon:SetAlpha(0.4)

-- Slow alpha blink (looping) on a region.
local function Blink(region)
    local group = region:CreateAnimationGroup()
    group:SetLooping("BOUNCE")
    local fade = group:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.2)
    fade:SetDuration(0.8)
    fade:SetSmoothing("IN_OUT")
    return group
end

-- Icon glow texture (Media/glow.tga, made by tools/make_glow.py). The icon
-- fills the centre half of the texture, so draw it at 2x icon size.
local glows = {}
local function IconGlow(parent)
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetTexture(GLOW_TEXTURE)
    t:SetPoint("CENTER")
    t:SetSize(SIZE * 2, SIZE * 2)
    glows[#glows + 1] = t
    return t
end

-- Screen edge glow: gradient strips along each screen edge. Each strip spans
-- the full edge, so they overlap in the corners instead of leaving gaps.
-- opaqueAtMin: gradient runs min -> max (left->right, bottom->top).
local edges = {}
local function EdgeStrips(parent)
    local function Strip(orientation, opaqueAtMin, a1, a2, horizontal)
        local t = parent:CreateTexture(nil, "ARTWORK")
        t:SetColorTexture(1, 1, 1, 1)
        t:SetPoint(a1); t:SetPoint(a2)
        edges[#edges + 1] = { tex = t, orientation = orientation,
                              opaqueAtMin = opaqueAtMin, horizontal = horizontal }
    end
    Strip("VERTICAL", false, "TOPLEFT", "TOPRIGHT", true)        -- top
    Strip("VERTICAL", true, "BOTTOMLEFT", "BOTTOMRIGHT", true)   -- bottom
    Strip("HORIZONTAL", true, "TOPLEFT", "BOTTOMLEFT", false)    -- left
    Strip("HORIZONTAL", false, "TOPRIGHT", "BOTTOMRIGHT", false) -- right
end

-- Previews, shown while the settings window is open.
local previewOverlay = CreateFrame("Frame", nil, body)
previewOverlay:SetAllPoints()
previewOverlay:SetFrameLevel(body:GetFrameLevel() + 20)
local previewGlow = IconGlow(previewOverlay)
local previewBlink = Blink(previewGlow)
previewBlink:SetScript("OnStop", function() previewGlow:SetAlpha(1) end)

local previewScreen = CreateFrame("Frame", "MaelstromTrackerScreenGlow", UIParent)
previewScreen:SetAllPoints(UIParent)
previewScreen:SetFrameStrata("BACKGROUND")
previewScreen:EnableMouse(false)
previewScreen:Hide()
EdgeStrips(previewScreen)
local previewScreenBlink = Blink(previewScreen)
previewScreenBlink:SetScript("OnStop", function() previewScreen:SetAlpha(1) end)

---------------------------------------------------------------------------
-- Game-driven display (Blizzard_AuraContainer)
---------------------------------------------------------------------------
local native = { built = false } -- iconContainer, screenContainer, iconGlow, error

local function SpellSet()
    local set = {}
    for _, id in ipairs(SPELL_IDS) do set[id] = true end
    return set
end

-- Stack count text: the number from 1 stack, colored at 5.
local function CountFormatter()
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then return nil end
    local ok, fmt = pcall(C_StringUtil.CreateNumericRuleFormatter)
    if not ok or not fmt then return nil end
    local R = (Enum and Enum.NumericRuleFormatRounding) or {}
    local down = R.Down or 2
    ok = pcall(fmt.SetBreakpoints, fmt, {
        { threshold = 0, format = "" },
        { threshold = 1, step = 1, rounding = down, format = "%d" },
        { threshold = MAX_STACKS, step = 1, rounding = down, format = MAX_COLOR .. "%d|r" },
    })
    return ok and fmt or nil
end

-- A status bar the game shows only at max stacks. Its fill is invisible; it
-- only exists so its children (our glows) follow its visibility.
local function MaxStackBar(button)
    local bar = CreateFrame("StatusBar", nil, button)
    bar:SetAllPoints(button)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:SetStatusBarColor(0, 0, 0, 0)
    local I = Enum and Enum.StatusBarInterpolation
    button:SetApplicationBar(bar, { minApplications = MAX_STACKS, maxApplications = MAX_STACKS,
                                    interpolation = I and I.Immediate })
    return bar
end

local function NoMouse(button)
    pcall(button.SetMouseClickEnabled, button, false)
    pcall(button.EnableMouseMotion, button, false)
    pcall(button.EnableMouse, button, false)
end

local function NewContainer(parent)
    local c = CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")
    c:SetAllPoints(parent)
    c:SetUnit("player")
    return c
end

local function BuildIcon()
    local c = NewContainer(body)
    c:AddAuraSlot("maelstrom", "HELPFUL", {
        candidateFilters = { includeSpellIDs = SpellSet() },
        initializeFrame = function(button)
            button:ClearAllPoints()
            button:SetAllPoints(c)
            NoMouse(button)
            Border(button)

            local icon = button:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints()
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            button:SetIcon(icon)

            local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
            cd:SetAllPoints()
            cd:SetDrawEdge(false)
            cd:SetHideCountdownNumbers(true)
            button:SetDurationCooldown(cd)

            local bar = MaxStackBar(button)
            bar:SetFrameLevel(cd:GetFrameLevel() + 2)
            native.iconGlow = IconGlow(bar)
            Blink(native.iconGlow):Play() -- loops forever; only visible at 5 stacks

            local overlay = CreateFrame("Frame", nil, button)
            overlay:SetAllPoints()
            overlay:SetFrameLevel(bar:GetFrameLevel() + 2)
            local count = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalHuge")
            count:SetPoint("CENTER")
            local fmt = CountFormatter()
            button:SetApplicationCount(count, fmt and { formatter = fmt } or nil)
        end,
    })
    native.iconContainer = c
end

local function BuildScreen()
    -- Own container on UIParent, so the icon's scale and opacity don't apply.
    local host = CreateFrame("Frame", nil, UIParent)
    host:SetAllPoints(UIParent)
    host:SetFrameStrata("BACKGROUND")
    host:EnableMouse(false)
    local c = NewContainer(host)
    c:AddAuraSlot("maelstromScreen", "HELPFUL", {
        candidateFilters = { includeSpellIDs = SpellSet() },
        initializeFrame = function(button)
            button:ClearAllPoints()
            button:SetAllPoints(c)
            NoMouse(button)
            local bar = MaxStackBar(button)
            local strips = CreateFrame("Frame", nil, bar)
            strips:SetAllPoints(bar)
            EdgeStrips(strips)
            Blink(strips):Play()
        end,
    })
    native.screenContainer = c
end

-- Builds the game-driven display. Must run while auras aren't secret
-- (out of combat): the game locks aura buttons from addons otherwise.
local function BuildNative()
    if native.built or AurasLocked() then return end
    native.built = true
    local ok, err = pcall(BuildIcon)
    if ok then ok, err = pcall(BuildScreen) end
    if not ok then
        native.error = tostring(err)
        print("|cff33ccffMaelstrom Tracker|r could not set up the game's aura display:", native.error)
    end
end

-- Apply colors, depth and strength from the saved settings.
local function ApplyLooks()
    local db = MaelstromTrackerDB
    local c = db.glowColor
    for _, t in ipairs(glows) do pcall(t.SetVertexColor, t, c.r, c.g, c.b) end
    local s = db.screenColor
    local solid = CreateColor(s.r, s.g, s.b, db.screenStrength)
    local clear = CreateColor(s.r, s.g, s.b, 0)
    for _, e in ipairs(edges) do
        local t = e.tex
        if e.opaqueAtMin then pcall(t.SetGradient, t, e.orientation, solid, clear)
        else pcall(t.SetGradient, t, e.orientation, clear, solid) end
        if e.horizontal then pcall(t.SetHeight, t, db.screenDepth)
        else pcall(t.SetWidth, t, db.screenDepth) end
    end
end

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
-- Update (settings and out-of-combat state only; stacks are drawn by the game)
---------------------------------------------------------------------------
local function Update()
    BuildNative()
    local db = MaelstromTrackerDB or DEFAULTS

    -- Learn the real icon while we can read the aura.
    local aura = not AurasLocked() and ReadAura()
    if aura and aura.icon and not IsSecret(aura.icon) then f.icon:SetTexture(aura.icon) end

    f:SetAlpha(db.opacity)
    empty:SetShown(db.showEmpty or settingsOpen)

    if native.iconGlow then pcall(native.iconGlow.SetShown, native.iconGlow, db.glow) end
    if native.screenContainer then
        pcall(native.screenContainer.SetAuraSlotEnabled, native.screenContainer,
              "maelstromScreen", db.screenGlow)
    end

    local glowPreview = settingsOpen and db.glow
    previewGlow:SetShown(glowPreview)
    if glowPreview and not previewBlink:IsPlaying() then previewBlink:Play() end
    if not glowPreview and previewBlink:IsPlaying() then previewBlink:Stop() end

    local edgePreview = settingsOpen and db.screenGlow
    previewScreen:SetShown(edgePreview)
    if edgePreview and not previewScreenBlink:IsPlaying() then previewScreenBlink:Play() end
    if not edgePreview and previewScreenBlink:IsPlaying() then previewScreenBlink:Stop() end
end

f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        MaelstromTrackerDB = MaelstromTrackerDB or {}
        MaelstromTrackerDB.calib = nil -- leftover from the old cast-time workaround
        for k, v in pairs(DEFAULTS) do
            if MaelstromTrackerDB[k] == nil then
                MaelstromTrackerDB[k] = type(v) == "table" and CopyTable(v) or v
            end
        end
        if MaelstromTrackerDB.locked then f:EnableMouse(false) end
        f:SetScale(MaelstromTrackerDB.scale)
        RestorePosition()
        self:UnregisterEvent("ADDON_LOADED")
    end
    Update()
    ApplyLooks()
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
        print("  in combat:", tostring(InCombatLockdown()), " auras secret:", tostring(AurasLocked()))
        if a == nil then
            print("  aura (addon read): blocked by game")
        elseif a == false then
            print("  aura (addon read): not found")
        else
            print("  aura (addon read): id=" .. Show(a.spellId), "stacks=" .. Show(a.applications))
        end
        if native.error then
            print("  game aura display: FAILED -", native.error)
        elseif native.iconContainer then
            local ok, n = pcall(native.iconContainer.GetAuraSlotFrame, native.iconContainer, "maelstrom")
            print("  game aura display: active, slot", ok and n and "ok" or "missing")
        else
            print("  game aura display: waiting to leave combat")
        end
    else
        P("/mwt (settings) | lock | unlock | reset | debug")
    end
end

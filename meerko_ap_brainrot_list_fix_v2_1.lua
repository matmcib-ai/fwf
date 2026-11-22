
-- ============================================================
-- MEERKO AP - standalone extraction (admin panel only)
-- Player panel + Click-to-AP + Mini ADMIN AP HUD + keybinds
-- ============================================================

-- LPH obfuscation no-op stubs (harmless in a clean environment)
if LPH_OBFUSCATED == nil then
    local _e = getfenv()
    for _,n in ipairs({"LPH_NO_VIRTUALIZE","LPH_NO_UPVALUES","LPH_JIT","LPH_JIT_MAX","LPH_ENCFUNC"}) do
        if _e[n] == nil then _e[n] = function(f) return f end end
    end
end

-- ---- shared prelude the AP borrows from earlier modules ----
_G.VanishUISizes = _G.VanishUISizes or {}
function MeerkoResize(frame, minW, minH, key)
    if not frame then return end
    minW, minH = minW or 160, minH or 120

    if key then
        local sv = _G.VanishUISizes[key]
        if type(sv) == "table" and tonumber(sv.x) and tonumber(sv.y) then
            frame.Size = UDim2.fromOffset(math.max(minW, sv.x), math.max(minH, sv.y))
        end
    end

    local g = Instance.new("TextButton")
    g.Name = "MeerkoResizeGrip"
    g.AnchorPoint = Vector2.new(1, 1)
    g.Position = UDim2.new(1, -2, 1, -2)
    g.Size = UDim2.fromOffset(16, 16)
    g.BackgroundTransparency = 1
    g.Text = "◢"
    g.TextColor3 = Color3.fromRGB(138, 148, 172)
    g.TextSize = 13
    g.Font = Enum.Font.GothamBold
    g.AutoButtonColor = false
    g.ZIndex = 9999
    g.Parent = frame

    local UIS_ = game:GetService("UserInputService")
    local dragging, startPos, startSize = false, nil, nil

    g.MouseEnter:Connect(function() g.TextColor3 = Color3.fromRGB(102, 140, 255) end)
    g.MouseLeave:Connect(function()
        if not dragging then g.TextColor3 = Color3.fromRGB(138, 148, 172) end
    end)
    g.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            startPos, startSize = i.Position, frame.AbsoluteSize
        end
    end)
    UIS_.InputChanged:Connect(function(i)
        if not dragging then return end
        if i.UserInputType ~= Enum.UserInputType.MouseMovement
            and i.UserInputType ~= Enum.UserInputType.Touch then return end
        local d = i.Position - startPos
        frame.Size = UDim2.fromOffset(
            math.max(minW, startSize.X + d.X),
            math.max(minH, startSize.Y + d.Y))
    end)
    UIS_.InputEnded:Connect(function(i)
        if i.UserInputType ~= Enum.UserInputType.MouseButton1
            and i.UserInputType ~= Enum.UserInputType.Touch then return end
        if not dragging then return end
        dragging = false
        g.TextColor3 = Color3.fromRGB(138, 148, 172)
        if key then
            _G.VanishUISizes[key] = { x = frame.Size.X.Offset, y = frame.Size.Y.Offset }
            if _G._stp_saveCurrent then pcall(_G._stp_saveCurrent) end
        end
    end)
    return g
end

local _MeerkoAPLazyQ = {}
local function LazyInit(name, fn, order)
    local q = _MeerkoAPLazyQ
    local item = { name = name, fn = fn, order = order or 100 }
    local i = #q
    while i > 0 and q[i].order > item.order do q[i + 1] = q[i]; i = i - 1 end
    q[i + 1] = item
end
task.defer(function()
    task.wait(tonumber(_G.VanishUIFirstDelay) or 4)
    while true do
        local q = _MeerkoAPLazyQ
        if #q > 0 then
            local group = q[1].order
            while #q > 0 and q[1].order == group do
                local item = table.remove(q, 1)
                _G.VanishUISlot = item.name
                local ok, err = pcall(item.fn)
                if not ok then _G.VanishUILastError = tostring(err) end
            end
            task.wait(tonumber(_G.VanishUIStagger) or 2)
        else
            task.wait(0.5)
        end
    end
end)

-- ---- AP detector: gamepass "Admin Commands" (Has AP badge) ----
-- Roblox blocks UserOwnsGamePassAsync for other players on client.
-- Inventory HTTP is-owned returns true/false for any userId.
do
    local AP_GAMEPASS_ID = 1227013099
    local AP_REQ = (syn and syn.request) or http_request or request
    local clock = os.clock

    local playerAPStatus  = {}   -- [userId] = true/false resolved; nil = unknown
    local playerAPPending = {}   -- [userId] = true while HTTP in flight
    local playerAPNextTry = {}   -- [userId] = clock() min before retry

    local function checkAdminPanelGamepass(plr)
        if not plr then return false end
        local uid = plr.UserId
        local cached = playerAPStatus[uid]
        if cached ~= nil then return cached end

        -- local-player shortcut (attribute only reliable on self in this game)
        if plr:GetAttribute("AdminCommands") == true then
            playerAPStatus[uid] = true
            return true
        end

        if AP_GAMEPASS_ID > 0 and AP_REQ and not playerAPPending[uid]
            and clock() >= (playerAPNextTry[uid] or 0) then
            playerAPPending[uid] = true
            task.spawn(function()
                local url = "https://inventory.roblox.com/v1/users/" .. uid
                    .. "/items/GamePass/" .. AP_GAMEPASS_ID .. "/is-owned"
                local ok, res = pcall(AP_REQ, { Url = url, Method = "GET" })
                local resolved = false
                if ok and type(res) == "table" and res.StatusCode == 200 then
                    local b = tostring(res.Body):gsub("%s+", ""):lower()
                    if b == "true" then
                        playerAPStatus[uid] = true
                        resolved = true
                    elseif b == "false" then
                        playerAPStatus[uid] = false
                        resolved = true
                    end
                end
                if not resolved then playerAPNextTry[uid] = clock() + 15 end
                playerAPPending[uid] = nil
            end)
        end
        return false
    end

    _G.checkAdminPanelGamepass = checkAdminPanelGamepass
    _G.VanishHasAP = checkAdminPanelGamepass

    pcall(function()
        game:GetService("Players").PlayerRemoving:Connect(function(plr)
            local uid = plr and plr.UserId
            if not uid then return end
            playerAPStatus[uid] = nil
            playerAPPending[uid] = nil
            playerAPNextTry[uid] = nil
        end)
    end)
end

-- ============================ AP MODULE ============================
;(function()

if not game:IsLoaded() then game.Loaded:Wait() end

if LPH_OBFUSCATED == nil then
    local env = getfenv()
    env["LPH_NO_" .. "VIRTUALIZE"] = function(...) return ... end
    env["LPH_JIT_" .. "MAX"]       = function(...) return ... end
end

Players             = game:GetService("Players")
UIS                 = game:GetService("UserInputService")
RunService          = game:GetService("RunService")
TweenService        = game:GetService("TweenService")
HttpService         = game:GetService("HttpService")
ReplicatedStorage   = game:GetService("ReplicatedStorage")
Workspace           = game:GetService("Workspace")
Lighting            = game:GetService("Lighting")
CoreGui             = game:GetService("CoreGui")
VirtualInputManager = game:GetService("VirtualInputManager")

if not Players.LocalPlayer then Players:GetPropertyChangedSignal("LocalPlayer"):Wait() end
LocalPlayer = Players.LocalPlayer
player      = LocalPlayer
playerGui   = player:WaitForChild("PlayerGui")

UI = UI or {Locked = false}
BoundToggles = BoundToggles or {}
_G.__MynxxLazyQ = _G.__MynxxLazyQ or {}

local Config, saveConfig, loadConfig


GlobalUIScaleVal = 1
scaledGuis = setmetatable({}, { __mode = "k" })

function getGlobalScale()
    return GlobalUIScaleVal
end

function updateAllGuisScale(newScale)
    GlobalUIScaleVal = newScale
    for sg, master in pairs(scaledGuis) do
        pcall(function()
            if sg and sg.Parent and master and master.Parent then
                local scaleObj = master:FindFirstChild("Mynxx_GlobalScale")
                if scaleObj then
                    scaleObj.Scale = newScale
                end
                master.Size = UDim2.new(1 / newScale, 0, 1 / newScale, 0)
            end
        end)
    end
end

function registerScreenGui(sg)
    local master = sg:FindFirstChild("Mynxx_MasterFrame")
    if not master then
        master = Instance.new("Frame")
        master.Name = "Mynxx_MasterFrame"
        master.BackgroundTransparency = 1
        master.BorderSizePixel = 0
        master.Parent = sg
        
        local scaleObj = Instance.new("UIScale")
        scaleObj.Name = "Mynxx_GlobalScale"
        scaleObj.Parent = master
    end
    scaledGuis[sg] = master
    
    pcall(function()
        local scaleObj = master:FindFirstChild("Mynxx_GlobalScale")
        if scaleObj then
            scaleObj.Scale = GlobalUIScaleVal
        end
        master.Size = UDim2.new(1 / GlobalUIScaleVal, 0, 1 / GlobalUIScaleVal, 0)
    end)
    return master
end

function recalculateScale()
    local cam = Workspace.CurrentCamera
    if not cam then return end
    local size = cam.ViewportSize
    local h = size.Y
    
    local isMobile = UIS.TouchEnabled
    local newScale = 1
    if isMobile then
        newScale = math.clamp(h / 1000, 0.40, 0.58)
    else
        newScale = math.clamp(h / 800, 0.65, 1.0)
    end
    updateAllGuisScale(newScale)
end

function setupCameraListener()
    if cameraConn then pcall(function() cameraConn:Disconnect() end) end
    local cam = Workspace.CurrentCamera
    if cam then
        cameraConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(recalculateScale)
        recalculateScale()
    end
end
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(setupCameraListener)
task.spawn(setupCameraListener)

local _old = playerGui:FindFirstChild("DoomAdmin_Standalone"); if _old then _old:Destroy() end
gui_sg = Instance.new("ScreenGui")
gui_sg.Name = "DoomAdmin_Standalone"; gui_sg.ResetOnSpawn = false
gui_sg.IgnoreGuiInset = true; gui_sg.DisplayOrder = 9999999; gui_sg.Parent = playerGui
gui = registerScreenGui(gui_sg)
panels, panelSetters, tabButtons = {}, {}, {}


ToggleState = {}
function regToggle(name, default)
    if not ToggleState[name] then ToggleState[name] = {value = default or false, listeners = {}} end
end
function getToggle(name) return ToggleState[name] and ToggleState[name].value or false end
function setToggle(name, val, skipNotify)
    regToggle(name)
    ToggleState[name].value = val
    if not skipNotify then
        for _, fn in ipairs(ToggleState[name].listeners) do pcall(fn, val) end
    end
end
function onToggleChanged(name, fn)
    regToggle(name); table.insert(ToggleState[name].listeners, fn)
end


Themes = {
    Light = {
        Background=Color3.fromRGB(245,245,247), MainBackground=Color3.fromRGB(252,252,254),
        SidebarBg=Color3.fromRGB(238,238,242), ContentBg=Color3.fromRGB(248,248,250),
        SidebarActive=Color3.fromRGB(255,255,255), SidebarActiveText=Color3.fromRGB(20,20,22),
        SidebarInactiveText=Color3.fromRGB(80,80,88),
        Panel=Color3.fromRGB(248,248,250), Row=Color3.fromRGB(240,240,244), RowHover=Color3.fromRGB(232,232,236),
        Accent=Color3.fromRGB(30,30,34), AccentLight=Color3.fromRGB(180,180,188),
        Green=Color3.fromRGB(245,245,247), Red=Color3.fromRGB(220,80,90), Red2=Color3.fromRGB(200,60,72),
        Text=Color3.fromRGB(24,24,28), Dim=Color3.fromRGB(110,110,118), Stroke=Color3.fromRGB(210,210,218),
        SoftButton=Color3.fromRGB(240,240,244), SoftButtonHover=Color3.fromRGB(232,232,236),
        SoftAccent=Color3.fromRGB(232,232,236), SoftAccentHover=Color3.fromRGB(224,224,228),
        ToggleOn=Color3.fromRGB(245,245,247), ToggleOff=Color3.fromRGB(210,210,216), ToggleOff2=Color3.fromRGB(210,210,216),
        ToggleKnobOn=Color3.fromRGB(30,30,34), ToggleKnobOff=Color3.fromRGB(170,170,178),
        InputBg=Color3.fromRGB(255,255,255), SliderBg=Color3.fromRGB(255,255,255), SliderFill=Color3.fromRGB(30,30,34),
        BlacklistHover=Color3.fromRGB(255,220,225), BlacklistLeave=Color3.fromRGB(248,240,242),
    },
    Dark = {
        Background=Color3.fromRGB(10,10,10), MainBackground=Color3.fromRGB(18,18,20),
        SidebarBg=Color3.fromRGB(0,0,0), ContentBg=Color3.fromRGB(26,26,28),
        SidebarActive=Color3.fromRGB(255,255,255), SidebarActiveText=Color3.fromRGB(12,12,14),
        SidebarInactiveText=Color3.fromRGB(210,210,214),
        Panel=Color3.fromRGB(28,28,30), Row=Color3.fromRGB(36,36,40), RowHover=Color3.fromRGB(48,48,52),
        Accent=Color3.fromRGB(255,255,255), AccentLight=Color3.fromRGB(70,70,76),
        Green=Color3.fromRGB(255,255,255), Red=Color3.fromRGB(220,90,100), Red2=Color3.fromRGB(190,70,82),
        Text=Color3.fromRGB(255,255,255), Dim=Color3.fromRGB(130,130,138), Stroke=Color3.fromRGB(42,42,48),
        SoftButton=Color3.fromRGB(34,34,38), SoftButtonHover=Color3.fromRGB(44,44,48),
        SoftAccent=Color3.fromRGB(34,34,38), SoftAccentHover=Color3.fromRGB(44,44,48),
        ToggleOn=Color3.fromRGB(255,255,255), ToggleOff=Color3.fromRGB(38,38,42), ToggleOff2=Color3.fromRGB(38,38,42),
        ToggleKnobOn=Color3.fromRGB(18,18,20), ToggleKnobOff=Color3.fromRGB(110,110,118),
        InputBg=Color3.fromRGB(32,32,36), SliderBg=Color3.fromRGB(255,255,255), SliderFill=Color3.fromRGB(255,255,255),
        BlacklistHover=Color3.fromRGB(70,40,48), BlacklistLeave=Color3.fromRGB(40,32,36),
    },
    Nexus = {
        Background=Color3.fromRGB(17,19,24), MainBackground=Color3.fromRGB(15,17,21),
        SidebarBg=Color3.fromRGB(13,15,19), ContentBg=Color3.fromRGB(19,21,26),
        SidebarActive=Color3.fromRGB(28,34,44), SidebarActiveText=Color3.fromRGB(96,160,255),
        SidebarInactiveText=Color3.fromRGB(125,133,145),
        Panel=Color3.fromRGB(22,25,31), Row=Color3.fromRGB(26,29,36), RowHover=Color3.fromRGB(33,37,46),
        Accent=Color3.fromRGB(74,140,255), AccentLight=Color3.fromRGB(52,64,84),
        Green=Color3.fromRGB(63,185,80), Red=Color3.fromRGB(226,72,82), Red2=Color3.fromRGB(196,54,66),
        Text=Color3.fromRGB(226,230,238), Dim=Color3.fromRGB(120,128,140), Stroke=Color3.fromRGB(43,48,58),
        SoftButton=Color3.fromRGB(28,32,40), SoftButtonHover=Color3.fromRGB(36,41,52),
        SoftAccent=Color3.fromRGB(30,38,52), SoftAccentHover=Color3.fromRGB(38,48,66),
        ToggleOn=Color3.fromRGB(74,140,255), ToggleOff=Color3.fromRGB(36,40,49), ToggleOff2=Color3.fromRGB(36,40,49),
        ToggleKnobOn=Color3.fromRGB(255,255,255), ToggleKnobOff=Color3.fromRGB(110,118,130),
        InputBg=Color3.fromRGB(26,29,36), SliderBg=Color3.fromRGB(46,52,63), SliderFill=Color3.fromRGB(74,140,255),
        BlacklistHover=Color3.fromRGB(70,40,48), BlacklistLeave=Color3.fromRGB(40,32,36),
    }
}
Theme = {}
for k, v in pairs(Themes.Nexus) do
    Theme[k] = v
end

UIFont = {
    Brand = Enum.Font.GothamBold,
    Title = Enum.Font.GothamBlack,
    Body = Enum.Font.GothamMedium,
    Label = Enum.Font.GothamSemibold,
    Button = Enum.Font.GothamBold,
    Small = Enum.Font.Gotham,
}

UITransparency = {
    MainPanel = 0.04,
    Sidebar = 0.02,
    Content = 0.05,
    Panel = 0.06,
    BottomBar = 0.08,
    Button = 0.08,
    MainButton = 0.10,
    Row = 0.14,
    RowAlt = 0.20,
    SoftRow = 0.12,
    Input = 0.10,
    Toggle = 0,
    Hud = 0.20,
    Alert = 0.24,
    Progress = 0.20,
    ConfigPanel = 0.06,
    SidebarTab = 0.12,
    TargetRow = 0.16,
    TargetRowAlt = 0.30,
    Dropdown = 0.04,
    Outline = 0.72,
    Avatar = 0.18,
}

Themes.Meerko = {
    Background=Color3.fromRGB(22,24,33),   MainBackground=Color3.fromRGB(18,20,28),
    SidebarBg=Color3.fromRGB(16,18,25),    ContentBg=Color3.fromRGB(26,29,40),
    SidebarActive=Color3.fromRGB(48,58,92), SidebarActiveText=Color3.fromRGB(140,164,255),
    SidebarInactiveText=Color3.fromRGB(138,148,172),
    Panel=Color3.fromRGB(30,34,46), Row=Color3.fromRGB(34,38,52), RowHover=Color3.fromRGB(48,54,74),
    Accent=Color3.fromRGB(104,132,248), AccentLight=Color3.fromRGB(140,164,255),
    Green=Color3.fromRGB(80,226,150), Red=Color3.fromRGB(235,80,90), Red2=Color3.fromRGB(190,60,72),
    Text=Color3.fromRGB(232,236,244), Dim=Color3.fromRGB(138,148,172), Stroke=Color3.fromRGB(52,58,80),
    SoftButton=Color3.fromRGB(30,34,46), SoftButtonHover=Color3.fromRGB(46,54,74),
    SoftAccent=Color3.fromRGB(40,52,84), SoftAccentHover=Color3.fromRGB(58,74,120),
    ToggleOn=Color3.fromRGB(104,132,248), ToggleOff=Color3.fromRGB(30,34,46), ToggleOff2=Color3.fromRGB(25,28,38),
    ToggleKnobOn=Color3.fromRGB(245,248,255), ToggleKnobOff=Color3.fromRGB(138,148,172),
    InputBg=Color3.fromRGB(25,28,38), SliderBg=Color3.fromRGB(46,52,72), SliderFill=Color3.fromRGB(104,132,248),
    BlacklistHover=Color3.fromRGB(74,44,58), BlacklistLeave=Color3.fromRGB(40,32,42),
}
for k, v in pairs(Themes.Meerko) do Theme[k] = v end


local CONFIG_FILE = "doom_admin_standalone.json"
local function canUseFiles()
    return typeof(readfile)=="function" and typeof(writefile)=="function" and typeof(isfile)=="function"
end
Config = {
    positions = {}, sizes = {},
    AdminPanelUI = true,
    ClickToAP = false, ClickToAPSingleCommand = false, ClickToAPRadius = 8,
    ProximityAP = false, ProximityRange = 15,
    apBlacklist = {}, apBlacklistNames = {},
    ShowJobJoiner = true,
    SpamBaseOwnerSingleCommand = false,
}
saveConfig = function()
    if not canUseFiles() then return end
    task.spawn(function() pcall(function() writefile(CONFIG_FILE, HttpService:JSONEncode(Config)) end) end)
end
loadConfig = function()
    if not canUseFiles() then return end
    local ok, data = pcall(function()
        if isfile(CONFIG_FILE) then return HttpService:JSONDecode(readfile(CONFIG_FILE)) end
    end)
    if ok and type(data) == "table" then
        for k, v in pairs(data) do
            if type(v) == "table" and type(Config[k]) == "table" then
                for sk, sv in pairs(v) do Config[k][sk] = sv end
            else Config[k] = v end
        end
    end
    if type(Config.positions) ~= "table" then Config.positions = {} end
    if type(Config.sizes)     ~= "table" then Config.sizes     = {} end
    Config.ProximityAP = false
    Config.ClickToAP = (Config.ClickToAP == true)
end
loadConfig()

function setClickToAP(on)
    on = on and true or false
    Config.ClickToAP = on
    setToggle("Click to AP", on)
    setToggle("ClickToAP", on)
    saveConfig()
    return on
end


function serializePos(pos) return {xs=pos.X.Scale,xo=pos.X.Offset,ys=pos.Y.Scale,yo=pos.Y.Offset} end
function rememberPosition(name, frame) if not name or not frame then return end; Config.positions[name]=serializePos(frame.Position); saveConfig() end
function applySavedPosition(name, frame)
    if not name or not frame then return end; local d=Config.positions and Config.positions[name]
    if d then frame.Position=UDim2.new(d.xs or 0,d.xo or 0,d.ys or 0,d.yo or 0) end
end

local _nGui = Instance.new("ScreenGui")
_nGui.Name = "DoomAdmin_Notifs"; _nGui.ResetOnSpawn = false
_nGui.IgnoreGuiInset = true; _nGui.DisplayOrder = 100000000
do
    local _cr = cloneref or function(x) return x end
    local okp = pcall(function() _nGui.Parent = _cr(game:GetService("CoreGui")) end)
    if not okp or not _nGui.Parent then _nGui.Parent = playerGui end
end
local _nHold = Instance.new("Frame", _nGui)
_nHold.AnchorPoint = Vector2.new(1,1); _nHold.Position = UDim2.new(1,-14,1,-14)
_nHold.Size = UDim2.new(0,270,1,-28); _nHold.BackgroundTransparency = 1
local _nl = Instance.new("UIListLayout", _nHold)
_nl.VerticalAlignment = Enum.VerticalAlignment.Bottom
_nl.HorizontalAlignment = Enum.HorizontalAlignment.Right
_nl.Padding = UDim.new(0,6); _nl.SortOrder = Enum.SortOrder.LayoutOrder
function ShowNotification(title, text)
    task.spawn(function()
        local card = Instance.new("Frame", _nHold)
        card.Size = UDim2.new(0,258,0,46); card.BackgroundColor3 = Color3.fromRGB(16,14,15)
        card.BackgroundTransparency = 0.05; card.BorderSizePixel = 0
        Instance.new("UICorner", card).CornerRadius = UDim.new(0,8)
        local st = Instance.new("UIStroke", card); st.Color = Color3.fromRGB(220,32,45); st.Transparency = 0.5
        local t = Instance.new("TextLabel", card)
        t.Size = UDim2.new(1,-16,0,16); t.Position = UDim2.new(0,10,0,6); t.BackgroundTransparency = 1
        t.Text = tostring(title or "DOOM"); t.TextColor3 = Color3.fromRGB(255,255,255)
        t.Font = Enum.Font.GothamBold; t.TextSize = 12; t.TextXAlignment = Enum.TextXAlignment.Left
        local b = Instance.new("TextLabel", card)
        b.Size = UDim2.new(1,-16,0,16); b.Position = UDim2.new(0,10,0,24); b.BackgroundTransparency = 1
        b.Text = tostring(text or ""); b.TextColor3 = Color3.fromRGB(180,168,170)
        b.Font = Enum.Font.GothamMedium; b.TextSize = 11; b.TextXAlignment = Enum.TextXAlignment.Left
        b.TextTruncate = Enum.TextTruncate.AtEnd
        task.wait(2.6); pcall(function() card:Destroy() end)
    end)
end


corner = function(o,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r); c.Parent=o; return c end
stroke = function(o,col,th,tr) local s=Instance.new("UIStroke"); s.Color=col or Theme.Stroke; s.Thickness=th or 1; s.Transparency=tr or 0; s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; s.Parent=o; return s end
tw = function(o,p,t) TweenService:Create(o,TweenInfo.new(t or 0.14,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),p):Play() end
addOutline = function(f) local o=Instance.new("UIStroke"); o.Color=Theme.Stroke; o.Thickness=1; o.Transparency=UITransparency.Outline; o.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; o.Parent=f; return o end
function clearBody(body) for _,c in ipairs(body:GetChildren()) do if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then c:Destroy() end end end

function openAnim(f) if not f then return end; local us=f:FindFirstChild("MynxxScale") or Instance.new("UIScale"); us.Name="MynxxScale"; us.Parent=f
    local tgt=f.Position; f.Visible=true; us.Scale=0.92; f.Position=UDim2.new(tgt.X.Scale,tgt.X.Offset,tgt.Y.Scale,tgt.Y.Offset+18); tw(us,{Scale=1},0.20); tw(f,{Position=tgt},0.20) end
function closeAnim(f) if not f then return end; f.Visible = false end

makeDraggable = function(frame,handle,saveName) local dragging,dragStart,startPos=false,nil,nil
    handle.InputBegan:Connect(function(i) if UI.Locked then return end; if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=true; dragStart=i.Position; startPos=frame.Position end end)
    UIS.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then if dragging and saveName then rememberPosition(saveName,frame) end; dragging=false end end)
    UIS.InputChanged:Connect(function(i) if dragging and not UI.Locked and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
        local d=i.Position-dragStart
        local scale = getGlobalScale()
        frame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+(d.X/scale),startPos.Y.Scale,startPos.Y.Offset+(d.Y/scale))
    end end)
end

makeResizable = function(frame, minSize, panelName)
    local h = Instance.new("TextButton")
    h.Name = "ResizeGrip"
    h.Size = UDim2.new(0, 16, 0, 16)
    h.Position = UDim2.new(1, -16, 1, -16)
    h.BackgroundTransparency = 1
    h.Text = "◢"
    h.TextColor3 = Theme.Dim or Color3.new(1, 1, 1)
    h.TextSize = 12
    h.ZIndex = 100
    h.Visible = not UI.Locked
    h.Parent = frame
    _G.__MynxxGrips = _G.__MynxxGrips or {}
    table.insert(_G.__MynxxGrips, h)
    local dragging, dragStart, startSize = false, nil, nil
    h.InputBegan:Connect(function(i)
        if UI.Locked then return end
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = i.Position; startSize = frame.AbsoluteSize
        end
    end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            if dragging then
                dragging = false
                if panelName then
                    if not Config.sizes then Config.sizes = {} end
                    Config.sizes[panelName] = {x = frame.Size.X.Offset, y = frame.Size.Y.Offset}
                    saveConfig()
                end
            end
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if dragging and not UI.Locked and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            local scale = getGlobalScale()
            local nx = math.max(minSize.X.Offset, startSize.X + (d.X / scale))
            local ny = math.max(minSize.Y.Offset, startSize.Y + (d.Y / scale))
            frame.Size = UDim2.new(0, nx, 0, ny)
        end
    end)
end

function makeHeader(f,t,isMain) local h=Instance.new("Frame"); h.Size=UDim2.new(1,0,0,42); h.BackgroundTransparency=1; h.Parent=f
    local parts={}; for s in string.gmatch(t,"([^\n]+)") do table.insert(parts,s) end
    if isMain then local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,-50,0,24); l.Position=UDim2.new(0,13,0,8); l.BackgroundTransparency=1; l.Text=parts[1] or "Mynxx"; l.TextColor3=Theme.Text; l.Font=UIFont.Title; l.TextSize=16; l.TextXAlignment=Enum.TextXAlignment.Left; l.Parent=h
    elseif parts[2] == "Invisible Steal" then
        local brand=Instance.new("TextLabel"); brand.Size=UDim2.new(1,-24,0,14); brand.Position=UDim2.new(0,12,0,5); brand.BackgroundTransparency=1; brand.Text=parts[1] or "Mynxx"; brand.TextColor3=Theme.Text; brand.Font=Enum.Font.GothamBlack; brand.TextSize=11; brand.TextXAlignment=Enum.TextXAlignment.Center; brand.Parent=h
        local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,-24,0,16); l.Position=UDim2.new(0,12,0,20); l.BackgroundTransparency=1; l.Text=parts[2]; l.TextColor3=Theme.Text; l.Font=Enum.Font.GothamBold; l.TextSize=12; l.TextXAlignment=Enum.TextXAlignment.Center; l.Parent=h
    else
        local brand=Instance.new("TextLabel"); brand.Size=UDim2.new(1,-58,0,12); brand.Position=UDim2.new(0,12,0,5); brand.BackgroundTransparency=1; brand.Text=parts[1] or "Mynxx"; brand.TextColor3=Theme.Dim; brand.Font=UIFont.Brand; brand.TextSize=9; brand.TextXAlignment=Enum.TextXAlignment.Center; brand.Parent=h
        local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,-58,0,16); l.Position=UDim2.new(0,12,0,18); l.BackgroundTransparency=1; l.Text=parts[2] or ""; l.TextColor3=Theme.Text; l.Font=UIFont.Title; l.TextSize=12; l.TextXAlignment=Enum.TextXAlignment.Center; l.Parent=h
    end
    local d=Instance.new("Frame"); d.Size=UDim2.new(1,-24,0,1); d.Position=UDim2.new(0,12,0,40); d.BackgroundColor3=Theme.Stroke; d.BackgroundTransparency=0.55; d.BorderSizePixel=0; d.Parent=f
    makeDraggable(f,h,t); return h end

function makeMainPanel(t,size,pos) local f=Instance.new("Frame"); f.Size=size; f.Position=pos; f.BackgroundColor3=Theme.MainBackground; f.BackgroundTransparency=UITransparency.MainPanel; f.BorderSizePixel=0; f.ClipsDescendants=true; f.Parent=gui; corner(f,14); addOutline(f)
    local sidebar=Instance.new("Frame"); sidebar.Name="Sidebar"; sidebar.Size=UDim2.new(0,128,1,0); sidebar.BackgroundColor3=Theme.SidebarBg or Color3.fromRGB(0,0,0); sidebar.BackgroundTransparency=UITransparency.Sidebar; sidebar.BorderSizePixel=0; sidebar.Parent=f; corner(sidebar,14)
    local sidebarClip=Instance.new("Frame"); sidebarClip.Size=UDim2.new(1,0,1,0); sidebarClip.BackgroundTransparency=1; sidebarClip.ClipsDescendants=true; sidebarClip.Parent=sidebar; corner(sidebarClip,14)
    local dragHandle=Instance.new("Frame"); dragHandle.Name="DragHandle"; dragHandle.Size=UDim2.new(1,0,0,44); dragHandle.BackgroundTransparency=1; dragHandle.Parent=sidebarClip
    local titleParts={}; for s in string.gmatch(t or "Mynxx","([^\n]+)") do table.insert(titleParts,s) end
    local titleLbl=Instance.new("TextLabel"); titleLbl.Name="SidebarTitle"; titleLbl.Size=UDim2.new(1,-16,0,44); titleLbl.Position=UDim2.new(0,12,0,0); titleLbl.BackgroundTransparency=1; titleLbl.Text=titleParts[1] or "Mynxx"; titleLbl.TextColor3=Theme.Text; titleLbl.Font=Enum.Font.GothamBlack; titleLbl.TextSize=13; titleLbl.TextXAlignment=Enum.TextXAlignment.Left; titleLbl.TextYAlignment=Enum.TextYAlignment.Center; titleLbl.Parent=sidebarClip
    sidebarNav=Instance.new("Frame"); sidebarNav.Name="SidebarNav"; sidebarNav.Size=UDim2.new(1,-16,1,-108); sidebarNav.Position=UDim2.new(0,8,0,48); sidebarNav.BackgroundTransparency=1; sidebarNav.Parent=sidebarClip
    local navLay=Instance.new("UIListLayout"); navLay.Padding=UDim.new(0,5); navLay.SortOrder=Enum.SortOrder.LayoutOrder; navLay.Parent=sidebarNav
    local profSep=Instance.new("Frame"); profSep.Size=UDim2.new(1,-20,0,1); profSep.Position=UDim2.new(0,10,1,-62); profSep.BackgroundColor3=Theme.Stroke; profSep.BackgroundTransparency=0.55; profSep.BorderSizePixel=0; profSep.Parent=sidebarClip
    sidebarProfile=Instance.new("Frame"); sidebarProfile.Name="SidebarProfile"; sidebarProfile.Size=UDim2.new(1,-16,0,54); sidebarProfile.Position=UDim2.new(0,8,1,-58); sidebarProfile.BackgroundTransparency=1; sidebarProfile.Parent=sidebarClip
    local avatarWrap=Instance.new("Frame"); avatarWrap.Size=UDim2.fromOffset(32,32); avatarWrap.Position=UDim2.new(0,0,0,6); avatarWrap.BackgroundTransparency=1; avatarWrap.Parent=sidebarProfile; corner(avatarWrap,16)
    local avatar=Instance.new("ImageLabel"); avatar.Size=UDim2.fromScale(1,1); avatar.BackgroundColor3=Theme.Row; avatar.BackgroundTransparency=UITransparency.Avatar; avatar.BorderSizePixel=0; avatar.Image=""; avatar.Parent=avatarWrap; corner(avatar,16)
    local profName=Instance.new("TextLabel"); profName.Name="ProfileName"; profName.Size=UDim2.new(1,-40,0,15); profName.Position=UDim2.new(0,38,0,8); profName.BackgroundTransparency=1; profName.Text=(player.DisplayName~="" and player.DisplayName) or player.Name; profName.TextColor3=Theme.Text; profName.Font=Enum.Font.GothamBold; profName.TextSize=11; profName.TextXAlignment=Enum.TextXAlignment.Left; profName.TextScaled=true; profName.Parent=sidebarProfile
    local pnc=Instance.new("UITextSizeConstraint"); pnc.MinTextSize=7; pnc.MaxTextSize=11; pnc.Parent=profName
    local profHandle=Instance.new("TextLabel"); profHandle.Name="ProfileHandle"; profHandle.Size=UDim2.new(1,-40,0,13); profHandle.Position=UDim2.new(0,38,0,24); profHandle.BackgroundTransparency=1; profHandle.Text="@"..string.lower(player.Name); profHandle.TextColor3=Theme.Dim; profHandle.Font=Enum.Font.Gotham; profHandle.TextSize=9; profHandle.TextXAlignment=Enum.TextXAlignment.Left; profHandle.TextScaled=true; profHandle.Parent=sidebarProfile
    local phc=Instance.new("UITextSizeConstraint"); phc.MinTextSize=6; phc.MaxTextSize=9; phc.Parent=profHandle
    local profSession=Instance.new("TextLabel"); profSession.Name="ProfileSession"; profSession.Size=UDim2.new(1,-40,0,11); profSession.Position=UDim2.new(0,38,0,38); profSession.BackgroundTransparency=1; profSession.Text="SESSION 0m 00s"; profSession.TextColor3=Theme.Accent or Theme.Dim; profSession.Font=Enum.Font.GothamBold; profSession.TextSize=8; profSession.TextXAlignment=Enum.TextXAlignment.Left; profSession.Parent=sidebarProfile
    task.spawn(function()
        local t0=os.clock()
        while profSession.Parent do
            local e=os.clock()-t0
            profSession.Text=string.format("SESSION %dm %02ds", math.floor(e/60), math.floor(e%60))
            task.wait(1)
        end
    end)
    task.spawn(function()
        for _=1,10 do
            local ok,img,ready=pcall(function() return Players:GetUserThumbnailAsync(player.UserId,Enum.ThumbnailType.HeadShot,Enum.ThumbnailSize.AvatarCircle) end)
            if ok and img and img~="" then avatar.Image=img; if ready~=false then break end end
            task.wait(2)
        end
    end)
    player:GetPropertyChangedSignal("DisplayName"):Connect(function() profName.Text=(player.DisplayName~="" and player.DisplayName) or player.Name end)
    local contentBg=Instance.new("Frame"); contentBg.Name="ContentBg"; contentBg.Size=UDim2.new(1,-136,1,-10); contentBg.Position=UDim2.new(0,130,0,5); contentBg.BackgroundColor3=Theme.ContentBg or Theme.MainBackground; contentBg.BackgroundTransparency=UITransparency.Content; contentBg.BorderSizePixel=0; contentBg.Parent=f; corner(contentBg,12)
    local content=Instance.new("Frame"); content.Name="Content"; content.Size=UDim2.new(1,0,1,0); content.BackgroundTransparency=1; content.Parent=contentBg
    local body=Instance.new("ScrollingFrame"); body.Size=UDim2.new(1,-20,1,-16); body.Position=UDim2.new(0,10,0,8); body.BackgroundTransparency=1; body.BorderSizePixel=0; body.ScrollBarThickness=2; body.ScrollBarImageColor3=Theme.Stroke; body.ScrollBarImageTransparency=0.35; body.CanvasSize=UDim2.new(0,0,0,0); body.Active=true; body.Parent=content
    local pad=Instance.new("UIPadding"); pad.PaddingTop=UDim.new(0,6); pad.PaddingBottom=UDim.new(0,10); pad.PaddingLeft=UDim.new(0,2); pad.PaddingRight=UDim.new(0,2); pad.Parent=body
    local lay=Instance.new("UIListLayout"); lay.Padding=UDim.new(0,8); lay.Parent=body
    lay:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() body.CanvasSize=UDim2.new(0,0,0,lay.AbsoluteContentSize.Y+16) end)
    tabBar=sidebarNav
    if Config.sizes and Config.sizes[t] then f.Size=UDim2.new(0,Config.sizes[t].x,0,Config.sizes[t].y) end
    makeDraggable(f,dragHandle,t); makeResizable(f,UDim2.new(0,340,0,300),t); return f,body end

function makeSyncStateRow(parent,text,toggleName,callback)
    regToggle(toggleName,getToggle(toggleName))
    local row=Instance.new("Frame"); row.Size=UDim2.new(1,-4,0,31); row.BackgroundTransparency=1; row.Parent=parent
    local label=Instance.new("TextLabel"); label.Size=UDim2.new(1,-62,1,0); label.Position=UDim2.new(0,4,0,0); label.BackgroundTransparency=1; label.Text=text; label.TextColor3=Theme.Text; label.Font=UIFont.Label; label.TextSize=11; label.TextXAlignment=Enum.TextXAlignment.Left; label.TextTruncate=Enum.TextTruncate.AtEnd; label.Parent=row
    local btn=Instance.new("TextButton"); btn.Name="SyncStateBtn"; btn.Size=UDim2.new(0,52,0,24); btn.Position=UDim2.new(1,-56,0.5,-12); btn.Font=UIFont.Button; btn.TextSize=11; btn.AutoButtonColor=false; btn.Parent=row; corner(btn,6)
    local function refresh(val)
        btn.BackgroundColor3=val and (Theme.ToggleOn or Color3.fromRGB(245,245,247)) or Theme.ToggleOff
        btn.BackgroundTransparency=UITransparency.Toggle
        btn.Text=val and "ON" or "OFF"
        btn.TextColor3=Color3.new(1,1,1)
    end
    refresh(getToggle(toggleName)); onToggleChanged(toggleName,function(val) refresh(val) end)
    btn.MouseButton1Click:Connect(function() local nv=not getToggle(toggleName); setToggle(toggleName,nv); if callback then callback(nv) end end)
    return function(ns,fire) if typeof(ns)=="boolean" then setToggle(toggleName,ns); if fire~=false and callback then callback(ns) end end end, label
end

function makeSyncMainToggle(parent,text,toggleName,callback)
    regToggle(toggleName,getToggle(toggleName))
    local row=Instance.new("Frame"); row.Size=UDim2.new(1,-4,0,32); row.BackgroundTransparency=1; row.Parent=parent
    local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,-34,1,0); l.Position=UDim2.new(0,2,0,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=Theme.Text; l.Font=UIFont.Label; l.TextSize=12; l.TextXAlignment=Enum.TextXAlignment.Left; l.TextTruncate=Enum.TextTruncate.AtEnd; l.Parent=row
    local toggle=Instance.new("TextButton"); toggle.Size=UDim2.new(0,15,0,15); toggle.Position=UDim2.new(1,-21,0.5,-8); toggle.Text=""; toggle.AutoButtonColor=false; toggle.Parent=row; corner(toggle,3)
    stroke(toggle,Theme.Stroke,1,0)
    local tStroke=toggle:FindFirstChildOfClass("UIStroke")
    local check=Instance.new("TextLabel"); check.Size=UDim2.new(1,0,1,0); check.Position=UDim2.new(0,0,0,-1); check.BackgroundTransparency=1; check.Text="✓"; check.TextColor3=Theme.ToggleKnobOn or Color3.new(1,1,1); check.Font=Enum.Font.GothamBold; check.TextSize=10; check.Parent=toggle
    local hit=Instance.new("TextButton"); hit.Size=UDim2.new(0,30,0,30); hit.Position=UDim2.new(1,-28,0.5,-15); hit.BackgroundTransparency=1; hit.Text=""; hit.Parent=row
    local function refresh(val)
        tw(toggle,{BackgroundColor3=val and (Theme.ToggleOn or Theme.Accent) or Theme.ToggleOff, BackgroundTransparency=val and 0 or 0.55},0.1)
        check.Visible=val and true or false
        if tStroke then tStroke.Color=val and (Theme.ToggleOn or Theme.Accent) or Theme.Stroke end
    end
    refresh(getToggle(toggleName))
    toggle.BackgroundColor3=getToggle(toggleName) and (Theme.ToggleOn or Theme.Accent) or Theme.ToggleOff
    toggle.BackgroundTransparency=getToggle(toggleName) and 0 or 0.55
    onToggleChanged(toggleName,function(val) refresh(val) end)
    local function clickFlip() local nv=not getToggle(toggleName); setToggle(toggleName,nv); if callback then callback(nv) end end
    toggle.MouseButton1Click:Connect(clickFlip)
    hit.MouseButton1Click:Connect(clickFlip)
    BoundToggles[text]=function(ns,fire) if typeof(ns)=="boolean" then setToggle(toggleName,ns); if fire~=false and callback then callback(ns) end end end
    return BoundToggles[text]
end

function makeQuickSlider(parent,text,min,max,default,callback,suffix) local holder=Instance.new("Frame"); holder.Size=UDim2.new(1,-4,0,54); holder.BackgroundTransparency=1; holder.Parent=parent
    local label=Instance.new("TextLabel"); label.Size=UDim2.new(1,0,0,18); label.Position=UDim2.new(0,2,0,0); label.BackgroundTransparency=1; label.Text=text..": "..tostring(default)..(suffix or ""); label.TextColor3=Theme.Text; label.Font=UIFont.Body; label.TextSize=12; label.TextXAlignment=Enum.TextXAlignment.Left; label.Parent=holder
    local bar=Instance.new("Frame"); bar.Size=UDim2.new(1,-8,0,4); bar.Position=UDim2.new(0,2,0,32); bar.BackgroundColor3=Theme.SliderBg or Color3.fromRGB(46,52,63); bar.BackgroundTransparency=0.25; bar.BorderSizePixel=0; bar.Parent=holder; corner(bar,6)
    local fill=Instance.new("Frame"); fill.Size=UDim2.new(math.clamp((default-min)/(max-min),0,1),0,1,0); fill.BackgroundColor3=Theme.SliderFill or Theme.Accent or Color3.fromRGB(74,140,255); fill.BackgroundTransparency=0; fill.BorderSizePixel=0; fill.Parent=bar; corner(fill,6)
    local knob=Instance.new("Frame"); knob.Size=UDim2.new(0,12,0,12); knob.AnchorPoint=Vector2.new(0.5,0.5); knob.Position=UDim2.new(math.clamp((default-min)/(max-min),0,1),0,0.5,0); knob.Name="WhiteSliderKnob"; knob.BackgroundColor3=Color3.fromRGB(255,255,255); knob.BorderSizePixel=0; knob.ZIndex=2; knob.Parent=bar; corner(knob,20)
    local dragging=false
    local function update(x) local rel=math.clamp((x-bar.AbsolutePosition.X)/bar.AbsoluteSize.X,0,1); local v=math.floor((min+(max-min)*rel)*10+0.5)/10; fill.Size=UDim2.new(rel,0,1,0); knob.Position=UDim2.new(rel,0,0.5,0); label.Text=text..": "..tostring(v)..(suffix or ""); if callback then callback(v) end end
    bar.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=true; update(i.Position.X) end end)
    UIS.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=false end end)
    UIS.InputChanged:Connect(function(i) if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then update(i.Position.X) end end)
    local function setVal(v, silent)
        v = math.clamp(v, min, max)
        local rel = (v - min) / (max - min)
        local displayVal = math.floor(v * 10 + 0.5) / 10
        fill.Size = UDim2.new(rel, 0, 1, 0)
        knob.Position = UDim2.new(rel, 0, 0.5, 0)
        label.Text = text..": "..tostring(displayVal)..(suffix or "")
        if callback and not silent then callback(displayVal) end
    end
    return {Set = setVal}
end

function makeMainButton(parent,text,callback,color) local b=Instance.new("TextButton"); b.Size=UDim2.new(1,-4,0,30); b.BackgroundColor3=color or Theme.Row; b.BackgroundTransparency=UITransparency.MainButton; b.Text=text; b.TextColor3=Theme.Text; b.Font=Enum.Font.GothamBold; b.TextSize=11; b.AutoButtonColor=false; b.Parent=parent; corner(b,6); stroke(b,Theme.Stroke,1,0.55)
    b.MouseEnter:Connect(function() tw(b,{BackgroundColor3=color or Theme.RowHover},0.12) end); b.MouseLeave:Connect(function() tw(b,{BackgroundColor3=color or Theme.Row},0.12) end)
    b.MouseButton1Click:Connect(function() if callback then callback() end end); return b end

ACTION_COOLDOWNS = {ragdoll=30,jail=60,rocket=120,balloon=30,inverse=30,jumpscare=30,tiny=30,morph=30,nightvision=30}
lastActionUse = {}

function _readRealAdminTimer(cmd)
    local realAdminGui = playerGui:FindFirstChild("AdminPanel")
    if not realAdminGui then return nil end
    local ok, contentScroll = pcall(function() return realAdminGui.AdminPanel.Content.ScrollingFrame end)
    if not ok or not contentScroll then return nil end
    local cmdBtn = contentScroll:FindFirstChild(cmd)
    if not cmdBtn then return nil end
    local timerLabel = cmdBtn:FindFirstChild("Timer")
    if not timerLabel or not timerLabel.Visible then return 0 end
    local num = tonumber(timerLabel.Text:match("%d+"))
    return num or 0
end

function apIsOnCooldown(cmd)
    local realTime = _readRealAdminTimer(cmd)
    if realTime ~= nil then return realTime > 0 end
    local l=lastActionUse[cmd]; local cd=ACTION_COOLDOWNS[cmd] or 0; return l and cd>0 and (tick()-l)<cd
end
function apGetRemaining(cmd)
    local realTime = _readRealAdminTimer(cmd)
    if realTime ~= nil then return realTime end
    local l=lastActionUse[cmd]; local cd=ACTION_COOLDOWNS[cmd] or 0; if not l then return 0 end; return math.max(0,cd-(tick()-l))
end
function apStartCooldown(cmd) lastActionUse[cmd]=tick() end
AP_ALL_COMMANDS={"balloon","inverse","jail","jumpscare","morph","nightvision","ragdoll","rocket","tiny"}
AP_COMMAND_EMOJIS={balloon="🎈",inverse="🔄",jail="🔒",jumpscare="👻",morph="🎭",nightvision="🌙",ragdoll="🤸‍♂️",rocket="🚀",tiny="🐜"}
if not Config.ClickToAPCommands then
    Config.ClickToAPCommands = {}
    for _, cmd in ipairs(AP_ALL_COMMANDS) do Config.ClickToAPCommands[cmd] = true end
end
if not Config.AdminPanelButtons then
    Config.AdminPanelButtons = {ragdoll=true, jail=true, rocket=true, balloon=true}
end
if not Config.ClickToAPRadius then
    Config.ClickToAPRadius = 8
end
if not Config.SpamBaseOwnerCommands then
    Config.SpamBaseOwnerCommands = {}
    for _, cmd in ipairs(AP_ALL_COMMANDS) do Config.SpamBaseOwnerCommands[cmd] = true end
end
if not Config.SpamBaseOwnerOrder then
    Config.SpamBaseOwnerOrder = {}
    for i, cmd in ipairs(AP_ALL_COMMANDS) do Config.SpamBaseOwnerOrder[i] = cmd end
end
if Config.SpamBaseOwnerSingleCommand == nil then
    Config.SpamBaseOwnerSingleCommand = false
end
setToggle("SpamBaseOwnerSingleCommand", Config.SpamBaseOwnerSingleCommand or false)

_G.apBlacklist      = Config.apBlacklist or {}
_G.apBlacklistNames = Config.apBlacklistNames or {}

function isPlayerBlacklisted(plr)
    if not plr then return false end
    local uid = plr.UserId
    if _G.apBlacklist[uid] == true or _G.apBlacklist[tostring(uid)] == true then return true end
    if #_G.apBlacklistNames > 0 then
        local n = tostring(plr.Name):lower()
        local d = tostring(plr.DisplayName or ""):lower()
        for _, nm in ipairs(_G.apBlacklistNames) do
            nm = tostring(nm):lower()
            if nm == n or nm == d then return true end
        end
    end
    return false
end

function apBlacklistSync()
    Config.apBlacklist      = _G.apBlacklist
    Config.apBlacklistNames = _G.apBlacklistNames
    saveConfig()
    if _G.refreshBlacklistPanel then pcall(_G.refreshBlacklistPanel) end
    if _G.refreshAdminPanelRows then pcall(_G.refreshAdminPanelRows) end
end
function apBlacklistAdd(plr)
    if not plr then return end
    _G.apBlacklist[tostring(plr.UserId)] = true
    apBlacklistSync()
end
function apBlacklistRemove(plr)
    if not plr then return end
    _G.apBlacklist[plr.UserId] = nil
    _G.apBlacklist[tostring(plr.UserId)] = nil
    local n, d = tostring(plr.Name):lower(), tostring(plr.DisplayName or ""):lower()
    for i = #_G.apBlacklistNames, 1, -1 do
        local nm = tostring(_G.apBlacklistNames[i]):lower()
        if nm == n or nm == d then table.remove(_G.apBlacklistNames, i) end
    end
    apBlacklistSync()
end
function apBlacklistTogglePlayer(plr)
    if not plr then return end
    if isPlayerBlacklisted(plr) then apBlacklistRemove(plr) else apBlacklistAdd(plr) end
    return isPlayerBlacklisted(plr)
end
function apBlacklistAddName(name)
    name = tostring(name or ""):gsub("^%s+",""):gsub("%s+$","")
    if name == "" then return false end
    for _, nm in ipairs(_G.apBlacklistNames) do
        if tostring(nm):lower() == name:lower() then return false end
    end
    table.insert(_G.apBlacklistNames, name)
    apBlacklistSync()
    return true
end
function apBlacklistRemoveName(name)
    for i = #_G.apBlacklistNames, 1, -1 do
        if tostring(_G.apBlacklistNames[i]):lower() == tostring(name):lower() then
            table.remove(_G.apBlacklistNames, i)
        end
    end
    apBlacklistSync()
end
function apBlacklistRemoveUid(uid)
    _G.apBlacklist[uid] = nil
    _G.apBlacklist[tostring(uid)] = nil
    if tonumber(uid) then _G.apBlacklist[tonumber(uid)] = nil end
    apBlacklistSync()
end

do
local _xchan
local _gu=debug.getupvalues or getupvalues
local function _isCh(v)
if type(v)~="table" then return false end
local o,y=pcall(function()return type(v.GetTable)=="function" and type(v.GetIndex)=="function" end)
return o and y
end
local function _chans()
if _xchan then return _xchan end
local ok,sync=pcall(function()return require(game:GetService("ReplicatedStorage"):WaitForChild("Packages"):WaitForChild("Synchronizer"))end)
if not(ok and type(sync)=="table")or not _gu then return nil end
if type(sync.GetTableFromChannel)=="function" then
local ok2,ups=pcall(_gu,sync.GetTableFromChannel)
if ok2 and type(ups)=="table" then
for _,u in pairs(ups)do if type(u)=="table" then _xchan=u break end end
end
end
if not _xchan then
for _,fn in pairs(sync)do
if type(fn)=="function" then
local o2,u2=pcall(_gu,fn)
if o2 and type(u2)=="table" then
for _,u in pairs(u2)do
if type(u)=="table" then
local n,g=0,0
for k,v in pairs(u)do n=n+1 if type(k)=="string" and _isCh(v)then g=g+1 end if n>=4 then break end end
if n>0 and g==n then _xchan=u break end
end
end
end
end
if _xchan then break end
end
end
return _xchan
end
-- Keep these helpers private to Meerko AP. The optimizer also owns the shared
-- XenSyncAll/XenSyncGet API; overwriting those functions breaks its target cache.
local function _apXenSyncAll()
    if type(_G.XenSyncAll) == "function" then
        local ok, result = pcall(_G.XenSyncAll)
        if ok and type(result) == "table" then return result end
    end
    return _chans()
end
local function _apXenSyncGet(idx)
    if idx == nil then return nil end
    if type(_G.XenSyncGet) == "function" then
        local ok, result = pcall(_G.XenSyncGet, idx)
        if ok and result ~= nil then return result end
    end
    local t = _chans()
    if type(t) == "table" then
        local ok, result = pcall(rawget, t, idx)
        if ok then return result end
    end
    return nil
end
-- Only provide compatibility globals if no other script has defined them.
if type(_G.XenSyncAll) ~= "function" then
    _G.XenSyncAll = function() return _chans() end
end
if type(_G.XenSyncGet) ~= "function" then
    _G.XenSyncGet = function(idx)
        local t = _chans()
        if not t or idx == nil then return nil end
        return rawget(t, idx)
    end
end
_G._xenRawCT=function(plotName)
local c=_apXenSyncGet(plotName)
if not c then return nil end
return rawget(c,"CacheTable")
end
local _AD,_MD,_TD
local function _data()
if _AD then return true end
local ok=pcall(function()
local d=game:GetService("ReplicatedStorage"):WaitForChild("Datas")
_AD=require(d:WaitForChild("Animals"))
_MD=require(d:WaitForChild("Mutations"))
_TD=require(d:WaitForChild("Traits"))
end)
return ok and _AD~=nil
end
_G._xenGen=function(index,mutation,traits)
if not _data() then return 0 end
local info=_AD[index]
if not info or not info.Generation then return 0 end
local mult=1
if mutation and mutation~="None" and mutation~="" then
local m=_MD[mutation]
if m and m.Modifier then mult=mult+m.Modifier end
end
if type(traits)=="table" then
for _,tr in ipairs(traits)do
local t=_TD[tr]
if t and t.MultiplierModifier then mult=mult+t.MultiplierModifier end
end
end
return info.Generation*mult
end
_G._xenAnimShim=setmetatable({GetGeneration=function(_,index,mutation,traits)return _G._xenGen(index,mutation,traits)end},{
__index=function(_,k)
local ok,real=pcall(function()return require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Animals"))end)
if ok and type(real)=="table" then return rawget(real,k) end
return nil
end})
end

do
    local cached
    function _G.__getSync()
        if cached then return cached end
        local ok, mod = pcall(function()
            local pkgs = ReplicatedStorage:FindFirstChild("Packages")
            return pkgs and require(pkgs:WaitForChild("Synchronizer", 5))
        end)
        if ok then cached = mod end
        return cached
    end
end


function getPlotOwner(plot)
    if not plot then return nil end
    local Synchronizer = _G.__getSync()
    if Synchronizer then
        local ch = _apXenSyncGet(plot.Name)
        if ch then
            local owner = ch:Get("Owner")
            if owner then
                if typeof(owner) == "Instance" and owner:IsA("Player") then
                    return owner
                elseif type(owner) == "table" and owner.Name then
                    return Players:FindFirstChild(owner.Name)
                elseif type(owner) == "number" then
                    return Players:GetPlayerByUserId(owner)
                end
            end
        end
    end
    local sign = plot:FindFirstChild("PlotSign")
    local textLabel = sign
        and sign:FindFirstChild("SurfaceGui")
        and sign.SurfaceGui:FindFirstChild("Frame")
        and sign.SurfaceGui.Frame:FindFirstChild("TextLabel")
    if textLabel then
        local baseText = textLabel.Text
        local nickname = (baseText and baseText:match("^(.-)'")) or baseText
        if nickname then
            for _, p in ipairs(Players:GetPlayers()) do
                if (p.DisplayName == nickname) or (p.Name == nickname) then
                    return p
                end
            end
        end
    end
    return nil
end

function getPlotAtPosition(pos)
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return nil end
    local closestPlot = nil
    local minDistance = math.huge
    for _, plot in ipairs(plots:GetChildren()) do
        local plotPos
        if plot:IsA("Model") then
            plotPos = plot.PrimaryPart and plot.PrimaryPart.Position or plot:GetPivot().Position
        else
            plotPos = plot.Position
        end
        if plotPos then
            local distH = math.sqrt((pos.X - plotPos.X)^2 + (pos.Z - plotPos.Z)^2)
            if distH < minDistance then
                minDistance = distH
                closestPlot = plot
            end
        end
    end
    if closestPlot and minDistance < 72 then
        return closestPlot
    end
    return nil
end

function getPlayerBaseInfo(plr)
    if not plr or not plr.Character then return nil, nil end
    local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil, nil end
    local plot = getPlotAtPosition(hrp.Position)
    if plot then
        return plot, getPlotOwner(plot)
    end
    return nil, nil
end

do
    local cachedId, lastT = nil, 0
    function _G.__getCurrentBaseOwnerId()
        local now = os.clock()
        if (now - lastT) < 0.4 then return cachedId end
        lastT = now
        cachedId = nil
        local _, owner = getPlayerBaseInfo(LocalPlayer)
        if owner then cachedId = owner.UserId end
        return cachedId
    end
end

_MynxxMorphCache = _MynxxMorphCache or {}
_MynxxStealSession = _MynxxStealSession or {}
Players.PlayerRemoving:Connect(function(plr)
    _MynxxMorphCache[plr.UserId] = nil
    _MynxxStealSession[plr.UserId] = nil
end)

function getStealingInfo(plr)
    if not plr or not plr.Character then return nil, nil end
    local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil, nil end

    pcall(function()
        if not _MynxxAnimalsData then
            local Datas = ReplicatedStorage:FindFirstChild("Datas")
            _MynxxAnimalsData = Datas and require(Datas:FindFirstChild("Animals"))
        end
        local AD = _MynxxAnimalsData
        if AD and not _MynxxAnimalNames then
            _MynxxAnimalNames = {}
            for idx, info in pairs(AD) do
                local disp = (type(info) == "table" and info.DisplayName) or tostring(idx)
                _MynxxAnimalNames[tostring(idx):lower()] = disp
                _MynxxAnimalNames[tostring(disp):lower()] = disp
            end
        end
    end)

    if plr:GetAttribute("Stealing") ~= true then
        _MynxxStealSession[plr.UserId] = nil
        local mc = _MynxxMorphCache[plr.UserId]
        if _MynxxAnimalNames and (not mc or (os.clock() - mc.t) > 1) then
            local names = {}
            pcall(function()
                for _, m in ipairs(plr.Character:GetDescendants()) do
                    if (m:IsA("Model") or m:IsA("MeshPart")) and _MynxxAnimalNames[m.Name:lower()] then
                        names[m.Name:lower()] = true
                    end
                end
            end)
            _MynxxMorphCache[plr.UserId] = { t = os.clock(), names = names }
        end
        return nil, nil
    end

    local sess = _MynxxStealSession[plr.UserId]
    if type(sess) == "string" then
        sess = { name = sess, locked = true }
        _MynxxStealSession[plr.UserId] = sess
    end

    if sess and sess.locked then
        return sess.owner, sess.name
    end

    local attrIdx = plr:GetAttribute("StealingIndex")
    if attrIdx ~= nil and tostring(attrIdx) ~= "" then
        local nm = tostring(attrIdx)
        if _MynxxAnimalNames then nm = _MynxxAnimalNames[nm:lower()] or nm end
        local sOwner = sess and sess.owner or nil
        _MynxxStealSession[plr.UserId] = { name = nm, owner = sOwner, locked = true }
        return sOwner, nm
    end

    local morphNames = _MynxxMorphCache[plr.UserId] and _MynxxMorphCache[plr.UserId].names

    local carried
    pcall(function()
        if _MynxxAnimalNames then
            for _, m in ipairs(plr.Character:GetDescendants()) do
                if m:IsA("Model") or m:IsA("MeshPart") then
                    local key = m.Name:lower()
                    local hit = _MynxxAnimalNames[key]
                    if hit and not (morphNames and morphNames[key]) then
                        carried = hit
                        return
                    end
                end
            end
        end
    end)
    if carried then
        local sOwner = sess and sess.owner or nil
        _MynxxStealSession[plr.UserId] = { name = carried, owner = sOwner, locked = true }
        return sOwner, carried
    end

    if sess and sess.t and (os.clock() - sess.t) < 0.4 then
        return sess.owner, sess.name
    end

    local isPlayingAnim = false
    local hum = plr.Character:FindFirstChildOfClass("Humanoid")
    local animator = hum and hum:FindFirstChildOfClass("Animator")
    if animator then
        pcall(function()
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                local id = track.Animation and track.Animation.AnimationId
                if id and (id:find("18537363391") or id:find("steal") or id:find("grab")) then
                    isPlayingAnim = true
                    break
                end
            end
        end)
    end

    local plots = Workspace:FindFirstChild("Plots")
    if plots then
        local maxDist = isPlayingAnim and 12 or 4.5
        local Synchronizer
        pcall(function() Synchronizer = _G.__getSync() end)
        local bestOwner, bestName, bestDist = nil, nil, maxDist
        local fbOwner, fbDist = nil, maxDist
        for _, plot in ipairs(plots:GetChildren()) do
            local owner = getPlotOwner(plot)
            if owner == plr then continue end

            local podiums = plot:FindFirstChild("AnimalPodiums")
            if podiums then
                local al
                pcall(function()
                    local ch = Synchronizer and _apXenSyncGet(plot.Name)
                    al = ch and ch:Get("AnimalList")
                end)
                for _, pod in ipairs(podiums:GetChildren()) do
                    local base = pod:FindFirstChild("Base")
                    local spawn = base and base:FindFirstChild("Spawn")
                    if spawn then
                        local dist = (hrp.Position - spawn.Position).Magnitude
                        local ad = al and (al[pod.Name] or al[tonumber(pod.Name)])
                        if ad and type(ad) == "table" and ad.Index then
                            if dist < bestDist then
                                local animalName = tostring(ad.Index)
                                pcall(function()
                                    if _MynxxAnimalNames then
                                        animalName = _MynxxAnimalNames[animalName:lower()] or animalName
                                    end
                                end)
                                bestDist = dist; bestOwner = owner; bestName = animalName
                            end
                        elseif dist < fbDist then
                            fbDist = dist; fbOwner = owner
                        end
                    end
                end
            end
        end
        if bestOwner and (not fbOwner or bestDist <= fbDist) then
            _MynxxStealSession[plr.UserId] = { name = bestName, owner = bestOwner, locked = false, t = os.clock() }
            return bestOwner, bestName
        end
        if fbOwner then
            local nm = (sess and sess.name) or "Brainrot"
            _MynxxStealSession[plr.UserId] = { name = nm, owner = fbOwner, locked = false, t = os.clock() }
            return fbOwner, nm
        end
    end

    if sess and sess.name then
        return sess.owner, sess.name
    end
    return nil, "Brainrot"
end

function isOurOverheadBillboard(bb)
    if not bb or not bb.Name then return true end
    local n = bb.Name
    if n:find("^PlayerESP_") or n:find("^BrainrotESP_") or n:find("PlotBeam") then return true end
    if n == "Overhead" or n == "StealProgressBar" or n == "ZenithPanel" then return true end
    return false
end

_MynxxJTCache = _MynxxJTCache or {}
function getPlayerJoinerTag(plr)
    if not plr or not plr.Character then return nil end
    local _c = _MynxxJTCache[plr.UserId]
    if _c and (os.clock() - _c.t) < 3 then return _c.tag or nil end
    local lines, seen = {}, {}
    local function addLine(t)
        if not t or type(t) ~= "string" then return end
        t = t:gsub("^%s+", ""):gsub("%s+$", "")
        if t == "" or #t > 64 then return end
        if t == plr.Name or t == plr.DisplayName then return end
        local key = t:lower()
        if seen[key] then return end
        seen[key] = true
        table.insert(lines, t)
    end
    local function scanBillboard(bb)
        if not bb:IsA("BillboardGui") or not bb.Enabled then return end
        if isOurOverheadBillboard(bb) then return end
        for _, lbl in ipairs(bb:GetDescendants()) do
            if (lbl:IsA("TextLabel") or lbl:IsA("TextBox")) and lbl.Visible ~= false then
                addLine(lbl.Text)
            end
        end
    end
    for _, desc in ipairs(plr.Character:GetDescendants()) do
        if desc:IsA("BillboardGui") then scanBillboard(desc) end
    end
    local function scanAdorneed(cont)
        if not cont then return end
        for _, bb in ipairs(cont:GetDescendants()) do
            if bb:IsA("BillboardGui") and bb.Adornee and plr.Character
                and bb.Adornee:IsDescendantOf(plr.Character) then
                scanBillboard(bb)
            end
        end
    end
    pcall(function() scanAdorneed(playerGui) end)
    pcall(function() scanAdorneed(typeof(gethui) == "function" and gethui() or game:GetService("CoreGui")) end)
    pcall(function()
        for attrName, attrVal in pairs(plr:GetAttributes()) do
            if typeof(attrVal) == "string" and #attrVal > 0 and #attrVal <= 40 then
                local an = attrName:lower()
                if an:find("hub") or an:find("script") or an:find("joiner") or an:find("executor") or an:find("tag") then
                    addLine(attrVal)
                end
            end
        end
    end)
    local result = (#lines > 0) and table.concat(lines, " · ") or nil
    _MynxxJTCache[plr.UserId] = { t = os.clock(), tag = result or false }
    return result
end
_G.getPlayerJoinerTag = getPlayerJoinerTag

HUB_BADGES = {
    { pats = {"bad boy"},                                     badge = "[ BAD BOY ]",   color = Color3.fromRGB(255, 60, 60), allowAP = true },
    { pats = {"good boy", "fmly"}, badge = "[ FMLY User ]", color = Color3.fromRGB(255, 220, 60) },
    { pats = {"bt user", "bt hub", "bt "},                    badge = "[ BT User ]",   color = Color3.fromRGB(170, 80, 255) },
    { pats = {"w user", "wuser", "w hub", "notifier", "wblox", "w /"}, badge = "[ W User ]", color = Color3.fromRGB(255, 220, 60) },
}
_MynxxHubCache = _MynxxHubCache or {}
function getHubUserBadge(plr)
    local tag = getPlayerJoinerTag(plr)
    local raw = (tag or ""):lower()
    local cached = _MynxxHubCache[plr.UserId]
    if not cached then cached = {}; _MynxxHubCache[plr.UserId] = cached end
    for i, def in ipairs(HUB_BADGES) do
        if not cached[i] then
            for _, pat in ipairs(def.pats) do
                if raw:find(pat, 1, true) then cached[i] = true break end
            end
        end
    end
    local list = {}
    local isBadBoy = cached[1]
    for i, def in ipairs(HUB_BADGES) do
        if cached[i] then
            if not (isBadBoy and def.badge == "[ FMLY User ]") then
                list[#list + 1] = def
            end
        end
    end
    if #list == 0 then return nil, nil, tag, nil end
    return list[1].badge, list[1].color, tag, list
end
_G.getHubUserBadge = getHubUserBadge
Players.PlayerRemoving:Connect(function(plr) _MynxxHubCache[plr.UserId] = nil end)

FMLY_LIST_URL = "https://gist.githubusercontent.com/josecastle21/fcc5696b9d37ae086a324d99e6b8fa5e/raw/fmly_badboys.json"
FMLY_GIST_API = "https://api.github.com/gists/fcc5696b9d37ae086a324d99e6b8fa5e"
_G.FmlyGood    = _G.FmlyGood or {}
_G.FmlyBad     = _G.FmlyBad or {}
_G.FmlyReasons = _G.FmlyReasons or {}
_G.FmlyLinks   = _G.FmlyLinks or {}
_G.FmlyKeys    = _G.FmlyKeys or {}

do
    local function httpGetJson(url)
        local bust = url .. (url:find("?", 1, true) and "&" or "?") .. "cb=" .. tostring(os.time())
        local body
        pcall(function() body = game:HttpGet(bust, true) end)
        if type(body) ~= "string" and typeof(request) == "function" then
            pcall(function() body = request({ Url = bust, Method = "GET" }).Body end)
        end
        if type(body) ~= "string" and syn and syn.request then
            pcall(function() body = syn.request({ Url = bust, Method = "GET" }).Body end)
        end
        if type(body) ~= "string" and typeof(http_request) == "function" then
            pcall(function() body = http_request({ Url = bust, Method = "GET" }).Body end)
        end
        if type(body) ~= "string" then return nil end
        local decoded
        if pcall(function() decoded = HttpService:JSONDecode(body) end) then return decoded end
        return nil
    end

    -- Fallback: the GitHub gist API. Same payload, but wrapped in
    -- files["fmly_badboys.json"].content as a JSON string. Only used if the
    -- raw URL fails, since the API is rate limited to 60 req/hr unauthenticated.
    local function fmlyFromGistApi()
        local data = httpGetJson(FMLY_GIST_API)
        if type(data) ~= "table" then return nil end
        local f = data.files and data.files["fmly_badboys.json"]
        local inner = f and f.content
        if type(inner) ~= "string" then return nil end
        local decoded
        if pcall(function() decoded = HttpService:JSONDecode(inner) end) then return decoded end
        return nil
    end

    function refreshFmlyList()
        -- raw first (no rate limit), gist API as backup
        local data = httpGetJson(FMLY_LIST_URL)
        if type(data) ~= "table" or (data.good == nil and data.bad == nil) then
            data = fmlyFromGistApi()
        end
        if type(data) ~= "table" then return false end

        local good, bad = {}, {}
        if type(data.good) == "table" then
            for _, nm in ipairs(data.good) do
                if type(nm) == "string" then good[nm:lower()] = true end
            end
        end
        if type(data.bad) == "table" then
            for _, nm in ipairs(data.bad) do
                if type(nm) == "string" then bad[nm:lower()] = true end
            end
        end
        table.clear(_G.FmlyGood); for k in pairs(good) do _G.FmlyGood[k] = true end
        table.clear(_G.FmlyBad);  for k in pairs(bad)  do _G.FmlyBad[k]  = true end

        -- reasons: keyed by lowercase username -> why they were flagged
        table.clear(_G.FmlyReasons)
        if type(data.reasons) == "table" then
            for k, v in pairs(data.reasons) do
                if type(k) == "string" and type(v) == "string" and v ~= "" then
                    _G.FmlyReasons[k:lower()] = v
                end
            end
        end

        -- links / keys are account-linking data (roblox <-> discord) and license
        -- keys. Parsed so they're available, but deliberately NOT surfaced in any
        -- overhead ESP -- putting someone's Discord ID above their head is a
        -- different thing from flagging a griefer.
        table.clear(_G.FmlyLinks)
        if type(data.links) == "table" then
            for k, v in pairs(data.links) do _G.FmlyLinks[tostring(k)] = v end
        end
        table.clear(_G.FmlyKeys)
        if type(data.keys) == "table" then
            for k, v in pairs(data.keys) do _G.FmlyKeys[tostring(k)] = v end
        end
        return true
    end
    _G.refreshFmlyList = refreshFmlyList
end

-- Why a player is on the list, if the list says. nil when unknown.
function getFmlyReason(plr)
    if not plr then return nil end
    return _G.FmlyReasons[(plr.Name or ""):lower()]
end
_G.getFmlyReason = getFmlyReason

function getFmlyClass(plr)
    if not plr then return nil end
    local n = (plr.Name or ""):lower()
    if _G.FmlyBad[n]  then return "bad"  end
    if _G.FmlyGood[n] then return "good" end
    return nil
end
_G.getFmlyClass = getFmlyClass

-- ===== SON list =====
-- Same shape as FMLY, but the API is key-gated and uses safe/grief instead of
-- good/bad. Entries may be usernames or UserIds, so both are indexed.
SON_LIST_URL = "http://169.128.190.109:3000/api/lists"
SON_API_KEY  = "son-esp-key-2026"
_G.SonSafe  = _G.SonSafe or {}
_G.SonGrief = _G.SonGrief or {}

do
    local function sonFetch()
        local headers = { ["x-api-key"] = SON_API_KEY, ["Content-Type"] = "application/json" }
        local req = (syn and syn.request) or request or http_request
        local body
        if typeof(req) == "function" then
            local ok, res = pcall(req, { Url = SON_LIST_URL, Method = "GET", Headers = headers })
            if ok and res then body = res.Body or res.body end
        end
        if type(body) ~= "string" or #body == 0 then return nil end
        local decoded
        if pcall(function() decoded = HttpService:JSONDecode(body) end) then return decoded end
        return nil
    end

    -- accepts {"name", ...} or {{Name=..,UserId=..}, ...}
    local function indexInto(t, src)
        if type(src) ~= "table" then return end
        for _, v in ipairs(src) do
            if type(v) == "string" then
                t[v:lower()] = true
            elseif type(v) == "number" then
                t[tostring(v)] = true
            elseif type(v) == "table" then
                local nm = v.Name or v.name or v.username or v.Username
                local id = v.UserId or v.userId or v.userid or v.Id or v.id
                if type(nm) == "string" then t[nm:lower()] = true end
                if id ~= nil then t[tostring(id)] = true end
            end
        end
    end

    function refreshSonList()
        local data = sonFetch()
        if type(data) ~= "table" then return false end
        local safe, grief = {}, {}
        indexInto(safe,  data.safe)
        indexInto(grief, data.grief)
        table.clear(_G.SonSafe);  for k in pairs(safe)  do _G.SonSafe[k]  = true end
        table.clear(_G.SonGrief); for k in pairs(grief) do _G.SonGrief[k] = true end
        return true
    end
    _G.refreshSonList = refreshSonList
end

-- "grief" | "safe" | nil  (grief wins, it's the one that matters)
function getSonClass(plr)
    if not plr then return nil end
    local n  = (plr.Name or ""):lower()
    local id = tostring(plr.UserId or "")
    if _G.SonGrief[n] or _G.SonGrief[id] then return "grief" end
    if _G.SonSafe[n]  or _G.SonSafe[id]  then return "safe"  end
    return nil
end
_G.getSonClass = getSonClass

-- ===== KING list (goodboy-api) =====
-- Same shape as FMLY (good/bad usernames). Key-gated endpoint requires
-- local player name + displayName as query params.
KING_LIST_BASE = "http://151.241.100.83:3002/goodboys"
KING_API_KEY   = "GB-YVY6U-7K7DX-YYNBJ"
_G.KingGood = _G.KingGood or {}
_G.KingBad  = _G.KingBad  or {}

do
    local function kingFetch()
        local function urlEnc(s)
            s = tostring(s or "")
            local ok, out = pcall(function() return HttpService:UrlEncode(s) end)
            if ok and type(out) == "string" then return out end
            return (s:gsub("[^%w%-_%.~]", function(c)
                return string.format("%%%02X", string.byte(c))
            end))
        end
        local u = tostring(LocalPlayer and LocalPlayer.Name or "unknown")
        local d = tostring(LocalPlayer and (LocalPlayer.DisplayName ~= "" and LocalPlayer.DisplayName or LocalPlayer.Name) or "unknown")
        local url = KING_LIST_BASE
            .. "?key=" .. KING_API_KEY
            .. "&u=" .. urlEnc(u)
            .. "&d=" .. urlEnc(d)
            .. "&cb=" .. tostring(os.time())
        local req = (syn and syn.request) or request or http_request
        local body
        if typeof(req) == "function" then
            local ok, res = pcall(req, { Url = url, Method = "GET" })
            if ok and res then body = res.Body or res.body end
        end
        if type(body) ~= "string" or #body == 0 then
            pcall(function() body = game:HttpGet(url, true) end)
        end
        if type(body) ~= "string" or #body == 0 then return nil end
        local decoded
        if pcall(function() decoded = HttpService:JSONDecode(body) end) then return decoded end
        return nil
    end

    local function indexNames(t, src)
        if type(src) ~= "table" then return end
        for _, v in ipairs(src) do
            if type(v) == "string" then
                t[v:lower()] = true
            elseif type(v) == "number" then
                t[tostring(v)] = true
            elseif type(v) == "table" then
                local nm = v.Name or v.name or v.username or v.Username
                local id = v.UserId or v.userId or v.userid or v.Id or v.id
                if type(nm) == "string" then t[nm:lower()] = true end
                if id ~= nil then t[tostring(id)] = true end
            end
        end
    end

    function refreshKingList()
        local data = kingFetch()
        if type(data) ~= "table" or data.ok == false then return false end
        local good, bad = {}, {}
        indexNames(good, data.good)
        indexNames(bad,  data.bad)
        -- some payloads also put everyone under "usernames" — only use good/bad
        table.clear(_G.KingGood); for k in pairs(good) do _G.KingGood[k] = true end
        table.clear(_G.KingBad);  for k in pairs(bad)  do _G.KingBad[k]  = true end
        return true
    end
    _G.refreshKingList = refreshKingList
end

-- "bad" | "good" | nil  (bad wins)
function getKingClass(plr)
    if not plr then return nil end
    local n  = (plr.Name or ""):lower()
    local id = tostring(plr.UserId or "")
    if _G.KingBad[n]  or _G.KingBad[id]  then return "bad"  end
    if _G.KingGood[n] or _G.KingGood[id] then return "good" end
    return nil
end
_G.getKingClass = getKingClass

task.spawn(function()
    while true do
        pcall(refreshFmlyList)
        pcall(refreshSonList)
        pcall(refreshKingList)
        task.wait(6 * 60 * 60)
    end
end)

do
    -- Player ESP -- overhead name + distance + body highlight over every player.
    -- Ported from meerko. meerko's 2nd line was the owner's MVP pet, which needs the
    -- hub's pet scanner (absent here), so this shows distance instead.
    local espOn = false
    local conns = {}
    local huds  = {}   -- [plr] = { gui=, hl=, bb=, distLbl= }

    local function clearOne(plr)
        local d = huds[plr]
        if d then pcall(function() d.gui:Destroy() end); huds[plr] = nil end
    end

    local function build(plr)
        if plr == LocalPlayer then return end
        local char = plr.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        clearOne(plr)

        local holder = Instance.new("ScreenGui")
        holder.Name = "MeerkoPlayerESP_" .. plr.UserId
        holder.ResetOnSpawn = false
        holder.Parent = (typeof(gethui) == "function" and gethui()) or playerGui

        local hl = Instance.new("Highlight", holder)
        hl.Adornee = char
        hl.FillColor = Color3.fromRGB(255, 80, 80)
        hl.FillTransparency = 0.6
        hl.OutlineColor = Color3.fromRGB(255, 180, 180)
        hl.OutlineTransparency = 0
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop

        local bb = Instance.new("BillboardGui", holder)
        bb.Name = "MeerkoPlayerBB_" .. plr.UserId
        bb.Adornee = hrp
        bb.AlwaysOnTop = true
        bb.Size = UDim2.new(0, 180, 0, 44)
        bb.StudsOffset = Vector3.new(0, 3.2, 0)
        bb.ResetOnSpawn = false

        local nameLbl = Instance.new("TextLabel", bb)
        nameLbl.Size = UDim2.new(1, 0, 0.5, 0)
        nameLbl.BackgroundTransparency = 1
        nameLbl.Text = plr.DisplayName
        nameLbl.Font = Enum.Font.GothamBlack
        nameLbl.TextSize = 14
        nameLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
        nameLbl.TextStrokeTransparency = 0.3
        nameLbl.TextXAlignment = Enum.TextXAlignment.Center

        local distLbl = Instance.new("TextLabel", bb)
        distLbl.Size = UDim2.new(1, 0, 0.5, 0)
        distLbl.Position = UDim2.new(0, 0, 0.5, 0)
        distLbl.BackgroundTransparency = 1
        distLbl.Text = ""
        distLbl.Font = Enum.Font.GothamBold
        distLbl.TextSize = 11
        distLbl.TextColor3 = Color3.fromRGB(160, 210, 255)
        distLbl.TextStrokeTransparency = 0.4
        distLbl.TextXAlignment = Enum.TextXAlignment.Center

        huds[plr] = { gui = holder, hl = hl, bb = bb, distLbl = distLbl }
    end

    local function enable()
        if espOn then return end
        espOn = true
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                pcall(build, plr)
                table.insert(conns, plr.CharacterAdded:Connect(function()
                    if espOn then task.wait(0.5); pcall(build, plr) end
                end))
            end
        end
        table.insert(conns, Players.PlayerAdded:Connect(function(plr)
            if not espOn then return end
            plr.CharacterAdded:Connect(function()
                if espOn then task.wait(0.5); pcall(build, plr) end
            end)
            task.wait(1); if espOn then pcall(build, plr) end
        end))
        table.insert(conns, Players.PlayerRemoving:Connect(function(plr) clearOne(plr) end))
        table.insert(conns, RunService.Heartbeat:Connect(function()
            if not espOn then return end
            local myChar = LocalPlayer.Character
            local myHrp  = myChar and myChar:FindFirstChild("HumanoidRootPart")
            for plr, d in pairs(huds) do
                if not plr.Parent then clearOne(plr)
                else
                    local char = plr.Character
                    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        if d.bb.Adornee ~= hrp then d.bb.Adornee = hrp; d.hl.Adornee = char end
                        if myHrp then
                            d.distLbl.Text = string.format("%d studs", math.floor((hrp.Position - myHrp.Position).Magnitude))
                        end
                    end
                end
            end
        end))
    end

    local function disable()
        espOn = false
        for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
        conns = {}
        for plr in pairs(huds) do clearOne(plr) end
        huds = {}
    end

    _G.MeerkoSetPlayerESP = function(v) if v then enable() else disable() end end
    _G.MeerkoPlayerESPOn  = function() return espOn end

    -- on by default (replaces the always-on classification ESP); toggle in the Ctrl panel
    if not (Config and Config.PlayerESP == false) then
        task.defer(function() task.wait(2); enable() end)
    end
end

function fireClick(button)
    if not button then return false end
    local ok=pcall(function()
        if typeof(firesignal)=="function" then
            pcall(firesignal, button.MouseButton1Click)
            pcall(firesignal, button.MouseButton1Down)
            pcall(firesignal, button.MouseButton1Up)
            pcall(firesignal, button.Activated)
        else
            local x=button.AbsolutePosition.X+(button.AbsoluteSize.X/2)
            local y=button.AbsolutePosition.Y+(button.AbsoluteSize.Y/2)+58
            VirtualInputManager:SendMouseButtonEvent(x,y,0,true,game,0)
            VirtualInputManager:SendMouseButtonEvent(x,y,0,false,game,0)
        end
    end); return ok
end
_G.fireClick=fireClick

function runAdminCommand(targetPlayer, commandName)
    pcall(function() if targetPlayer==LocalPlayer then _G.__MynxxSelfCmdT=os.clock() end end)
    if not targetPlayer or not commandName or commandName=="" then return false end
    if isPlayerBlacklisted(targetPlayer) then
        ShowNotification("BLOCKED", targetPlayer.DisplayName .. " is blacklisted")
        return false
    end
    do
        local _, _, _, hubList = getHubUserBadge(targetPlayer)
        local protBadge
        if hubList then
            for _, def in ipairs(hubList) do
                if def.badge == "[ BT User ]" or def.badge == "[ W User ]" then
                    protBadge = def.badge; break
                end
            end
        end
        if protBadge then
            ShowNotification("PROTECTED", targetPlayer.DisplayName .. " " .. protBadge)
            return false
        end
        if getFmlyClass(targetPlayer) == "good" then
            ShowNotification("PROTECTED", targetPlayer.DisplayName .. " [ FMLY GOOD ]")
            return false
        end
        if getKingClass(targetPlayer) == "good" then
            ShowNotification("PROTECTED", targetPlayer.DisplayName .. " [ KING GOOD ]")
            return false
        end
    end
    local realAdminGui=playerGui:FindFirstChild("AdminPanel")
    if not realAdminGui then realAdminGui=playerGui:WaitForChild("AdminPanel",3) end
    if not realAdminGui then return false end
    local wasEnabled = realAdminGui.Enabled
    realAdminGui.Enabled = true
    local okC,contentScroll=pcall(function() return realAdminGui.AdminPanel.Content.ScrollingFrame end)
    if not okC or not contentScroll then realAdminGui.Enabled=wasEnabled; return false end
    local cmdBtn=contentScroll:FindFirstChild(commandName); if not cmdBtn then realAdminGui.Enabled=wasEnabled; return false end
    fireClick(cmdBtn)
    task.wait(0.01)
    local okP,profilesScroll=pcall(function() return realAdminGui.AdminPanel.Profiles.ScrollingFrame end)
    if not okP or not profilesScroll then realAdminGui.Enabled=wasEnabled; return false end
    local playerBtn=profilesScroll:FindFirstChild(targetPlayer.Name)
    if not playerBtn then
        task.wait(0.01)
        playerBtn=profilesScroll:FindFirstChild(targetPlayer.Name)
    end
    if not playerBtn then
        for _,child in ipairs(profilesScroll:GetChildren()) do
            if child:IsA("GuiButton") then local nl=child:FindFirstChildWhichIsA("TextLabel")
                if nl and (nl.Text==targetPlayer.Name or nl.Text==targetPlayer.DisplayName) then playerBtn=child; break end
            end
        end
    end
    if not playerBtn then realAdminGui.Enabled=wasEnabled; return false end
    fireClick(playerBtn)
    apStartCooldown(commandName)
    task.delay(0.05, function()
        if realAdminGui and realAdminGui.Parent then realAdminGui.Enabled=wasEnabled end
    end)
    return true
end
_G.runAdminCommand=runAdminCommand

DANGER_TOOLS={["Boogie Bomb"]=true,["Medusa's Head"]=true,["Body Swap Potion"]=true,["Laser Cape"]=true,["Rainbowrath Sword"]=true,["Gummy Bear"]=true}
function getHeldTool(p) local c=p.Character; if not c then return nil end; for _,o in ipairs(c:GetChildren()) do if o:IsA("Tool") then return o.Name end end; return nil end

ProximityAPActive=false
proxAPRing = nil

function createProxAPRing()
    local existing = Workspace:FindFirstChild("XiProxAPRing")
    if existing then existing:Destroy() end
    local r = Instance.new("Part")
    r.Name = "XiProxAPRing"
    r.Shape = Enum.PartType.Cylinder
    r.Anchored = true
    r.CanCollide = false
    r.CanTouch = false
    r.CanQuery = false
    r.CastShadow = false
    r.Material = Enum.Material.Neon
    r.Transparency = 0.7
    r.Color = Color3.fromRGB(255, 40, 40)
    local range = Config.ProximityRange or 15
    r.Size = Vector3.new(0.2, range*2, range*2)
    r.Parent = Workspace
    proxAPRing = r
end

function destroyProxAPRing()
    if proxAPRing then proxAPRing:Destroy(); proxAPRing = nil end
    local e = Workspace:FindFirstChild("XiProxAPRing")
    if e then e:Destroy() end
end

_proxAPRingFrame=0
RunService.Heartbeat:Connect(function()
    if not ProximityAPActive then return end
    _proxAPRingFrame = _proxAPRingFrame + 1
    if _proxAPRingFrame < 2 then return end
    _proxAPRingFrame = 0
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp or not proxAPRing then return end
    local range = Config.ProximityRange or 15
    proxAPRing.Size = Vector3.new(0.2, range * 2, range * 2)
    proxAPRing.CFrame = (hrp.CFrame * CFrame.Angles(0, 0, math.rad(90))) - Vector3.new(0, 2.8, 0)
    if proxAPRing.Material ~= Enum.Material.Neon then proxAPRing.Material = Enum.Material.Neon end
    if proxAPRing.Transparency > 0.75 then proxAPRing.Transparency = 0.7 end
    proxAPRing.Color = Color3.fromRGB(255, 40, 40)
end)

function setProximityAP(on)
    ProximityAPActive = on
    Config.ProximityAP = false
    setToggle("Proximity", on)
    if on then createProxAPRing() else destroyProxAPRing() end
end

onToggleChanged("Proximity", function(on)
    ProximityAPActive = on
    Config.ProximityAP = false
    if on then createProxAPRing() else destroyProxAPRing() end
end)

task.spawn(function()
    while true do
        task.wait(0.2)
        if ProximityAPActive then
            local mc = player.Character
            local mh = mc and mc:FindFirstChild("HumanoidRootPart")
            if mh then
                for _,p in ipairs(Players:GetPlayers()) do
                    if p ~= player and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
                        if isPlayerBlacklisted(p) then continue end
                        if (p.Character.HumanoidRootPart.Position - mh.Position).Magnitude <= (Config.ProximityRange or 15) then
                            local activeCmds = {}
                            for _,cmd in ipairs(AP_ALL_COMMANDS) do
                                if not apIsOnCooldown(cmd) then
                                    table.insert(activeCmds, cmd)
                                end
                            end
                            for i, cmd in ipairs(activeCmds) do
                                task.spawn(function()
                                    task.wait((i - 1) * 0.01)
                                    runAdminCommand(p, cmd)
                                end)
                            end
                        end
                    end
                end
            end
        end
    end
end)

ctapHighlight=Instance.new("Highlight",CoreGui)
ctapHighlight.FillColor=Color3.fromRGB(220,32,45); ctapHighlight.FillTransparency=0.3
ctapHighlight.OutlineColor=Color3.fromRGB(255,58,68); ctapHighlight.OutlineTransparency=0
ctapHighlight.Adornee=nil; ctapHighlight.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop

function rayToCubeIntersect(rayOrigin,rayDirection,cubeCenter,cubeSize)
    local halfSize=cubeSize/2; local minB=cubeCenter-Vector3.new(halfSize,halfSize,halfSize); local maxB=cubeCenter+Vector3.new(halfSize,halfSize,halfSize)
    local rd=Vector3.new(rayDirection.X==0 and 0.0001 or rayDirection.X, rayDirection.Y==0 and 0.0001 or rayDirection.Y, rayDirection.Z==0 and 0.0001 or rayDirection.Z)
    local tmin,tmax=(minB.X-rayOrigin.X)/rd.X,(maxB.X-rayOrigin.X)/rd.X; if tmin>tmax then tmin,tmax=tmax,tmin end
    local tymin,tymax=(minB.Y-rayOrigin.Y)/rd.Y,(maxB.Y-rayOrigin.Y)/rd.Y; if tymin>tymax then tymin,tymax=tymax,tymin end
    if tmin>tymax or tymin>tmax then return false end; if tymin>tmin then tmin=tymin end; if tymax<tmax then tmax=tymax end
    local tzmin,tzmax=(minB.Z-rayOrigin.Z)/rd.Z,(maxB.Z-rayOrigin.Z)/rd.Z; if tzmin>tzmax then tzmin,tzmax=tzmax,tzmin end
    return not(tmin>tzmax or tzmin>tmax)
end

RunService.RenderStepped:Connect(function()
    if Config.ClickToAP then
        local camera=Workspace.CurrentCamera; local mousePos=UIS:GetMouseLocation()
        local ray=camera:ViewportPointToRay(mousePos.X,mousePos.Y); local bestPlayer,bestDist=nil,math.huge
        for _,p in ipairs(Players:GetPlayers()) do if p~=LocalPlayer and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
            if rayToCubeIntersect(ray.Origin,ray.Direction,p.Character.HumanoidRootPart.Position,Config.ClickToAPRadius or 8) then
                local dist=(ray.Origin-p.Character.HumanoidRootPart.Position).Magnitude; if dist<bestDist then bestDist=dist; bestPlayer=p end
            end
        end end
        ctapHighlight.Adornee=(bestPlayer and bestPlayer.Character) or nil
    else ctapHighlight.Adornee=nil end
end)

UIS.InputBegan:Connect(function(inp,g)
    if not g and inp.UserInputType==Enum.UserInputType.MouseButton1 and Config.ClickToAP then
        local camera=Workspace.CurrentCamera; local mousePos=UIS:GetMouseLocation()
        local ray=camera:ViewportPointToRay(mousePos.X,mousePos.Y); local bestPlayer,bestDist=nil,math.huge
        for _,p in ipairs(Players:GetPlayers()) do if p~=LocalPlayer and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
            if rayToCubeIntersect(ray.Origin,ray.Direction,p.Character.HumanoidRootPart.Position,Config.ClickToAPRadius or 8) then
                local dist=(ray.Origin-p.Character.HumanoidRootPart.Position).Magnitude; if dist<bestDist then bestDist=dist; bestPlayer=p end
            end
        end end
        if bestPlayer then
            if isPlayerBlacklisted(bestPlayer) then
                ShowNotification("CLICK AP", bestPlayer.DisplayName .. " is blacklisted")
                return
            end
            local cmdList = Config.ClickToAPOrder or AP_ALL_COMMANDS
            local startIndex = _G.ClickToAPIndex or 1
            if startIndex > #cmdList then startIndex = 1 end
            
            local picked = nil
            local attempts = 0
            while attempts < #cmdList do
                local idx = ((startIndex - 1 + attempts) % #cmdList) + 1
                local cmd = cmdList[idx]
                if Config.ClickToAPCommands and Config.ClickToAPCommands[cmd] and not apIsOnCooldown(cmd) then
                    picked = cmd
                    _G.ClickToAPIndex = idx + 1
                    break
                end
                attempts = attempts + 1
            end

            if not picked then
                ShowNotification("CLICK AP", "No commands enabled or all on cooldown")
                return
            end

            if runAdminCommand(bestPlayer, picked) then
                local emoji = AP_COMMAND_EMOJIS[picked] or "⚡"
                ShowNotification("CLICK AP", emoji .. " " .. picked .. " → " .. bestPlayer.DisplayName)
            end
        end
    end
end)

function spamPlayerBaseOwner(targetPlayer)
    if not targetPlayer then return 0 end
    local cmdList = Config.SpamBaseOwnerOrder or AP_ALL_COMMANDS
    
    if Config.SpamBaseOwnerSingleCommand then
        local startIndex = _G.SpamBaseOwnerIndex or 1
        if startIndex > #cmdList then startIndex = 1 end
        
        local picked = nil
        local attempts = 0
        while attempts < #cmdList do
            local idx = ((startIndex - 1 + attempts) % #cmdList) + 1
            local cmd = cmdList[idx]
            if Config.SpamBaseOwnerCommands and Config.SpamBaseOwnerCommands[cmd] and not apIsOnCooldown(cmd) then
                picked = cmd
                _G.SpamBaseOwnerIndex = idx + 1
                break
            end
            attempts = attempts + 1
        end
        
        if picked then
            runAdminCommand(targetPlayer, picked)
            return 1
        end
        return 0
    else
        local activeCmds = {}
        for _, cmd in ipairs(cmdList) do
            if Config.SpamBaseOwnerCommands and Config.SpamBaseOwnerCommands[cmd] and not apIsOnCooldown(cmd) then
                table.insert(activeCmds, cmd)
            end
        end
        task.spawn(function()
            for i, cmd in ipairs(activeCmds) do
                if not targetPlayer or not targetPlayer.Parent then break end
                runAdminCommand(targetPlayer, cmd)
                if i < #activeCmds then task.wait(1) end
            end
        end)
        return #activeCmds
    end
end

function spamBaseOwner()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        ShowNotification("SPAM OWNER", "No character found")
        return
    end
    local nearestPlot = nil
    local nearestDist = math.huge
    local Plots = Workspace:FindFirstChild("Plots")
    if Plots then
        for _, plot in ipairs(Plots:GetChildren()) do
            local sign = plot:FindFirstChild("PlotSign")
            if sign then
                local yourBase = sign:FindFirstChild("YourBase")
                if not yourBase or not yourBase.Enabled then
                    local signPos = (sign:IsA("BasePart") and sign.Position)
                        or (sign.PrimaryPart and sign.PrimaryPart.Position)
                    if not signPos then
                        local part = sign:FindFirstChildWhichIsA("BasePart", true)
                        signPos = part and part.Position
                    end
                    if signPos then
                        local dist = (hrp.Position - signPos).Magnitude
                        if dist < nearestDist then
                            nearestDist = dist
                            nearestPlot = plot
                        end
                    end
                end
            end
        end
    end
    if not nearestPlot then
        ShowNotification("SPAM OWNER", "No nearby base found")
        return
    end
    local targetPlayer = nil
    local ok, Synchronizer = pcall(require, ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Synchronizer"))
    if ok and Synchronizer then
        local ch = _apXenSyncGet(nearestPlot.Name)
        if ch then
            local owner = ch:Get("Owner")
            if owner then
                if (typeof(owner) == "Instance") and owner:IsA("Player") then
                    targetPlayer = owner
                elseif (type(owner) == "table") and owner.Name then
                    targetPlayer = Players:FindFirstChild(owner.Name)
                end
            end
        end
    end
    if not targetPlayer then
        local sign = nearestPlot:FindFirstChild("PlotSign")
        local textLabel = sign
            and sign:FindFirstChild("SurfaceGui")
            and sign.SurfaceGui:FindFirstChild("Frame")
            and sign.SurfaceGui.Frame:FindFirstChild("TextLabel")
        if textLabel then
            local baseText = textLabel.Text
            local nickname = (baseText and baseText:match("^(.-)'")) or baseText
            if nickname then
                for _, p in ipairs(Players:GetPlayers()) do
                    if (p.DisplayName == nickname) or (p.Name == nickname) then
                        targetPlayer = p
                        break
                    end
                end
            end
        end
    end
    if not targetPlayer or (targetPlayer == LocalPlayer) then
        ShowNotification("SPAM OWNER", "Owner not found or is you")
        return
    end
    if isPlayerBlacklisted(targetPlayer) then
        ShowNotification("SPAM OWNER", targetPlayer.DisplayName .. " is blacklisted")
        return
    end
    ShowNotification("SPAM OWNER", "Spamming " .. targetPlayer.DisplayName)
    local sentCount = spamPlayerBaseOwner(targetPlayer)
    ShowNotification("SPAM OWNER", "Sent " .. tostring(sentCount) .. " commands")
end

MK = {
    bg   = Color3.fromRGB(22, 24, 33),  surf = Color3.fromRGB(34, 38, 52),
    acc  = Color3.fromRGB(102,140,255), grn  = Color3.fromRGB(72, 199,142),
    text = Color3.fromRGB(232,236,244), dim  = Color3.fromRGB(138,148,172),
    brd  = Color3.fromRGB(52, 58, 78),  off  = Color3.fromRGB(25, 28, 38),
}
function mkShell(parent, w, h, name)
    local f = Instance.new("Frame")
    f.Name = name; f.Size = UDim2.fromOffset(w, h)
    f.BackgroundColor3 = MK.bg; f.BorderSizePixel = 0; f.Parent = parent
    corner(f, 12)
    MeerkoResize(f, math.min(w, 180), math.min(h, 140), name)
    local s = Instance.new("UIStroke", f)
    s.Color = MK.brd; s.Thickness = 1; s.Transparency = 0.35
    local g = Instance.new("UIGradient", f)
    g.Color = ColorSequence.new(Color3.fromRGB(30,33,46), Color3.fromRGB(20,22,30))
    g.Rotation = 90
    return f
end
function mkTitle(parent, text, sub)
    local t = Instance.new("TextLabel", parent)
    t.Size = UDim2.new(1,-24,0,20); t.Position = UDim2.fromOffset(12,10)
    t.BackgroundTransparency = 1; t.Text = text; t.TextColor3 = MK.acc
    t.Font = Enum.Font.GothamBlack; t.TextSize = 16; t.ZIndex = 201
    t.TextXAlignment = Enum.TextXAlignment.Left
    if sub then
        local s = Instance.new("TextLabel", parent)
        s.Size = UDim2.new(1,-24,0,12); s.Position = UDim2.fromOffset(12,29)
        s.BackgroundTransparency = 1; s.Text = sub; s.TextColor3 = MK.dim
        s.Font = Enum.Font.GothamSemibold; s.TextSize = 9; s.ZIndex = 201
        s.TextXAlignment = Enum.TextXAlignment.Left
    end
    return t
end
function mkBtn(parent, text, cb, order)
    local b = Instance.new("TextButton", parent)
    b.Size = UDim2.new(1,0,0,32); b.BackgroundColor3 = MK.surf
    b.Text = text; b.TextColor3 = MK.text; b.Font = Enum.Font.GothamBold
    b.TextSize = 12; b.AutoButtonColor = false; b.BorderSizePixel = 0
    b.ZIndex = 202; b.LayoutOrder = order or 0
    corner(b, 8)
    local s = Instance.new("UIStroke", b); s.Color = MK.brd; s.Thickness = 1; s.Transparency = 0.5
    b.MouseEnter:Connect(function() tw(b,{BackgroundColor3=MK.acc},0.12) end)
    b.MouseLeave:Connect(function() tw(b,{BackgroundColor3=MK.surf},0.12) end)
    b.MouseButton1Click:Connect(cb)
    return b
end
function mkToggle(parent, text, get, set, order)
    local row = Instance.new("Frame", parent)
    row.Size = UDim2.new(1,0,0,28); row.BackgroundTransparency = 1
    row.ZIndex = 202; row.LayoutOrder = order or 0
    local l = Instance.new("TextLabel", row)
    l.Size = UDim2.new(1,-46,1,0); l.BackgroundTransparency = 1
    l.Text = text; l.TextColor3 = MK.text; l.Font = Enum.Font.GothamSemibold
    l.TextSize = 12; l.TextXAlignment = Enum.TextXAlignment.Left; l.ZIndex = 203
    local sw = Instance.new("TextButton", row)
    sw.AnchorPoint = Vector2.new(1,0.5); sw.Position = UDim2.new(1,0,0.5,0)
    sw.Size = UDim2.fromOffset(38,18); sw.AutoButtonColor = false; sw.Text = ""
    sw.BackgroundColor3 = MK.off; sw.BorderSizePixel = 0; sw.ZIndex = 203
    corner(sw, 9)
    local kn = Instance.new("Frame", sw)
    kn.Size = UDim2.fromOffset(14,14); kn.AnchorPoint = Vector2.new(0,0.5)
    kn.Position = UDim2.new(0,2,0.5,0); kn.BackgroundColor3 = MK.dim
    kn.BorderSizePixel = 0; kn.ZIndex = 204
    corner(kn, 7)
    local function paint()
        local on = get() and true or false
        tw(sw, { BackgroundColor3 = on and MK.grn or MK.off }, 0.15)
        tw(kn, {
            BackgroundColor3 = on and Color3.fromRGB(245,248,255) or MK.dim,
            Position = on and UDim2.new(1,-16,0.5,0) or UDim2.new(0,2,0.5,0),
        }, 0.15)
    end
    paint()
    sw.MouseButton1Click:Connect(function() set(not (get() and true or false)); paint() end)
    task.spawn(function() while row.Parent do task.wait(0.5); pcall(paint) end end)
    return row
end

-- ===== DOGE FLING (engine grafted verbatim from message__1_.txt; standalone UI dropped) =====
do
local Players    = game:GetService("Players")
local Workspace  = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local CoreGui    = game:GetService("CoreGui")
local player     = Players.LocalPlayer

-- =========================================================================
-- MODULE
-- =========================================================================
local DogeFling = (function()
    local MAX_RADIUS      = 60
    local FLING_DURATION  = 2.5
    local LINEAR_XZ_MAX   = 4000
    local LINEAR_Y_MIN    = 2000
    local LINEAR_Y_MAX    = 6000
    local ANGULAR         = 10000

    local EQUIP_DELAY   = 0.1    -- doge must register as equipped before Activate() will place
    local ACTIVATE_GAP  = 0.08   -- re-activate + poll window while waiting for the doge to appear
    local PLACE_TIMEOUT = 2.0    -- stop trying to place after this long

    local activeFling = nil

    local function findMyDoge()
        local model = Workspace:FindFirstChild("PlayerName_" .. player.Name .. "_Doge")
        if model then return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart") end
        local nameLower = player.Name:lower()
        for _, c in ipairs(Workspace:GetChildren()) do
            local nl = c.Name:lower()
            if nl:find("doge") and nl:find(nameLower) then
                if c:IsA("BasePart") then return c end
                if c:IsA("Model") then
                    local part = c.PrimaryPart or c:FindFirstChildWhichIsA("BasePart")
                    if part then return part end
                end
            end
        end
        return nil
    end

    local function findAttackDogeTool()
        local char = player.Character
        if not char then return nil end
        local bp = player:FindFirstChild("Backpack")
        local t = char:FindFirstChild("Attack Doge")
            or (bp and bp:FindFirstChild("Attack Doge"))
        if t then return t end
        for _, container in ipairs({ char, bp }) do
            if container then
                for _, tool in ipairs(container:GetChildren()) do
                    if tool:IsA("Tool") and tool.Name:lower():find("doge") then
                        return tool
                    end
                end
            end
        end
        return nil
    end

    local function findFlyingCarpetTool()
        local char = player.Character
        if not char then return nil end
        local bp = player:FindFirstChild("Backpack")
        local t = char:FindFirstChild("Flying Carpet")
            or (bp and bp:FindFirstChild("Flying Carpet"))
        if t then return t end
        for _, container in ipairs({ char, bp }) do
            if container then
                for _, tool in ipairs(container:GetChildren()) do
                    if tool:IsA("Tool") and tool.Name:lower():find("carpet") then
                        return tool
                    end
                end
            end
        end
        return nil
    end

    local function ensureDoge()
        local doge = findMyDoge()
        if not doge then
            local char = player.Character
            if not char then return nil end
            local hum = char:FindFirstChildOfClass("Humanoid")
            if not hum then return nil end
            local bp = player:FindFirstChild("Backpack")
            local tool = findAttackDogeTool()
            if not tool then return nil end

            -- take out the doge
            if tool.Parent ~= char then
                tool.Parent = char
                task.wait(EQUIP_DELAY)
            end

            -- keep activating and watch the workspace until the doge actually appears
            local deadline = os.clock() + PLACE_TIMEOUT
            while os.clock() < deadline do
                pcall(function() tool:Activate() end)
                local nextTry = os.clock() + ACTIVATE_GAP
                repeat
                    doge = findMyDoge()
                    if doge then break end
                    RunService.Heartbeat:Wait()
                until os.clock() >= nextTry
                if doge then break end
            end

            -- stow the doge tool
            if bp and tool.Parent == char then
                tool.Parent = bp
            end
        end

        -- the instant it's placed (or was already down), switch to the carpet
        if doge then
            local carpet = findFlyingCarpetTool()
            if carpet then
                local ch = player.Character
                if ch and carpet.Parent ~= ch then
                    pcall(function() carpet.Parent = ch end)
                end
            end
        end

        return doge
    end

    local function stopFling()
        if not activeFling then return end
        if activeFling.conn then activeFling.conn:Disconnect() end
        activeFling = nil
    end

    local function fireAt(targetPlayer)
        stopFling()
        local myChar = player.Character
        local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if not myHRP then return false end
        ensureDoge()  -- equip, place (waits until detected), then switch to carpet
        local tc = targetPlayer.Character
        local thrp = tc and tc:FindFirstChild("HumanoidRootPart")
        if not thrp then return false end

        local startTime = os.clock()
        local dogePart = nil
        activeFling = { target = targetPlayer }
        activeFling.conn = RunService.Heartbeat:Connect(function()
            if os.clock() - startTime > FLING_DURATION then stopFling(); return end
            local curMyChar = player.Character
            local curMyHRP = curMyChar and curMyChar:FindFirstChild("HumanoidRootPart")
            local curTC = targetPlayer.Character
            local curTHRP = curTC and curTC:FindFirstChild("HumanoidRootPart")
            if not curMyHRP or not curTHRP then stopFling(); return end
            if not dogePart or not dogePart:IsDescendantOf(Workspace) then
                dogePart = findMyDoge()
            end
            if not dogePart then return end
            local offset = curTHRP.Position - curMyHRP.Position
            local dist = offset.Magnitude
            local clampedPos = (dist > MAX_RADIUS) and (curMyHRP.Position + offset.Unit * (MAX_RADIUS - 1)) or curTHRP.Position
            dogePart.CFrame = CFrame.new(clampedPos) * CFrame.Angles(
                math.rad(math.random(-180, 180)),
                math.rad(math.random(-180, 180)),
                math.rad(math.random(-180, 180))
            )
            dogePart.AssemblyLinearVelocity = Vector3.new(
                math.random(-LINEAR_XZ_MAX, LINEAR_XZ_MAX),
                math.random( LINEAR_Y_MIN,  LINEAR_Y_MAX),
                math.random(-LINEAR_XZ_MAX, LINEAR_XZ_MAX)
            )
            dogePart.AssemblyAngularVelocity = Vector3.new(ANGULAR, ANGULAR, ANGULAR)
        end)
        return true
    end

    return {
        fireAt = function(target) task.spawn(function() pcall(fireAt, target) end) end,
        stop   = stopFling,
        RANGE  = MAX_RADIUS,
    }
end)()

_G._FH_DogeFling = DogeFling
end
-- ===== END DOGE FLING =====

-- ===== LASER CAPE (engine grafted verbatim from message.txt; standalone UI dropped) =====
_G._FH_LaserCape = (function()
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer
local AIM_TARGET_PARTS = {"HumanoidRootPart", "UpperTorso", "Torso", "Head"}
local AIM_LEAD_TIME    = 0.18
local EQUIP_DELAY      = 0.006   -- cape equip must register server-side
local SHOT_INTERVAL    = 0.005   -- gap between shots — server rate-limits same-frame floods
local POST_FIRE_WAIT   = 0.005   -- last shot must arrive before we unequip
local SWAP_GAP         = 0.004   -- gap between carpet unequip and cape equip
local BURST_SHOTS      = 5
_G._FH_ResolveUseItemRemote = _G._FH_ResolveUseItemRemote or function()
    local cached = _G._FH_UseItemRemote
    if typeof(cached) == "Instance" and cached.Parent then return cached end
    local nm = _G._FH_NET
    if nm and typeof(nm.UseItem) == "Instance" and nm.UseItem.Parent then
        _G._FH_UseItemRemote = nm.UseItem; return nm.UseItem
    end
    local _getconnections = getconnections
    local _getconstants   = (debug and debug.getconstants) or getconstants
    if type(_getconnections) ~= "function" or type(_getconstants) ~= "function" then return nil end
    local ok, netFolder = pcall(function()
        return ReplicatedStorage:WaitForChild("Packages", 15):WaitForChild("Net", 15)
    end)
    if not ok or not netFolder then return nil end
    local found
    for _, r in ipairs(netFolder:GetChildren()) do
        if r:IsA("RemoteEvent") and not found then
            local okc, conns = pcall(_getconnections, r.OnClientEvent)
            if okc and conns then
                for _, c2 in ipairs(conns) do
                    if type(c2.Function) == "function" then
                        local okk, consts = pcall(_getconstants, c2.Function)
                        if okk and consts then
                            for _, k in ipairs(consts) do
                                if k == "PaintballHitted" then found = r; break end
                            end
                        end
                    end
                    if found then break end
                end
            end
        end
        if found then break end
    end
    if found then _G._FH_UseItemRemote = found end
    return found
end

local aimRemoteIndex, aimRemoteObjects = {}, {}
local function aimInitRemotes()
    local ok, children = pcall(function()
        return ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Net"):GetChildren()
    end)
    if not ok or not children then return end
    aimRemoteIndex, aimRemoteObjects = {}, {}
    for i, obj in ipairs(children) do
        if obj:IsA("RemoteEvent") then
            local nxt = children[i + 1]
            if nxt then aimRemoteIndex[obj.Name] = i + 1; aimRemoteObjects[i + 1] = nxt end
        end
    end
end

local function aimFireRemote(name, ...)
    if name == "RE/UseItem" or name == "UseItem" then
        local r = _G._FH_ResolveUseItemRemote and _G._FH_ResolveUseItemRemote()
        if r then r:FireServer(...); return true end
    end
    local idx = aimRemoteIndex[name]
    if idx and aimRemoteObjects[idx] then aimRemoteObjects[idx]:FireServer(...); return true end
    return false
end

local function isAlive(char)
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    return hum ~= nil and hum.Health > 0
end

-- kill tool equip/hold animations that Roblox auto-loads on equip
-- (tool animations are always Action priority)
local function killToolAnims()
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local animator = hum and hum:FindFirstChildOfClass("Animator")
    if not animator then return end
    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
        if track.Priority == Enum.AnimationPriority.Action then
            pcall(function() track:Stop(0) end)
        end
    end
end

-- neutralize the cape's visual footprint — uses regular Transparency (server-replicated,
-- shows invisible to ALL clients including others) instead of LocalTransparencyModifier
-- which the game's anti-cheat scans for.
-- also disables particles/beams/trails/sounds/lights inside the tool.
-- also sets Grip so the tool's visual anchor point sits 100 studs above the arm — any
-- residual visual leak happens up in the sky instead of on the character's body.
local function neutralizeTool(tool)
    if not tool then return end

    -- Grip offset: replicates to all clients. Handle appears 100 studs above the hand
    -- (or wherever the arm's motor puts it). Anything spawned from the Handle position
    -- also spawns up there.
    pcall(function() tool.Grip = CFrame.new(0, 100, 0) end)

    for _, d in ipairs(tool:GetDescendants()) do
        if d:IsA("BasePart") then
            pcall(function() d.Transparency = 1 end)
            pcall(function() d.CanCollide = false end)
            pcall(function() d.CanQuery = false end)
        elseif d:IsA("Decal") or d:IsA("Texture") then
            pcall(function() d.Transparency = 1 end)
        elseif d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then
            pcall(function() d.Enabled = false end)
        elseif d:IsA("Sound") then
            pcall(function() d.Volume = 0 end)
        elseif d:IsA("Light") then
            pcall(function() d.Enabled = false end)
        end
    end
end

-- kill the RightGrip motor that visually attaches the Handle to the character's hand
-- (client-side only — helps our view, doesn't affect others)
local function killGrip()
    local char = LP.Character
    if not char then return end
    for _, part in ipairs(char:GetChildren()) do
        if part:IsA("BasePart") then
            for _, w in ipairs(part:GetChildren()) do
                if (w:IsA("Motor6D") or w:IsA("Weld")) and w.Name == "RightGrip" then
                    pcall(function() w:Destroy() end)
                end
            end
        end
    end
end

local function getBestPart(char)
    for _, n in ipairs(AIM_TARGET_PARTS) do
        local p = char:FindFirstChild(n); if p then return p end
    end
end

local function aimShootAt(targetPlayer)
    if not targetPlayer then return false end
    local char = targetPlayer.Character
    if not char or not isAlive(char) then return false end
    local part = getBestPart(char); if not part then return false end
    local vel = Vector3.zero
    pcall(function()
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then vel = hrp.Velocity or Vector3.zero end
    end)
    local targetPos = part.Position + Vector3.new(0, 0.5, 0) + vel * AIM_LEAD_TIME
    if not (aimRemoteIndex["RE/UseItem"] or aimRemoteIndex["UseItem"]) then aimInitRemotes() end
    local ok = aimFireRemote("RE/UseItem", targetPos, part)
    if not ok then aimInitRemotes(); ok = aimFireRemote("RE/UseItem", targetPos, part) end
    return ok
end

local function fireLaserCapeAt(targetPlayer)
    local char = LP.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    local bp = LP:FindFirstChild("Backpack")
    local cape = char:FindFirstChild("Laser Cape") or (bp and bp:FindFirstChild("Laser Cape"))
    if not cape then return false end
    local carpet = char:FindFirstChild("Flying Carpet") or (bp and bp:FindFirstChild("Flying Carpet"))
    aimInitRemotes()

    -- 1) carpet mask: equip → unequip (only if not already equipped, else just unequip)
    if carpet then
        if carpet.Parent ~= char then
            carpet.Parent = char
            task.wait(EQUIP_DELAY)
        end
        if bp and carpet.Parent == char then
            carpet.Parent = bp
            task.wait(SWAP_GAP)  -- let carpet unequip register before cape equip
        end
    end

    -- 2) equip cape
    if cape.Parent ~= char then
        neutralizeTool(cape)     -- make invisible + no effects/sounds (persistent)
        cape.Parent = char
        killToolAnims()           -- stop equip arm-raise before it starts
        killGrip()                -- detach visual bond to character hand
        task.wait(EQUIP_DELAY)
        killToolAnims()           -- catch any animation loaded during the wait
    end

    -- 3) fire burst — small gap between shots so server doesn't drop as flood
    for i = 1, BURST_SHOTS do
        pcall(aimShootAt, targetPlayer)
        if i < BURST_SHOTS then task.wait(SHOT_INTERVAL) end
    end

    -- 4) let final shot arrive server-side before stowing cape
    task.wait(POST_FIRE_WAIT)

    -- 5) unequip cape
    if bp and cape.Parent == char then cape.Parent = bp end
    killToolAnims()  -- kill any lingering unequip anim

    -- 6) re-equip carpet immediately (masks the empty-hand state)
    if carpet and carpet.Parent ~= char then
        pcall(function() carpet.Parent = char end)
    end

    return true
end
task.spawn(function()
    task.wait(1)
    local bp = LP:FindFirstChild("Backpack")
    local cape = (bp and bp:FindFirstChild("Laser Cape"))
              or (LP.Character and LP.Character:FindFirstChild("Laser Cape"))
    if cape then neutralizeTool(cape) end
end)
LP.CharacterAdded:Connect(function()
    task.wait(1.5)
    local bp = LP:FindFirstChild("Backpack")
    local cape = bp and bp:FindFirstChild("Laser Cape")
    if cape then neutralizeTool(cape) end
end)
task.spawn(function()
    while true do
        task.wait(2)
        local bp = LP:FindFirstChild("Backpack")
        local char = LP.Character
        local cape = (bp and bp:FindFirstChild("Laser Cape"))
                  or (char and char:FindFirstChild("Laser Cape"))
        if cape then neutralizeTool(cape) end
    end
end)
    return { fireAt = function(target) task.spawn(function() pcall(fireLaserCapeAt, target) end) end }
end)()
-- ===== END LASER CAPE =====

local _APTITLE = "MEERKO AP"

setToggle("Click to AP", Config.ClickToAP, true)
setToggle("ClickToAP",   Config.ClickToAP, true)
setToggle("Click AP Single Cmd", Config.ClickToAPSingleCommand, true)
setToggle("Proximity", false, true)
setToggle("Admin Panel UI", Config.AdminPanelUI, true)

LazyInit("Admin Panel UI", function()
    pcall(function() local e=playerGui:FindFirstChild("ZenithPanel"); if e then e:Destroy() end end)
    apGui=Instance.new("ScreenGui"); apGui.Name="ZenithPanel"; apGui.ResetOnSpawn=false; apGui.IgnoreGuiInset=true; apGui.DisplayOrder=9999998; apGui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; apGui.Parent=playerGui
    apGui.Enabled = (Config.AdminPanelUI == true)
    apOuter=Instance.new("Frame"); apOuter.Name="Frame"; apOuter.BackgroundTransparency=1; apOuter.BorderSizePixel=0; apOuter.Size=UDim2.fromOffset(480,0); apOuter.AutomaticSize=Enum.AutomaticSize.Y; apOuter.Position=UDim2.new(0.18,0,0.57,0); apOuter.ZIndex=10; apOuter.ClipsDescendants=true; apOuter.Parent=registerScreenGui(apGui)
    apBG=Instance.new("Frame"); apBG.BackgroundTransparency=1; apBG.BorderSizePixel=0; apBG.Position=UDim2.fromOffset(-3,-2); apBG.Size=UDim2.new(1,6,1,4); apBG.ZIndex=0; apBG.Parent=apOuter; corner(apBG,8)
    apTop=Instance.new("Frame"); apTop.BackgroundTransparency=1; apTop.BorderSizePixel=0; apTop.Size=UDim2.new(1,0,0,16); apTop.Parent=apOuter; corner(apTop,3)

    makeDraggable(apOuter,apTop,"AdminPanel"); applySavedPosition("AdminPanel",apOuter);

    apList=Instance.new("Frame"); apList.BackgroundTransparency=1; apList.BorderSizePixel=0; apList.Position=UDim2.new(0,0,0,20); apList.Size=UDim2.new(1,0,0,0); apList.AutomaticSize=Enum.AutomaticSize.Y; apList.Parent=apOuter; corner(apList,3)
    apPad=Instance.new("UIPadding"); apPad.PaddingTop=UDim.new(0,2); apPad.PaddingBottom=UDim.new(0,2); apPad.PaddingLeft=UDim.new(0,4); apPad.PaddingRight=UDim.new(0,4); apPad.Parent=apList
    Instance.new("UIListLayout",apList).SortOrder=Enum.SortOrder.LayoutOrder; apList:FindFirstChildOfClass("UIListLayout").Padding=UDim.new(0,2)

    apRows,stealLabels={},{}; rc=0
    local function buildRPButtons()
        local btns = {}
        local order = Config.AdminPanelOrder or AP_ALL_COMMANDS
        for _, cmd in ipairs(order) do
            if Config.AdminPanelButtons and Config.AdminPanelButtons[cmd] then
                table.insert(btns, {AP_COMMAND_EMOJIS[cmd] or "⚡", cmd})
            end
        end
        if #btns == 0 then btns = {{"🤸","ragdoll"},{"🔒","jail"},{"🚀","rocket"},{"🎈","balloon"}} end
        return btns
    end
    RP_BUTTONS = buildRPButtons()

    _G.refreshAdminPanelRows = function()
        for uid, row in pairs(apRows) do
            if row then row:Destroy() end
        end
        table.clear(apRows)
        table.clear(stealLabels)
        rc = 0
        RP_BUTTONS = buildRPButtons()
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= player then createAPRow(plr) end
        end
    end

    function createAPRow(plr)
        if not plr or plr==player then return end; if apRows[plr.UserId] and apRows[plr.UserId].Parent then return end
        rc=rc+1
        local actW = #RP_BUTTONS * 32 + 32
        local rowW = math.max(460, actW + 180)
        local row=Instance.new("Frame"); row.Name="Row_"..plr.UserId; row.BackgroundColor3=Color3.fromRGB(22,24,26); row.BackgroundTransparency=0.35; row.BorderSizePixel=0; row.Size=UDim2.new(0,rowW,0,54); row.ZIndex=5; row.ClipsDescendants=false; row.Parent=apList; corner(row,10)
        apRows[plr.UserId]=row

        local avatarH=Instance.new("Frame"); avatarH.BackgroundTransparency=1; avatarH.BorderSizePixel=0; avatarH.Size=UDim2.fromOffset(34,34); avatarH.Position=UDim2.fromOffset(8,10); avatarH.Parent=row; corner(avatarH,8)
        local avatar=Instance.new("ImageLabel"); avatar.BackgroundTransparency=1; avatar.Size=UDim2.fromScale(1,1); avatar.ZIndex=10; avatar.Parent=avatarH; corner(avatar,8)
        task.spawn(function() local ok,img=pcall(function() return Players:GetUserThumbnailAsync(plr.UserId,Enum.ThumbnailType.HeadShot,Enum.ThumbnailSize.Size48x48) end); if ok then avatar.Image=img end end)
        local dogeBtn=Instance.new("TextButton"); dogeBtn.Name="DogeBtn"; dogeBtn.Size=UDim2.fromOffset(22,22); dogeBtn.Position=UDim2.fromOffset(44,16); dogeBtn.BackgroundColor3=Color3.fromRGB(45,120,255); dogeBtn.BackgroundTransparency=0; dogeBtn.BorderSizePixel=0; dogeBtn.AutoButtonColor=true; dogeBtn.Text="D"; dogeBtn.Font=Enum.Font.GothamBold; dogeBtn.TextSize=13; dogeBtn.TextColor3=Color3.new(1,1,1); dogeBtn.ZIndex=13; dogeBtn.Parent=row; corner(dogeBtn,6)
        dogeBtn.MouseButton1Click:Connect(function()
            if isPlayerBlacklisted(plr) then ShowNotification("BLOCKED", plr.DisplayName .. " is blacklisted"); return end
            local DF=_G._FH_DogeFling; if DF then DF.fireAt(plr) end
        end)
        local laserBtn=Instance.new("TextButton"); laserBtn.Name="LaserBtn"; laserBtn.Size=UDim2.fromOffset(22,22); laserBtn.Position=UDim2.fromOffset(68,16); laserBtn.BackgroundColor3=Color3.fromRGB(240,68,68); laserBtn.BackgroundTransparency=0; laserBtn.BorderSizePixel=0; laserBtn.AutoButtonColor=true; laserBtn.Text="L"; laserBtn.Font=Enum.Font.GothamBold; laserBtn.TextSize=13; laserBtn.TextColor3=Color3.new(1,1,1); laserBtn.ZIndex=13; laserBtn.Parent=row; corner(laserBtn,6)
        laserBtn.MouseButton1Click:Connect(function()
            if isPlayerBlacklisted(plr) then ShowNotification("BLOCKED", plr.DisplayName .. " is blacklisted"); return end
            local LC=_G._FH_LaserCape; if LC then LC.fireAt(plr) end
        end)

        local txtW=-(actW+60)
        local nameLabel=Instance.new("TextLabel"); nameLabel.Size=UDim2.new(1,txtW-44,0,20); nameLabel.Position=UDim2.fromOffset(94,6); nameLabel.BackgroundTransparency=1; nameLabel.Text=plr.DisplayName; nameLabel.Font=Enum.Font.GothamBold; nameLabel.TextSize=14; nameLabel.TextColor3=Theme.Text; nameLabel.TextXAlignment=Enum.TextXAlignment.Left; nameLabel.ZIndex=10; nameLabel.Parent=row
        local userL=Instance.new("TextLabel"); userL.BackgroundTransparency=1; userL.Position=UDim2.fromOffset(94,23); userL.Size=UDim2.new(1,txtW-44,0,16); userL.TextXAlignment=Enum.TextXAlignment.Left; userL.Text="@"..plr.Name; userL.Font=Enum.Font.GothamMedium; userL.TextSize=10; userL.TextColor3=Theme.Dim; userL.ZIndex=10; userL.Parent=row
        local apL=Instance.new("TextLabel"); apL.BackgroundTransparency=1; apL.AnchorPoint=Vector2.new(1,0); apL.Position=UDim2.new(1,-(actW+16),0,6); apL.Size=UDim2.fromOffset(64,16); apL.TextXAlignment=Enum.TextXAlignment.Right; apL.Font=Enum.Font.GothamBlack; apL.TextSize=10; apL.ZIndex=11; apL.Parent=row
        local function paintAP()
            local has = (_G.checkAdminPanelGamepass and _G.checkAdminPanelGamepass(plr))
                or (_G.VanishHasAP and _G.VanishHasAP(plr))
            apL.Text = has and "AP" or ""
            apL.TextColor3 = has and Color3.fromRGB(255,59,59) or Theme.Dim
        end
        paintAP()
        task.spawn(function()
            while apL.Parent do task.wait(1.5); pcall(paintAP) end
        end)
        local statusL=Instance.new("TextLabel"); statusL.BackgroundTransparency=1; statusL.Position=UDim2.fromOffset(94,37); statusL.Size=UDim2.new(1,txtW-44,0,14); statusL.TextXAlignment=Enum.TextXAlignment.Left; statusL.Text=""; statusL.Font=Enum.Font.GothamBold; statusL.TextSize=11; statusL.TextColor3=Theme.AccentLight; statusL.ZIndex=10; statusL.Parent=row
        stealLabels[plr.UserId]=statusL

        local actions=Instance.new("Frame"); actions.BackgroundTransparency=1; actions.AnchorPoint=Vector2.new(1,0.5); actions.Position=UDim2.new(1,-8,0.5,0); actions.Size=UDim2.fromOffset(actW+10,38); actions.ZIndex=12; actions.Parent=row
        local al=Instance.new("UIListLayout"); al.FillDirection=Enum.FillDirection.Horizontal; al.SortOrder=Enum.SortOrder.LayoutOrder; al.Padding=UDim.new(0,2); al.Parent=actions

        for i,b in ipairs(RP_BUTTONS) do
            local btn=Instance.new("TextButton"); btn.Size=UDim2.fromOffset(30,30); btn.BackgroundTransparency=1; btn.AutoButtonColor=false; btn.Text=b[1]; btn.TextSize=14; btn.LayoutOrder=i; btn.Parent=actions
            btn.BackgroundColor3=Theme.SoftButton; btn.Font=Enum.Font.GothamBold; btn.TextColor3=Color3.new(1,1,1); btn.ZIndex=13
            btn.MouseButton1Click:Connect(function()
                if isPlayerBlacklisted(plr) then
                    ShowNotification("BLOCKED", plr.DisplayName .. " is blacklisted")
                    return
                end
                if apIsOnCooldown(b[2]) then return end; pcall(runAdminCommand,plr,b[2])
            end)
        end

        local blBtn=Instance.new("TextButton"); blBtn.Name="BLBtn"
        blBtn.Size=UDim2.fromOffset(30,30); blBtn.BackgroundTransparency=1
        blBtn.AutoButtonColor=false; blBtn.Text="X"; blBtn.TextSize=15
        blBtn.Font=Enum.Font.GothamBold; blBtn.LayoutOrder=999; blBtn.ZIndex=13
        blBtn.Parent=actions
        blBtn.MouseButton1Click:Connect(function()
            local nowBl = apBlacklistTogglePlayer(plr)
            ShowNotification("BLACKLIST", plr.DisplayName .. (nowBl and " blocked" or " unblocked"))
        end)

        local function updateBlacklistVisuals()
            local isBlacklisted = isPlayerBlacklisted(plr)
            if blBtn and blBtn.Parent then
                blBtn.Text = isBlacklisted and "O" or "X"
                blBtn.TextColor3 = isBlacklisted and Theme.Green or Theme.Red
                blBtn.TextTransparency = 0
            end
            if isBlacklisted then
                avatar.ImageTransparency = 0
                nameLabel.TextTransparency = 0
                userL.TextTransparency = 0
                statusL.TextTransparency = 0
                for _, child in ipairs(actions:GetChildren()) do
                    if child:IsA("TextButton") and child.Name ~= "BLBtn" then
                        child.TextTransparency = 0.8
                    end
                end
            else
                avatar.ImageTransparency = 0
                nameLabel.TextTransparency = 0
                userL.TextTransparency = 0
                statusL.TextTransparency = 0
                for _, child in ipairs(actions:GetChildren()) do
                    if child:IsA("TextButton") and child.Name ~= "BLBtn" then
                        child.TextTransparency = 0
                    end
                end
            end
        end

        updateBlacklistVisuals()

        row.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
            local mousePos = UIS:GetMouseLocation()
            if actions and actions.AbsolutePosition and actions.AbsoluteSize then
                local ax, ay = actions.AbsolutePosition.X, actions.AbsolutePosition.Y
                local aw, ah = actions.AbsoluteSize.X, actions.AbsoluteSize.Y
                if mousePos.X >= ax and mousePos.X <= ax+aw and mousePos.Y >= ay and mousePos.Y <= ay+ah then
                    return
                end
            end
            if dogeBtn and dogeBtn.AbsolutePosition and dogeBtn.AbsoluteSize then
                local dx, dy = dogeBtn.AbsolutePosition.X, dogeBtn.AbsolutePosition.Y
                local dw, dh = dogeBtn.AbsoluteSize.X, dogeBtn.AbsoluteSize.Y
                if mousePos.X >= dx and mousePos.X <= dx+dw and mousePos.Y >= dy and mousePos.Y <= dy+dh then
                    return
                end
            end
            if laserBtn and laserBtn.AbsolutePosition and laserBtn.AbsoluteSize then
                local lx, ly = laserBtn.AbsolutePosition.X, laserBtn.AbsolutePosition.Y
                local lw, lh = laserBtn.AbsoluteSize.X, laserBtn.AbsoluteSize.Y
                if mousePos.X >= lx and mousePos.X <= lx+lw and mousePos.Y >= ly and mousePos.Y <= ly+lh then
                    return
                end
            end
            if isPlayerBlacklisted(plr) then
                ShowNotification("BLOCKED", plr.DisplayName .. " is blacklisted")
                return
            end
            task.spawn(function()
                local activeCmds = {}
                for _,cmd in ipairs(AP_ALL_COMMANDS) do
                    if not apIsOnCooldown(cmd) then
                        table.insert(activeCmds, cmd)
                    end
                end
                if #activeCmds == 0 then
                    ShowNotification("ADMIN PANEL", "All commands on cooldown")
                    return
                end
                for i, cmd in ipairs(activeCmds) do
                    task.spawn(function()
                        task.wait((i - 1) * 0.01)
                        runAdminCommand(plr, cmd)
                    end)
                end
                ShowNotification("ADMIN PANEL", "Fired " .. #activeCmds .. " cmds on " .. plr.DisplayName)
            end)
        end)

        task.spawn(function() while row.Parent do task.wait(0.5)
            if not plr or not plr.Parent then break end
            local st=stealLabels[plr.UserId]; if not st then break end

            local stealOwner, stealPet = getStealingInfo(plr)
            local hubBadge, hubColor, joinerTag, hubBadges = getHubUserBadge(plr)
            local curBaseOwnerId = _G.__getCurrentBaseOwnerId()

            pcall(function()
                if hubBadges then
                    nameLabel.RichText = true
                    local parts = {}
                    for _, def in ipairs(hubBadges) do
                        local hex = string.format("#%02X%02X%02X",
                            math.floor(def.color.R * 255), math.floor(def.color.G * 255), math.floor(def.color.B * 255))
                        parts[#parts + 1] = '<font color="' .. hex .. '"><b>' .. def.badge .. '</b></font>'
                    end
                    nameLabel.Text = plr.DisplayName .. '  ' .. table.concat(parts, " ")
                elseif nameLabel.RichText then
                    nameLabel.RichText = false
                    nameLabel.Text = plr.DisplayName
                end
            end)

            pcall(function()
                local cls = getFmlyClass(plr)
                local son = getSonClass(plr)
                local king = getKingClass(plr)
                -- SON grief is the most important thing to surface, so it wins.
                local sonTag = ""
                if son == "grief" then
                    sonTag = '  <font color="#FF7B29"><b>SON Grief</b></font>'
                elseif son == "safe" then
                    sonTag = '  <font color="#58A6FF"><b>SON Safe</b></font>'
                end
                -- KING goodboy-api badges
                local kingTag = ""
                if king == "bad" then
                    kingTag = '  <font color="#FF4D6D"><b>KING Bad</b></font>'
                elseif king == "good" then
                    kingTag = '  <font color="#F0C14A"><b>KING Good</b></font>'
                end
                -- show WHY they're flagged when the list tells us
                local why = getFmlyReason(plr)
                local whyTag = ""
                if why and why ~= "" then
                    local short = tostring(why)
                    if #short > 24 then short = short:sub(1, 24) .. "..." end
                    short = short:gsub("[<>]", "")
                    whyTag = '  <font color="#8B949E">(' .. short .. ')</font>'
                end
                if cls == "good" then
                    userL.RichText = true
                    userL.Text = "@" .. plr.Name .. '  <font color="#3FB950"><b>Good</b></font>' .. sonTag .. kingTag
                elseif cls == "bad" then
                    userL.RichText = true
                    userL.Text = "@" .. plr.Name .. '  <font color="#EB2D37"><b>Bad</b></font>' .. whyTag .. sonTag .. kingTag
                elseif sonTag ~= "" or kingTag ~= "" then
                    userL.RichText = true
                    userL.Text = "@" .. plr.Name .. sonTag .. kingTag
                elseif userL.RichText then
                    userL.RichText = false
                    userL.Text = "@" .. plr.Name
                end
            end)

            local isOwner = curBaseOwnerId and curBaseOwnerId == plr.UserId
            local fx = nil
            if joinerTag then
                local raw = joinerTag:lower()
                for _, kw in ipairs({ "invers", "jail", "jumpscare", "morph", "nightvision", "rocket", "tiny", "balloon" }) do
                    if raw:find(kw, 1, true) then
                        fx = kw:sub(1, 1):upper() .. kw:sub(2)
                        if fx == "Invers" then fx = "Inversed" end
                        break
                    end
                end
            end
            -- held tool for this player (used for both status text + danger name color)
            local heldToolName = nil
            pcall(function() heldToolName = getHeldTool(plr) end)

            local statusPart, statusHex = "", nil
            if stealPet then
                statusPart = "● Stealing : " .. tostring(stealPet)
                statusHex = "#FF5A5A"
                row.LayoutOrder = 1
            elseif isOwner then
                statusPart = fx and ("● Base Owner | " .. fx) or "● Base Owner"
                statusHex = "#5AE678"
                row.LayoutOrder = 2
            elseif fx then
                statusPart = "● " .. fx
                statusHex = "#FFBE46"
                row.LayoutOrder = 10
            else
                statusPart = ""
                row.LayoutOrder = 10
            end

            local isAP = false
            pcall(function()
                isAP = (_G.checkAdminPanelGamepass and _G.checkAdminPanelGamepass(plr))
                    or (_G.VanishHasAP and _G.VanishHasAP(plr))
                    or false
            end)

            -- render status line as: [stealing/owner/fx]  ·  Holding: <tool>  ·  Has AP
            pcall(function()
                st.RichText = true
                local segs = {}
                if statusPart ~= "" and statusHex then
                    segs[#segs + 1] = '<font color="' .. statusHex .. '">' .. statusPart .. '</font>'
                end
                if heldToolName and heldToolName ~= "" then
                    local toolTxt = tostring(heldToolName):gsub("[<>]", "")
                    if #toolTxt > 22 then toolTxt = toolTxt:sub(1, 22) .. "..." end
                    local toolHex = DANGER_TOOLS[heldToolName] and "#FF3C3C" or "#8AA0FF"
                    segs[#segs + 1] = '<font color="' .. toolHex .. '">Holding: ' .. toolTxt .. '</font>'
                end
                if isAP then
                    segs[#segs + 1] = '<font color="#FF3B3B"><b>Has AP</b></font>'
                end
                st.Text = table.concat(segs, '  <font color="#5A6270">·</font>  ')
            end)

            pcall(function() local ht=getHeldTool(plr)
                if ht and DANGER_TOOLS[ht] then nameLabel.TextColor3=Color3.fromRGB(255,60,60) else nameLabel.TextColor3=Theme.Text end
            end)
        end end)
    end

    for _,plr in ipairs(Players:GetPlayers()) do if plr~=player then createAPRow(plr) end end
    Players.PlayerAdded:Connect(function(plr) task.defer(function() createAPRow(plr) end) end)
    Players.PlayerRemoving:Connect(function(plr) local row=apRows[plr.UserId]; if row then row:Destroy(); apRows[plr.UserId]=nil end; stealLabels[plr.UserId]=nil end)
end, 1)

local function makeAPConfigPanel(panelKey, titleText, configTable, orderKey, onToggleCb)
    if panels[panelKey] then
        panels[panelKey].Visible = not panels[panelKey].Visible
        return
    end

    if not Config[orderKey] then
        Config[orderKey] = {}
        for i, cmd in ipairs(AP_ALL_COMMANDS) do Config[orderKey][i] = cmd end
    end
    local cmdOrder = Config[orderKey]

    local cfgPanel = Instance.new("Frame")
    cfgPanel.Name = panelKey
    cfgPanel.Size = UDim2.fromOffset(240, 0)
    cfgPanel.AutomaticSize = Enum.AutomaticSize.Y
    cfgPanel.Position = panelKey == "AdminPanelCmds" and UDim2.new(0.5, 200, 0.5, -200) or UDim2.new(0.5, 200, 0.5, -50)
    cfgPanel.BackgroundColor3 = Theme.Background
    cfgPanel.BackgroundTransparency = UITransparency.ConfigPanel
    cfgPanel.BorderSizePixel = 0
    cfgPanel.ZIndex = 100
    cfgPanel.Parent = gui_sg
    panels[panelKey] = cfgPanel
    corner(cfgPanel, 10)
    stroke(cfgPanel, Theme.Accent, 1.5, 0.3)
    makeDraggable(cfgPanel, cfgPanel)

    local cfgTitleLbl = Instance.new("TextLabel")
    cfgTitleLbl.Size = UDim2.new(1, 0, 0, 28)
    cfgTitleLbl.BackgroundColor3 = Theme.Panel
    cfgTitleLbl.BackgroundTransparency = 0.3
    cfgTitleLbl.Text = titleText
    cfgTitleLbl.TextColor3 = Theme.Text
    cfgTitleLbl.Font = Enum.Font.GothamBold
    cfgTitleLbl.TextSize = 12
    cfgTitleLbl.ZIndex = 101
    cfgTitleLbl.Parent = cfgPanel
    corner(cfgTitleLbl, 8)

    local cfgBody = Instance.new("Frame")
    cfgBody.Size = UDim2.new(1, -8, 0, 0)
    cfgBody.AutomaticSize = Enum.AutomaticSize.Y
    cfgBody.Position = UDim2.fromOffset(4, 32)
    cfgBody.BackgroundTransparency = 1
    cfgBody.ZIndex = 101
    cfgBody.Parent = cfgPanel
    Instance.new("UIListLayout", cfgBody).SortOrder = Enum.SortOrder.LayoutOrder
    cfgBody:FindFirstChildOfClass("UIListLayout").Padding = UDim.new(0, 2)

    local rowMap = {}
    local numMap = {}

    local function refreshNumbers()
        for i, cmd in ipairs(cmdOrder) do
            if rowMap[cmd] then rowMap[cmd].LayoutOrder = i end
            if numMap[cmd] then numMap[cmd].Text = tostring(i) end
        end
    end

    local function swapOrder(idx1, idx2)
        if idx1 < 1 or idx2 < 1 or idx1 > #cmdOrder or idx2 > #cmdOrder then return end
        cmdOrder[idx1], cmdOrder[idx2] = cmdOrder[idx2], cmdOrder[idx1]
        Config[orderKey] = cmdOrder
        saveConfig()
        refreshNumbers()
    end

    for idx, cmd in ipairs(cmdOrder) do
        local emoji = AP_COMMAND_EMOJIS[cmd] or "⚡"
        local isOn = configTable[cmd] == true
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 28)
        row.BackgroundColor3 = Theme.Panel
        row.BackgroundTransparency = UITransparency.RowAlt
        row.LayoutOrder = idx
        row.ZIndex = 102
        row.Parent = cfgBody
        corner(row, 5)
        rowMap[cmd] = row

        local numLbl = Instance.new("TextLabel")
        numLbl.Size = UDim2.fromOffset(16, 28)
        numLbl.Position = UDim2.fromOffset(2, 0)
        numLbl.BackgroundTransparency = 1
        numLbl.Text = tostring(idx)
        numLbl.TextColor3 = Theme.Dim
        numLbl.Font = Enum.Font.GothamBold
        numLbl.TextSize = 10
        numLbl.ZIndex = 103
        numLbl.Parent = row
        numMap[cmd] = numLbl

        local upBtn = Instance.new("TextButton")
        upBtn.Size = UDim2.fromOffset(16, 13)
        upBtn.Position = UDim2.fromOffset(18, 1)
        upBtn.BackgroundTransparency = 1
        upBtn.Text = "▲"
        upBtn.TextColor3 = Theme.AccentLight
        upBtn.Font = Enum.Font.GothamBold
        upBtn.TextSize = 8
        upBtn.AutoButtonColor = false
        upBtn.ZIndex = 103
        upBtn.Parent = row

        local dnBtn = Instance.new("TextButton")
        dnBtn.Size = UDim2.fromOffset(16, 13)
        dnBtn.Position = UDim2.fromOffset(18, 14)
        dnBtn.BackgroundTransparency = 1
        dnBtn.Text = "▼"
        dnBtn.TextColor3 = Theme.AccentLight
        dnBtn.Font = Enum.Font.GothamBold
        dnBtn.TextSize = 8
        dnBtn.AutoButtonColor = false
        dnBtn.ZIndex = 103
        dnBtn.Parent = row

        upBtn.MouseButton1Click:Connect(function()
            local curIdx
            for i, c in ipairs(cmdOrder) do if c == cmd then curIdx = i; break end end
            if curIdx and curIdx > 1 then swapOrder(curIdx, curIdx - 1) end
        end)
        dnBtn.MouseButton1Click:Connect(function()
            local curIdx
            for i, c in ipairs(cmdOrder) do if c == cmd then curIdx = i; break end end
            if curIdx and curIdx < #cmdOrder then swapOrder(curIdx, curIdx + 1) end
        end)

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -90, 1, 0)
        lbl.Position = UDim2.fromOffset(36, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = emoji .. " " .. cmd
        lbl.TextColor3 = Theme.Text
        lbl.Font = Enum.Font.GothamMedium
        lbl.TextSize = 11
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.ZIndex = 103
        lbl.Parent = row

        local btn = Instance.new("TextButton")
        btn.Size = UDim2.fromOffset(36, 18)
        btn.Position = UDim2.new(1, -42, 0.5, -9)
        btn.BackgroundColor3 = isOn and Theme.Green or Theme.ToggleOff
        btn.Text = isOn and "ON" or "OFF"
        btn.TextColor3 = Color3.new(1, 1, 1)
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 9
        btn.AutoButtonColor = false
        btn.ZIndex = 103
        btn.Parent = row
        corner(btn, 5)

        btn.MouseButton1Click:Connect(function()
            isOn = not isOn
            configTable[cmd] = isOn
            saveConfig()
            btn.BackgroundColor3 = isOn and Theme.Green or Theme.ToggleOff
            btn.Text = isOn and "ON" or "OFF"
            if onToggleCb then onToggleCb(cmd, isOn) end
        end)
    end

    if panelKey == "ClickToAPCmds" then
        local function setZIndex(inst)
            if inst:IsA("GuiObject") then
                inst.ZIndex = 103
            end
            for _, child in ipairs(inst:GetChildren()) do
                setZIndex(child)
            end
        end

        local sep = Instance.new("Frame")
        sep.Size = UDim2.new(1, -8, 0, 1)
        sep.Position = UDim2.new(0, 4, 0, 0)
        sep.BackgroundColor3 = Theme.Stroke
        sep.BackgroundTransparency = 0.2
        sep.LayoutOrder = 1000
        sep.ZIndex = 103
        sep.Parent = cfgBody

        local subHeader = Instance.new("TextLabel")
        subHeader.Size = UDim2.new(1, 0, 0, 24)
        subHeader.BackgroundTransparency = 1
        subHeader.Text = "Settings"
        subHeader.TextColor3 = Theme.Accent
        subHeader.Font = Enum.Font.GothamBold
        subHeader.TextSize = 10
        subHeader.LayoutOrder = 1001
        subHeader.ZIndex = 103
        subHeader.Parent = cfgBody

        local sliderWrapper = Instance.new("Frame")
        sliderWrapper.Size = UDim2.new(1, 0, 0, 50)
        sliderWrapper.BackgroundTransparency = 1
        sliderWrapper.LayoutOrder = 1002
        sliderWrapper.Parent = cfgBody

        local sliderObj = makeQuickSlider(sliderWrapper, "Click Radius", 1, 50, Config.ClickToAPRadius or 8, function(v)
            Config.ClickToAPRadius = v
            saveConfig()
        end, " studs")
        setZIndex(sliderWrapper)
    end

    if panelKey == "SpamBaseOwnerCmds" then
        local function setZIndex(inst)
            if inst:IsA("GuiObject") then
                inst.ZIndex = 103
            end
            for _, child in ipairs(inst:GetChildren()) do
                setZIndex(child)
            end
        end

        local sep = Instance.new("Frame")
        sep.Size = UDim2.new(1, -8, 0, 1)
        sep.Position = UDim2.new(0, 4, 0, 0)
        sep.BackgroundColor3 = Theme.Stroke
        sep.BackgroundTransparency = 0.2
        sep.LayoutOrder = 1000
        sep.ZIndex = 103
        sep.Parent = cfgBody

        local subHeader = Instance.new("TextLabel")
        subHeader.Size = UDim2.new(1, 0, 0, 24)
        subHeader.BackgroundTransparency = 1
        subHeader.Text = "Settings"
        subHeader.TextColor3 = Theme.Accent
        subHeader.Font = Enum.Font.GothamBold
        subHeader.TextSize = 10
        subHeader.LayoutOrder = 1001
        subHeader.ZIndex = 103
        subHeader.Parent = cfgBody

        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 34)
        row.BackgroundTransparency = 1
        row.LayoutOrder = 1002
        row.Parent = cfgBody

        local toggleFunc = makeSyncStateRow(row, "Single Command:", "SpamBaseOwnerSingleCommand", function(on)
            Config.SpamBaseOwnerSingleCommand = on
            saveConfig()
        end)
        setZIndex(row)
    end

    local pad = Instance.new("Frame")
    pad.Size = UDim2.new(1, 0, 0, 6)
    pad.BackgroundTransparency = 1
    pad.LayoutOrder = 1004
    pad.Parent = cfgBody
end


do
    local blPanel = Instance.new("Frame")
    blPanel.Name = "Doom_BlacklistPanel"
    blPanel.Size = UDim2.fromOffset(272, 330)
    blPanel.Position = UDim2.new(0.5, 60, 0.5, -165)
    blPanel.BackgroundColor3 = Theme.Background
    blPanel.BackgroundTransparency = 0.04
    blPanel.BorderSizePixel = 0
    blPanel.Visible = false
    blPanel.ZIndex = 150
    blPanel.Parent = gui_sg
    corner(blPanel, 10); stroke(blPanel, Theme.Accent, 1.5, 0.3)
    makeDraggable(blPanel, blPanel, "BlacklistPanel")
    applySavedPosition("BlacklistPanel", blPanel)

    local ttl = Instance.new("TextLabel")
    ttl.Size = UDim2.new(1,-40,0,26); ttl.Position = UDim2.fromOffset(10,4)
    ttl.BackgroundTransparency = 1; ttl.Text = "AP BLACKLIST"
    ttl.TextColor3 = Theme.Accent; ttl.Font = Enum.Font.GothamBold; ttl.TextSize = 12
    ttl.TextXAlignment = Enum.TextXAlignment.Left; ttl.ZIndex = 151; ttl.Parent = blPanel

    local closeB = Instance.new("TextButton")
    closeB.Size = UDim2.fromOffset(22,22); closeB.Position = UDim2.new(1,-28,0,6)
    closeB.BackgroundTransparency = 1; closeB.Text = "X"; closeB.TextColor3 = Theme.Dim
    closeB.Font = Enum.Font.GothamBold; closeB.TextSize = 12; closeB.ZIndex = 151
    closeB.AutoButtonColor = false; closeB.Parent = blPanel
    closeB.MouseButton1Click:Connect(function() blPanel.Visible = false end)

    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1,-78,0,26); box.Position = UDim2.fromOffset(10,32)
    box.BackgroundColor3 = Theme.InputBg; box.BackgroundTransparency = 0.02
    box.PlaceholderText = "username to block..."
    box.PlaceholderColor3 = Theme.Dim
    box.Text = ""; box.TextColor3 = Theme.Text; box.Font = Enum.Font.GothamMedium
    box.TextSize = 11; box.ClearTextOnFocus = false; box.ZIndex = 151; box.Parent = blPanel
    corner(box,6); stroke(box, Theme.Stroke, 1, 0.4)
    local pad = Instance.new("UIPadding", box); pad.PaddingLeft = UDim.new(0,8)

    local addB = Instance.new("TextButton")
    addB.Size = UDim2.fromOffset(58,26); addB.Position = UDim2.new(1,-64,0,32)
    addB.BackgroundColor3 = Theme.Accent; addB.BackgroundTransparency = 0.05
    addB.Text = "ADD"; addB.TextColor3 = Color3.new(1,1,1)
    addB.Font = Enum.Font.GothamBold; addB.TextSize = 11; addB.AutoButtonColor = false
    addB.ZIndex = 151; addB.Parent = blPanel
    corner(addB,6)

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1,-20,1,-70); scroll.Position = UDim2.fromOffset(10,64)
    scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 3; scroll.ScrollBarImageColor3 = Theme.Accent
    scroll.CanvasSize = UDim2.new(0,0,0,0); scroll.ZIndex = 151; scroll.Parent = blPanel
    local ll = Instance.new("UIListLayout", scroll)
    ll.Padding = UDim.new(0,4); ll.SortOrder = Enum.SortOrder.LayoutOrder

    local function header(text, order)
        local h = Instance.new("TextLabel")
        h.Size = UDim2.new(1,-6,0,18); h.BackgroundTransparency = 1
        h.Text = text; h.TextColor3 = Theme.Dim; h.Font = Enum.Font.GothamBold
        h.TextSize = 10; h.TextXAlignment = Enum.TextXAlignment.Left
        h.LayoutOrder = order; h.ZIndex = 152; h.Parent = scroll
        return h
    end

    local function entryRow(labelText, order, btnText, btnColor, onClick)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1,-6,0,28); row.BackgroundColor3 = Theme.Row
        row.BackgroundTransparency = 0.1; row.BorderSizePixel = 0
        row.LayoutOrder = order; row.ZIndex = 152; row.Parent = scroll
        corner(row,6)
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1,-72,1,0); l.Position = UDim2.fromOffset(8,0)
        l.BackgroundTransparency = 1; l.Text = labelText; l.TextColor3 = Theme.Text
        l.Font = Enum.Font.GothamMedium; l.TextSize = 11
        l.TextXAlignment = Enum.TextXAlignment.Left; l.TextTruncate = Enum.TextTruncate.AtEnd
        l.ZIndex = 153; l.Parent = row
        local b = Instance.new("TextButton")
        b.Size = UDim2.fromOffset(58,20); b.Position = UDim2.new(1,-64,0.5,-10)
        b.BackgroundColor3 = btnColor; b.BackgroundTransparency = 0.05
        b.Text = btnText; b.TextColor3 = Color3.new(1,1,1)
        b.Font = Enum.Font.GothamBold; b.TextSize = 10; b.AutoButtonColor = false
        b.ZIndex = 153; b.Parent = row
        corner(b,5)
        b.MouseButton1Click:Connect(onClick)
        return row
    end

    function _G.refreshBlacklistPanel()
        for _, ch in ipairs(scroll:GetChildren()) do
            if not ch:IsA("UIListLayout") then ch:Destroy() end
        end
        local order = 0
        local function nxt() order = order + 1; return order end

        local uidList = {}
        for k, v in pairs(_G.apBlacklist) do
            if v == true then
                local uid = tonumber(k) or k
                local disp = tostring(uid)
                for _, p in ipairs(Players:GetPlayers()) do
                    if tostring(p.UserId) == tostring(uid) then
                        disp = p.Name .. "  (" .. tostring(uid) .. ")"; break
                    end
                end
                table.insert(uidList, {uid = uid, label = disp})
            end
        end

        local total = #uidList + #_G.apBlacklistNames
        header("BLACKLISTED (" .. total .. ")", nxt())
        if total == 0 then
            local e = Instance.new("TextLabel")
            e.Size = UDim2.new(1,-6,0,22); e.BackgroundTransparency = 1
            e.Text = "nobody blocked yet"; e.TextColor3 = Theme.Dim
            e.Font = Enum.Font.GothamMedium; e.TextSize = 10
            e.TextXAlignment = Enum.TextXAlignment.Left
            e.LayoutOrder = nxt(); e.ZIndex = 152; e.Parent = scroll
        end
        for _, it in ipairs(uidList) do
            entryRow(it.label, nxt(), "REMOVE", Theme.Red2, function()
                apBlacklistRemoveUid(it.uid)
            end)
        end
        for _, nm in ipairs(_G.apBlacklistNames) do
            local nmc = nm
            entryRow(tostring(nmc) .. "   [name]", nxt(), "REMOVE", Theme.Red2, function()
                apBlacklistRemoveName(nmc)
            end)
        end

        header("PLAYERS IN SERVER", nxt())
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then
                local pl = p
                local blocked = isPlayerBlacklisted(pl)
                entryRow(pl.Name, nxt(),
                    blocked and "UNBLOCK" or "BLOCK",
                    blocked and Theme.SoftButtonHover or Theme.Accent,
                    function() apBlacklistTogglePlayer(pl) end)
            end
        end

        task.defer(function()
            if scroll and scroll.Parent then
                scroll.CanvasSize = UDim2.new(0,0,0, ll.AbsoluteContentSize.Y + 8)
            end
        end)
    end

    local function doAdd()
        local nm = box.Text
        if apBlacklistAddName(nm) then
            box.Text = ""
            ShowNotification("BLACKLIST", nm .. " blocked")
        else
            ShowNotification("BLACKLIST", "already blocked / empty")
        end
    end
    addB.MouseButton1Click:Connect(doAdd)
    box.FocusLost:Connect(function(enter) if enter then doAdd() end end)

    function _G.toggleBlacklistPanel()
        blPanel.Visible = not blPanel.Visible
        if blPanel.Visible then _G.refreshBlacklistPanel() end
    end

    Players.PlayerAdded:Connect(function()
        if blPanel.Visible then task.defer(_G.refreshBlacklistPanel) end
    end)
    Players.PlayerRemoving:Connect(function()
        if blPanel.Visible then task.defer(_G.refreshBlacklistPanel) end
    end)

    _G.refreshBlacklistPanel()
end

local cmdMenu
local miniAP
LazyInit("Control Panel", function()
    cmdMenu = mkShell(gui_sg, 272, 306, "Doom_CmdConfigMenu")
    cmdMenu.Position = UDim2.new(0.5, -136, 0.5, -153)
    cmdMenu.Visible = false
    cmdMenu.ZIndex = 200
    makeDraggable(cmdMenu, cmdMenu, "CmdConfigMenu")
    applySavedPosition("CmdConfigMenu", cmdMenu)

    mkTitle(cmdMenu, "meerko ap", "control panel")

    local body = Instance.new("ScrollingFrame", cmdMenu)
    body.Size = UDim2.new(1,-24,1,-56); body.Position = UDim2.fromOffset(12,48)
    body.BackgroundTransparency = 1; body.BorderSizePixel = 0; body.ZIndex = 201
    body.ScrollBarThickness = 3; body.ScrollBarImageColor3 = MK.acc
    body.CanvasSize = UDim2.new(0,0,0,0)
    body.AutomaticCanvasSize = Enum.AutomaticSize.Y
    local ll = Instance.new("UIListLayout", body)
    ll.Padding = UDim.new(0,6); ll.SortOrder = Enum.SortOrder.LayoutOrder

    local ord = 0
    local function nx() ord = ord + 1; return ord end

    local function hdr(text)
        local l = Instance.new("TextLabel", body)
        l.Size = UDim2.new(1,0,0,14); l.BackgroundTransparency = 1
        l.Text = text; l.TextColor3 = MK.dim; l.Font = Enum.Font.GothamBold
        l.TextSize = 10; l.TextXAlignment = Enum.TextXAlignment.Left
        l.ZIndex = 202; l.LayoutOrder = nx()
    end
    local function btn(text, cb) return mkBtn(body, text, cb, nx()) end
    local function toggle(text, get, set) return mkToggle(body, text, get, set, nx()) end

    local function slider(text, min, max, get, set, suffix)
        local h = Instance.new("Frame", body)
        h.Size = UDim2.new(1,0,0,38); h.BackgroundTransparency = 1
        h.ZIndex = 202; h.LayoutOrder = nx()
        local l = Instance.new("TextLabel", h)
        l.Size = UDim2.new(1,-64,0,16); l.BackgroundTransparency = 1
        l.Text = text; l.TextColor3 = MK.text; l.Font = Enum.Font.GothamSemibold
        l.TextSize = 12; l.TextXAlignment = Enum.TextXAlignment.Left; l.ZIndex = 203
        local vl = Instance.new("TextLabel", h)
        vl.Size = UDim2.new(0,64,0,16); vl.Position = UDim2.new(1,-64,0,0)
        vl.BackgroundTransparency = 1; vl.TextColor3 = MK.text
        vl.Font = Enum.Font.GothamBold; vl.TextSize = 12
        vl.TextXAlignment = Enum.TextXAlignment.Right; vl.ZIndex = 203
        local tr = Instance.new("Frame", h)
        tr.Size = UDim2.new(1,0,0,8); tr.Position = UDim2.new(0,0,0,24)
        tr.BackgroundColor3 = MK.surf; tr.BorderSizePixel = 0; tr.ZIndex = 203
        corner(tr, 4)
        local fl = Instance.new("Frame", tr)
        fl.Size = UDim2.new(0,0,1,0); fl.BackgroundColor3 = MK.acc
        fl.BorderSizePixel = 0; fl.ZIndex = 204
        corner(fl, 4)
        local kn = Instance.new("Frame", tr)
        kn.Size = UDim2.fromOffset(14,14); kn.Position = UDim2.new(0,-7,0.5,-7)
        kn.BackgroundColor3 = MK.text; kn.BorderSizePixel = 0; kn.ZIndex = 205
        corner(kn, 7)
        local function draw()
            local cur = math.clamp(tonumber(get()) or min, min, max)
            local fr = (cur - min) / (max - min)
            fl.Size = UDim2.new(fr,0,1,0); kn.Position = UDim2.new(fr,-7,0.5,-7)
            vl.Text = tostring(math.floor(cur)) .. (suffix or "")
        end
        draw()
        local drag = false
        local hit = Instance.new("TextButton", tr)
        hit.Size = UDim2.new(1,0,1,12); hit.Position = UDim2.new(0,0,0,-6)
        hit.BackgroundTransparency = 1; hit.Text = ""; hit.ZIndex = 205
        local function apply(x)
            local fr = math.clamp((x - tr.AbsolutePosition.X) / math.max(1, tr.AbsoluteSize.X), 0, 1)
            set(math.floor(min + fr * (max - min) + 0.5)); draw()
        end
        hit.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                drag = true; apply(i.Position.X)
            end
        end)
        UIS.InputChanged:Connect(function(i)
            if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
                apply(i.Position.X)
            end
        end)
        UIS.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then drag = false end
        end)
    end

    hdr("ADMIN PANEL")
    toggle("Click to AP", function() return Config.ClickToAP end, function(v) setClickToAP(v) end)
    toggle("Proximity",   function() return ProximityAPActive end, function(v) setProximityAP(v) end)
    toggle("Player ESP",  function() return _G.MeerkoPlayerESPOn and _G.MeerkoPlayerESPOn() end, function(v) if _G.MeerkoSetPlayerESP then _G.MeerkoSetPlayerESP(v) end; Config.PlayerESP = v; saveConfig() end)
    slider("Distance", 1, 50, function() return Config.ProximityRange or 15 end,
        function(v) Config.ProximityRange = v; saveConfig() end, " studs")

    hdr("COMMANDS")
    btn("Admin Panel Commands", function()
        makeAPConfigPanel("AdminPanelCmds", "Admin Panel Commands", Config.AdminPanelButtons, "AdminPanelOrder", function()
            if _G.refreshAdminPanelRows then _G.refreshAdminPanelRows() end
        end)
    end)
    btn("Click to AP Commands", function()
        makeAPConfigPanel("ClickToAPCmds", "Click to AP Commands", Config.ClickToAPCommands, "ClickToAPOrder")
    end)
    btn("Spam Base Owner Commands", function()
        makeAPConfigPanel("SpamBaseOwnerCmds", "Spam Base Owner Commands", Config.SpamBaseOwnerCommands, "SpamBaseOwnerOrder")
    end)
end, 3)

-- Compact always-on HUD (layout like classic ADMIN AP, Meerko colors)
LazyInit("Mini Admin AP", function()
    -- force small default (ignore prior resized size)
    if _G.VanishUISizes then _G.VanishUISizes["Doom_MiniAdminAP"] = nil end
    miniAP = mkShell(gui_sg, 168, 138, "Doom_MiniAdminAP")
    miniAP.Position = UDim2.new(0, 14, 0.5, -69)
    miniAP.Visible = true
    miniAP.ZIndex = 210
    makeDraggable(miniAP, miniAP, "MiniAdminAP")
    applySavedPosition("MiniAdminAP", miniAP)

    local title = Instance.new("TextLabel", miniAP)
    title.Size = UDim2.new(1, -34, 0, 18)
    title.Position = UDim2.fromOffset(8, 5)
    title.BackgroundTransparency = 1
    title.Text = "ADMIN AP"
    title.TextColor3 = MK.text
    title.Font = Enum.Font.GothamBlack
    title.TextSize = 11
    title.TextXAlignment = Enum.TextXAlignment.Center
    title.ZIndex = 211

    local gear = Instance.new("TextButton", miniAP)
    gear.Size = UDim2.fromOffset(18, 18)
    gear.Position = UDim2.new(1, -24, 0, 5)
    gear.BackgroundColor3 = MK.surf
    gear.Text = "⚙"
    gear.TextColor3 = MK.dim
    gear.Font = Enum.Font.GothamBold
    gear.TextSize = 10
    gear.AutoButtonColor = false
    gear.ZIndex = 212
    corner(gear, 5)
    stroke(gear, MK.brd, 1, 0.45)
    gear.MouseEnter:Connect(function() tw(gear, {BackgroundColor3 = MK.acc, TextColor3 = MK.text}, 0.12) end)
    gear.MouseLeave:Connect(function() tw(gear, {BackgroundColor3 = MK.surf, TextColor3 = MK.dim}, 0.12) end)
    gear.MouseButton1Click:Connect(function()
        if not cmdMenu then return end
        cmdMenu.Visible = not cmdMenu.Visible
    end)

    local list = Instance.new("Frame", miniAP)
    list.Size = UDim2.new(1, -14, 1, -30)
    list.Position = UDim2.fromOffset(7, 26)
    list.BackgroundTransparency = 1
    list.ZIndex = 211
    local lay = Instance.new("UIListLayout", list)
    lay.Padding = UDim.new(0, 4)
    lay.SortOrder = Enum.SortOrder.LayoutOrder

    local function paintBtn(btn, on, mode)
        if mode == "action" then
            btn.BackgroundColor3 = Theme.Red2 or Color3.fromRGB(190, 60, 72)
            btn.TextColor3 = MK.text
            return
        end
        if on then
            btn.BackgroundColor3 = MK.grn
            btn.TextColor3 = Color3.fromRGB(12, 18, 16)
        else
            btn.BackgroundColor3 = MK.surf
            btn.TextColor3 = MK.text
        end
    end

    local function makeKeyChip(parent, label, on)
        local k = Instance.new("TextButton", parent)
        k.Size = UDim2.fromOffset(34, 22)
        k.Position = UDim2.new(1, -34, 0, 0)
        k.Text = label
        k.Font = Enum.Font.GothamBold
        k.TextSize = 9
        k.AutoButtonColor = false
        k.BorderSizePixel = 0
        k.ZIndex = 213
        corner(k, 6)
        local s = Instance.new("UIStroke", k)
        s.Color = MK.brd; s.Thickness = 1; s.Transparency = 0.45
        paintBtn(k, on)
        return k
    end

    local function makeToggleRow(order, prefix, getOn, onToggle, keyLabel)
        local row = Instance.new("Frame", list)
        row.Size = UDim2.new(1, 0, 0, 22)
        row.BackgroundTransparency = 1
        row.LayoutOrder = order
        row.ZIndex = 212

        local main = Instance.new("TextButton", row)
        main.Size = UDim2.new(1, keyLabel and -38 or 0, 1, 0)
        main.BackgroundColor3 = MK.surf
        main.Font = Enum.Font.GothamBold
        main.TextSize = 10
        main.AutoButtonColor = false
        main.BorderSizePixel = 0
        main.ZIndex = 213
        corner(main, 6)
        local ms = Instance.new("UIStroke", main)
        ms.Color = MK.brd; ms.Thickness = 1; ms.Transparency = 0.45

        local chip
        if keyLabel then
            chip = makeKeyChip(row, keyLabel, getOn())
        end

        local function refresh()
            local on = getOn() and true or false
            main.Text = prefix .. (on and ": ON" or ": OFF")
            paintBtn(main, on)
            if chip then paintBtn(chip, on) end
        end
        refresh()

        local function flip()
            onToggle(not (getOn() and true or false))
            refresh()
        end
        main.MouseButton1Click:Connect(flip)
        if chip then chip.MouseButton1Click:Connect(flip) end
        return refresh
    end

    local function makeFullToggle(order, prefix, getOn, onToggle)
        return makeToggleRow(order, prefix, getOn, onToggle, nil)
    end

    local refreshProx = makeToggleRow(1, "PROXIMITY", function()
        return ProximityAPActive
    end, function(v)
        setProximityAP(v)
        ShowNotification("PROXIMITY", v and "Enabled (P)" or "Disabled (P)")
    end, "P")

    local refreshClick = makeToggleRow(2, "CLICK TO AP", function()
        return Config.ClickToAP
    end, function(v)
        setClickToAP(v)
        ShowNotification("CLICK AP", v and "Enabled (U)" or "Disabled (U)")
    end, "U")

    local refreshPanel = makeFullToggle(3, "AP PANEL", function()
        if apGui then return apGui.Enabled end
        return Config.AdminPanelUI == true
    end, function(v)
        if apGui then apGui.Enabled = v end
        Config.AdminPanelUI = v and true or false
        saveConfig()
        pcall(setToggle, "Admin Panel UI", v and true or false)
        local qp = panels and panels["Admin Command Panel"]
        if qp then qp.Visible = v and true or false end
        ShowNotification("AP PANEL", v and "Shown" or "Hidden")
    end)

    do
        local row = Instance.new("Frame", list)
        row.Size = UDim2.new(1, 0, 0, 22)
        row.BackgroundTransparency = 1
        row.LayoutOrder = 4
        row.ZIndex = 212

        local main = Instance.new("TextButton", row)
        main.Size = UDim2.new(1, -38, 1, 0)
        main.Text = "SPAM BASE OWNER"
        main.Font = Enum.Font.GothamBold
        main.TextSize = 9
        main.AutoButtonColor = false
        main.BorderSizePixel = 0
        main.ZIndex = 213
        corner(main, 6)
        local ms = Instance.new("UIStroke", main)
        ms.Color = MK.brd; ms.Thickness = 1; ms.Transparency = 0.45
        paintBtn(main, false, "action")

        local chip = makeKeyChip(row, "PageD", false)
        paintBtn(chip, false)

        local function fire()
            pcall(spamBaseOwner)
        end
        main.MouseButton1Click:Connect(fire)
        chip.MouseButton1Click:Connect(fire)
    end

    onToggleChanged("Proximity", function() refreshProx() end)
    onToggleChanged("Click to AP", function() refreshClick() end)
    onToggleChanged("ClickToAP", function() refreshClick() end)
    onToggleChanged("Admin Panel UI", function() refreshPanel() end)

    _G.refreshMiniAdminAP = function()
        pcall(refreshProx)
        pcall(refreshClick)
        pcall(refreshPanel)
    end
end, 101)

UIS.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.U then
        setClickToAP(not Config.ClickToAP)
        ShowNotification("CLICK AP", Config.ClickToAP and "Enabled (U)" or "Disabled (U)")
        if _G.refreshMiniAdminAP then pcall(_G.refreshMiniAdminAP) end
    elseif input.KeyCode == Enum.KeyCode.P then
        setProximityAP(not ProximityAPActive)
        ShowNotification("PROXIMITY", ProximityAPActive and "Enabled (P)" or "Disabled (P)")
        if _G.refreshMiniAdminAP then pcall(_G.refreshMiniAdminAP) end
    elseif input.KeyCode == Enum.KeyCode.PageDown then
        pcall(spamBaseOwner)
    end
end)

task.defer(function()
    local chip = Instance.new("TextButton")
    chip.Name = "Doom_AP_Reopen"; chip.Size = UDim2.fromOffset(52,26)
    chip.Position = UDim2.new(0,14,0,120); chip.BackgroundColor3 = MK.surf
    chip.Text = "AP"; chip.TextColor3 = MK.acc
    chip.Font = Enum.Font.GothamBlack; chip.TextSize = 13; chip.AutoButtonColor = false
    chip.Parent = gui_sg
    corner(chip,8); stroke(chip, MK.brd, 1, 0.4)
    makeDraggable(chip, chip, "AP_ReopenChip"); applySavedPosition("AP_ReopenChip", chip)
    chip.MouseButton1Click:Connect(function()
        if apGui then
            local nv = not apGui.Enabled
            apGui.Enabled = nv; Config.AdminPanelUI = nv; saveConfig()
            pcall(setToggle, "Admin Panel UI", nv)
        end
        local qp = panels and panels["Admin Command Panel"]
        if qp then qp.Visible = (apGui and apGui.Enabled) or (qp.Visible ~= true) end
        if _G.refreshMiniAdminAP then pcall(_G.refreshMiniAdminAP) end
    end)
end)

setToggle("Click to AP", Config.ClickToAP)
setToggle("ClickToAP",   Config.ClickToAP)
setToggle("Click AP Single Cmd", Config.ClickToAPSingleCommand)
setToggle("Proximity", false)
setToggle("Admin Panel UI", Config.AdminPanelUI)
ShowNotification("MEERKO AP", "AP loaded")
end)()

-- ---- WalkSpeed setter used by the AP WalkSpeed toggle ----
do
    local RunService = game:GetService("RunService")
    local LocalPlayer = Players.LocalPlayer
    local wsConn
    _G.VanishSetWalkSpeed = function(enabled)
        _G.VanishWalkSpeed = enabled and true or false
        if wsConn then wsConn:Disconnect(); wsConn = nil end
        if not _G.VanishWalkSpeed then return end
        wsConn = RunService.Heartbeat:Connect(function()
            if not _G.VanishWalkSpeed then return end
            if LocalPlayer:GetAttribute("Stealing") ~= true then return end
            local c = LocalPlayer.Character
            if not c then return end
            local hum = c:FindFirstChildOfClass("Humanoid")
            local hrp = c:FindFirstChild("HumanoidRootPart")
            if not hum or not hrp then return end
            local state = hum:GetState()
            if state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping then return end
            local spd = math.clamp(tonumber(_G.VanishWalkSpeedValue) or 22, 16, 29)
            local md = hum.MoveDirection
            if md.Magnitude > 0.01 then
                local dir = Vector3.new(md.X, 0, md.Z).Unit
                local keepY = hrp.AssemblyLinearVelocity.Y
                hrp.AssemblyLinearVelocity = Vector3.new(dir.X * spd, keepY, dir.Z * spd)
            end
        end)
    end
end

if _G.VanishWalkSpeed == true and _G.VanishSetWalkSpeed then
    task.defer(function() pcall(_G.VanishSetWalkSpeed, true) end)
end
-- Minimal ESP: Players + Beast + ComputerTables
-- Stripped from Unnamed ESP by ic3w0lf
-- No GUI · No file I/O · Xeno compatible (no GetDebugId)
-- Uses identical drawing library & visuals as original Unnamed ESP

if not cloneref then cloneref = function(o) return o end end

local RunService   = cloneref(game:GetService("RunService"))
local Players      = cloneref(game:GetService("Players"))
local LocalPlayer  = Players.LocalPlayer
local Camera       = workspace.CurrentCamera
local V2New        = Vector2.new
local V3New        = Vector3.new
local WTVP         = Camera.WorldToViewportPoint
local WorldToViewport = function(...) return WTVP(Camera, ...) end

-- ── Config ───────────────────────────────────────────────────────────────────
local CFG = {
    Enabled       = true,
    MaxDistance    = 2500,
    TextSize      = 14,
    ShowBoxes     = true,
    ShowNames     = true,
    ShowDistance   = false,
    ShowHealth    = false,
    ShowTracers   = false,
    ShowDot       = false,
    TextOutline   = true,
    EnemyColor    = Color3.fromRGB(100, 255, 100),
    TeamColor     = Color3.new(0, 1, 0),
    BeastColor    = Color3.new(1, 0, 0),
    ComputerColor = Color3.fromRGB(13,  255, 227),
    ComputerDone  = Color3.fromRGB(40,  200, 80),
}
-- ─────────────────────────────────────────────────────────────────────────────

local TracerPosition = V2New(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y - 135)

-- Force Lines instead of Quad - many executors have buggy Quad (Visible=false doesn't hide)
local QUAD_SUPPORTED_EXPLOIT = false

local function Set(t, i, v) t[i] = v end

-- ── Visibility helper (dot product, executor-independent) ────────────────────
-- Returns inFront, inFOV in one call (avoids computing dot product twice)
local function CheckVisibility(worldPos, camCF, marginDeg)
    local toTarget = worldPos - camCF.Position
    local dist = toTarget.Magnitude
    if dist < 0.01 then return true, true end
    local dot = camCF.LookVector:Dot(toTarget / dist)
    if dot <= 0 then return false, false end
    local halfFov = math.rad((Camera.FieldOfView / 2) + (marginDeg or 30))
    return true, dot > math.cos(halfFov)
end

-- ── Drawing helpers (identical to Unnamed ESP) ───────────────────────────────
function NewDrawing(InstanceName)
    local Instance = Drawing.new(InstanceName)
    return (function(Properties)
        for i, v in pairs(Properties) do
            pcall(Set, Instance, i, v)
        end
        return Instance
    end)
end

-- ── LineBox (with layered safety) ────────────────────────────────────────────
local LineBox = {}

local function Combine(...)
    local Output = {}
    for i, v in pairs{...} do
        if typeof(v) == 'table' then
            table.foreach(v, function(i, v)
                Output[i] = v
            end)
        end
    end
    return Output
end

function LineBox:Create(Properties)
    local Box = { Visible = true }

    local Properties = Combine({
        Transparency = 1;
        Thickness    = 3;
        Visible      = true;
    }, Properties)

    if QUAD_SUPPORTED_EXPLOIT then
        Box['Quad'] = NewDrawing'Quad'(Properties)
    else
        Box['TopLeft']     = NewDrawing'Line'(Properties)
        Box['TopRight']    = NewDrawing'Line'(Properties)
        Box['BottomLeft']  = NewDrawing'Line'(Properties)
        Box['BottomRight'] = NewDrawing'Line'(Properties)
    end

    function Box:Update(CF, Size, Color, Properties)
        if not CF or not Size then return end

        -- Project center and sanity check
        local centerSP = WorldToViewport(CF.Position)

        if centerSP.Z <= 0
        or centerSP.X ~= centerSP.X or centerSP.Y ~= centerSP.Y then
            Box:SetVisible(false)
            return
        end

        -- Project the 4 corners
        local TLPos = WorldToViewport((CF * CFrame.new( Size.X,  Size.Y, 0)).Position)
        local TRPos = WorldToViewport((CF * CFrame.new(-Size.X,  Size.Y, 0)).Position)
        local BLPos = WorldToViewport((CF * CFrame.new( Size.X, -Size.Y, 0)).Position)
        local BRPos = WorldToViewport((CF * CFrame.new(-Size.X, -Size.Y, 0)).Position)

        -- All corners must be finite and in front of camera
        if TLPos.Z <= 0 or TRPos.Z <= 0 or BLPos.Z <= 0 or BRPos.Z <= 0
        or TLPos.X ~= TLPos.X or TRPos.X ~= TRPos.X
        or BLPos.X ~= BLPos.X or BRPos.X ~= BRPos.X then
            Box:SetVisible(false)
            return
        end

        -- Box shouldn't be insanely large (catches edge-of-screen projection blow-up)
        local VPX = Camera.ViewportSize.X
        local boxW = math.max(TLPos.X, TRPos.X, BLPos.X, BRPos.X)
                   - math.min(TLPos.X, TRPos.X, BLPos.X, BRPos.X)
        local boxH = math.max(TLPos.Y, TRPos.Y, BLPos.Y, BRPos.Y)
                   - math.min(TLPos.Y, TRPos.Y, BLPos.Y, BRPos.Y)

        if boxW > VPX * 1.5 or boxH > VPX * 1.5 then
            Box:SetVisible(false)
            return
        end

        -- ALL CHECKS PASSED — draw the box
        local Quad = Box['Quad']

        if QUAD_SUPPORTED_EXPLOIT then
            Quad.Visible = true
            Quad.Color   = Color
            Quad.PointA  = V2New(TLPos.X, TLPos.Y)
            Quad.PointB  = V2New(TRPos.X, TRPos.Y)
            Quad.PointC  = V2New(BRPos.X, BRPos.Y)
            Quad.PointD  = V2New(BLPos.X, BLPos.Y)
        else
            Box['TopLeft'].Visible = true
            Box['TopLeft'].Color   = Color
            Box['TopLeft'].From    = V2New(TLPos.X, TLPos.Y)
            Box['TopLeft'].To      = V2New(TRPos.X, TRPos.Y)

            Box['TopRight'].Visible = true
            Box['TopRight'].Color   = Color
            Box['TopRight'].From    = V2New(TRPos.X, TRPos.Y)
            Box['TopRight'].To      = V2New(BRPos.X, BRPos.Y)

            Box['BottomLeft'].Visible = true
            Box['BottomLeft'].Color   = Color
            Box['BottomLeft'].From    = V2New(BLPos.X, BLPos.Y)
            Box['BottomLeft'].To      = V2New(TLPos.X, TLPos.Y)

            Box['BottomRight'].Visible = true
            Box['BottomRight'].Color   = Color
            Box['BottomRight'].From    = V2New(BRPos.X, BRPos.Y)
            Box['BottomRight'].To      = V2New(BLPos.X, BLPos.Y)

            if Properties and typeof(Properties) == 'table' then
                for i, v in pairs(Properties) do
                    pcall(Set, Box['TopLeft'],     i, v)
                    pcall(Set, Box['TopRight'],    i, v)
                    pcall(Set, Box['BottomLeft'],  i, v)
                    pcall(Set, Box['BottomRight'], i, v)
                end
            end
        end
    end

    function Box:SetVisible(bool)
        if self.Quad then
            self.Quad.Visible = bool
            if not bool then
                -- Force collapse quad points to prevent ghosting
                pcall(function()
                    self.Quad.PointA = V2New(0, 0)
                    self.Quad.PointB = V2New(0, 0)
                    self.Quad.PointC = V2New(0, 0)
                    self.Quad.PointD = V2New(0, 0)
                end)
            end
        elseif self.TopLeft and self.TopRight and self.BottomLeft and self.BottomRight then
            self.TopLeft.Visible     = bool
            self.TopRight.Visible    = bool
            self.BottomLeft.Visible  = bool
            self.BottomRight.Visible = bool
            if not bool then
                -- Force collapse line positions to prevent ghosting
                local zero = V2New(0, 0)
                self.TopLeft.From = zero; self.TopLeft.To = zero
                self.TopRight.From = zero; self.TopRight.To = zero
                self.BottomLeft.From = zero; self.BottomLeft.To = zero
                self.BottomRight.From = zero; self.BottomRight.To = zero
            end
        end
    end

    function Box:Remove()
        self:SetVisible(false)
        if self.Quad then
            Box['Quad']:Remove()
        elseif self.TopLeft and self.TopRight and self.BottomLeft and self.BottomRight then
            self.TopLeft:Remove()
            self.TopRight:Remove()
            self.BottomLeft:Remove()
            self.BottomRight:Remove()
        end
    end

    return Box
end

-- ── Per-player ESP data ──────────────────────────────────────────────────────
local PlayerESP = {}

local function MakePlayerESP()
    return {
        Box = LineBox:Create{ Thickness = 4 },
        OutlineTracer = NewDrawing'Line'{
            Transparency = 1;
            Thickness    = 3;
            Color        = Color3.new(0.1, 0.1, 0.1);
        },
        Tracer = NewDrawing'Line'{
            Transparency = 1;
            Thickness    = 1;
        },
        HeadDot = NewDrawing'Circle'{
            Filled   = true;
            NumSides = 30;
        },
        NameTag = NewDrawing'Text'{
            Size           = CFG.TextSize;
            Center         = true;
            Outline        = CFG.TextOutline;
            OutlineOpacity = 1;
            Visible        = false;
        },
        DistanceTag = NewDrawing'Text'{
            Size           = CFG.TextSize - 1;
            Center         = true;
            Outline        = CFG.TextOutline;
            OutlineOpacity = 1;
            Visible        = false;
        },
    }
end

local function RemovePlayerESP(p)
    local d = PlayerESP[p]
    if not d then return end
    pcall(function() d.Box:Remove() end)
    pcall(function() d.NameTag:Remove() end)
    pcall(function() d.DistanceTag:Remove() end)
    pcall(function() d.Tracer:Remove() end)
    pcall(function() d.OutlineTracer:Remove() end)
    pcall(function() d.HeadDot:Remove() end)
    PlayerESP[p] = nil
end

for _, p in ipairs(Players:GetPlayers()) do
    if p ~= LocalPlayer then PlayerESP[p] = MakePlayerESP() end
end
Players.PlayerAdded:Connect(function(p)
    PlayerESP[p] = MakePlayerESP()
end)
Players.PlayerRemoving:Connect(RemovePlayerESP)

-- ── Per-computer ESP data ────────────────────────────────────────────────────
local ComputerESP = {}

local SCREEN_DONE_COLOR = Color3.fromRGB(40, 127, 71)

local function GetComputerColor(model)
    local s = model:FindFirstChild("Screen", true)
    if s and s:IsA("BasePart") and s.Color == SCREEN_DONE_COLOR then
        return CFG.ComputerDone
    end
    return CFG.ComputerColor
end

local function MakeComputerESP()
    return {
        Box = LineBox:Create{ Thickness = 4 },
        NameTag = NewDrawing'Text'{
            Size    = CFG.TextSize;
            Center  = true;
            Outline = CFG.TextOutline;
            Visible = false;
        },
        DistanceTag = NewDrawing'Text'{
            Size    = CFG.TextSize - 1;
            Center  = true;
            Outline = CFG.TextOutline;
            Visible = false;
        },
        OutlineTracer = NewDrawing'Line'{
            Transparency = 0.75;
            Thickness    = 5;
            Color        = Color3.new(0.1, 0.1, 0.1);
        },
        Tracer = NewDrawing'Line'{
            Transparency = 1;
            Thickness    = 2;
        },
        conns = {},
    }
end

local function RemoveComputerESP(model)
    local d = ComputerESP[model]
    if not d then return end
    pcall(function() d.Box:Remove() end)
    pcall(function() d.NameTag:Remove() end)
    pcall(function() d.DistanceTag:Remove() end)
    pcall(function() d.Tracer:Remove() end)
    pcall(function() d.OutlineTracer:Remove() end)
    for _, c in ipairs(d.conns) do pcall(function() c:Disconnect() end) end
    ComputerESP[model] = nil
end

local function AddComputerESP(model)
    if ComputerESP[model] then return end
    local d = MakeComputerESP()
    ComputerESP[model] = d

    table.insert(d.conns, model.AncestryChanged:Connect(function(_, parent)
        if not parent then RemoveComputerESP(model) end
    end))
    local screen = model:FindFirstChild("Screen", true)
    if screen and screen:IsA("BasePart") then
        table.insert(d.conns, screen:GetPropertyChangedSignal("Color"):Connect(function() end))
    end
end

for _, desc in ipairs(workspace:GetDescendants()) do
    if desc:IsA("Model") and desc.Name == "ComputerTable" then
        AddComputerESP(desc)
    end
end
workspace.DescendantAdded:Connect(function(desc)
    if desc:IsA("Model") and desc.Name == "ComputerTable" then
        AddComputerESP(desc)
    end
end)
workspace.DescendantRemoving:Connect(function(desc)
    if desc:IsA("Model") and desc.Name == "ComputerTable" then
        RemoveComputerESP(desc)
    end
end)

-- ── Team / beast helpers ─────────────────────────────────────────────────────
local IsBeastGame = (game.PlaceId == 893973440)

local function IsBeast(player)
    if not IsBeastGame then return false end
    local ok, v = pcall(function()
        return player:FindFirstChild("TempPlayerStatsModule").IsBeast.Value
    end)
    return ok and v == true
end

local function CheckTeam(player)
    if IsBeastGame then return false end
    if player.Neutral and LocalPlayer.Neutral then return true end
    return player.TeamColor == LocalPlayer.TeamColor
end

-- ── Camera fix ───────────────────────────────────────────────────────────────
local function CameraCon()
    workspace.CurrentCamera:GetPropertyChangedSignal('ViewportSize'):Connect(function()
        TracerPosition = V2New(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y - 135)
    end)
end
CameraCon()

-- ── Toggle (F3) ──────────────────────────────────────────────────────────────
local UserInputService = cloneref(game:GetService("UserInputService"))

local function HideAllESP()
    for _, d in pairs(PlayerESP) do
        d.NameTag.Visible       = false
        d.DistanceTag.Visible   = false
        d.HeadDot.Visible       = false
        d.Tracer.Visible        = false
        d.OutlineTracer.Visible = false
        d.Box:SetVisible(false)
    end
    for _, d in pairs(ComputerESP) do
        d.NameTag.Visible       = false
        d.DistanceTag.Visible   = false
        d.Tracer.Visible        = false
        d.OutlineTracer.Visible = false
        d.Box:SetVisible(false)
    end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.F3 then
        CFG.Enabled = not CFG.Enabled
        if not CFG.Enabled then HideAllESP() end
    end
end)

-- ── Main render loop ─────────────────────────────────────────────────────────
local RSName = "MinimalESP_" .. tostring(math.random(1e6))
RunService:UnbindFromRenderStep(RSName)

RunService:BindToRenderStep(RSName, Enum.RenderPriority.Camera.Value + 1, function()
    if not CFG.Enabled then return end

    if Camera.Parent ~= workspace then
        Camera = workspace.CurrentCamera
        CameraCon()
        WTVP = Camera.WorldToViewportPoint
    end

    -- Cache per-frame values
    local camCF  = Camera.CFrame
    local camPos = camCF.Position
    local showBoxes   = CFG.ShowBoxes
    local showNames   = CFG.ShowNames
    local showDist    = CFG.ShowDistance
    local showHealth  = CFG.ShowHealth
    local showTracers = CFG.ShowTracers
    local showDot     = CFG.ShowDot
    local maxDist     = CFG.MaxDistance

    -- ── Players ──────────────────────────────────────────────────────────────
    for player, d in pairs(PlayerESP) do
        local NameTag       = d.NameTag
        local DistanceTag   = d.DistanceTag
        local Tracer        = d.Tracer
        local OutlineTracer = d.OutlineTracer
        local HeadDot       = d.HeadDot
        local Box           = d.Box

        local Character        = player.Character
        local Head             = Character and Character:FindFirstChild('Head')
        local HumanoidRootPart = Character and Character:FindFirstChild('HumanoidRootPart')
        local Humanoid         = Character and Character:FindFirstChildOfClass('Humanoid')

        if not Character or not Head or not HumanoidRootPart or not Humanoid
        or Humanoid:GetState() == Enum.HumanoidStateType.Dead then
            NameTag.Visible       = false
            DistanceTag.Visible   = false
            HeadDot.Visible       = false
            Tracer.Visible        = false
            OutlineTracer.Visible = false
            Box:SetVisible(false)
            continue
        end

        local headPos = Head.Position
        local Distance = (camPos - headPos).Magnitude
        if Distance > maxDist then
            NameTag.Visible       = false
            DistanceTag.Visible   = false
            HeadDot.Visible       = false
            Tracer.Visible        = false
            OutlineTracer.Visible = false
            Box:SetVisible(false)
            continue
        end

        local ScreenPosition = WorldToViewport(headPos)

        -- Color (cache IsBeast result — avoid calling it twice)
        local isBeast = IsBeast(player)
        local Color
        if isBeast then
            Color = CFG.BeastColor
        elseif CheckTeam(player) then
            Color = CFG.TeamColor
        else
            Color = CFG.EnemyColor
        end

        -- Tracers — only compute tracer math when tracers are enabled
        if showTracers then
            local OPos = camCF:pointToObjectSpace(headPos)
            if ScreenPosition.Z < 0 then
                local AT = math.atan2(OPos.Y, OPos.X) + math.pi
                OPos = CFrame.Angles(0, 0, AT):vectorToWorldSpace((CFrame.Angles(0, math.rad(89.9), 0):vectorToWorldSpace(V3New(0, 0, -1))))
            end
            local Position = WorldToViewport(camCF:pointToWorldSpace(OPos))

            if TracerPosition.X >= Camera.ViewportSize.X or TracerPosition.Y >= Camera.ViewportSize.Y or TracerPosition.X < 0 or TracerPosition.Y < 0 then
                TracerPosition = V2New(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y - 135)
            end

            Tracer.Visible      = true
            Tracer.Transparency = math.clamp(1 - (Distance / 200), 0.25, 0.75)
            Tracer.From         = TracerPosition
            Tracer.To           = V2New(Position.X, Position.Y)
            Tracer.Color        = Color
            OutlineTracer.From         = Tracer.From
            OutlineTracer.To           = Tracer.To
            OutlineTracer.Transparency = Tracer.Transparency - 0.15
            OutlineTracer.Visible      = true
        else
            Tracer.Visible        = false
            OutlineTracer.Visible = false
        end

        -- Visibility check (single dot product for both front + FOV)
        local headInFront, headInFOV = CheckVisibility(headPos, camCF, 30)

        if headInFront and ScreenPosition.Z > 0 then
            local Scale = Head.Size.Y / 2

            -- Name tag
            if showNames then
                local ScreenPositionUpper = WorldToViewport((HumanoidRootPart:GetRenderCFrame() * CFrame.new(0, Head.Size.Y + HumanoidRootPart.Size.Y, 0)).Position)
                local tag = isBeast and ("[BEAST] " .. player.Name) or player.Name
                NameTag.Visible      = true
                NameTag.Text         = tag
                NameTag.Size         = CFG.TextSize
                NameTag.Outline      = CFG.TextOutline
                NameTag.Position     = V2New(ScreenPositionUpper.X, ScreenPositionUpper.Y) - V2New(0, NameTag.TextBounds.Y)
                NameTag.Color        = Color
                NameTag.OutlineColor = Color3.new(0.05, 0.05, 0.05)
                NameTag.Transparency = 0.85
            else
                NameTag.Visible = false
            end

            -- Distance / Health tag
            if showDist or showHealth then
                local Str = ''
                if showDist then
                    Str = Str .. string.format('[%d] ', Distance)
                end
                if showHealth then
                    Str = Str .. string.format('[%d/%d] [%s%%]', Humanoid.Health, Humanoid.MaxHealth, math.floor(Humanoid.Health / Humanoid.MaxHealth * 100))
                end

                local distPos
                if showNames then
                    distPos = NameTag.Position + V2New(0, NameTag.TextBounds.Y)
                else
                    local sp2 = WorldToViewport((HumanoidRootPart:GetRenderCFrame() * CFrame.new(0, Head.Size.Y + HumanoidRootPart.Size.Y, 0)).Position)
                    distPos = V2New(sp2.X, sp2.Y)
                end

                DistanceTag.Visible      = true
                DistanceTag.Size         = CFG.TextSize - 1
                DistanceTag.Outline      = CFG.TextOutline
                DistanceTag.Color        = Color3.new(1, 1, 1)
                DistanceTag.Transparency = 0.85
                DistanceTag.Text         = Str
                DistanceTag.OutlineColor = Color3.new(0.05, 0.05, 0.05)
                DistanceTag.Position     = distPos
            else
                DistanceTag.Visible = false
            end

            -- Head dot (gated by FOV check)
            if showDot and headInFOV then
                local Top    = WorldToViewport((Head.CFrame * CFrame.new(0,  Scale, 0)).Position)
                local Bottom = WorldToViewport((Head.CFrame * CFrame.new(0, -Scale, 0)).Position)
                HeadDot.Visible  = true
                HeadDot.Color    = Color
                HeadDot.Position = V2New(ScreenPosition.X, ScreenPosition.Y)
                HeadDot.Radius   = math.abs((Top - Bottom).Y)
            else
                HeadDot.Visible = false
            end

            -- Box (gated by FOV)
            if showBoxes and headInFOV then
                Box:Update(HumanoidRootPart.CFrame, V3New(2, 3, 1) * (Scale * 2), Color)
            else
                Box:SetVisible(false)
            end
        else
            NameTag.Visible     = false
            DistanceTag.Visible = false
            HeadDot.Visible     = false
            Box:SetVisible(false)
        end
    end

    -- ── Computers ────────────────────────────────────────────────────────────
    for model, d in pairs(ComputerESP) do
        local NameTag       = d.NameTag
        local DistanceTag   = d.DistanceTag
        local Tracer        = d.Tracer
        local OutlineTracer = d.OutlineTracer
        local Box           = d.Box

        if not model.Parent then
            NameTag.Visible       = false
            DistanceTag.Visible   = false
            Tracer.Visible        = false
            OutlineTracer.Visible = false
            Box:SetVisible(false)
            continue
        end

        local screen = model:FindFirstChild("Screen", true)
        local useScreen = screen and screen:IsA("BasePart")

        local refPos
        if useScreen then
            refPos = screen.Position
        else
            local ok, cf = pcall(function() return model:GetBoundingBox() end)
            if not ok or not cf then
                NameTag.Visible       = false
                DistanceTag.Visible   = false
                Tracer.Visible        = false
                OutlineTracer.Visible = false
                Box:SetVisible(false)
                continue
            end
            refPos = cf.Position
        end

        local dist = (camPos - refPos).Magnitude
        if dist > maxDist then
            NameTag.Visible       = false
            DistanceTag.Visible   = false
            Tracer.Visible        = false
            OutlineTracer.Visible = false
            Box:SetVisible(false)
            continue
        end

        -- Single visibility check (front + FOV)
        local inFront, inFOV = CheckVisibility(refPos, camCF, 30)
        if not inFront then
            NameTag.Visible       = false
            DistanceTag.Visible   = false
            Tracer.Visible        = false
            OutlineTracer.Visible = false
            Box:SetVisible(false)
            continue
        end

        local sp = WorldToViewport(refPos)
        if sp.Z <= 0 then
            NameTag.Visible       = false
            DistanceTag.Visible   = false
            Tracer.Visible        = false
            OutlineTracer.Visible = false
            Box:SetVisible(false)
            continue
        end

        local color = GetComputerColor(model)

        -- Box (gated by FOV; Box:Update has internal safety)
        if showBoxes and inFOV then
            if useScreen then
                Box:Update(screen.CFrame, screen.Size, color)
            else
                local ok, cf, sz = pcall(function() return model:GetBoundingBox() end)
                if ok and cf then
                    Box:Update(cf, sz, color)
                else
                    Box:SetVisible(false)
                end
            end
        else
            Box:SetVisible(false)
        end

        -- Name
        if showNames and inFOV then
            NameTag.Visible  = true
            NameTag.Text     = "Computer"
            NameTag.Size     = CFG.TextSize
            NameTag.Outline  = CFG.TextOutline
            NameTag.Position = V2New(sp.X, sp.Y)
            NameTag.Color    = color
        else
            NameTag.Visible = false
        end

        -- Distance
        if showDist and inFOV then
            DistanceTag.Visible  = true
            DistanceTag.Size     = CFG.TextSize - 1
            DistanceTag.Outline  = CFG.TextOutline
            DistanceTag.Color    = Color3.new(1, 1, 1)
            DistanceTag.Text     = string.format('[%d] ', dist)
            DistanceTag.Position = V2New(sp.X, sp.Y) + V2New(0, NameTag.TextBounds.Y)
        else
            DistanceTag.Visible = false
        end

        -- Tracers
        if showTracers then
            local OPos = camCF:pointToObjectSpace(refPos)
            if sp.Z < 0 then
                local AT = math.atan2(OPos.Y, OPos.X) + math.pi
                OPos = CFrame.Angles(0, 0, AT):vectorToWorldSpace((CFrame.Angles(0, math.rad(89.9), 0):vectorToWorldSpace(V3New(0, 0, -1))))
            end
            local Position = WorldToViewport(camCF:pointToWorldSpace(OPos))

            Tracer.Transparency        = math.clamp(dist / 200, 0.45, 0.8)
            Tracer.Visible             = true
            Tracer.From                = TracerPosition
            Tracer.To                  = V2New(Position.X, Position.Y)
            Tracer.Color               = color
            OutlineTracer.Visible      = true
            OutlineTracer.Transparency = Tracer.Transparency - 0.1
            OutlineTracer.From         = Tracer.From
            OutlineTracer.To           = Tracer.To
        else
            Tracer.Visible        = false
            OutlineTracer.Visible = false
        end
    end
end)

print("[ESP] Loaded — Players, Beast & Computers")

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
-- Returns true if a world position is actually in front of the camera
-- This does NOT rely on WorldToViewportPoint at all
local function IsInFrontOfCamera(worldPos)
    local camCF = Camera.CFrame
    local toTarget = (worldPos - camCF.Position)
    local dist = toTarget.Magnitude
    if dist < 0.01 then return true end
    local dot = camCF.LookVector:Dot(toTarget / dist)
    return dot > 0
end

-- Returns true if a world position is roughly within the camera's field of view
local function IsInCameraFOV(worldPos, marginDeg)
    local camCF = Camera.CFrame
    local toTarget = (worldPos - camCF.Position)
    local dist = toTarget.Magnitude
    if dist < 0.01 then return true end
    local dot = camCF.LookVector:Dot(toTarget / dist)
    local halfFov = math.rad((Camera.FieldOfView / 2) + (marginDeg or 20))
    return dot > math.cos(halfFov)
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

-- Check if a number is finite (not NaN, not inf)
local function isFinite(n)
    return n == n and n ~= math.huge and n ~= -math.huge
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

        -- LAYER 1: Dot product — is the box center actually in front of the camera?
        if not IsInFrontOfCamera(CF.Position) then
            Box:SetVisible(false)
            return
        end

        -- LAYER 2: FOV check — is the center roughly within the camera's FOV?
        -- Use generous margin (40 degrees past FOV edge) so boxes partially on screen still show
        if not IsInCameraFOV(CF.Position, 40) then
            Box:SetVisible(false)
            return
        end

        -- LAYER 3: Project center as single point (same as nametags) and sanity check
        local centerSP = WorldToViewport(CF.Position)
        local VPX, VPY = Camera.ViewportSize.X, Camera.ViewportSize.Y

        if not isFinite(centerSP.X) or not isFinite(centerSP.Y) or not isFinite(centerSP.Z) then
            Box:SetVisible(false)
            return
        end

        if centerSP.Z <= 0 then
            Box:SetVisible(false)
            return
        end

        -- Center must be roughly on screen (generous margin)
        local centerMargin = math.max(VPX, VPY)
        if centerSP.X < -centerMargin or centerSP.X > VPX + centerMargin
        or centerSP.Y < -centerMargin or centerSP.Y > VPY + centerMargin then
            Box:SetVisible(false)
            return
        end

        -- LAYER 4: Project the 4 corners
        local TLPos = WorldToViewport((CF * CFrame.new( Size.X,  Size.Y, 0)).Position)
        local TRPos = WorldToViewport((CF * CFrame.new(-Size.X,  Size.Y, 0)).Position)
        local BLPos = WorldToViewport((CF * CFrame.new( Size.X, -Size.Y, 0)).Position)
        local BRPos = WorldToViewport((CF * CFrame.new(-Size.X, -Size.Y, 0)).Position)

        -- LAYER 5: Check each corner is finite
        local corners = {TLPos, TRPos, BLPos, BRPos}
        for idx, c in ipairs(corners) do
            if not isFinite(c.X) or not isFinite(c.Y) or not isFinite(c.Z) then
                Box:SetVisible(false)
                return
            end
        end

        -- LAYER 6: All corners must have Z > 0 (in front of camera)
        if TLPos.Z <= 0 or TRPos.Z <= 0 or BLPos.Z <= 0 or BRPos.Z <= 0 then
            Box:SetVisible(false)
            return
        end

        -- LAYER 7: No corner should be absurdly far from the projected center
        -- If any corner is more than 1 viewport-width away from center, something is wrong
        local maxCornerDist = math.max(VPX, VPY)
        for idx, c in ipairs(corners) do
            local dx = math.abs(c.X - centerSP.X)
            local dy = math.abs(c.Y - centerSP.Y)
            if dx > maxCornerDist or dy > maxCornerDist then
                Box:SetVisible(false)
                return
            end
        end

        -- LAYER 8: The projected box shouldn't be insanely large
        local minX = math.min(TLPos.X, TRPos.X, BLPos.X, BRPos.X)
        local maxX = math.max(TLPos.X, TRPos.X, BLPos.X, BRPos.X)
        local minY = math.min(TLPos.Y, TRPos.Y, BLPos.Y, BRPos.Y)
        local maxY = math.max(TLPos.Y, TRPos.Y, BLPos.Y, BRPos.Y)
        local boxW = maxX - minX
        local boxH = maxY - minY

        if boxW > VPX * 1.5 or boxH > VPY * 1.5 then
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

    -- ── Players ──────────────────────────────────────────────────────────────
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end

        local d = PlayerESP[player]
        if not d then continue end

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

        local function hideAll()
            NameTag.Visible       = false
            DistanceTag.Visible   = false
            HeadDot.Visible       = false
            Tracer.Visible        = false
            OutlineTracer.Visible = false
            Box:SetVisible(false)
        end

        local Dead = Humanoid and Humanoid:GetState().Name == 'Dead'

        if not Character or not Head or not HumanoidRootPart or not Humanoid or Dead then
            hideAll(); continue
        end

        local ScreenPosition, Vis = WorldToViewport(Head.Position)

        local Distance = (Camera.CFrame.Position - Head.Position).Magnitude
        if Distance > CFG.MaxDistance then hideAll(); continue end

        local Color
        if IsBeast(player) then
            Color = CFG.BeastColor
        elseif CheckTeam(player) then
            Color = CFG.TeamColor
        else
            Color = CFG.EnemyColor
        end

        -- Tracers (identical to Unnamed ESP)
        local OPos = Camera.CFrame:pointToObjectSpace(Head.Position)

        if ScreenPosition.Z < 0 then
            local AT = math.atan2(OPos.Y, OPos.X) + math.pi
            OPos = CFrame.Angles(0, 0, AT):vectorToWorldSpace((CFrame.Angles(0, math.rad(89.9), 0):vectorToWorldSpace(V3New(0, 0, -1))))
        end

        local Position = WorldToViewport(Camera.CFrame:pointToWorldSpace(OPos))

        if CFG.ShowTracers then
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

        -- Use dot product to check if head is actually visible (executor-independent)
        local headInFront = IsInFrontOfCamera(Head.Position)
        local headInFOV   = IsInCameraFOV(Head.Position, 30)

        if headInFront and ScreenPosition.Z > 0 then
            local ScreenPositionUpper = WorldToViewport((HumanoidRootPart:GetRenderCFrame() * CFrame.new(0, Head.Size.Y + HumanoidRootPart.Size.Y, 0)).Position)
            local Scale = Head.Size.Y / 2

            -- Name tag (same as before — these work fine)
            if CFG.ShowNames then
                local tag = player.Name
                if IsBeast(player) then tag = "[BEAST] " .. tag end
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
            if CFG.ShowDistance or CFG.ShowHealth then
                local Str = ''
                if CFG.ShowDistance then
                    Str = Str .. string.format('[%d] ', Distance)
                end
                if CFG.ShowHealth then
                    Str = Str .. string.format('[%d/%d] [%s%%]', Humanoid.Health, Humanoid.MaxHealth, math.floor(Humanoid.Health / Humanoid.MaxHealth * 100))
                end

                DistanceTag.Visible      = true
                DistanceTag.Size         = CFG.TextSize - 1
                DistanceTag.Outline      = CFG.TextOutline
                DistanceTag.Color        = Color3.new(1, 1, 1)
                DistanceTag.Transparency = 0.85
                DistanceTag.Text         = Str
                DistanceTag.OutlineColor = Color3.new(0.05, 0.05, 0.05)
                DistanceTag.Position     = (NameTag.Visible and NameTag.Position + V2New(0, NameTag.TextBounds.Y) or V2New(ScreenPositionUpper.X, ScreenPositionUpper.Y))
            else
                DistanceTag.Visible = false
            end

            -- Head dot (gated by FOV check)
            if CFG.ShowDot and headInFOV then
                local Top    = WorldToViewport((Head.CFrame * CFrame.new(0,  Scale, 0)).Position)
                local Bottom = WorldToViewport((Head.CFrame * CFrame.new(0, -Scale, 0)).Position)
                local Radius = math.abs((Top - Bottom).Y)

                HeadDot.Visible  = true
                HeadDot.Color    = Color
                HeadDot.Position = V2New(ScreenPosition.X, ScreenPosition.Y)
                HeadDot.Radius   = Radius
            else
                HeadDot.Visible = false
            end

            -- Box: Box:Update has 8 layers of safety checks internally
            -- Only call it if head is within FOV (prevents edge cases entirely)
            if CFG.ShowBoxes and headInFOV and HumanoidRootPart then
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

        local function hideAll()
            NameTag.Visible       = false
            DistanceTag.Visible   = false
            Tracer.Visible        = false
            OutlineTracer.Visible = false
            Box:SetVisible(false)
        end

        if not model.Parent then hideAll(); continue end

        local screen = model:FindFirstChild("Screen", true)
        local useScreen = screen and screen:IsA("BasePart")

        local refPos
        if useScreen then
            refPos = screen.Position
        else
            local ok, cf, sz = pcall(function() return model:GetBoundingBox() end)
            if not ok or not cf then hideAll(); continue end
            refPos = cf.Position
        end

        -- Dot product check (executor-independent)
        if not IsInFrontOfCamera(refPos) then hideAll(); continue end

        local sp = WorldToViewport(refPos)
        if sp.Z <= 0 then hideAll(); continue end

        local dist = (Camera.CFrame.Position - refPos).Magnitude
        if dist > CFG.MaxDistance then hideAll(); continue end

        local color = GetComputerColor(model)
        local inFOV = IsInCameraFOV(refPos, 30)

        -- Box (gated by FOV; Box:Update has internal safety layers)
        if CFG.ShowBoxes and inFOV then
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
        if CFG.ShowNames and inFOV then
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
        if CFG.ShowDistance and inFOV then
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
        if CFG.ShowTracers then
            local OPos = Camera.CFrame:pointToObjectSpace(refPos)
            if sp.Z < 0 then
                local AT = math.atan2(OPos.Y, OPos.X) + math.pi
                OPos = CFrame.Angles(0, 0, AT):vectorToWorldSpace((CFrame.Angles(0, math.rad(89.9), 0):vectorToWorldSpace(V3New(0, 0, -1))))
            end
            local Position = WorldToViewport(Camera.CFrame:pointToWorldSpace(OPos))

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

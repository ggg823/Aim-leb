--[[
    AIM LAB MOBILE
    Mobile Aim Assist + RGB ESP + Natural Team Check

    Uso: ambiente de teste próprio no Roblox.

    Recursos:
    - Interface mobile
    - Aim Assist ON/OFF
    - Team Check natural (ignora aliados silenciosamente)
    - Wall Check
    - Target Lock
    - NPC Targets
    - FOV ajustável
    - Smoothness ajustável
    - Target Part: Head / UpperTorso / HumanoidRootPart
    - RGB ESP
    - Nome e distância no ESP
    - Botão HIDE
    - Botão OPEN pequeno quando a UI estiver escondida
    - Janela arrastável por touch
    - Limpeza automática ao executar novamente
]]

--==============================================================
-- SERVICES
--==============================================================

local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Camera = workspace.CurrentCamera

--==============================================================
-- CLEANUP
--==============================================================

pcall(function()
    RunService:UnbindFromRenderStep("AimLabMobile_Render")
end)

local oldGui = PlayerGui:FindFirstChild("AimLabMobile")
if oldGui then
    oldGui:Destroy()
end

local oldESPFolder = workspace:FindFirstChild("_AimLabMobileESP")
if oldESPFolder then
    oldESPFolder:Destroy()
end

--==============================================================
-- SETTINGS
--==============================================================

local Settings = {
    Aim = {
        Enabled = true,
        Active = false,

        TeamCheck = true,
        WallCheck = true,
        TargetLock = true,
        TargetNPCs = true,

        FOV = 180,
        ShowFOV = true,
        Smoothness = 0.14,
        MaxDistance = 1500,

        TargetPart = "Head",
        ReacquireRate = 0.06,
    },

    ESP = {
        Enabled = true,
        Players = true,
        NPCs = true,
        Rainbow = true,
        Names = true,
        Distance = true,

        FillTransparency = 0.78,
        OutlineTransparency = 0,
        RainbowSpeed = 0.17,
        UpdateRate = 1 / 30,
    }
}

--==============================================================
-- THEME
--==============================================================

local Theme = {
    Background = Color3.fromRGB(9, 10, 14),
    Panel = Color3.fromRGB(17, 19, 26),
    Card = Color3.fromRGB(25, 28, 38),
    CardHover = Color3.fromRGB(34, 38, 50),
    Border = Color3.fromRGB(69, 75, 98),

    Text = Color3.fromRGB(245, 246, 250),
    Secondary = Color3.fromRGB(143, 149, 169),

    Accent = Color3.fromRGB(137, 105, 255),
    Ally = Color3.fromRGB(72, 227, 145),
    Enemy = Color3.fromRGB(255, 83, 108),
    Neutral = Color3.fromRGB(255, 198, 84),
    NPC = Color3.fromRGB(188, 112, 255),
}

--==============================================================
-- STATE
--==============================================================

local CurrentTarget = nil
local TargetCache = {}
local ESPObjects = {}

local CacheTimer = 999
local ESPTimer = 999
local ReacquireTimer = 999

local TargetParts = {
    "Head",
    "UpperTorso",
    "HumanoidRootPart"
}

local TargetPartIndex = 1

--==============================================================
-- BASIC HELPERS
--==============================================================

local function New(className, properties, parent)
    local object = Instance.new(className)

    for property, value in pairs(properties) do
        object[property] = value
    end

    if parent then
        object.Parent = parent
    end

    return object
end

local function AddCorner(parent, radius)
    return New("UICorner", {
        CornerRadius = UDim.new(0, radius)
    }, parent)
end

local function AddStroke(parent, transparency)
    return New("UIStroke", {
        Color = Theme.Border,
        Thickness = 1,
        Transparency = transparency or 0.55
    }, parent)
end

local function Tween(object, properties, duration)
    TweenService:Create(
        object,
        TweenInfo.new(
            duration or 0.16,
            Enum.EasingStyle.Quint,
            Enum.EasingDirection.Out
        ),
        properties
    ):Play()
end

--==============================================================
-- TEAM RECOGNIZER
--==============================================================

local function FindTeamFromColor(teamColor)
    for _, team in ipairs(Teams:GetTeams()) do
        if team.TeamColor == teamColor then
            return team
        end
    end

    return nil
end

local function IsSameTeam(model)
    local targetPlayer = Players:GetPlayerFromCharacter(model)

    -- NPC não possui time.
    if not targetPlayer then
        return false
    end

    if targetPlayer == LocalPlayer then
        return true
    end

    -- Neutral não é considerado aliado automaticamente.
    if LocalPlayer.Neutral or targetPlayer.Neutral then
        return false
    end

    -- Método principal: compara o objeto Team.
    if LocalPlayer.Team and targetPlayer.Team then
        return LocalPlayer.Team == targetPlayer.Team
    end

    -- Fallback para jogos que dependem de TeamColor.
    local localTeam = FindTeamFromColor(LocalPlayer.TeamColor)
    local targetTeam = FindTeamFromColor(targetPlayer.TeamColor)

    if localTeam and targetTeam then
        return localTeam == targetTeam
    end

    return false
end

--==============================================================
-- TARGET HELPERS
--==============================================================

local function GetHumanoid(model)
    if not model then
        return nil
    end

    return model:FindFirstChildOfClass("Humanoid")
end

local function GetTargetPart(model)
    if not model then
        return nil
    end

    local humanoid = GetHumanoid(model)

    if not humanoid or humanoid.Health <= 0 then
        return nil
    end

    local preferred = model:FindFirstChild(Settings.Aim.TargetPart)

    if preferred and preferred:IsA("BasePart") then
        return preferred
    end

    local head = model:FindFirstChild("Head")

    if head and head:IsA("BasePart") then
        return head
    end

    local torso = model:FindFirstChild("UpperTorso")

    if torso and torso:IsA("BasePart") then
        return torso
    end

    local root = model:FindFirstChild("HumanoidRootPart")

    if root and root:IsA("BasePart") then
        return root
    end

    return nil
end

local function WorldDistance(model)
    if not Camera then
        return math.huge
    end

    local part = GetTargetPart(model)

    if not part then
        return math.huge
    end

    return (part.Position - Camera.CFrame.Position).Magnitude
end

local function ScreenDistance(part)
    if not Camera or not part then
        return math.huge
    end

    local point, onScreen = Camera:WorldToViewportPoint(part.Position)

    if not onScreen or point.Z <= 0 then
        return math.huge
    end

    local center = Vector2.new(
        Camera.ViewportSize.X / 2,
        Camera.ViewportSize.Y / 2
    )

    return (
        Vector2.new(point.X, point.Y)
        - center
    ).Magnitude
end

local function IsVisible(model, targetPart)
    if not Settings.Aim.WallCheck then
        return true
    end

    if not Camera then
        return false
    end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude

    local ignore = {}

    if LocalPlayer.Character then
        table.insert(ignore, LocalPlayer.Character)
    end

    params.FilterDescendantsInstances = ignore

    local origin = Camera.CFrame.Position
    local direction = targetPart.Position - origin

    local result = workspace:Raycast(
        origin,
        direction,
        params
    )

    if not result then
        return true
    end

    return result.Instance:IsDescendantOf(model)
end

--==============================================================
-- TARGET CACHE
--==============================================================

local function RefreshTargets()
    local newCache = {}
    local added = {}

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local humanoid = GetHumanoid(player.Character)

            if humanoid and humanoid.Health > 0 then
                added[player.Character] = true
                table.insert(newCache, player.Character)
            end
        end
    end

    if Settings.Aim.TargetNPCs or Settings.ESP.NPCs then
        for _, object in ipairs(workspace:GetDescendants()) do
            if
                object:IsA("Model")
                and object ~= LocalPlayer.Character
                and not added[object]
            then
                local humanoid = object:FindFirstChildOfClass("Humanoid")

                if humanoid and humanoid.Health > 0 then
                    added[object] = true
                    table.insert(newCache, object)
                end
            end
        end
    end

    TargetCache = newCache
end

--==============================================================
-- TARGET FILTER
--==============================================================

local function TargetAllowed(model)
    if not model or not model.Parent then
        return false
    end

    if model == LocalPlayer.Character then
        return false
    end

    local humanoid = GetHumanoid(model)

    if not humanoid or humanoid.Health <= 0 then
        return false
    end

    local player = Players:GetPlayerFromCharacter(model)

    if player then
        -- TEAM RECOGNIZER:
        -- aliados são removidos silenciosamente da seleção.
        if Settings.Aim.TeamCheck and IsSameTeam(model) then
            return false
        end
    else
        if not Settings.Aim.TargetNPCs then
            return false
        end
    end

    local part = GetTargetPart(model)

    if not part then
        return false
    end

    if WorldDistance(model) > Settings.Aim.MaxDistance then
        return false
    end

    return true
end

local function TargetValid(model)
    if not TargetAllowed(model) then
        return false
    end

    local part = GetTargetPart(model)

    if not part then
        return false
    end

    if ScreenDistance(part) > Settings.Aim.FOV then
        return false
    end

    if not IsVisible(model, part) then
        return false
    end

    return true
end

local function FindBestTarget()
    local bestTarget = nil
    local bestDistance = Settings.Aim.FOV

    for _, model in ipairs(TargetCache) do
        if TargetAllowed(model) then
            local part = GetTargetPart(model)

            if part then
                local distance = ScreenDistance(part)

                if
                    distance < bestDistance
                    and IsVisible(model, part)
                then
                    bestDistance = distance
                    bestTarget = model
                end
            end
        end
    end

    return bestTarget
end

local function SwitchTarget()
    local candidates = {}

    for _, model in ipairs(TargetCache) do
        if TargetAllowed(model) then
            local part = GetTargetPart(model)

            if part then
                local distance = ScreenDistance(part)

                if
                    distance <= Settings.Aim.FOV
                    and IsVisible(model, part)
                then
                    table.insert(candidates, {
                        Model = model,
                        Distance = distance
                    })
                end
            end
        end
    end

    table.sort(candidates, function(a, b)
        return a.Distance < b.Distance
    end)

    if #candidates == 0 then
        CurrentTarget = nil
        return
    end

    if not CurrentTarget then
        CurrentTarget = candidates[1].Model
        return
    end

    local currentIndex = nil

    for index, data in ipairs(candidates) do
        if data.Model == CurrentTarget then
            currentIndex = index
            break
        end
    end

    if not currentIndex then
        CurrentTarget = candidates[1].Model
        return
    end

    currentIndex += 1

    if currentIndex > #candidates then
        currentIndex = 1
    end

    CurrentTarget = candidates[currentIndex].Model
end

--==============================================================
-- AIM CAMERA
--==============================================================

local function AimAt(model, deltaTime)
    if not Camera then
        return
    end

    local part = GetTargetPart(model)

    if not part then
        return
    end

    local cameraPosition = Camera.CFrame.Position

    local targetCFrame = CFrame.lookAt(
        cameraPosition,
        part.Position
    )

    local smooth = math.clamp(
        Settings.Aim.Smoothness,
        0.01,
        1
    )

    local alpha =
        1
        - math.pow(
            1 - smooth,
            deltaTime * 60
        )

    Camera.CFrame = Camera.CFrame:Lerp(
        targetCFrame,
        math.clamp(alpha, 0, 1)
    )
end

--==============================================================
-- GUI ROOT
--==============================================================

local Gui = New("ScreenGui", {
    Name = "AimLabMobile",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 999999
}, PlayerGui)

local ESPFolder = New("Folder", {
    Name = "_AimLabMobileESP"
}, workspace)

--==============================================================
-- FOV
--==============================================================

local FOVCircle = New("Frame", {
    Name = "FOVCircle",

    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),

    Size = UDim2.fromOffset(
        Settings.Aim.FOV * 2,
        Settings.Aim.FOV * 2
    ),

    BackgroundTransparency = 1,
    BorderSizePixel = 0,

    ZIndex = 2
}, Gui)

New("UICorner", {
    CornerRadius = UDim.new(1, 0)
}, FOVCircle)

local FOVStroke = New("UIStroke", {
    Color = Theme.Accent,
    Thickness = 1,
    Transparency = 0.5
}, FOVCircle)

--==============================================================
-- MAIN WINDOW
--==============================================================

local Main = New("Frame", {
    Name = "Main",

    AnchorPoint = Vector2.new(0, 0.5),

    Position = UDim2.new(
        0,
        14,
        0.5,
        0
    ),

    Size = UDim2.fromOffset(
        350,
        520
    ),

    BackgroundColor3 = Theme.Background,
    BackgroundTransparency = 0.035,

    BorderSizePixel = 0,
    ClipsDescendants = true,

    ZIndex = 50
}, Gui)

AddCorner(Main, 21)
AddStroke(Main, 0.24)

New("UIGradient", {
    Rotation = 125,

    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(
            0,
            Color3.fromRGB(29, 31, 42)
        ),

        ColorSequenceKeypoint.new(
            0.5,
            Color3.fromRGB(16, 18, 25)
        ),

        ColorSequenceKeypoint.new(
            1,
            Color3.fromRGB(8, 9, 13)
        )
    })
}, Main)

--==============================================================
-- HEADER
--==============================================================

local Header = New("Frame", {
    Size = UDim2.new(
        1,
        0,
        0,
        70
    ),

    BackgroundTransparency = 1,
    Active = true,

    ZIndex = 51
}, Main)

local Logo = New("Frame", {
    Position = UDim2.fromOffset(
        16,
        15
    ),

    Size = UDim2.fromOffset(
        40,
        40
    ),

    BackgroundColor3 = Theme.Accent,
    BorderSizePixel = 0,

    ZIndex = 52
}, Header)

AddCorner(Logo, 13)

New("UIGradient", {
    Rotation = 45,

    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(
            0,
            Color3.fromRGB(198, 133, 255)
        ),

        ColorSequenceKeypoint.new(
            1,
            Color3.fromRGB(73, 98, 255)
        )
    })
}, Logo)

New("TextLabel", {
    Size = UDim2.fromScale(1, 1),

    BackgroundTransparency = 1,

    Text = "A",
    TextColor3 = Color3.new(1, 1, 1),
    TextSize = 18,

    Font = Enum.Font.GothamBold,

    ZIndex = 53
}, Logo)

New("TextLabel", {
    Position = UDim2.fromOffset(
        67,
        13
    ),

    Size = UDim2.new(
        1,
        -145,
        0,
        24
    ),

    BackgroundTransparency = 1,

    Text = "AIM LAB",
    TextColor3 = Theme.Text,
    TextSize = 17,

    TextXAlignment = Enum.TextXAlignment.Left,

    Font = Enum.Font.GothamBold,

    ZIndex = 52
}, Header)

New("TextLabel", {
    Position = UDim2.fromOffset(
        67,
        37
    ),

    Size = UDim2.new(
        1,
        -145,
        0,
        16
    ),

    BackgroundTransparency = 1,

    Text = "MOBILE TEST BUILD",
    TextColor3 = Theme.Secondary,
    TextSize = 8,

    TextXAlignment = Enum.TextXAlignment.Left,

    Font = Enum.Font.GothamBold,

    ZIndex = 52
}, Header)

local HideButton = New("TextButton", {
    AnchorPoint = Vector2.new(1, 0),

    Position = UDim2.new(
        1,
        -14,
        0,
        17
    ),

    Size = UDim2.fromOffset(
        54,
        36
    ),

    BackgroundColor3 = Theme.Card,
    BackgroundTransparency = 0.08,

    BorderSizePixel = 0,

    Text = "HIDE",
    TextColor3 = Theme.Secondary,
    TextSize = 9,

    Font = Enum.Font.GothamBold,
    AutoButtonColor = false,

    ZIndex = 53
}, Header)

AddCorner(HideButton, 11)
AddStroke(HideButton, 0.65)

--==============================================================
-- OPEN BUTTON
--==============================================================

local OpenButton = New("TextButton", {
    AnchorPoint = Vector2.new(0, 0.5),

    Position = UDim2.new(
        0,
        14,
        0.5,
        0
    ),

    Size = UDim2.fromOffset(
        58,
        42
    ),

    BackgroundColor3 = Theme.Background,
    BackgroundTransparency = 0.08,

    BorderSizePixel = 0,

    Text = "OPEN",
    TextColor3 = Theme.Text,
    TextSize = 9,

    Font = Enum.Font.GothamBold,
    AutoButtonColor = false,

    Visible = false,

    ZIndex = 100
}, Gui)

AddCorner(OpenButton, 13)
AddStroke(OpenButton, 0.35)

--==============================================================
-- TABS
--==============================================================

local Tabs = New("Frame", {
    Position = UDim2.fromOffset(
        14,
        70
    ),

    Size = UDim2.new(
        1,
        -28,
        0,
        44
    ),

    BackgroundColor3 = Color3.fromRGB(
        13,
        14,
        20
    ),

    BackgroundTransparency = 0.11,

    BorderSizePixel = 0,

    ZIndex = 52
}, Main)

AddCorner(Tabs, 13)
AddStroke(Tabs, 0.73)

New("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,

    HorizontalAlignment =
        Enum.HorizontalAlignment.Center,

    VerticalAlignment =
        Enum.VerticalAlignment.Center,

    Padding = UDim.new(
        0,
        4
    ),

    SortOrder = Enum.SortOrder.LayoutOrder
}, Tabs)

local function CreateTab(text)
    local button = New("TextButton", {
        Size = UDim2.new(
            0.315,
            0,
            0,
            34
        ),

        BackgroundColor3 = Theme.Card,
        BackgroundTransparency = 1,

        BorderSizePixel = 0,

        Text = text,
        TextColor3 = Theme.Secondary,
        TextSize = 9,

        Font = Enum.Font.GothamBold,

        AutoButtonColor = false,

        ZIndex = 53
    }, Tabs)

    AddCorner(button, 10)

    return button
end

local AimTab = CreateTab("AIM")
local ESPTab = CreateTab("ESP")
local ConfigTab = CreateTab("CONFIG")

--==============================================================
-- PAGE HOLDER
--==============================================================

local PageHolder = New("Frame", {
    Position = UDim2.fromOffset(
        14,
        124
    ),

    Size = UDim2.new(
        1,
        -28,
        1,
        -198
    ),

    BackgroundTransparency = 1,
    ClipsDescendants = true,

    ZIndex = 52
}, Main)

local function CreatePage(name)
    local page = New("ScrollingFrame", {
        Name = name,

        Size = UDim2.fromScale(
            1,
            1
        ),

        BackgroundTransparency = 1,
        BorderSizePixel = 0,

        CanvasSize = UDim2.new(),
        AutomaticCanvasSize =
            Enum.AutomaticSize.Y,

        ScrollBarThickness = 2,
        ScrollBarImageColor3 = Theme.Accent,

        Visible = false,

        ZIndex = 53
    }, PageHolder)

    New("UIListLayout", {
        Padding = UDim.new(
            0,
            8
        ),

        SortOrder = Enum.SortOrder.LayoutOrder
    }, page)

    New("UIPadding", {
        PaddingBottom = UDim.new(
            0,
            10
        )
    }, page)

    return page
end

local AimPage = CreatePage("Aim")
local ESPPage = CreatePage("ESP")
local ConfigPage = CreatePage("Config")

--==============================================================
-- UI COMPONENTS
--==============================================================

local function Section(parent, text)
    return New("TextLabel", {
        Size = UDim2.new(
            1,
            0,
            0,
            22
        ),

        BackgroundTransparency = 1,

        Text = string.upper(text),
        TextColor3 = Theme.Secondary,
        TextSize = 8,

        TextXAlignment = Enum.TextXAlignment.Left,

        Font = Enum.Font.GothamBold,

        ZIndex = 54
    }, parent)
end

local function Toggle(
    parent,
    title,
    description,
    defaultValue,
    callback
)
    local enabled = defaultValue

    local card = New("TextButton", {
        Size = UDim2.new(
            1,
            0,
            0,
            60
        ),

        BackgroundColor3 = Theme.Card,
        BackgroundTransparency = 0.09,

        BorderSizePixel = 0,

        Text = "",
        AutoButtonColor = false,

        ZIndex = 54
    }, parent)

    AddCorner(card, 13)
    AddStroke(card, 0.69)

    New("TextLabel", {
        Position = UDim2.fromOffset(
            14,
            9
        ),

        Size = UDim2.new(
            1,
            -80,
            0,
            20
        ),

        BackgroundTransparency = 1,

        Text = title,
        TextColor3 = Theme.Text,
        TextSize = 11,

        TextXAlignment = Enum.TextXAlignment.Left,

        Font = Enum.Font.GothamMedium,

        ZIndex = 55
    }, card)

    New("TextLabel", {
        Position = UDim2.fromOffset(
            14,
            31
        ),

        Size = UDim2.new(
            1,
            -80,
            0,
            15
        ),

        BackgroundTransparency = 1,

        Text = description,
        TextColor3 = Theme.Secondary,
        TextSize = 8,

        TextXAlignment = Enum.TextXAlignment.Left,

        Font = Enum.Font.Gotham,

        ZIndex = 55
    }, card)

    local switch = New("Frame", {
        AnchorPoint = Vector2.new(
            1,
            0.5
        ),

        Position = UDim2.new(
            1,
            -14,
            0.5,
            0
        ),

        Size = UDim2.fromOffset(
            44,
            25
        ),

        BackgroundColor3 =
            enabled
            and Theme.Accent
            or Theme.CardHover,

        BorderSizePixel = 0,

        ZIndex = 55
    }, card)

    AddCorner(switch, 20)

    local knob = New("Frame", {
        AnchorPoint = Vector2.new(
            0.5,
            0.5
        ),

        Position =
            enabled
            and UDim2.new(
                1,
                -13,
                0.5,
                0
            )
            or UDim2.new(
                0,
                13,
                0.5,
                0
            ),

        Size = UDim2.fromOffset(
            18,
            18
        ),

        BackgroundColor3 = Theme.Text,
        BorderSizePixel = 0,

        ZIndex = 56
    }, switch)

    AddCorner(knob, 20)

    card.Activated:Connect(function()
        enabled = not enabled

        Tween(switch, {
            BackgroundColor3 =
                enabled
                and Theme.Accent
                or Theme.CardHover
        })

        Tween(knob, {
            Position =
                enabled
                and UDim2.new(
                    1,
                    -13,
                    0.5,
                    0
                )
                or UDim2.new(
                    0,
                    13,
                    0.5,
                    0
                )
        })

        if callback then
            callback(enabled)
        end
    end)

    return card
end

local function Adjuster(
    parent,
    title,
    minimum,
    maximum,
    step,
    defaultValue,
    callback,
    formatter
)
    local value = defaultValue

    local card = New("Frame", {
        Size = UDim2.new(
            1,
            0,
            0,
            62
        ),

        BackgroundColor3 = Theme.Card,
        BackgroundTransparency = 0.09,

        BorderSizePixel = 0,

        ZIndex = 54
    }, parent)

    AddCorner(card, 13)
    AddStroke(card, 0.69)

    New("TextLabel", {
        Position = UDim2.fromOffset(
            14,
            8
        ),

        Size = UDim2.new(
            1,
            -120,
            0,
            20
        ),

        BackgroundTransparency = 1,

        Text = title,
        TextColor3 = Theme.Text,
        TextSize = 11,

        TextXAlignment = Enum.TextXAlignment.Left,

        Font = Enum.Font.GothamMedium,

        ZIndex = 55
    }, card)

    local valueLabel = New("TextLabel", {
        Position = UDim2.fromOffset(
            14,
            31
        ),

        Size = UDim2.new(
            1,
            -120,
            0,
            18
        ),

        BackgroundTransparency = 1,

        Text = "",
        TextColor3 = Theme.Accent,
        TextSize = 10,

        TextXAlignment = Enum.TextXAlignment.Left,

        Font = Enum.Font.GothamBold,

        ZIndex = 55
    }, card)

    local minus = New("TextButton", {
        AnchorPoint = Vector2.new(
            1,
            0.5
        ),

        Position = UDim2.new(
            1,
            -55,
            0.5,
            0
        ),

        Size = UDim2.fromOffset(
            38,
            38
        ),

        BackgroundColor3 = Theme.CardHover,
        BorderSizePixel = 0,

        Text = "-",
        TextColor3 = Theme.Text,
        TextSize = 18,

        Font = Enum.Font.GothamBold,
        AutoButtonColor = false,

        ZIndex = 55
    }, card)

    AddCorner(minus, 11)

    local plus = New("TextButton", {
        AnchorPoint = Vector2.new(
            1,
            0.5
        ),

        Position = UDim2.new(
            1,
            -10,
            0.5,
            0
        ),

        Size = UDim2.fromOffset(
            38,
            38
        ),

        BackgroundColor3 = Theme.CardHover,
        BorderSizePixel = 0,

        Text = "+",
        TextColor3 = Theme.Text,
        TextSize = 17,

        Font = Enum.Font.GothamBold,
        AutoButtonColor = false,

        ZIndex = 55
    }, card)

    AddCorner(plus, 11)

    local function refresh()
        if formatter then
            valueLabel.Text = formatter(value)
        else
            valueLabel.Text = tostring(value)
        end

        if callback then
            callback(value)
        end
    end

    minus.Activated:Connect(function()
        value = math.max(
            minimum,
            value - step
        )

        refresh()
    end)

    plus.Activated:Connect(function()
        value = math.min(
            maximum,
            value + step
        )

        refresh()
    end)

    refresh()

    return card
end

local function Action(parent, text, callback)
    local button = New("TextButton", {
        Size = UDim2.new(
            1,
            0,
            0,
            48
        ),

        BackgroundColor3 = Theme.Card,
        BackgroundTransparency = 0.08,

        BorderSizePixel = 0,

        Text = text,
        TextColor3 = Theme.Text,
        TextSize = 9,

        Font = Enum.Font.GothamBold,

        AutoButtonColor = false,

        ZIndex = 54
    }, parent)

    AddCorner(button, 13)
    AddStroke(button, 0.67)

    button.Activated:Connect(function()
        Tween(button, {
            BackgroundColor3 = Theme.CardHover
        }, 0.08)

        task.delay(0.12, function()
            if button.Parent then
                Tween(button, {
                    BackgroundColor3 = Theme.Card
                })
            end
        end)

        if callback then
            callback(button)
        end
    end)

    return button
end

--==============================================================
-- AIM PAGE
--==============================================================

Section(AimPage, "Aim Assist")

Toggle(
    AimPage,
    "Aim Assist",
    "Ativa o controlador de mira",
    Settings.Aim.Enabled,

    function(value)
        Settings.Aim.Enabled = value

        if not value then
            Settings.Aim.Active = false
            CurrentTarget = nil
        end
    end
)

Toggle(
    AimPage,
    "Team Check",
    "Ignora jogadores do mesmo time",
    Settings.Aim.TeamCheck,

    function(value)
        Settings.Aim.TeamCheck = value
        CurrentTarget = nil
    end
)

Toggle(
    AimPage,
    "Target Lock",
    "Mantem o alvo enquanto ele for valido",
    Settings.Aim.TargetLock,

    function(value)
        Settings.Aim.TargetLock = value
    end
)

Toggle(
    AimPage,
    "Wall Check",
    "Ignora alvos atras de paredes",
    Settings.Aim.WallCheck,

    function(value)
        Settings.Aim.WallCheck = value
    end
)

Toggle(
    AimPage,
    "NPC Targets",
    "Permite selecionar NPCs com Humanoid",
    Settings.Aim.TargetNPCs,

    function(value)
        Settings.Aim.TargetNPCs = value
        CacheTimer = 999
        CurrentTarget = nil
    end
)

Toggle(
    AimPage,
    "FOV Circle",
    "Mostra a area de aquisicao",
    Settings.Aim.ShowFOV,

    function(value)
        Settings.Aim.ShowFOV = value
    end
)

Section(AimPage, "Precision")

Adjuster(
    AimPage,
    "FOV",
    50,
    450,
    25,
    Settings.Aim.FOV,

    function(value)
        Settings.Aim.FOV = value
    end,

    function(value)
        return tostring(value) .. " px"
    end
)

Adjuster(
    AimPage,
    "Smoothness",
    0.02,
    0.60,
    0.02,
    Settings.Aim.Smoothness,

    function(value)
        Settings.Aim.Smoothness = value
    end,

    function(value)
        return string.format("%.2f", value)
    end
)

Adjuster(
    AimPage,
    "Max Distance",
    100,
    3000,
    100,
    Settings.Aim.MaxDistance,

    function(value)
        Settings.Aim.MaxDistance = value
    end,

    function(value)
        return tostring(math.floor(value)) .. " studs"
    end
)

Action(
    AimPage,
    "TARGET PART : HEAD",

    function(button)
        TargetPartIndex += 1

        if TargetPartIndex > #TargetParts then
            TargetPartIndex = 1
        end

        Settings.Aim.TargetPart =
            TargetParts[TargetPartIndex]

        button.Text =
            "TARGET PART : "
            .. string.upper(
                Settings.Aim.TargetPart
            )

        CurrentTarget = nil
    end
)

--==============================================================
-- ESP PAGE
--==============================================================

Section(ESPPage, "Visual ESP")

Toggle(
    ESPPage,
    "ESP",
    "Ativa o sistema visual",
    Settings.ESP.Enabled,

    function(value)
        Settings.ESP.Enabled = value
    end
)

Toggle(
    ESPPage,
    "RGB",
    "Anima a cor do ESP",
    Settings.ESP.Rainbow,

    function(value)
        Settings.ESP.Rainbow = value
    end
)

Toggle(
    ESPPage,
    "Players",
    "Mostra jogadores",
    Settings.ESP.Players,

    function(value)
        Settings.ESP.Players = value
    end
)

Toggle(
    ESPPage,
    "NPCs",
    "Mostra NPCs",
    Settings.ESP.NPCs,

    function(value)
        Settings.ESP.NPCs = value
        CacheTimer = 999
    end
)

Toggle(
    ESPPage,
    "Names",
    "Mostra o nome",
    Settings.ESP.Names,

    function(value)
        Settings.ESP.Names = value
    end
)

Toggle(
    ESPPage,
    "Distance",
    "Mostra distancia em studs",
    Settings.ESP.Distance,

    function(value)
        Settings.ESP.Distance = value
    end
)

Section(ESPPage, "RGB")

Adjuster(
    ESPPage,
    "RGB Speed",
    0.02,
    0.60,
    0.03,
    Settings.ESP.RainbowSpeed,

    function(value)
        Settings.ESP.RainbowSpeed = value
    end,

    function(value)
        return string.format("%.2f", value)
    end
)

Adjuster(
    ESPPage,
    "Fill Transparency",
    0,
    1,
    0.05,
    Settings.ESP.FillTransparency,

    function(value)
        Settings.ESP.FillTransparency = value
    end,

    function(value)
        return string.format("%.2f", value)
    end
)

--==============================================================
-- CONFIG PAGE
--==============================================================

Section(ConfigPage, "Interface")

Action(
    ConfigPage,
    "CENTER MENU",

    function()
        Main.AnchorPoint =
            Vector2.new(
                0.5,
                0.5
            )

        Main.Position =
            UDim2.fromScale(
                0.5,
                0.5
            )
    end
)

Action(
    ConfigPage,
    "CLEAR TARGET",

    function()
        CurrentTarget = nil
    end
)

Action(
    ConfigPage,
    "REFRESH TARGET CACHE",

    function()
        CacheTimer = 999
    end
)

Action(
    ConfigPage,
    "HIDE MENU",

    function()
        Main.Visible = false
        OpenButton.Visible = true
    end
)

--==============================================================
-- PAGE SWITCHING
--==============================================================

local function SelectPage(name)
    AimPage.Visible = name == "AIM"
    ESPPage.Visible = name == "ESP"
    ConfigPage.Visible = name == "CONFIG"

    local buttons = {
        {
            AimTab,
            "AIM"
        },

        {
            ESPTab,
            "ESP"
        },

        {
            ConfigTab,
            "CONFIG"
        }
    }

    for _, data in ipairs(buttons) do
        local selected = data[2] == name

        Tween(data[1], {
            BackgroundTransparency =
                selected
                and 0
                or 1,

            TextColor3 =
                selected
                and Theme.Text
                or Theme.Secondary
        })
    end
end

AimTab.Activated:Connect(function()
    SelectPage("AIM")
end)

ESPTab.Activated:Connect(function()
    SelectPage("ESP")
end)

ConfigTab.Activated:Connect(function()
    SelectPage("CONFIG")
end)

SelectPage("AIM")

--==============================================================
-- BOTTOM CONTROLS
--==============================================================

local ControlBar = New("Frame", {
    AnchorPoint = Vector2.new(
        0,
        1
    ),

    Position = UDim2.new(
        0,
        14,
        1,
        -14
    ),

    Size = UDim2.new(
        1,
        -28,
        0,
        52
    ),

    BackgroundColor3 = Color3.fromRGB(
        13,
        14,
        20
    ),

    BackgroundTransparency = 0.08,

    BorderSizePixel = 0,

    ZIndex = 52
}, Main)

AddCorner(ControlBar, 14)
AddStroke(ControlBar, 0.64)

local AimButton = New("TextButton", {
    Position = UDim2.fromOffset(
        6,
        6
    ),

    Size = UDim2.new(
        0.67,
        -9,
        1,
        -12
    ),

    BackgroundColor3 = Theme.Card,
    BackgroundTransparency = 0.06,

    BorderSizePixel = 0,

    Text = "AIM : OFF",
    TextColor3 = Theme.Text,
    TextSize = 10,

    Font = Enum.Font.GothamBold,
    AutoButtonColor = false,

    ZIndex = 53
}, ControlBar)

AddCorner(AimButton, 11)

local NextButton = New("TextButton", {
    AnchorPoint = Vector2.new(
        1,
        0
    ),

    Position = UDim2.new(
        1,
        -6,
        0,
        6
    ),

    Size = UDim2.new(
        0.33,
        -3,
        1,
        -12
    ),

    BackgroundColor3 = Theme.Card,
    BackgroundTransparency = 0.06,

    BorderSizePixel = 0,

    Text = "NEXT",
    TextColor3 = Theme.Secondary,
    TextSize = 9,

    Font = Enum.Font.GothamBold,
    AutoButtonColor = false,

    ZIndex = 53
}, ControlBar)

AddCorner(NextButton, 11)

local function RefreshAimButton()
    if
        Settings.Aim.Active
        and Settings.Aim.Enabled
    then
        AimButton.Text = "AIM : ON"

        Tween(AimButton, {
            BackgroundColor3 = Theme.Accent,
            TextColor3 = Theme.Text
        })
    else
        AimButton.Text = "AIM : OFF"

        Tween(AimButton, {
            BackgroundColor3 = Theme.Card,
            TextColor3 = Theme.Text
        })
    end
end

AimButton.Activated:Connect(function()
    if not Settings.Aim.Enabled then
        return
    end

    Settings.Aim.Active =
        not Settings.Aim.Active

    if Settings.Aim.Active then
        CurrentTarget =
            FindBestTarget()
    else
        CurrentTarget = nil
    end

    RefreshAimButton()
end)

NextButton.Activated:Connect(function()
    SwitchTarget()
end)

--==============================================================
-- HIDE / OPEN
--==============================================================

HideButton.Activated:Connect(function()
    Main.Visible = false
    OpenButton.Visible = true
end)

OpenButton.Activated:Connect(function()
    Main.Visible = true
    OpenButton.Visible = false
end)

--==============================================================
-- MOBILE DRAG
--==============================================================

local Dragging = false
local DragStart = nil
local StartPosition = nil
local DragInput = nil

Header.InputBegan:Connect(function(input)
    if
        input.UserInputType
        == Enum.UserInputType.Touch

        or

        input.UserInputType
        == Enum.UserInputType.MouseButton1
    then
        Dragging = true
        DragInput = input
        DragStart = input.Position
        StartPosition = Main.Position
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if not Dragging then
        return
    end

    if
        input == DragInput

        or

        input.UserInputType
        == Enum.UserInputType.MouseMovement
    then
        local delta =
            input.Position
            - DragStart

        Main.Position =
            UDim2.new(
                StartPosition.X.Scale,
                StartPosition.X.Offset
                    + delta.X,

                StartPosition.Y.Scale,
                StartPosition.Y.Offset
                    + delta.Y
            )
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input == DragInput then
        Dragging = false
        DragInput = nil
    end
end)

--==============================================================
-- ESP
--==============================================================

local function RemoveESP(model)
    local data = ESPObjects[model]

    if not data then
        return
    end

    if data.Highlight then
        data.Highlight:Destroy()
    end

    if data.Billboard then
        data.Billboard:Destroy()
    end

    ESPObjects[model] = nil
end

local function CreateESP(model)
    if ESPObjects[model] then
        return
    end

    local part = GetTargetPart(model)

    if not part then
        return
    end

    local highlight = New("Highlight", {
        Name = "AimLabHighlight",

        Adornee = model,

        DepthMode =
            Enum.HighlightDepthMode.AlwaysOnTop,

        FillColor = Theme.Accent,
        OutlineColor = Theme.Accent,

        FillTransparency =
            Settings.ESP.FillTransparency,

        OutlineTransparency =
            Settings.ESP.OutlineTransparency,

        Enabled = true
    }, ESPFolder)

    local billboard = New("BillboardGui", {
        Name = "AimLabLabel",

        Adornee = part,

        AlwaysOnTop = true,
        LightInfluence = 0,

        Size = UDim2.fromOffset(
            190,
            44
        ),

        StudsOffset = Vector3.new(
            0,
            2.8,
            0
        )
    }, Gui)

    local label = New("TextLabel", {
        Size = UDim2.fromScale(
            1,
            1
        ),

        BackgroundTransparency = 1,

        Text = "",
        TextColor3 = Theme.Text,

        TextStrokeColor3 =
            Color3.new(
                0,
                0,
                0
            ),

        TextStrokeTransparency = 0.2,

        TextSize = 10,
        TextWrapped = true,

        Font = Enum.Font.GothamBold
    }, billboard)

    ESPObjects[model] = {
        Highlight = highlight,
        Billboard = billboard,
        Label = label
    }
end

local function GetESPColor(model, rainbow)
    local player =
        Players:GetPlayerFromCharacter(
            model
        )

    if not player then
        return
            Settings.ESP.Rainbow
            and rainbow
            or Theme.NPC
    end

    if
        Settings.Aim.TeamCheck
        and IsSameTeam(model)
    then
        return Theme.Ally
    end

    if Settings.ESP.Rainbow then
        return rainbow
    end

    return Theme.Enemy
end

local function UpdateESP(rainbow)
    local valid = {}

    for _, model in ipairs(TargetCache) do
        if model and model.Parent then
            local player =
                Players:GetPlayerFromCharacter(
                    model
                )

            local shouldShow = false

            if player then
                shouldShow =
                    Settings.ESP.Players
            else
                shouldShow =
                    Settings.ESP.NPCs
            end

            local humanoid =
                GetHumanoid(model)

            if
                Settings.ESP.Enabled
                and shouldShow
                and humanoid
                and humanoid.Health > 0
                and GetTargetPart(model)
            then
                valid[model] = true
                CreateESP(model)
            end
        end
    end

    for model, data in pairs(
        ESPObjects
    ) do
        if
            not Settings.ESP.Enabled
            or not valid[model]
            or not model.Parent
        then
            RemoveESP(model)
        else
            local humanoid =
                GetHumanoid(model)

            local part =
                GetTargetPart(model)

            if
                not humanoid
                or humanoid.Health <= 0
                or not part
            then
                RemoveESP(model)
            else
                local color =
                    GetESPColor(
                        model,
                        rainbow
                    )

                data.Highlight.FillColor =
                    color

                data.Highlight.OutlineColor =
                    color

                data.Highlight.FillTransparency =
                    Settings.ESP.FillTransparency

                data.Highlight.OutlineTransparency =
                    Settings.ESP.OutlineTransparency

                data.Billboard.Adornee =
                    part

                local textParts = {}

                if Settings.ESP.Names then
                    table.insert(
                        textParts,
                        model.Name
                    )
                end

                if Settings.ESP.Distance then
                    table.insert(
                        textParts,

                        tostring(
                            math.floor(
                                WorldDistance(
                                    model
                                )
                            )
                        )
                        .. " studs"
                    )
                end

                data.Label.Text =
                    table.concat(
                        textParts,
                        "  •  "
                    )

                data.Label.Visible =
                    #textParts > 0

                data.Label.TextColor3 =
                    color
            end
        end
    end
end

--==============================================================
-- TEAM CHANGES
--==============================================================

local function WatchPlayer(player)
    player:GetPropertyChangedSignal(
        "Team"
    ):Connect(function()
        CurrentTarget = nil
        CacheTimer = 999
    end)

    player:GetPropertyChangedSignal(
        "TeamColor"
    ):Connect(function()
        CurrentTarget = nil
        CacheTimer = 999
    end)

    player:GetPropertyChangedSignal(
        "Neutral"
    ):Connect(function()
        CurrentTarget = nil
        CacheTimer = 999
    end)
end

for _, player in ipairs(
    Players:GetPlayers()
) do
    WatchPlayer(player)
end

Players.PlayerAdded:Connect(function(player)
    WatchPlayer(player)
    CacheTimer = 999
end)

Players.PlayerRemoving:Connect(function()
    CacheTimer = 999
end)

LocalPlayer.CharacterAdded:Connect(function()
    CurrentTarget = nil
    Settings.Aim.Active = false

    task.wait(0.5)

    RefreshAimButton()

    CacheTimer = 999
end)

--==============================================================
-- MAIN LOOP
--==============================================================

RefreshTargets()
RefreshAimButton()

RunService:BindToRenderStep(
    "AimLabMobile_Render",

    Enum.RenderPriority.Camera.Value + 1,

    function(deltaTime)
        Camera = workspace.CurrentCamera

        if not Camera then
            return
        end

        CacheTimer += deltaTime
        ESPTimer += deltaTime
        ReacquireTimer += deltaTime

        if CacheTimer >= 1.0 then
            CacheTimer = 0
            RefreshTargets()
        end

        local hue =
            (
                time()
                * Settings.ESP.RainbowSpeed
            )
            % 1

        local rainbow =
            Color3.fromHSV(
                hue,
                0.90,
                1
            )

        FOVCircle.Visible =
            Settings.Aim.Enabled
            and Settings.Aim.ShowFOV

        FOVCircle.Size =
            UDim2.fromOffset(
                Settings.Aim.FOV * 2,
                Settings.Aim.FOV * 2
            )

        FOVStroke.Color =
            Settings.ESP.Rainbow
            and rainbow
            or Theme.Accent

        if
            ESPTimer
            >= Settings.ESP.UpdateRate
        then
            ESPTimer = 0
            UpdateESP(rainbow)
        end

        if
            not Settings.Aim.Enabled
            or not Settings.Aim.Active
        then
            return
        end

        if Settings.Aim.TargetLock then
            if not TargetValid(
                CurrentTarget
            ) then
                if
                    ReacquireTimer
                    >= Settings.Aim.ReacquireRate
                then
                    ReacquireTimer = 0

                    CurrentTarget =
                        FindBestTarget()
                end
            end
        else
            if
                ReacquireTimer
                >= Settings.Aim.ReacquireRate
            then
                ReacquireTimer = 0

                CurrentTarget =
                    FindBestTarget()
            end
        end

        if CurrentTarget then
            AimAt(
                CurrentTarget,
                deltaTime
            )
        end
    end
)

print("======================================")
print(" AIM LAB MOBILE")
print(" Natural Team Check + RGB ESP")
print("======================================")
print("Loaded successfully.")

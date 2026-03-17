--[[
    ╔══════════════════════════════════════════════╗
    ║   MM2 Auto Farm Coin Script v5.0             ║
    ║   Game: Murder Mystery 2 (Roblox)            ║
    ║   Phương pháp: Bay đến coin (RenderStepped)  ║
    ╚══════════════════════════════════════════════╝
    
    Cấu trúc game MM2:
    game.Workspace
    └── [MapName]
        └── CoinContainer
            ├── Coin_Server → CoinVisual
            └── ...
    
    Player bay mượt đến coin bằng CFrame Lerp + RenderStepped.
    Tắt trọng lực bằng BodyVelocity.
    Noclip giúp bay xuyên tường đến coin.
]]

-- ═══════════════════════════════════════════
-- CẤU HÌNH
-- ═══════════════════════════════════════════
local Config = {
    FarmEnabled       = false,
    
    -- Tốc độ bay (LOCKED = 25 studs/giây)
    FlySpeed          = 25,           -- Tốc độ bay cố định 25 studs/giây
    
    -- Delays
    CoinDelay         = 1            -- Delay sau khi nhặt mỗi coin (đợi 2s trước khi tele tiếp)
    SweepDelay        = 1.5,          -- Delay sau mỗi lượt quét
    ReScanDelay       = 2,            -- Delay khi không tìm thấy coin
    
    -- Noclip (bay xuyên tường)
    Noclip            = true,         -- Bật noclip khi farm
    
    AntiAFK           = true,
    ShowNotifications = true,
}

-- ═══════════════════════════════════════════
-- SERVICES
-- ═══════════════════════════════════════════
local Players           = game:GetService("Players")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")
local VirtualUser       = game:GetService("VirtualUser")
local StarterGui        = game:GetService("StarterGui")
local UserInputService  = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local Camera      = Workspace.CurrentCamera

-- ═══════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════
local totalCoinsCollected = 0
local currentMapName      = nil
local isRunning           = false
local noclipConnection    = nil

-- ═══════════════════════════════════════════
-- UTILITIES
-- ═══════════════════════════════════════════

local function Notify(title, text, duration)
    if not Config.ShowNotifications then return end
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = duration or 3,
        })
    end)
end

local function GetRoot()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function GetHumanoid()
    local char = LocalPlayer.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

-- ═══════════════════════════════════════════
-- NOCLIP (bay xuyên tường)
-- ═══════════════════════════════════════════

local function EnableNoclip()
    if noclipConnection then return end
    noclipConnection = RunService.Stepped:Connect(function()
        pcall(function()
            local char = LocalPlayer.Character
            if not char then return end
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = false
                end
            end
        end)
    end)
end

local function DisableNoclip()
    if noclipConnection then
        noclipConnection:Disconnect()
        noclipConnection = nil
    end
    -- Khôi phục collision
    pcall(function()
        local char = LocalPlayer.Character
        if not char then return end
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                part.CanCollide = true
            end
        end
    end)
end

-- ═══════════════════════════════════════════
-- TELEPORT TO COIN (Dịch chuyển tức thời)
-- ═══════════════════════════════════════════

local function TeleportToCoin(targetPosition)
    local root = GetRoot()
    if not root then return false end
    
    -- Teleport tức thời đến vị trí coin
    -- Dùng CFrame + nhích lên 1 chút xíu trục Y để chống kẹt mặt đất
    root.CFrame = CFrame.new(targetPosition + Vector3.new(0, 1, 0))
    
    return true
end

--- Touch coin để thu thập
local function TouchCoin(coinPart)
    local root = GetRoot()
    if not root or not coinPart then return end
    pcall(function()
        if firetouchinterest then
            firetouchinterest(root, coinPart, 0)
            task.wait()
            firetouchinterest(root, coinPart, 1)
        end
    end)
end

-- ═══════════════════════════════════════════
-- MAP DETECTION
-- ═══════════════════════════════════════════

local function FindCurrentMap()
    for _, child in ipairs(Workspace:GetChildren()) do
        if child:IsA("Model") or child:IsA("Folder") then
            local coinContainer = child:FindFirstChild("CoinContainer")
            if coinContainer then
                return child, coinContainer
            end
        end
    end
    
    for _, child in ipairs(Workspace:GetChildren()) do
        if child:IsA("Model") or child:IsA("Folder") then
            for _, grandchild in ipairs(child:GetChildren()) do
                if grandchild.Name == "CoinContainer" then
                    return child, grandchild
                end
            end
        end
    end
    
    return nil, nil
end

-- ═══════════════════════════════════════════
-- COIN DETECTION
-- ═══════════════════════════════════════════

local function GetCoins(coinContainer)
    if not coinContainer then return {} end
    
    local coins = {}
    
    for _, coinObj in ipairs(coinContainer:GetChildren()) do
        if coinObj.Name == "Coin_Server" or coinObj.Name:find("Coin") then
            local coinVisual = coinObj:FindFirstChild("CoinVisual")
            if coinVisual and coinVisual:IsA("BasePart") then
                table.insert(coins, {
                    Visual = coinVisual,
                    Position = coinVisual.Position,
                })
            else
                local part = coinObj:FindFirstChildWhichIsA("BasePart")
                if part then
                    table.insert(coins, {
                        Visual = part,
                        Position = part.Position,
                    })
                elseif coinObj:IsA("BasePart") then
                    table.insert(coins, {
                        Visual = coinObj,
                        Position = coinObj.Position,
                    })
                end
            end
        elseif coinObj:IsA("BasePart") then
            table.insert(coins, {
                Visual = coinObj,
                Position = coinObj.Position,
            })
        end
    end
    
    return coins
end

local function SortByDistance(coins)
    local root = GetRoot()
    if not root then return coins end
    
    local rootPos = root.Position
    table.sort(coins, function(a, b)
        return (a.Position - rootPos).Magnitude < (b.Position - rootPos).Magnitude
    end)
    return coins
end

-- ═══════════════════════════════════════════
-- MAIN FARM LOOP
-- Player BAY đến từng coin, dừng lại nhặt
-- ═══════════════════════════════════════════

local function FarmLoop()
    if isRunning then return end
    isRunning = true
    
    -- Bật noclip
    if Config.Noclip then
        EnableNoclip()
    end
    
    Notify("🪙 Auto Farm", "Đang bay đến coins...")
    
    spawn(function()
        while Config.FarmEnabled and isRunning do
            local success, err = pcall(function()
                if not GetRoot() then
                    if LocalPlayer.Character then
                        task.wait(1)
                    else
                        LocalPlayer.CharacterAdded:Wait()
                        task.wait(2)
                        if Config.Noclip then EnableNoclip() end
                    end
                    return
                end
                
                local mapModel, coinContainer = FindCurrentMap()
                
                if not mapModel or not coinContainer then
                    task.wait(Config.ReScanDelay)
                    return
                end
                
                if mapModel.Name ~= currentMapName then
                    currentMapName = mapModel.Name
                    Notify("🗺️ Map", currentMapName)
                end
                
                local coins = GetCoins(coinContainer)
                
                if #coins == 0 then
                    task.wait(Config.ReScanDelay)
                    return
                end
                
                coins = SortByDistance(coins)
                
                for _, coinData in ipairs(coins) do
                    if not Config.FarmEnabled or not isRunning then break end
                    
                    if coinData.Visual and coinData.Visual.Parent then
                        -- Teleport đến coin
                        local reached = TeleportToCoin(coinData.Position)
                        
                        if reached then
                            TouchCoin(coinData.Visual)
                            totalCoinsCollected = totalCoinsCollected + 1
                        end
                        
                        task.wait(Config.CoinDelay)
                    end
                end
                
                task.wait(Config.SweepDelay)
            end)
            
            if not success then
                warn("[MM2 AutoFarm] Error: " .. tostring(err))
            end
            
            task.wait(0.3)
        end
        
        -- Tắt noclip khi dừng
        DisableNoclip()
        isRunning = false
    end)
end

local function StopFarm()
    Config.FarmEnabled = false
    isRunning = false
    DisableNoclip()
    Notify("⛔ Dừng Farm", "Tổng coins: " .. totalCoinsCollected)
end

-- ═══════════════════════════════════════════
-- ANTI-AFK
-- ═══════════════════════════════════════════
local function SetupAntiAFK()
    if not Config.AntiAFK then return end
    LocalPlayer.Idled:Connect(function()
        VirtualUser:Button2Down(Vector2.new(0, 0), Camera.CFrame)
        task.wait(1)
        VirtualUser:Button2Up(Vector2.new(0, 0), Camera.CFrame)
    end)
end

-- ═══════════════════════════════════════════
-- UI
-- ═══════════════════════════════════════════
local function CreateUI()
    pcall(function()
        local old = LocalPlayer.PlayerGui:FindFirstChild("MM2FarmUI")
        if old then old:Destroy() end
    end)
    
    local gui = Instance.new("ScreenGui")
    gui.Name = "MM2FarmUI"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    
    pcall(function()
        if syn and syn.protect_gui then syn.protect_gui(gui) end
    end)
    
    -- Main Frame
    local frame = Instance.new("Frame")
    frame.Name = "Main"
    frame.Size = UDim2.new(0, 240, 0, 195)
    frame.Position = UDim2.new(0, 10, 0.5, -97)
    frame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    frame.BackgroundTransparency = 0.05
    frame.BorderSizePixel = 0
    frame.Parent = gui
    
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)
    
    local stroke = Instance.new("UIStroke", frame)
    stroke.Color = Color3.fromRGB(255, 200, 50)
    stroke.Thickness = 2
    stroke.Transparency = 0.3
    
    -- Title Bar
    local titleBar = Instance.new("Frame")
    titleBar.Name = "TitleBar"
    titleBar.Size = UDim2.new(1, 0, 0, 36)
    titleBar.BackgroundColor3 = Color3.fromRGB(255, 200, 50)
    titleBar.BorderSizePixel = 0
    titleBar.Parent = frame
    
    Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 12)
    
    local titleFix = Instance.new("Frame")
    titleFix.Size = UDim2.new(1, 0, 0, 14)
    titleFix.Position = UDim2.new(0, 0, 1, -14)
    titleFix.BackgroundColor3 = Color3.fromRGB(255, 200, 50)
    titleFix.BorderSizePixel = 0
    titleFix.Parent = titleBar
    
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, 0, 1, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "🪙 MM2 Auto Farm v5"
    titleLabel.TextColor3 = Color3.fromRGB(20, 20, 30)
    titleLabel.TextSize = 15
    titleLabel.Font = Enum.Font.GothamBlack
    titleLabel.Parent = titleBar
    
    -- Toggle Farm Button
    local toggleBtn = Instance.new("TextButton")
    toggleBtn.Name = "ToggleFarm"
    toggleBtn.Size = UDim2.new(0.88, 0, 0, 36)
    toggleBtn.Position = UDim2.new(0.06, 0, 0, 46)
    toggleBtn.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
    toggleBtn.BorderSizePixel = 0
    toggleBtn.Text = "▶  BẮT ĐẦU FARM"
    toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggleBtn.TextSize = 14
    toggleBtn.Font = Enum.Font.GothamBold
    toggleBtn.Parent = frame
    Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 8)
    
    -- Noclip Toggle
    local noclipBtn = Instance.new("TextButton")
    noclipBtn.Name = "NoclipBtn"
    noclipBtn.Size = UDim2.new(0.88, 0, 0, 26)
    noclipBtn.Position = UDim2.new(0.06, 0, 0, 90)
    noclipBtn.BackgroundColor3 = Config.Noclip and Color3.fromRGB(52, 152, 219) or Color3.fromRGB(80, 80, 90)
    noclipBtn.BorderSizePixel = 0
    noclipBtn.Text = "👻 Noclip: " .. (Config.Noclip and "ON" or "OFF")
    noclipBtn.TextColor3 = Color3.fromRGB(220, 220, 220)
    noclipBtn.TextSize = 11
    noclipBtn.Font = Enum.Font.GothamSemibold
    noclipBtn.Parent = frame
    Instance.new("UICorner", noclipBtn).CornerRadius = UDim.new(0, 8)
    
    -- Info Labels
    local mapLabel = Instance.new("TextLabel")
    mapLabel.Name = "MapLabel"
    mapLabel.Size = UDim2.new(0.88, 0, 0, 20)
    mapLabel.Position = UDim2.new(0.06, 0, 0, 124)
    mapLabel.BackgroundTransparency = 1
    mapLabel.Text = "🗺️ Map: Đang tìm..."
    mapLabel.TextColor3 = Color3.fromRGB(180, 180, 190)
    mapLabel.TextSize = 11
    mapLabel.Font = Enum.Font.Gotham
    mapLabel.TextXAlignment = Enum.TextXAlignment.Left
    mapLabel.Parent = frame
    
    local statusLabel = Instance.new("TextLabel")
    statusLabel.Name = "StatusLabel"
    statusLabel.Size = UDim2.new(0.88, 0, 0, 20)
    statusLabel.Position = UDim2.new(0.06, 0, 0, 144)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = "⏸️ Chờ bật..."
    statusLabel.TextColor3 = Color3.fromRGB(180, 180, 190)
    statusLabel.TextSize = 11
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.Parent = frame
    
    local coinLabel = Instance.new("TextLabel")
    coinLabel.Name = "CoinLabel"
    coinLabel.Size = UDim2.new(0.88, 0, 0, 22)
    coinLabel.Position = UDim2.new(0.06, 0, 0, 166)
    coinLabel.BackgroundTransparency = 1
    coinLabel.Text = "🪙 Coins: 0"
    coinLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
    coinLabel.TextSize = 13
    coinLabel.Font = Enum.Font.GothamBold
    coinLabel.TextXAlignment = Enum.TextXAlignment.Left
    coinLabel.Parent = frame
    
    -- Draggable
    local dragging, dragInput, dragStart, startPos
    
    titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or
           input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    
    titleBar.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or
           input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
    
    -- Button Events
    toggleBtn.MouseButton1Click:Connect(function()
        if isRunning then
            StopFarm()
            toggleBtn.Text = "▶  BẮT ĐẦU FARM"
            toggleBtn.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
        else
            Config.FarmEnabled = true
            FarmLoop()
            toggleBtn.Text = "⏹  DỪNG FARM"
            toggleBtn.BackgroundColor3 = Color3.fromRGB(231, 76, 60)
        end
    end)
    
    noclipBtn.MouseButton1Click:Connect(function()
        Config.Noclip = not Config.Noclip
        noclipBtn.Text = "👻 Noclip: " .. (Config.Noclip and "ON" or "OFF")
        noclipBtn.BackgroundColor3 = Config.Noclip and Color3.fromRGB(52, 152, 219) or Color3.fromRGB(80, 80, 90)
        if Config.Noclip and isRunning then
            EnableNoclip()
        else
            DisableNoclip()
        end
    end)
    
    -- Update Loop
    spawn(function()
        while task.wait(0.5) do
            pcall(function()
                coinLabel.Text = "🪙 Coins: " .. totalCoinsCollected
                
                local mapModel, coinContainer = FindCurrentMap()
                if mapModel then
                    mapLabel.Text = "🗺️ Map: " .. mapModel.Name
                    if isRunning then
                        local coins = GetCoins(coinContainer)
                        statusLabel.Text = "⚡ Teleport farm... (" .. #coins .. " coins)"
                    end
                else
                    mapLabel.Text = "🗺️ Lobby / Chờ round..."
                    if isRunning then
                        statusLabel.Text = "⏳ Đợi round mới..."
                    end
                end
                
                if not isRunning then
                    statusLabel.Text = "⏸️ Chờ bật..."
                end
            end)
        end
    end)
    
    gui.Parent = LocalPlayer.PlayerGui
end

-- ═══════════════════════════════════════════
-- ROUND DETECTION
-- ═══════════════════════════════════════════
local function WatchForNewMaps()
    Workspace.ChildAdded:Connect(function(child)
        task.wait(0.5)
        if child:IsA("Model") or child:IsA("Folder") then
            local cc = child:FindFirstChild("CoinContainer")
            if cc then
                currentMapName = child.Name
                Notify("🗺️ Round Mới", "Map: " .. child.Name)
            end
        end
    end)
end

-- ═══════════════════════════════════════════
-- INIT
-- ═══════════════════════════════════════════
local function Init()
    print("══════════════════════════════════════════")
    print("  MM2 Auto Farm Coin v6.0")
    print("  Phương pháp: Teleport cực nhanh")
    print("  Dịch chuyển tức thời đến coin")
    print("══════════════════════════════════════════")
    
    if not game:IsLoaded() then
        game.Loaded:Wait()
    end
    task.wait(2)
    
    if not LocalPlayer.Character then
        LocalPlayer.CharacterAdded:Wait()
    end
    task.wait(1)
    
    SetupAntiAFK()
    WatchForNewMaps()
    CreateUI()
    
    local mapModel = FindCurrentMap()
    if mapModel then
        currentMapName = mapModel.Name
        Notify("✅ Loaded", "Map: " .. mapModel.Name .. "\nBấm nút để farm!")
    else
        Notify("✅ Loaded", "Đang đợi round...")
    end
end

Init()

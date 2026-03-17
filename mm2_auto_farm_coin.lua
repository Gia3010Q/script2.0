--[[
    ╔══════════════════════════════════════════════╗
    ║   MM2 Auto Farm Coin Script                  ║
    ║   Game: Murder Mystery 2 (Roblox)            ║
    ║   Cấu trúc: Workspace → Map → CoinContainer ║
    ╚══════════════════════════════════════════════╝
    
    Cấu trúc game MM2:
    game.Workspace
    └── [MapName]                  -- Map được load mỗi round
        └── CoinContainer          -- Folder chứa coins
            ├── Coin_Server        -- Mỗi coin instance
            │   └── CoinVisual     -- Part hiển thị (dùng để teleport)
            ├── Coin_Server
            │   └── CoinVisual
            └── ...
]]

-- ═══════════════════════════════════════════
-- CẤU HÌNH
-- ═══════════════════════════════════════════
local Config = {
    -- Farm
    FarmEnabled       = false,        -- Bắt đầu tắt, bấm nút UI để bật
    FarmDelay         = 0.05,         -- Delay giữa mỗi lần teleport coin (giây)
    ReScanDelay       = 1,            -- Delay khi không tìm thấy coin (chờ spawn)
    TeleportYOffset   = 2,            -- Offset Y khi teleport (tránh kẹt dưới đất)
    
    -- Safe Mode (Tween teleport mượt thay vì instant)
    SafeMode          = false,        -- true = tween, false = instant teleport
    TweenSpeed        = 0.08,         -- Thời gian tween (giây), chỉ khi SafeMode = true
    
    -- Anti-AFK
    AntiAFK           = true,         -- Chống bị kick AFK
    
    -- UI
    ShowNotifications = true,         -- Hiển thị thông báo game
}

-- ═══════════════════════════════════════════
-- SERVICES
-- ═══════════════════════════════════════════
local Players           = game:GetService("Players")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
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

-- ═══════════════════════════════════════════
-- UTILITIES
-- ═══════════════════════════════════════════

--- Gửi notification trong game
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

--- Lấy HumanoidRootPart
local function GetRoot()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

--- Lấy Humanoid
local function GetHumanoid()
    local char = LocalPlayer.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

--- Teleport đến vị trí (hỗ trợ SafeMode)
local function TeleportTo(targetCFrame)
    local root = GetRoot()
    if not root then return false end
    
    if Config.SafeMode then
        local tween = TweenService:Create(root, TweenInfo.new(Config.TweenSpeed, Enum.EasingStyle.Linear), {
            CFrame = targetCFrame
        })
        tween:Play()
        tween.Completed:Wait()
    else
        root.CFrame = targetCFrame
    end
    return true
end

--- Fire touch interest để trigger thu thập coin
local function TouchPart(part)
    local root = GetRoot()
    if not root or not part then return end
    pcall(function()
        if firetouchinterest then
            firetouchinterest(root, part, 0) -- Touch bắt đầu
            task.wait()
            firetouchinterest(root, part, 1) -- Touch kết thúc
        end
    end)
end

-- ═══════════════════════════════════════════
-- MAP DETECTION
-- Tìm map hiện tại trong Workspace bằng cách
-- tìm child nào có "CoinContainer" bên trong
-- ═══════════════════════════════════════════

--- Tìm map hiện tại đang active trong Workspace
local function FindCurrentMap()
    for _, child in ipairs(Workspace:GetChildren()) do
        -- Map là một Model hoặc Folder chứa CoinContainer
        if (child:IsA("Model") or child:IsA("Folder")) then
            local coinContainer = child:FindFirstChild("CoinContainer")
            if coinContainer then
                return child, coinContainer
            end
        end
    end
    
    -- Fallback: tìm sâu hơn trong Workspace
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
-- Lấy tất cả coins từ CoinContainer
-- Cấu trúc: CoinContainer → Coin_Server → CoinVisual
-- ═══════════════════════════════════════════

--- Lấy danh sách tất cả coins có thể collect
local function GetCoins(coinContainer)
    if not coinContainer then return {} end
    
    local coins = {}
    
    for _, coinObj in ipairs(coinContainer:GetChildren()) do
        -- Mỗi coin thường là "Coin_Server" chứa "CoinVisual"
        if coinObj.Name == "Coin_Server" or coinObj.Name:find("Coin") then
            -- Tìm CoinVisual bên trong (part mà player cần chạm)
            local coinVisual = coinObj:FindFirstChild("CoinVisual")
            if coinVisual and coinVisual:IsA("BasePart") then
                table.insert(coins, {
                    Object = coinObj,
                    Visual = coinVisual,
                    Position = coinVisual.Position,
                })
            else
                -- Fallback: nếu không có CoinVisual, tìm BasePart đầu tiên
                local part = coinObj:FindFirstChildWhichIsA("BasePart")
                if part then
                    table.insert(coins, {
                        Object = coinObj,
                        Visual = part,
                        Position = part.Position,
                    })
                elseif coinObj:IsA("BasePart") then
                    -- Coin chính là BasePart
                    table.insert(coins, {
                        Object = coinObj,
                        Visual = coinObj,
                        Position = coinObj.Position,
                    })
                end
            end
        elseif coinObj:IsA("BasePart") then
            -- Trường hợp coin là BasePart trực tiếp trong CoinContainer
            table.insert(coins, {
                Object = coinObj,
                Visual = coinObj,
                Position = coinObj.Position,
            })
        end
    end
    
    return coins
end

--- Sắp xếp coins theo khoảng cách gần nhất so với player
local function SortCoinsByDistance(coins)
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
-- ═══════════════════════════════════════════

local function FarmLoop()
    if isRunning then return end
    isRunning = true
    
    Notify("🪙 MM2 Auto Farm", "Bắt đầu farm coin...")
    
    spawn(function()
        while Config.FarmEnabled and isRunning do
            local success, err = pcall(function()
                -- 1) Đợi character tồn tại
                if not GetRoot() then
                    if LocalPlayer.Character then
                        task.wait(1)
                    else
                        LocalPlayer.CharacterAdded:Wait()
                        task.wait(2) -- đợi character load đầy đủ
                    end
                    return -- retry vòng lặp tiếp
                end
                
                -- 2) Tìm map hiện tại
                local mapModel, coinContainer = FindCurrentMap()
                
                if not mapModel or not coinContainer then
                    -- Chưa có map (đang lobby/intermission) → chờ
                    task.wait(Config.ReScanDelay)
                    return
                end
                
                -- Cập nhật tên map nếu đổi
                if mapModel.Name ~= currentMapName then
                    currentMapName = mapModel.Name
                    Notify("🗺️ Map", "Đã detect map: " .. currentMapName)
                end
                
                -- 3) Lấy tất cả coins trong CoinContainer
                local coins = GetCoins(coinContainer)
                
                if #coins == 0 then
                    -- Không còn coin → chờ spawn mới
                    task.wait(Config.ReScanDelay)
                    return
                end
                
                -- 4) Sắp xếp theo khoảng cách gần nhất
                coins = SortCoinsByDistance(coins)
                
                -- 5) Teleport đến từng coin
                for _, coinData in ipairs(coins) do
                    if not Config.FarmEnabled or not isRunning then break end
                    
                    -- Kiểm tra coin vẫn tồn tại (chưa bị collect)
                    if coinData.Visual and coinData.Visual.Parent then
                        local targetPos = coinData.Position
                        local targetCFrame = CFrame.new(
                            targetPos.X,
                            targetPos.Y + Config.TeleportYOffset,
                            targetPos.Z
                        )
                        
                        -- Teleport đến coin
                        local moved = TeleportTo(targetCFrame)
                        
                        if moved then
                            -- Trigger touch để thu thập
                            TouchPart(coinData.Visual)
                            
                            -- Thử touch cả Object cha nếu khác Visual
                            if coinData.Object ~= coinData.Visual and coinData.Object:IsA("BasePart") then
                                TouchPart(coinData.Object)
                            end
                            
                            totalCoinsCollected = totalCoinsCollected + 1
                        end
                        
                        task.wait(Config.FarmDelay)
                    end
                end
            end)
            
            if not success then
                warn("[MM2 AutoFarm] Error: " .. tostring(err))
            end
            
            task.wait(Config.FarmDelay)
        end
        
        isRunning = false
    end)
end

local function StopFarm()
    Config.FarmEnabled = false
    isRunning = false
    Notify("⛔ MM2 Auto Farm", "Đã dừng. Tổng coins: " .. totalCoinsCollected)
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
    -- Xóa UI cũ
    pcall(function()
        local old = LocalPlayer.PlayerGui:FindFirstChild("MM2FarmUI")
        if old then old:Destroy() end
    end)
    
    local gui = Instance.new("ScreenGui")
    gui.Name = "MM2FarmUI"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    
    -- Protect GUI khỏi bị xóa
    pcall(function()
        if syn and syn.protect_gui then syn.protect_gui(gui) end
    end)
    
    -- ── Main Frame ──
    local frame = Instance.new("Frame")
    frame.Name = "Main"
    frame.Size = UDim2.new(0, 230, 0, 200)
    frame.Position = UDim2.new(0, 10, 0.5, -100)
    frame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    frame.BackgroundTransparency = 0.05
    frame.BorderSizePixel = 0
    frame.Parent = gui
    
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)
    
    local stroke = Instance.new("UIStroke", frame)
    stroke.Color = Color3.fromRGB(255, 200, 50)
    stroke.Thickness = 2
    stroke.Transparency = 0.3
    
    -- ── Title Bar ──
    local titleBar = Instance.new("Frame")
    titleBar.Name = "TitleBar"
    titleBar.Size = UDim2.new(1, 0, 0, 36)
    titleBar.BackgroundColor3 = Color3.fromRGB(255, 200, 50)
    titleBar.BorderSizePixel = 0
    titleBar.Parent = frame
    
    Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 12)
    
    -- Fix bo tròn phía dưới title
    local titleFix = Instance.new("Frame")
    titleFix.Size = UDim2.new(1, 0, 0, 14)
    titleFix.Position = UDim2.new(0, 0, 1, -14)
    titleFix.BackgroundColor3 = Color3.fromRGB(255, 200, 50)
    titleFix.BorderSizePixel = 0
    titleFix.Parent = titleBar
    
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, 0, 1, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "🪙 MM2 Auto Farm"
    titleLabel.TextColor3 = Color3.fromRGB(20, 20, 30)
    titleLabel.TextSize = 15
    titleLabel.Font = Enum.Font.GothamBlack
    titleLabel.Parent = titleBar
    
    -- ── Toggle Farm Button ──
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
    
    -- ── Safe Mode Button ──
    local safeBtn = Instance.new("TextButton")
    safeBtn.Name = "SafeMode"
    safeBtn.Size = UDim2.new(0.88, 0, 0, 30)
    safeBtn.Position = UDim2.new(0.06, 0, 0, 90)
    safeBtn.BackgroundColor3 = Config.SafeMode and Color3.fromRGB(52, 152, 219) or Color3.fromRGB(80, 80, 90)
    safeBtn.BorderSizePixel = 0
    safeBtn.Text = "🛡️ Safe Mode: " .. (Config.SafeMode and "ON" or "OFF")
    safeBtn.TextColor3 = Color3.fromRGB(220, 220, 220)
    safeBtn.TextSize = 12
    safeBtn.Font = Enum.Font.GothamSemibold
    safeBtn.Parent = frame
    Instance.new("UICorner", safeBtn).CornerRadius = UDim.new(0, 8)
    
    -- ── Info Labels ──
    local mapLabel = Instance.new("TextLabel")
    mapLabel.Name = "MapLabel"
    mapLabel.Size = UDim2.new(0.88, 0, 0, 20)
    mapLabel.Position = UDim2.new(0.06, 0, 0, 130)
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
    statusLabel.Position = UDim2.new(0.06, 0, 0, 150)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = "⏸️ Trạng thái: Chờ bật..."
    statusLabel.TextColor3 = Color3.fromRGB(180, 180, 190)
    statusLabel.TextSize = 11
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.Parent = frame
    
    local coinLabel = Instance.new("TextLabel")
    coinLabel.Name = "CoinLabel"
    coinLabel.Size = UDim2.new(0.88, 0, 0, 22)
    coinLabel.Position = UDim2.new(0.06, 0, 0, 172)
    coinLabel.BackgroundTransparency = 1
    coinLabel.Text = "🪙 Coins: 0"
    coinLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
    coinLabel.TextSize = 13
    coinLabel.Font = Enum.Font.GothamBold
    coinLabel.TextXAlignment = Enum.TextXAlignment.Left
    coinLabel.Parent = frame
    
    -- ── Draggable ──
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
    
    -- ── Button Events ──
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
    
    safeBtn.MouseButton1Click:Connect(function()
        Config.SafeMode = not Config.SafeMode
        safeBtn.Text = "🛡️ Safe Mode: " .. (Config.SafeMode and "ON" or "OFF")
        safeBtn.BackgroundColor3 = Config.SafeMode and Color3.fromRGB(52, 152, 219) or Color3.fromRGB(80, 80, 90)
        Notify("🛡️ Safe Mode", Config.SafeMode and "Bật - Tween teleport" or "Tắt - Instant teleport")
    end)
    
    -- ── Update Loop (cập nhật UI) ──
    spawn(function()
        while task.wait(0.5) do
            pcall(function()
                -- Cập nhật coin counter
                coinLabel.Text = "🪙 Coins: " .. totalCoinsCollected
                
                -- Cập nhật map name
                local mapModel, coinContainer = FindCurrentMap()
                if mapModel then
                    mapLabel.Text = "🗺️ Map: " .. mapModel.Name
                    
                    if isRunning then
                        local coins = GetCoins(coinContainer)
                        statusLabel.Text = "🔄 Farming... (" .. #coins .. " coins trên map)"
                    end
                else
                    mapLabel.Text = "🗺️ Map: Lobby / Chờ round..."
                    if isRunning then
                        statusLabel.Text = "⏳ Đợi round mới..."
                    end
                end
                
                if not isRunning then
                    statusLabel.Text = "⏸️ Trạng thái: Chờ bật..."
                end
            end)
        end
    end)
    
    gui.Parent = LocalPlayer.PlayerGui
end

-- ═══════════════════════════════════════════
-- ROUND DETECTION
-- Tự động re-detect khi map thay đổi
-- ═══════════════════════════════════════════
local function WatchForNewMaps()
    Workspace.ChildAdded:Connect(function(child)
        task.wait(0.5) -- đợi map load xong
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
-- INITIALIZATION
-- ═══════════════════════════════════════════
local function Init()
    print("══════════════════════════════════════════")
    print("  MM2 Auto Farm Coin - v2.0 Loaded!")
    print("  Cấu trúc: Workspace → Map → CoinContainer")
    print("══════════════════════════════════════════")
    
    -- Đợi game load
    if not game:IsLoaded() then
        game.Loaded:Wait()
    end
    task.wait(2)
    
    -- Đợi character
    if not LocalPlayer.Character then
        LocalPlayer.CharacterAdded:Wait()
    end
    task.wait(1)
    
    -- Khởi tạo
    SetupAntiAFK()
    WatchForNewMaps()
    CreateUI()
    
    -- Thông báo map hiện tại nếu có
    local mapModel = FindCurrentMap()
    if mapModel then
        currentMapName = mapModel.Name
        Notify("✅ Loaded", "Map hiện tại: " .. mapModel.Name .. "\nBấm nút để farm!")
    else
        Notify("✅ Loaded", "Đang đợi round...\nBấm nút để farm khi vào round!")
    end
end

Init()

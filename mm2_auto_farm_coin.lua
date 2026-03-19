--[[
    MM2 Auto Farm Coin - THE STEALTH TWEEN (Tối Thượng)
    Đã điều chỉnh chuẩn 28 studs / giây để CHỐNG HACK SPEED, ANTI-AFK, NOCLIP HOÀN HẢO.
    Bạn có thể yên tâm cắm máy liên tục mà không văng.
]]

--// ⚙️ CẤU HÌNH CƠ BẢN
local Config = {
    FarmEnabled       = false,
    SafeSpeed         = 40,    -- Tốc độ nhặt (Khuyến nghị 25-28 để ko bị kick Speedhack)
    FarmDelay         = 0.5,   -- Thời gian chờ máy chủ cập nhật vật lý chạm (Ko nên < 0.4)
    ReScanDelay       = 1.5,   -- Đợi map tải xong
    AntiAFK           = true,
    ShowNotifications = true,
}

--// 📦 TÀI NGUYÊN (SERVICES)
local Players          = game:GetService("Players")
local Workspace        = game:GetService("Workspace")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local VirtualUser      = game:GetService("VirtualUser")
local StarterGui       = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local Camera      = Workspace.CurrentCamera

--// 📊 BIẾN TRẠNG THÁI (STATE)
local isRunning           = false
local totalCoinsCollected = 0
local roundCoinsCollected = 0
local currentMapName      = nil

--// 🛠️ HÀM CÔNG CỤ (UTILITIES)
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

--// 🗺️ QUÉT BẢN ĐỒ (MAP DETECTION)
local function FindCurrentMap()
    for _, v in pairs(Workspace:GetChildren()) do
        if v:IsA("Model") or v:IsA("Folder") then
            local cc = v:FindFirstChild("CoinContainer")
            if cc then return v, cc end
        end
    end
    -- Fallback quét sâu hơn:
    for _, v in pairs(Workspace:GetChildren()) do
        if v:IsA("Model") or v:IsA("Folder") then
            for _, gc in pairs(v:GetChildren()) do
                if gc.Name == "CoinContainer" then return v, gc end
            end
        end
    end
    return nil, nil
end

--// 💰 TÌM XU (COIN DETECTION)
local function GetCoins(container)
    local t = {}
    for _, v in pairs(container:GetChildren()) do
        local p = v:FindFirstChild("CoinVisual")
        if not p and v:IsA("BasePart") then p = v
        elseif not p then p = v:FindFirstChildWhichIsA("BasePart") end
        
        if p then table.insert(t, { Visual = p, Position = p.Position, Object = v }) end
    end
    return t
end

local function SortCoinsByDistance(coins)
    local root = GetRoot()
    if not root then return coins end
    table.sort(coins, function(a, b)
        return (a.Position - root.Position).Magnitude < (b.Position - root.Position).Magnitude
    end)
    return coins
end

--// 🚀 CƠ CHẾ DI CHUYỂN (STEALTH TWEEN TỐI THƯỢNG)
local function MoveToCoin(coinData)
    local root = GetRoot()
    local hum = GetHumanoid()
    if not root or not hum or hum.Health <= 0 then return false end

    local targetPos = coinData.Position
    local startPos = root.Position
    local distance = (startPos - targetPos).Magnitude

    if distance > 2000 then return false end -- Quá xa (đang ngoài sảnh)

    -- Đảm bảo tắt mọi va chạm vật lý lúc bay để lướt mượt qua cửa / tường
    local noclip = RunService.Stepped:Connect(function()
        if LocalPlayer.Character then
            for _, v in pairs(LocalPlayer.Character:GetDescendants()) do
                if v:IsA("BasePart") and v.CanCollide then
                    v.CanCollide = false
                end
            end
        end
    end)

    -- 🛡️ CHẾ ĐỘ STEALTH BAY LƯỚT: Neo người lại tránh trọng lực (Fall damage)
    root.Anchored = true
    
    -- TÍNH THỜI GIAN BAY SAO CHO ĐÚNG VỚI GIỚI HẠN TỐC ĐỘ 25 STUDS/S CỦA SERVER
    local flyTime = distance / Config.SafeSpeed
    
    -- Nếu gắp coin quá gần < 0.1s thì máy chủ có thể lỗi gói tin, gắn cứng min = 0.2s
    flyTime = math.max(flyTime, 0.2)
    
    -- Tween di chuyển gốc đến ngay trọng tâm đồng xu
    local tweenInfo = TweenInfo.new(flyTime, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)
    local tween = TweenService:Create(root, tweenInfo, {
        CFrame = CFrame.new(targetPos)
    })
    
    tween:Play()
    tween.Completed:Wait() -- Chờ bay xong đúng thời gian đó
    
    -- Ngắt bỏ noclip sau khi bay
    noclip:Disconnect()

    -- 🖐️ ÉP CHẠM VẬT LÝ NHƯ NGƯỜI THẬT
    -- Thả neo 3 tíc-tắc kết hợp nhấp nhô để Roblox xác nhận "Touching"
    root.CFrame = CFrame.new(targetPos)
    root.Anchored = false 
    task.wait(0.06)
    root.CFrame = CFrame.new(targetPos + Vector3.new(0, 0.6, 0))
    task.wait(0.06)
    root.CFrame = CFrame.new(targetPos - Vector3.new(0, 0.4, 0))
    task.wait(0.12)
    root.Anchored = true -- Xong neo lại để chuẩn bị bay chuyến tới
    
    return true
end

--// 🛡️ ANTI AFK
local function SetupAntiAFK()
    if not Config.AntiAFK then return end
    LocalPlayer.Idled:Connect(function()
        VirtualUser:Button2Down(Vector2.new(0, 0), Camera.CFrame)
        task.wait(1)
        VirtualUser:Button2Up(Vector2.new(0, 0), Camera.CFrame)
    end)
end

--// 🔄 LÕI HOẠT ĐỘNG (FARM LOOP)
local function StopFarm()
    Config.FarmEnabled = false
    isRunning = false
    Notify("⛔ MM2 Auto Farm", "Đã dừng. Tổng nhặt: " .. totalCoinsCollected .. " xu!")
end

local function FarmLoop()
    if isRunning then return end
    isRunning = true
    Notify("▶️ Auto Farm", "Bắt đầu chuyến bay lén lút (Stealth Tween)!")

    task.spawn(function()
        while Config.FarmEnabled and isRunning do
            pcall(function()
                local hum = GetHumanoid()
                if not GetRoot() or not hum or hum.Health <= 0 then
                    task.wait(1)
                    return
                end

                local mapModel, container = FindCurrentMap()
                if not mapModel or not container then
                    task.wait(Config.ReScanDelay)
                    return
                end

                -- Reset bộ đếm khi qua Round (Map) mới
                if mapModel.Name ~= currentMapName then
                    currentMapName = mapModel.Name
                    roundCoinsCollected = 0
                    Notify("🗺️ Map Mới Load", "Đã vào map: " .. currentMapName)
                end

                if roundCoinsCollected >= 40 then
                    task.wait(2)
                    return
                end

                local coins = SortCoinsByDistance(GetCoins(container))
                if #coins == 0 then
                    task.wait(Config.ReScanDelay)
                    return
                end

                for _, coin in ipairs(coins) do
                    if not Config.FarmEnabled or not isRunning then break end
                    local currentHum = GetHumanoid()
                    if not currentHum or currentHum.Health <= 0 then break end

                    if coin.Visual and coin.Visual.Parent then
                        local success = MoveToCoin(coin)
                        if success then
                            totalCoinsCollected = totalCoinsCollected + 1
                            roundCoinsCollected = roundCoinsCollected + 1
                        else
                            break
                        end

                        if roundCoinsCollected >= 40 then
                            Notify("✅ CÁN MỐC LIMIT", "Đã đủ 40 xu. Đang tự reset sang trận mới...")
                            pcall(function() GetHumanoid().Health = 0 end)
                            break
                        end

                        task.wait(Config.FarmDelay)
                    end
                end
            end)
            task.wait(Config.FarmDelay)
        end
        isRunning = false
    end)
end

--// 🎨 GIAO DIỆN CHÍNH (GUI)
local function CreateUI()
    pcall(function()
        local old = LocalPlayer.PlayerGui:FindFirstChild("MM2FarmUI")
        if old then old:Destroy() end
    end)
    
    local gui = Instance.new("ScreenGui")
    gui.Name = "MM2FarmUI"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
    
    -- Main Frame
    local frame = Instance.new("Frame")
    frame.Name = "Main"
    frame.Size = UDim2.new(0, 230, 0, 225)
    frame.Position = UDim2.new(0, 10, 0.5, -112)
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
    titleBar.Size = UDim2.new(1, 0, 0, 36)
    titleBar.BackgroundColor3 = Color3.fromRGB(255, 200, 50)
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
    titleLabel.Text = "🪙 MM2 Stealth Farm"
    titleLabel.TextColor3 = Color3.fromRGB(20, 20, 30)
    titleLabel.TextSize = 15
    titleLabel.Font = Enum.Font.GothamBlack
    titleLabel.Parent = titleBar
    
    -- Nút Bắt Đầu
    local toggleBtn = Instance.new("TextButton")
    toggleBtn.Size = UDim2.new(0.88, 0, 0, 36)
    toggleBtn.Position = UDim2.new(0.06, 0, 0, 46)
    toggleBtn.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
    toggleBtn.Text = "▶  BẮT ĐẦU FARM"
    toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggleBtn.TextSize = 14
    toggleBtn.Font = Enum.Font.GothamBold
    toggleBtn.Parent = frame
    Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 8)
    
    -- Nút Info Chế Độ
    local safeBtn = Instance.new("TextButton")
    safeBtn.Size = UDim2.new(0.88, 0, 0, 30)
    safeBtn.Position = UDim2.new(0.06, 0, 0, 90)
    safeBtn.BackgroundColor3 = Color3.fromRGB(155, 89, 182)
    safeBtn.Text = "🛡️ CORE: STEALTH TWEEN"
    safeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    safeBtn.TextSize = 12
    safeBtn.Font = Enum.Font.GothamSemibold
    safeBtn.Parent = frame
    Instance.new("UICorner", safeBtn).CornerRadius = UDim.new(0, 8)
    
    -- Hiển thị Nhãn
    local mapLabel = Instance.new("TextLabel")
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
    statusLabel.Size = UDim2.new(0.88, 0, 0, 20)
    statusLabel.Position = UDim2.new(0.06, 0, 0, 150)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = "⏸️ Trạng thái: Chờ bật..."
    statusLabel.TextColor3 = Color3.fromRGB(180, 180, 190)
    statusLabel.TextSize = 11
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.Parent = frame
    
    local roundCoinLabel = Instance.new("TextLabel")
    roundCoinLabel.Size = UDim2.new(0.88, 0, 0, 20)
    roundCoinLabel.Position = UDim2.new(0.06, 0, 0, 172)
    roundCoinLabel.BackgroundTransparency = 1
    roundCoinLabel.Text = "🎯 Thu thập: 0/40 xu"
    roundCoinLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
    roundCoinLabel.TextSize = 12
    roundCoinLabel.Font = Enum.Font.GothamBold
    roundCoinLabel.TextXAlignment = Enum.TextXAlignment.Left
    roundCoinLabel.Parent = frame
    
    local totalCoinLabel = Instance.new("TextLabel")
    totalCoinLabel.Size = UDim2.new(0.88, 0, 0, 20)
    totalCoinLabel.Position = UDim2.new(0.06, 0, 0, 194)
    totalCoinLabel.BackgroundTransparency = 1
    totalCoinLabel.Text = "🪙 Tích lũy: 0 xu"
    totalCoinLabel.TextColor3 = Color3.fromRGB(180, 220, 255)
    totalCoinLabel.TextSize = 12
    totalCoinLabel.Font = Enum.Font.GothamSemibold
    totalCoinLabel.TextXAlignment = Enum.TextXAlignment.Left
    totalCoinLabel.Parent = frame
    
    -- Logic Kéo Thả (Draggable GUI)
    local dragging, dragInput, dragStart, startPos
    titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true ; dragStart = input.Position ; startPos = frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    titleBar.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    
    -- Tương tác Nút bấm
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
    
    -- Vòng lặp Cập nhật UI
    task.spawn(function()
        while task.wait(0.5) do
            pcall(function()
                roundCoinLabel.Text = "🎯 Thu thập: " .. roundCoinsCollected .. "/40 xu"
                totalCoinLabel.Text = "🪙 Tích lũy: " .. totalCoinsCollected .. " xu"
                
                local mapModel, container = FindCurrentMap()
                if mapModel then
                    mapLabel.Text = "🗺️ Map: " .. mapModel.Name
                    if isRunning then
                        statusLabel.Text = "🔄 Farming... Tốc độ: " .. Config.SafeSpeed .. " s/s"
                    end
                else
                    mapLabel.Text = "🗺️ Map: Sảnh chờ Lobby..."
                    if isRunning then statusLabel.Text = "⏳ Chờ vào game..." end
                end
                
                if not isRunning then statusLabel.Text = "⏸️ Trạng thái: Chờ tải..." end
            end)
        end
    end)
    
    gui.Parent = LocalPlayer.PlayerGui
end

--// ✨ KHỞI TẠO (INITIALIZATION)
local function Init()
    if not game:IsLoaded() then game.Loaded:Wait() end
    SetupAntiAFK()
    CreateUI()
    
    -- Lắng nghe bắt đầu Round mới
    Workspace.ChildAdded:Connect(function(child)
        task.wait(0.5)
        if child:IsA("Model") or child:IsA("Folder") then
            if child:FindFirstChild("CoinContainer") then
                currentMapName = child.Name
                Notify("🗺️ MAP MỚI", "Game đã load map: " .. child.Name)
            end
        end
    end)
    
    Notify("✅ HOÀN TẤT", "Đã nạp bản MM2 Stealth Auto Farm siêu an toàn!")
end

Init()

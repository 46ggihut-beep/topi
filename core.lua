-- DoubleAttack.lua (standalone, no UI)
-- Cầm Melee/Sword + bắn LeftClickRemote của Fruit trong Backpack cùng lúc.
-- Config: getgenv().DoubleAttackConfig = { ... } đặt TRƯỚC khi chạy script.
-- Tắt: getgenv().DoubleAttackStop()
-- Bật/tắt tạm: getgenv().DoubleAttackConfig.Enabled = true/false

local cloneref = cloneref or function(v)
    return v
end

local Players = cloneref(game:GetService("Players"))
local RS = cloneref(game:GetService("ReplicatedStorage"))
local WS = cloneref(game:GetService("Workspace"))

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local LP = Players.LocalPlayer
local env = getgenv()

-- ===== Config =====
local Config = env.DoubleAttackConfig or {}
env.DoubleAttackConfig = Config

local defaults = {
    Enabled = true,          -- bật/tắt Double Attack
    Weapon = "Melee",        -- vũ khí cầm tay: "Melee" | "Sword"
    Range = 60,              -- tầm đánh (melee + fruit)
    Delay = 0.01,            -- delay vòng melee
    AttackPlayers = false,   -- đánh cả player
    PlayAnimation = false,    -- chơi animation melee
    SecondFruit = true,     -- (AttackConfig.DoubleAttack cũ) bắn thêm 1 fruit khác trong Backpack
}
for k, v in pairs(defaults) do
    if Config[k] == nil then
        Config[k] = v
    end
end

-- ===== Session (chạy lại script sẽ tắt instance cũ) =====
if env.DoubleAttackStop then
    pcall(env.DoubleAttackStop)
end
local session = {}
env.DoubleAttackSession = session
env.DoubleAttackStop = function()
    if env.DoubleAttackSession == session then
        env.DoubleAttackSession = nil
    end
end
local function alive()
    return env.DoubleAttackSession == session
end

-- ===== Services / remotes =====
local CombatUtil = require(RS.Modules.CombatUtil)
local Net = require(RS.Modules.Net)
local RegisterAttack = RS.Modules.Net:WaitForChild("RE/RegisterAttack")
local RegisterHit = Net:RemoteEvent("RegisterHit", true)
local validator2 = RS.Remotes:WaitForChild("Validator2")
local Enemies = WS:WaitForChild("Enemies")

local BODY_PARTS = {
    RightUpperArm = true, RightLowerArm = true, RightHand = true,
    RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
    LeftUpperArm = true, LeftLowerArm = true, LeftHand = true,
    LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true,
    UpperTorso = true, LowerTorso = true, Head = true,
}

local function getRoot()
    local character = LP.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

-- ===== Equip =====
local function equipWeaponType(want)
    local character = LP.Character
    if not character then
        return
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return
    end
    local function match(tool)
        if want == "Fruit" then
            return tool.ToolTip == "Blox Fruit"
        end
        return tool:GetAttribute("WeaponType") == want
    end
    local tool = character:FindFirstChildOfClass("Tool")
    if tool and match(tool) then
        return true
    end
    for _, item in ipairs(LP.Backpack:GetChildren()) do
        if item:IsA("Tool") and match(item) then
            humanoid:EquipTool(item)
            break
        end
    end
    return false
end

-- ===== Core hit detection (melee) =====
local combatAttackUps
local function getCombatUpvalues()
    if combatAttackUps then
        return combatAttackUps
    end
    local ok, fn = pcall(function()
        return getupvalue(require(RS.Controllers.CombatController).Attack, 9)
    end)
    if ok and fn then
        combatAttackUps = fn
    end
    return combatAttackUps
end

local function advanceValidator()
    local fn = getCombatUpvalues()
    if not fn then
        return
    end
    pcall(function()
        local u15 = getupvalue(fn, 15)
        local u13 = getupvalue(fn, 13)
        local u16 = getupvalue(fn, 16)
        local u17 = getupvalue(fn, 17)
        local u14 = getupvalue(fn, 14)
        local u12 = getupvalue(fn, 12)
        local u18 = getupvalue(fn, 18)
        if not u15 or not u13 or not u16 or not u17 then
            return
        end
        u12 = u12 or 0
        u14 = u14 or 0
        u18 = u18 or 0
        local q = u12 * u13
        local d = (((u14 * u13 + u12 * u15) % u16) * u16 + q) % u17
        u14 = math.floor(d / u16)
        u12 = d - u14 * u16
        u18 = u18 + 1
        setupvalue(fn, 15, u15)
        setupvalue(fn, 13, u13)
        setupvalue(fn, 16, u16)
        setupvalue(fn, 17, u17)
        setupvalue(fn, 14, u14)
        setupvalue(fn, 12, u12)
        setupvalue(fn, 18, u18)
        validator2:FireServer(math.floor((d / u17) * 16777215), u18)
    end)
end

local function getBladeHits(character, rootList, range, includePlayers)
    local hits = {}
    local rootPos = rootList[1].Position
    local folders = { WS:FindFirstChild("Enemies") }
    if includePlayers then
        table.insert(folders, WS:FindFirstChild("Characters"))
    end
    for _, folder in ipairs(folders) do
        if folder then
            for _, mob in ipairs(folder:GetChildren()) do
                if mob ~= character and mob:FindFirstChild("HumanoidRootPart") then
                    local hrp = mob.HumanoidRootPart
                    local checkPos = { hrp.Position }
                    if hrp.Size.Y > 5 then
                        table.insert(checkPos, (hrp.CFrame * CFrame.new(0, -hrp.Size.Y * 1.5 + 3, 0)).Position)
                    end
                    local hitRadius = range
                    if Players:GetPlayerFromCharacter(mob) then
                        hitRadius = range / 1.5
                    end
                    for _, pos in ipairs(checkPos) do
                        if (pos - rootPos).Magnitude < (10 + hitRadius) + hrp.Size.X / 2 then
                            for _, part in ipairs(mob:GetChildren()) do
                                if part:IsA("BasePart") and (part.Position - rootPos).Magnitude <= hitRadius + hrp.Size.X / 2 then
                                    table.insert(hits, part)
                                end
                            end
                            break
                        end
                    end
                end
            end
        end
    end
    return hits
end

local function AttackAOE(character, range, includePlayers)
    local hits, seen = {}, {}
    local rootList = { character.HumanoidRootPart }
    for _, part in ipairs(getBladeHits(character, rootList, range, includePlayers)) do
        local rig = CombatUtil:GetRigOfHitPart(part)
        if rig and not seen[rig] and BODY_PARTS[part.Name] and CombatUtil:IsVulnerable(rig) then
            local myPlayer = Players:GetPlayerFromCharacter(character)
            local summoner = rig:FindFirstChild("Summoner")
            local mySummoner = character:FindFirstChild("Summoner")
            local valid = rig ~= character
                and (not mySummoner or rig ~= mySummoner.Value.Character)
                and (not myPlayer or not summoner or summoner.Value ~= myPlayer)
            if valid then
                table.insert(hits, { rig, part })
                seen[rig] = true
            end
        end
    end
    return #hits > 0 and hits or nil
end

-- ===== Melee attack =====
local animState = { comboIndex = 0, lastComboTime = 0, currentAnim = nil }

local function getMovesetAnimCache(character)
    local ok, res = pcall(function()
        return CombatUtil:GetMovesetAnimCache(character.Humanoid)
    end)
    return ok and res or nil
end

local function attackMelee(character, tool, range)
    if not tool then
        return
    end
    local hits = AttackAOE(character, range or Config.Range, Config.AttackPlayers)
    if not hits then
        return
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return
    end
    local ok, wname = pcall(function()
        return CombatUtil:GetWeaponName(tool)
    end)
    if not ok or not wname then
        return
    end
    local ok2, wdata = pcall(function()
        return CombatUtil:GetWeaponData(wname)
    end)
    if not ok2 or not wdata then
        return
    end
    local root = humanoid.RootPart
    local rig = root and root.Parent
    if not CombatUtil:CanAttack(rig, wdata.WeaponType) then
        return
    end
    local cache = getMovesetAnimCache(character)
    if not cache then
        return
    end
    local moveset = wdata.Moveset
    local now = tick()
    if now - animState.lastComboTime > 0.8 then
        animState.comboIndex = 0
    end
    animState.comboIndex = animState.comboIndex % #moveset.Basic + 1
    animState.lastComboTime = now
    local pureName = CombatUtil:GetPureWeaponName(wname)
    local anim = cache[pureName .. ("-basic" .. animState.comboIndex)]
    if not anim then
        return
    end
    local speedMult = anim:GetAttribute("SpeedMult") or 1
    local duration = anim.Length / speedMult
    RegisterAttack:FireServer(duration)
    RegisterHit:FireServer((table.remove(hits, 1))[2], hits)
    pcall(function()
        if animState.currentAnim and animState.currentAnim ~= anim then
            animState.currentAnim:Stop()
        end
        anim:Play(0.1, 1, speedMult)
        animState.currentAnim = anim
    end)
    table.clear(hits)
    return true
end

local function attackNoAnim(character, range)
    if character.Stun and character.Stun.Value ~= 0 then
        return
    end
    local hits = AttackAOE(character, range or Config.Range, Config.AttackPlayers)
    if not hits then
        return
    end
    advanceValidator()
    RegisterAttack:FireServer(0)
    RegisterHit:FireServer((table.remove(hits, 1))[2], hits)
    table.clear(hits)
    return true
end

local function AttackFunction(range)
    local character = LP.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then
        return
    end
    if character.Stun and character.Stun.Value ~= 0 then
        return
    end
    local tool = character:FindFirstChildOfClass("Tool")
    if Config.PlayAnimation and tool and tool:GetAttribute("WeaponType") then
        attackMelee(character, tool, range)
    else
        attackNoAnim(character, range)
    end
end

-- ===== Fruit attack =====
local MULTI_HIT = { ["Blade-Blade"] = true, ["Gas-Gas"] = true }
local comboCount, comboLast = 0, 0

local function validEnemy(target)
    if not target or not target.Parent then
        return false
    end
    if not target:IsDescendantOf(Enemies) then
        return false
    end
    if target:GetAttribute("IsBoat") then
        return false
    end
    local humanoid = target:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then
        return false
    end
    local rootPart = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart
    if not rootPart then
        return false
    end
    return true, humanoid, rootPart
end

-- fruit thường: bắn xuống đất
local function fireDown(tool)
    local remote = tool:FindFirstChild("LeftClickRemote")
    if not remote then
        return
    end
    pcall(function()
        remote:FireServer(Vector3.new(0.01, -500, 0.01), 1, true)
    end)
end

-- Blade-Blade: bắn theo hướng từng enemy trong range, combo 1..5
local function fireBlade(tool)
    local remote = tool:FindFirstChild("LeftClickRemote")
    if not remote then
        return
    end
    if tick() - comboLast > 0.65 then
        comboCount = 0
    end
    comboCount = comboCount >= 5 and 1 or comboCount + 1
    comboLast = tick()
    local root = getRoot()
    if not root then
        return
    end
    for _, item in ipairs(Enemies:GetChildren()) do
        local ok, _, rootPart = validEnemy(item)
        if ok and (rootPart.Position - root.Position).Magnitude <= Config.Range then
            local unit = (rootPart.Position - root.Position).Unit
            pcall(function()
                remote:FireServer(unit, comboCount)
            end)
        end
    end
end

-- Gas-Gas: quét target gần nhất, bắn luân phiên
local GAS_RANGE = 100
local GAS_MAX_TARGETS = 6
local gasParts, gasHumanoids, gasScanned, gasIndex = {}, {}, 0, 0
local gasActive = false

local function gasScan()
    if tick() - gasScanned < 0.1 then
        return
    end
    gasScanned = tick()
    table.clear(gasParts)
    table.clear(gasHumanoids)
    local root = getRoot()
    if not root then
        return
    end
    local origin = root.Position
    local found = {}
    for _, item in ipairs(Enemies:GetChildren()) do
        local ok, humanoid, rootPart = validEnemy(item)
        if ok then
            local distance = (rootPart.Position - origin).Magnitude
            if distance <= GAS_RANGE then
                found[#found + 1] = { part = rootPart, humanoid = humanoid, distance = distance }
            end
        end
    end
    table.sort(found, function(a, b)
        return a.distance < b.distance
    end)
    for i = 1, math.min(#found, GAS_MAX_TARGETS) do
        gasParts[i] = found[i].part
        gasHumanoids[i] = found[i].humanoid
    end
end

local function fireGas(tool)
    local remote = tool:FindFirstChild("LeftClickRemote")
    local root = getRoot()
    if not remote or not root then
        return
    end
    gasScan()
    local total = #gasParts
    if total > 0 then
        local origin = root.Position
        for _ = 1, total do
            gasIndex = gasIndex % total + 1
            local part = gasParts[gasIndex]
            if part.Parent and gasHumanoids[gasIndex].Health > 0 then
                local offset = part.Position - origin
                if offset.Magnitude > 0.01 and offset.Magnitude <= GAS_RANGE then
                    remote:FireServer(offset.Unit, 1)
                    return
                end
            end
        end
    end
    remote:FireServer(Vector3.new(0.01, -500, 0.01), 1, true)
end

local function fireFruit(tool)
    if tool.Name == "Gas-Gas" then
        gasActive = true
        fireGas(tool)
    elseif MULTI_HIT[tool.Name] then
        -- fruit phụ: bắn 1 hit/enemy, không combo
        local remote = tool:FindFirstChild("LeftClickRemote")
        local root = getRoot()
        if remote and root then
            for _, item in ipairs(Enemies:GetChildren()) do
                local ok, _, rootPart = validEnemy(item)
                if ok and (rootPart.Position - root.Position).Magnitude <= Config.Range then
                    local unit = (rootPart.Position - root.Position).Unit
                    pcall(function()
                        remote:FireServer(unit, 1)
                    end)
                end
            end
        end
    else
        fireDown(tool)
    end
end

-- Double Attack: fruit KHÔNG cần cầm tay, lấy từ Backpack
local function fruitAttack()
    local character = LP.Character
    local tool = character and character:FindFirstChildOfClass("Tool")
    if tool and tool:GetAttribute("ServerState") ~= nil then
        return
    end
    if not tool or tool.ToolTip ~= "Blox Fruit" then
        tool = nil
        for _, item in ipairs(LP.Backpack:GetChildren()) do
            if item:IsA("Tool") and item.ToolTip == "Blox Fruit" and item:FindFirstChild("LeftClickRemote") then
                tool = item
                break
            end
        end
    end
    if not tool or not tool:FindFirstChild("LeftClickRemote") then
        return
    end
    if not getRoot() then
        return
    end

    -- fruit thứ 2 (tùy chọn)
    if Config.SecondFruit then
        for _, item in ipairs(LP.Backpack:GetChildren()) do
            if item:IsA("Tool") and item.ToolTip == "Blox Fruit" and item ~= tool and item:FindFirstChild("LeftClickRemote") then
                fireFruit(item)
                break
            end
        end
    end

    gasActive = tool.Name == "Gas-Gas"
    if gasActive then
        fireGas(tool)
    elseif MULTI_HIT[tool.Name] then
        fireBlade(tool)
    else
        fireDown(tool)
    end
end

-- ===== Loops =====
-- Loop 1: melee/sword
task.spawn(function()
    while alive() do
        if Config.Enabled then
            pcall(function()
                local character = LP.Character
                if not character or not character:FindFirstChild("HumanoidRootPart") then
                    return
                end
                local want = Config.Weapon
                local held = character:FindFirstChildOfClass("Tool")
                local heldType = held and (held:GetAttribute("WeaponType") or held.ToolTip)
                local alreadyOk = heldType == want
                    or (want == "Fruit" and held and held.ToolTip == "Blox Fruit")
                if not alreadyOk and AttackAOE(character, Config.Range, Config.AttackPlayers) then
                    equipWeaponType(want)
                end
                if not character:FindFirstChildOfClass("Tool") then
                    return
                end
                AttackFunction()
            end)
            task.wait(Config.Delay)
        else
            task.wait(0.2)
        end
    end
end)

-- Loop 2: fruit
task.spawn(function()
    while alive() do
        if Config.Enabled then
            gasActive = false
            pcall(fruitAttack)
            task.wait(gasActive and 0.03 or 0.05)
        else
            task.wait(1)
        end
    end
end)

env.AttackFunction = AttackFunction
env.FruitAttack = fruitAttack

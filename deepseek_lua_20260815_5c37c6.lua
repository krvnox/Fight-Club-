-- ================================================================
-- AUTO COMBATE ADAPTATIVO + AUTO PARRY ULTRA + OBSERVADOR DE COMBOS
-- COM NOVOS BUFFERS DE ANIMAÇÕES (PARTES)
-- ================================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local packetRemote = ReplicatedStorage:WaitForChild("Packet"):WaitForChild("RemoteEvent")

-- ==================== NOVOS BUFFERS (COM PARTES) ====================
local PUNCH_BUFFER = buffer.fromstring("\005\004part\r\022)\186\217\193\241C$A\211\172[\195\022\204\028\224\180\000\000\128\191\000\000\000\000\022\137\178?Ao\f-A0\212|B\v$c9cffed9-c7bd-4d44-83c0-7ebd1249d30c")
local HIGHKICK_BUFFER = buffer.fromstring("\005\004part\r\022Q\155\222\193\212\023\250@K'[\195\022\000\000\000\000\000\000\000\000\000\000\128?\022r[\211?\2261$?X#!A\v$97d552c3-f618-4ac9-91bc-b8c34d19ea28")
local LOWKICK_BUFFER = buffer.fromstring("\005\004part\r\022\158n\221\193`\172\243@\220\224X\195\022\000\000\000\000\000\000\128\191\000\000\000\000\022\000\000\141C\000\000\160@\000\000@@\v$fca0b62b-ffc8-4a72-ba0d-ce444dae256b")
local BLOCK_PRESS = buffer.fromstring("\005\bkeypress\v\001f\000\000\000\000")
local BLOCK_RELEASE = buffer.fromstring("\005\bkeyrelease\v\001f\000\000\000\000")
local PARRY_PRESS = buffer.fromstring("\005\bkeypress\v\001g\000\000\000\000")   -- Tecla do parry (ajuste se necessário)
local PARRY_RELEASE = buffer.fromstring("\005\bkeyrelease\v\001g\000\000\000\000")

-- Partes usadas
local PUNCH_PART_PATH = {"train", "train", "body"}
local HIGHKICK_PART_PATH = {"railway", "sleeper"}
local LOWKICK_PART_PATH = {"subway", "concretes", "concrete"}

-- ==================== CONFIGURAÇÕES ====================
local DETECTION_RANGE = 60
local ATTACK_RANGE = 8
local KITER_ATTACK_RANGE = 15
local FACING_THRESHOLD = 0.5

-- Bloqueio super rápido
local BASE_BLOCK_COOLDOWN = 0.02
local BLOCK_DURATION_MIN = 0.002
local BLOCK_DURATION_MAX = 0.008
local BLOCK_RECOVERY = 0.01
local THREAT_SPEED = 14
local THREAT_DISTANCE = 8
local PREDICTIVE_BLOCK_DISTANCE = 4

-- Parry ultra-rápido
local BASE_PARRY_COOLDOWN = 0.0
local BASE_PARRY_PRESS_DURATION = 0.2
local MIN_PARRY_PRESS = 0.15
local MAX_PARRY_PRESS = 0.3
local PARRY_RECOVERY = 0.0

-- Aproximação
local FOLLOW_SPEED = 24
local FOLLOW_RANGE = KITER_ATTACK_RANGE

-- Cooldowns de ataque
local PUNCH_COOLDOWN_NORMAL = 0.02
local PUNCH_COOLDOWN_FAST = 0.008
local KICK_COOLDOWN_NORMAL = 0.04
local KICK_COOLDOWN_FAST = 0.015
local SHARINGAN_DURATION = 5

-- ==================== ESTADO ====================
local lastPunchTime = 0
local lastKickTime = 0
local lastBlock = 0
local blockReleaseAt = 0
local isBlocking = false
local sharinganActive = false
local sharinganEndTime = 0
local comboStep = 1
local currentCombo = {}
local approachEnabled = true

-- Parry
local lastParryTime = 0
local isParrying = false
local parryReleaseAt = 0
local parryRecoveryUntil = 0
local postParryCounter = false

-- Observador
local COMBO_TIMEOUT = 1.2
local MIN_COMBO_LENGTH = 2
local currentTarget = nil
local activeAnims = {}
local currentSequence = {}
local lastAttackObserved = 0
local detectedCombos = {}
local learnedComboFunctions = {}
local comboCount = {}

-- ==================== FUNÇÕES AUXILIARES ====================
local function getPart(path)
    local obj = workspace
    for _, name in ipairs(path) do
        obj = obj and obj:FindFirstChild(name)
        if not obj then return nil end
    end
    return obj
end

local function classifyAttack(animId)
    local lower = tostring(animId):lower()
    if lower:find("punch") or lower:find("soco") or lower:find("jab") or lower:find("cross") or lower:find("uppercut") or lower:find("lmb") then
        return "Soco"
    elseif (lower:find("high") and lower:find("kick")) or lower:find("highkick") or lower:find("high_kick") or lower:find("chutealto") then
        return "Chute Alto"
    elseif (lower:find("low") and lower:find("kick")) or lower:find("lowkick") or lower:find("low_kick") or lower:find("chutebaixo") then
        return "Chute Baixo"
    elseif lower:find("kick") or lower:find("chute") then
        return "Chute"
    elseif lower:find("attack") or lower:find("hit") or lower:find("ataque") or lower:find("golpe") then
        return "Ataque"
    else
        local idNumber = tostring(animId):match("rbxassetid://(%d+)")
        return "MOVE:" .. (idNumber or tostring(animId))
    end
end

local attackFunctionMap = {
    ["Soco"] = executePunch,
    ["Chute Alto"] = executeHighKick,
    ["Chute Baixo"] = executeLowKick,
    ["Chute"] = executeHighKick,
    ["Ataque"] = executePunch,
}

-- ==================== FUNÇÕES DE GOLPE (COM PARTES) ====================
function executePunch()
    local part = getPart(PUNCH_PART_PATH)
    if part then
        pcall(function() packetRemote:FireServer(PUNCH_BUFFER, { part }) end)
    else
        pcall(function() packetRemote:FireServer(buffer.fromstring("\005\003lmb\000\000\000\000\000")) end)
    end
end

function executeHighKick()
    local part = getPart(HIGHKICK_PART_PATH)
    if part then
        pcall(function() packetRemote:FireServer(HIGHKICK_BUFFER, { part }) end)
    else
        pcall(function() packetRemote:FireServer(buffer.fromstring("\005\bkeypress\v\001q\000\000\000\000")) end)
    end
end

function executeLowKick()
    local part = getPart(LOWKICK_PART_PATH)
    if part then
        pcall(function() packetRemote:FireServer(LOWKICK_BUFFER, { part }) end)
    else
        pcall(function() packetRemote:FireServer(buffer.fromstring("\005\bkeypress\v\001e\000\000\000\000")) end)
    end
end

-- ==================== OBSERVADOR DE COMBOS ====================
local function resetComboObserver(newTarget)
    currentTarget = newTarget
    activeAnims = {}
    currentSequence = {}
    lastAttackObserved = 0
end

local function finalizeLearnedCombo()
    if #currentSequence >= MIN_COMBO_LENGTH then
        local comboStr = table.concat(currentSequence, " > ")
        comboCount[comboStr] = (comboCount[comboStr] or 0) + 1
        if not table.find(detectedCombos, comboStr) then
            table.insert(detectedCombos, comboStr)
            local newCombo = {}
            local valid = true
            for _, attackType in ipairs(currentSequence) do
                local func = attackFunctionMap[attackType]
                if func then
                    table.insert(newCombo, func)
                else
                    valid = false
                    break
                end
            end
            if valid and #newCombo >= 2 then
                table.insert(learnedComboFunctions, newCombo)
                print("⚔️ Aprendido combo do inimigo: " .. comboStr)
            end
        end
    end
    currentSequence = {}
    lastAttackObserved = 0
end

local function observeEnemyCombos(enemyChar)
    if not enemyChar then return end
    local hum = enemyChar:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return end

    local now = tick()
    if #currentSequence > 0 and (now - lastAttackObserved) > COMBO_TIMEOUT then
        finalizeLearnedCombo()
    end

    for _, track in ipairs(hum:GetPlayingAnimationTracks()) do
        if track.IsPlaying then
            local anim = track.Animation
            if anim then
                local classified = classifyAttack(anim.AnimationId)
                if classified then
                    local isNew = not activeAnims[track]
                    local startedRecently = track.TimePosition < 0.25
                    if isNew and startedRecently then
                        activeAnims[track] = true
                        if #currentSequence > 0 and (now - lastAttackObserved) > COMBO_TIMEOUT then
                            finalizeLearnedCombo()
                        end
                        table.insert(currentSequence, classified)
                        lastAttackObserved = now
                    end
                end
            end
        else
            activeAnims[track] = nil
        end
    end
end

-- ==================== COMBOS ADAPTATIVOS ====================
local fallbackCombos = {
    {executePunch, executePunch, executePunch, executeHighKick},
    {executePunch, executePunch, executePunch, executeLowKick},
    {executeHighKick, executePunch, executePunch, executePunch},
    {executeLowKick, executePunch, executePunch, executePunch},
    {executePunch, executeHighKick, executePunch, executeLowKick},
    {executePunch, executeLowKick, executePunch, executeHighKick},
}

local function chooseAdaptiveCombo()
    if #learnedComboFunctions > 0 then
        currentCombo = learnedComboFunctions[math.random(#learnedComboFunctions)]
    else
        currentCombo = fallbackCombos[math.random(#fallbackCombos)]
    end
    comboStep = 1
end
chooseAdaptiveCombo()

-- ==================== DETECÇÃO DE INIMIGO ====================
local function findEnemy()
    local char = player.Character
    if not char then return nil end
    local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
    if not root then return nil end

    local nearest, minDist = nil, DETECTION_RANGE
    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= player and other.Character then
            local otherRoot = other.Character:FindFirstChild("HumanoidRootPart") or other.Character:FindFirstChild("Torso")
            local otherHum = other.Character:FindFirstChildOfClass("Humanoid")
            if otherRoot and otherHum and otherHum.Health > 0 then
                local d = (root.Position - otherRoot.Position).Magnitude
                if d < minDist then
                    minDist = d
                    nearest = other.Character
                end
            end
        end
    end
    return nearest
end

-- ==================== LEITURA DO OPONENTE ====================
local function isEnemyAttackingNow(enemyChar)
    if not enemyChar then return false end
    local hum = enemyChar:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    for _, track in ipairs(hum:GetPlayingAnimationTracks()) do
        local anim = track.Animation
        if anim and track.IsPlaying then
            local name = string.lower(anim.AnimationId)
            if name:find("attack") or name:find("punch") or name:find("kick") or name:find("soco") or name:find("chute") or name:find("hit") then
                return true
            end
        end
    end
    return false
end

local function isEnemyBlockingNow(enemyChar)
    if not enemyChar then return false end
    local hum = enemyChar:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    for _, track in ipairs(hum:GetPlayingAnimationTracks()) do
        local anim = track.Animation
        if anim and track.IsPlaying then
            local name = string.lower(anim.AnimationId)
            if name:find("block") or name:find("guard") or name:find("defend") or name:find("defesa") or name:find("bloqueio") then
                return true
            end
        end
    end
    return false
end

local function getEnemyBlockRemainingTime(enemyChar)
    if not enemyChar then return 0 end
    local hum = enemyChar:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return 0 end
    local maxRemaining = 0
    for _, track in ipairs(hum:GetPlayingAnimationTracks()) do
        local anim = track.Animation
        if anim and track.IsPlaying then
            local name = string.lower(anim.AnimationId)
            if name:find("block") or name:find("guard") or name:find("defend") or name:find("defesa") or name:find("bloqueio") then
                local remaining = track.Length - track.TimePosition
                if remaining > maxRemaining then maxRemaining = remaining end
            end
        end
    end
    return maxRemaining
end

local function shouldParry(enemyChar, myRoot)
    if not enemyChar or not myRoot then return false end
    local targetRoot = enemyChar:FindFirstChild("HumanoidRootPart") or enemyChar:FindFirstChild("Torso")
    if not targetRoot then return false end
    local dist = (myRoot.Position - targetRoot.Position).Magnitude
    if dist > 10 then return false end
    local hum = enemyChar:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    for _, track in ipairs(hum:GetPlayingAnimationTracks()) do
        local anim = track.Animation
        if anim and track.IsPlaying then
            local name = string.lower(anim.AnimationId)
            if name:find("attack") or name:find("punch") or name:find("kick") or name:find("soco") or name:find("chute") or name:find("hit") then
                local remaining = track.Length - track.TimePosition
                if remaining > 0 and remaining < 0.1 then return true end
            end
        end
    end
    return false
end

local function shouldBlock(enemyChar, myRoot)
    if not enemyChar or not myRoot then return false end
    local targetRoot = enemyChar:FindFirstChild("HumanoidRootPart") or enemyChar:FindFirstChild("Torso")
    if not targetRoot then return false end
    local dist = (myRoot.Position - targetRoot.Position).Magnitude
    if tick() < blockRecoveryUntil then return false end
    if shouldParry(enemyChar, myRoot) then return true end
    if isEnemyAttackingNow(enemyChar) and dist <= 10 then
        return true
    end
    local vel = targetRoot.Velocity
    if vel and vel.Magnitude > THREAT_SPEED then
        local dirToMe = (myRoot.Position - targetRoot.Position).Unit
        if vel.Unit:Dot(dirToMe) > 0.5 and dist <= THREAT_DISTANCE then return true end
    end
    if dist <= PREDICTIVE_BLOCK_DISTANCE then
        local toMe = (myRoot.Position - targetRoot.Position).Unit
        local facing = targetRoot.CFrame.LookVector:Dot(toMe)
        if facing > 0.3 and not isEnemyBlockingNow(enemyChar) then
            local moveSpeed = vel and vel.Magnitude or 0
            if moveSpeed > 2 then return true end
        end
    end
    return false
end

local function canAttack(targetRoot, myRoot)
    if not targetRoot or not myRoot then return false end
    local dist = (myRoot.Position - targetRoot.Position).Magnitude
    if dist > ATTACK_RANGE then return false end
    local toEnemy = (targetRoot.Position - myRoot.Position).Unit
    local myFacing = myRoot.CFrame.LookVector:Dot(toEnemy)
    if myFacing < FACING_THRESHOLD then return false end
    return true
end

local function isEnemyDown(enemyChar)
    if not enemyChar then return false end
    local hum = enemyChar:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    for _, track in ipairs(hum:GetPlayingAnimationTracks()) do
        local anim = track.Animation
        if anim and track.IsPlaying then
            local name = string.lower(anim.AnimationId)
            if name:find("down") or name:find("knock") or name:find("stun") or name:find("fall") or name:find("floor") or name:find("dizzy") or name:find("slow") then
                return true
            end
        end
    end
    return false
end

-- ==================== UI BOTÕES ====================
local playerGui = player:WaitForChild("PlayerGui")
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MainUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local sharinganButton = Instance.new("TextButton")
sharinganButton.Size = UDim2.new(0, 70, 0, 70)
sharinganButton.Position = UDim2.new(0.85, 0, 0.78, 0)
sharinganButton.BackgroundColor3 = Color3.fromRGB(180, 0, 0)
sharinganButton.BackgroundTransparency = 0.1
sharinganButton.TextColor3 = Color3.new(1, 1, 1)
sharinganButton.Text = "写"
sharinganButton.Font = Enum.Font.SourceSansBold
sharinganButton.TextSize = 30
sharinganButton.AutoButtonColor = true
sharinganButton.AnchorPoint = Vector2.new(0.5, 0.5)
sharinganButton.Parent = screenGui
Instance.new("UIStroke", sharinganButton).Color = Color3.fromRGB(255, 100, 100)
sharinganButton.Activated:Connect(function()
    sharinganActive = true
    sharinganEndTime = tick() + SHARINGAN_DURATION
    sharinganButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    wait(SHARINGAN_DURATION)
    sharinganButton.BackgroundColor3 = Color3.fromRGB(180, 0, 0)
    sharinganActive = false
end)

local approachButton = Instance.new("TextButton")
approachButton.Size = UDim2.new(0, 120, 0, 40)
approachButton.Position = UDim2.new(0.75, 0, 0.75, 0)
approachButton.BackgroundColor3 = Color3.fromRGB(0, 100, 0)
approachButton.BackgroundTransparency = 0.1
approachButton.TextColor3 = Color3.new(1, 1, 1)
approachButton.Text = "APROX: ON"
approachButton.Font = Enum.Font.SourceSansBold
approachButton.TextSize = 16
approachButton.AutoButtonColor = true
approachButton.AnchorPoint = Vector2.new(0.5, 0.5)
approachButton.Parent = screenGui
Instance.new("UIStroke", approachButton).Color = Color3.fromRGB(0, 200, 0)
approachButton.Activated:Connect(function()
    approachEnabled = not approachEnabled
    if approachEnabled then
        approachButton.Text = "APROX: ON"
        approachButton.BackgroundColor3 = Color3.fromRGB(0, 100, 0)
    else
        approachButton.Text = "APROX: OFF"
        approachButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    end
end)

-- ==================== LOOP PRINCIPAL ====================
RunService.RenderStepped:Connect(function()
    local char = player.Character
    if not char then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then
        if isBlocking then
            pcall(function() packetRemote:FireServer(BLOCK_RELEASE) end)
            isBlocking = false
        end
        return
    end

    if isBlocking and tick() >= blockReleaseAt then
        pcall(function() packetRemote:FireServer(BLOCK_RELEASE) end)
        isBlocking = false
        postBlockCounter = true
        blockRecoveryUntil = tick() + BLOCK_RECOVERY
    end

    if isParrying and tick() >= parryReleaseAt then
        pcall(function() packetRemote:FireServer(PARRY_RELEASE) end)
        isParrying = false
        postParryCounter = true
        parryRecoveryUntil = tick() + PARRY_RECOVERY
    end

    local myRoot = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
    if not myRoot then return end

    local target = findEnemy()
    if not target then
        if isBlocking then pcall(function() packetRemote:FireServer(BLOCK_RELEASE) end) isBlocking = false end
        if isParrying then pcall(function() packetRemote:FireServer(PARRY_RELEASE) end) isParrying = false end
        if humanoid then humanoid.WalkSpeed = 16 end
        return
    end

    local targetRoot = target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Torso")
    if not targetRoot then return end

    observeEnemyCombos(target)

    -- Atualizar tempo restante da defesa inimiga
    local enemyBlockEndTime = 0
    if isEnemyBlockingNow(target) then
        enemyBlockEndTime = tick() + getEnemyBlockRemainingTime(target)
    end

    local distToEnemy = (myRoot.Position - targetRoot.Position).Magnitude

    -- ==================== APROXIMAÇÃO ====================
    local shouldApproach = false
    if approachEnabled and not isBlocking and not shouldBlock(target, myRoot) then
        if distToEnemy > ATTACK_RANGE and distToEnemy <= FOLLOW_RANGE then
            shouldApproach = true
        end
    end

    if shouldApproach and humanoid then
        humanoid.WalkSpeed = FOLLOW_SPEED
        humanoid:MoveTo(targetRoot.Position)
    else
        if humanoid then humanoid.WalkSpeed = 16 end
    end

    -- ==================== PARry ULTRA ====================
    if shouldParry(target, myRoot) then
        if not isParrying and (tick() - lastParryTime >= BASE_PARRY_COOLDOWN) then
            lastParryTime = tick()
            pcall(function() packetRemote:FireServer(PARRY_PRESS) end)
            isParrying = true
            parryReleaseAt = tick() + BASE_PARRY_PRESS_DURATION
            postParryCounter = false
            print("🛡️ Parry!")
        end
        return
    end

    -- ==================== BLOQUEIO NORMAL ====================
    if shouldBlock(target, myRoot) then
        if not isBlocking and (tick() - lastBlock >= BASE_BLOCK_COOLDOWN) then
            lastBlock = tick()
            pcall(function() packetRemote:FireServer(BLOCK_PRESS) end)
            isBlocking = true
            local duration = BLOCK_DURATION_MIN + math.random() * (BLOCK_DURATION_MAX - BLOCK_DURATION_MIN)
            blockReleaseAt = tick() + duration
            postBlockCounter = false
        end
        return
    else
        if isBlocking then
            pcall(function() packetRemote:FireServer(BLOCK_RELEASE) end)
            isBlocking = false
            postBlockCounter = true
            blockRecoveryUntil = tick() + BLOCK_RECOVERY
        end
    end

    -- ==================== CONTRA-ATAQUES ====================
    if postBlockCounter then
        postBlockCounter = false
        executePunch()
        print("⚡ Contra-ataque pós-bloqueio!")
        return
    end

    if postParryCounter then
        postParryCounter = false
        executePunch()
        print("⚡ Contra-ataque pós-parry!")
        return
    end

    -- ==================== PUNIÇÃO ANTI-KITER ====================
    if (tick() - lastParryTime) < 0.8 then
        if distToEnemy <= 10 and (tick() - lastPunchTime >= 0.3) then
            lastPunchTime = tick()
            pcall(function()
                packetRemote:FireServer(HIGHKICK_BUFFER)
                packetRemote:FireServer(PUNCH_BUFFER)
            end)
            print("💢 Punindo kiter!")
            return
        end
    end

    -- ==================== ATAQUE ====================
    if not canAttack(targetRoot, myRoot) then return end

    -- Chute no fim da defesa
    if enemyBlockEndTime > 0 and (enemyBlockEndTime - tick()) < 0.1 then
        executeHighKick()
        print("🎯 Chute no fim da defesa!")
        return
    end

    if isEnemyDown(target) then
        local now = tick()
        local cooldown = sharinganActive and PUNCH_COOLDOWN_FAST or PUNCH_COOLDOWN_NORMAL
        if now - lastPunchTime >= cooldown then
            lastPunchTime = now
            executePunch()
            print("👊 Socando caído")
        end
        return
    end

    -- Combo adaptativo
    if #currentCombo == 0 or comboStep > #currentCombo then
        chooseAdaptiveCombo()
    end

    local currentAction = currentCombo[comboStep]
    local isPunchAction = (currentAction == executePunch)
    local cooldown = isPunchAction and (sharinganActive and PUNCH_COOLDOWN_FAST or PUNCH_COOLDOWN_NORMAL) or (sharinganActive and KICK_COOLDOWN_FAST or KICK_COOLDOWN_NORMAL)
    local lastTime = isPunchAction and lastPunchTime or lastKickTime
    local now = tick()

    if now - lastTime < cooldown then return end

    if isPunchAction then lastPunchTime = now else lastKickTime = now end
    currentAction()

    comboStep = comboStep + 1
    if comboStep > #currentCombo then
        chooseAdaptiveCombo()
    end
end)

print("🧠 Auto parry ultra + observador de combos + novas animações ativados!")
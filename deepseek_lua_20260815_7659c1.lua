-- ================================================================
-- AUTO COMBATE ADAPTATIVO + BUFFERS CORRETOS + AUTO PARRY + ANIMAÇÕES
-- ================================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local packetRemote = ReplicatedStorage:WaitForChild("Packet"):WaitForChild("RemoteEvent")

-- ==================== BUFFERS (com partes) ====================
local PUNCH_BUFFER_NEW = buffer.fromstring("\005\004part\r\022\139\000\145\193X&2AM\199[\195\022\000\000\128\191y\185\1465\000\000\000\000\022\137\178?Ao\f-A0\212|B\v$0ed3edcb-5fef-4b50-8797-643f0c3754d2")
local HIGHKICK_BUFFER_NEW = buffer.fromstring("\005\004part\r\022n\225\160\193M\219\245@\000\000Y\195\022\000\000\000\000\000\000\000\000\000\000\128\191\022\000\000\141C\000\000\160@\000\000@@\v$59d30d2b-1120-4c4c-a95b-3b326c30204b")
local LOWKICK_BUFFER_NEW = buffer.fromstring("\005\004part\r\022\026x\143\193_\172\243@\144-[\195\022\000\000\000\000\255\255\127\191\000\000\000\000\022r[\211?\2261$?X#!A\v$2bfc18a7-9525-4646-b993-d3598b162b07")
local BLOCK_PRESS = buffer.fromstring("\005\bkeypress\v\001f\000\000\000\000")
local BLOCK_RELEASE = buffer.fromstring("\005\bkeyrelease\v\001f\000\000\000\000")

-- Fallbacks antigos (se partes falharem)
local PUNCH_SIMPLE = buffer.fromstring("\005\003lmb\000\000\000\000\000")
local Q_PRESS = buffer.fromstring("\005\bkeypress\v\001q\000\000\000\000")
local Q_RELEASE = buffer.fromstring("\005\bkeyrelease\v\001q\000\000\000\000")
local E_PRESS = buffer.fromstring("\005\bkeypress\v\001e\000\000\000\000")
local E_RELEASE = buffer.fromstring("\005\bkeyrelease\v\001e\000\000\000\000")

-- Partes do mapa
local PUNCH_PART_PATH = {"train", "train", "body"}
local HIGHKICK_PART_PATH = {"subway", "concretes", "concrete"}
local LOWKICK_PART_PATH = {"railway", "sleeper"}

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

-- Aproximação (ativada por padrão)
local FOLLOW_SPEED = 24
local FOLLOW_RANGE = KITER_ATTACK_RANGE

-- Cooldowns de ataque (moderados para animações)
local PUNCH_COOLDOWN_NORMAL = 0.02
local PUNCH_COOLDOWN_FAST = 0.008
local KICK_COOLDOWN_NORMAL = 0.04
local KICK_COOLDOWN_FAST = 0.015
local SHARINGAN_DURATION = 5

-- ==================== ESTATÍSTICAS DO INIMIGO ====================
local enemyStats = {
    attackCount = 0,
    attackWindow = 0,
    retreatCount = 0,
    retreatWindow = 0,
    totalDistance = 0,
    distanceSamples = 0,
    lastAttackTime = 0,
    lastPosition = nil,
    playStyle = "unknown",
}

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
local postBlockCounter = false
local blockRecoveryUntil = 0

-- Variáveis adaptativas
local currentBlockCooldown = BASE_BLOCK_COOLDOWN
local aggressionLevel = 1.0

-- Aproximação controlada pelo botão
local approachEnabled = true

-- Previsão de fim de defesa
local enemyBlockEndTime = 0

-- ==================== BOTÃO SHARINGAN ====================
local playerGui = player:WaitForChild("PlayerGui")
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SharinganUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local sharinganButton = Instance.new("TextButton")
sharinganButton.Name = "SharinganButton"
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

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(255, 100, 100)
stroke.Thickness = 3
stroke.Parent = sharinganButton

sharinganButton.Activated:Connect(function()
    sharinganActive = true
    sharinganEndTime = tick() + SHARINGAN_DURATION
    sharinganButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    wait(SHARINGAN_DURATION)
    sharinganButton.BackgroundColor3 = Color3.fromRGB(180, 0, 0)
    sharinganActive = false
end)

-- ==================== BOTÃO DE APROXIMAÇÃO ====================
local approachButton = Instance.new("TextButton")
approachButton.Name = "ApproachButton"
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

local approachStroke = Instance.new("UIStroke")
approachStroke.Color = Color3.fromRGB(0, 200, 0)
approachStroke.Thickness = 2
approachStroke.Parent = approachButton

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

-- ==================== LEITURA DE ATAQUE E DEFESA ====================
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

-- ==================== TEMPO RESTANTE DA DEFESA INIMIGA ====================
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
                if remaining > maxRemaining then
                    maxRemaining = remaining
                end
            end
        end
    end
    return maxRemaining
end

-- ==================== AUTO PARRY ====================
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
                if remaining > 0 and remaining < 0.1 then
                    return true
                end
            end
        end
    end

    return false
end

-- ==================== ATUALIZAR ESTATÍSTICAS ====================
local function updateEnemyStats(enemyChar, myRoot)
    if not enemyChar or not myRoot then return end
    local targetRoot = enemyChar:FindFirstChild("HumanoidRootPart") or enemyChar:FindFirstChild("Torso")
    if not targetRoot then return end

    local now = tick()
    local dist = (myRoot.Position - targetRoot.Position).Magnitude

    enemyStats.totalDistance = enemyStats.totalDistance + dist
    enemyStats.distanceSamples = enemyStats.distanceSamples + 1

    if isEnemyAttackingNow(enemyChar) then
        if now - enemyStats.lastAttackTime > 0.5 then
            enemyStats.attackCount = enemyStats.attackCount + 1
            enemyStats.attackWindow = now + 3.0
            enemyStats.lastAttackTime = now
        end
    end
    if now > enemyStats.attackWindow then
        enemyStats.attackCount = 0
    end

    if enemyStats.lastPosition then
        local distBefore = (myRoot.Position - enemyStats.lastPosition).Magnitude
        if dist > distBefore and dist > ATTACK_RANGE then
            if now - enemyStats.retreatWindow > 2.0 then
                enemyStats.retreatCount = enemyStats.retreatCount + 1
                enemyStats.retreatWindow = now + 2.0
            end
        end
    end
    enemyStats.lastPosition = targetRoot.Position

    if math.floor(now / 5) > math.floor((now - 0.1) / 5) then
        local avgDist = enemyStats.distanceSamples > 0 and enemyStats.totalDistance / enemyStats.distanceSamples or 999
        local attackRate = enemyStats.attackCount
        local retreatRate = enemyStats.retreatCount

        if attackRate >= 4 and avgDist < 6 then
            enemyStats.playStyle = "aggressive"
        elseif retreatRate >= 3 and avgDist > 7 then
            enemyStats.playStyle = "kiter"
        elseif attackRate <= 1 and retreatRate <= 1 and avgDist > 5 then
            enemyStats.playStyle = "passive"
        else
            enemyStats.playStyle = "balanced"
        end

        enemyStats.attackCount = math.max(0, enemyStats.attackCount - 1)
        enemyStats.retreatCount = math.max(0, enemyStats.retreatCount - 1)
    end
end

-- ==================== DECISÃO DE BLOQUEIO (INTELIGENTE) ====================
local function shouldBlock(enemyChar, myRoot)
    if not enemyChar or not myRoot then return false end
    local targetRoot = enemyChar:FindFirstChild("HumanoidRootPart") or enemyChar:FindFirstChild("Torso")
    if not targetRoot then return false end

    local dist = (myRoot.Position - targetRoot.Position).Magnitude

    if tick() < blockRecoveryUntil then
        return false
    end

    if shouldParry(enemyChar, myRoot) then
        return true
    end

    if isEnemyAttackingNow(enemyChar) and dist <= 10 then
        enemyStats.lastAttackTime = tick()
        return true
    end

    local vel = targetRoot.Velocity
    if vel and vel.Magnitude > THREAT_SPEED then
        local dirToMe = (myRoot.Position - targetRoot.Position).Unit
        if vel.Unit:Dot(dirToMe) > 0.5 and dist <= THREAT_DISTANCE then
            return true
        end
    end

    if dist <= PREDICTIVE_BLOCK_DISTANCE then
        local toMe = (myRoot.Position - targetRoot.Position).Unit
        local facing = targetRoot.CFrame.LookVector:Dot(toMe)
        if facing > 0.3 and not isEnemyBlockingNow(enemyChar) then
            local moveSpeed = vel and vel.Magnitude or 0
            if moveSpeed > 2 then
                return true
            end
        end
    end

    return false
end

-- ==================== VERIFICAÇÃO DE ALCANCE ====================
local function canAttack(targetRoot, myRoot)
    if not targetRoot or not myRoot then return false end
    local dist = (myRoot.Position - targetRoot.Position).Magnitude
    if dist > ATTACK_RANGE then return false end
    local toEnemy = (targetRoot.Position - myRoot.Position).Unit
    local myFacing = myRoot.CFrame.LookVector:Dot(toEnemy)
    if myFacing < FACING_THRESHOLD then return false end
    return true
end

-- ==================== FUNÇÕES DE PARTE ====================
local function getPart(path)
    local obj = workspace
    for _, name in ipairs(path) do
        obj = obj and obj:FindFirstChild(name)
        if not obj then return nil end
    end
    return obj
end

-- ==================== GOLPES (com partes e fallback) ====================
local function executePunch()
    local part = getPart(PUNCH_PART_PATH)
    if part then
        pcall(function() packetRemote:FireServer(PUNCH_BUFFER_NEW, { part }) end)
    else
        pcall(function() packetRemote:FireServer(PUNCH_SIMPLE) end)
    end
end

local function executeHighKick()
    local part = getPart(HIGHKICK_PART_PATH)
    if part then
        pcall(function() packetRemote:FireServer(HIGHKICK_BUFFER_NEW, { part }) end)
    else
        pcall(function()
            packetRemote:FireServer(Q_PRESS)
            task.wait(0.03)
            packetRemote:FireServer(Q_RELEASE)
        end)
    end
end

local function executeLowKick()
    local part = getPart(LOWKICK_PART_PATH)
    if part then
        pcall(function() packetRemote:FireServer(LOWKICK_BUFFER_NEW, { part }) end)
    else
        pcall(function()
            packetRemote:FireServer(E_PRESS)
            task.wait(0.03)
            packetRemote:FireServer(E_RELEASE)
        end)
    end
end

-- ==================== COMBOS ====================
local comboList = {
    {executePunch, executePunch, executePunch, executeHighKick},
    {executePunch, executePunch, executePunch, executeLowKick},
    {executeHighKick, executePunch, executePunch, executePunch},
    {executeLowKick, executePunch, executePunch, executePunch},
    {executePunch, executeHighKick, executePunch, executeLowKick},
    {executePunch, executeLowKick, executePunch, executeHighKick},
}

local function chooseRandomCombo()
    local index = math.random(1, #comboList)
    currentCombo = comboList[index]
    comboStep = 1
end
chooseRandomCombo()

-- ==================== VERIFICAR SE INIMIGO ESTÁ CAÍDO ====================
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

    local myRoot = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
    if not myRoot then return end

    local target = findEnemy()
    if not target then
        if isBlocking then
            pcall(function() packetRemote:FireServer(BLOCK_RELEASE) end)
            isBlocking = false
        end
        if humanoid then humanoid.WalkSpeed = 16 end
        return
    end

    local targetRoot = target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Torso")
    if not targetRoot then return end

    updateEnemyStats(target, myRoot)

    -- Atualizar tempo restante da defesa inimiga
    if isEnemyBlockingNow(target) then
        enemyBlockEndTime = tick() + getEnemyBlockRemainingTime(target)
    else
        enemyBlockEndTime = 0
    end

    -- Ajustar cooldown do bloqueio
    if enemyStats.playStyle == "aggressive" then
        currentBlockCooldown = 0.02
    elseif enemyStats.playStyle == "kiter" then
        currentBlockCooldown = 0.03
    else
        currentBlockCooldown = BASE_BLOCK_COOLDOWN
    end

    if enemyStats.playStyle == "passive" then
        aggressionLevel = 0.8
    elseif enemyStats.playStyle == "aggressive" then
        aggressionLevel = 1.2
    else
        aggressionLevel = 1.0
    end

    local enemyPosNow = targetRoot.Position
    local distToEnemy = (myRoot.Position - enemyPosNow).Magnitude
    local enemyRetreating = false
    if enemyStats.lastPosition then
        local distBefore = (myRoot.Position - enemyStats.lastPosition).Magnitude
        enemyRetreating = (distToEnemy > distBefore and distToEnemy > ATTACK_RANGE)
    end
    enemyStats.lastPosition = enemyPosNow

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

    -- ==================== DEFESA ====================
    if shouldBlock(target, myRoot) then
        if not isBlocking and (tick() - lastBlock >= currentBlockCooldown) then
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

    -- ==================== CONTRA-ATAQUE PÓS-BLOQUEIO ====================
    if postBlockCounter then
        postBlockCounter = false
        executePunch()
        print("⚡ Contra-ataque pós-bloqueio!")
        return
    end

    -- ==================== PUNIÇÃO ANTI-KITER ====================
    if not isBlocking and (tick() - enemyStats.lastAttackTime) < 0.8 then
        if distToEnemy <= 10 and (tick() - lastPunchTime >= 0.3) then
            lastPunchTime = tick()
            pcall(function()
                executeHighKick()
                executePunch()
            end)
            print("💢 Punindo kiter!")
            return
        end
    end

    -- ==================== ATAQUE ====================
    if not canAttack(targetRoot, myRoot) then return end

    -- 🔥 CHUTE NO FIM DA DEFESA INIMIGA
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

    -- Pega a ação atual do combo e aplica cooldown específico
    local currentAction = currentCombo[comboStep]
    local isPunchAction = (currentAction == executePunch)
    local cooldown
    if isPunchAction then
        cooldown = sharinganActive and PUNCH_COOLDOWN_FAST or PUNCH_COOLDOWN_NORMAL
    else
        cooldown = sharinganActive and KICK_COOLDOWN_FAST or KICK_COOLDOWN_NORMAL
    end

    local lastTime = isPunchAction and lastPunchTime or lastKickTime
    local now = tick()

    if now - lastTime < cooldown then return end

    if isPunchAction then
        lastPunchTime = now
    else
        lastKickTime = now
    end

    currentAction()

    comboStep = comboStep + 1
    if comboStep > #currentCombo then
        chooseRandomCombo()
    end
end)

print("🧠 Buffers corrigidos: chutes e socos com partes + auto parry + spam moderado ativados!")
-- ================================================================
-- AUTO COMBATE ADAPTATIVO + AUTO PARRY ULTRA + OBSERVADOR DE COMBOS
-- VERSÃO ITADORI / TEKKEN
-- ================================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local packetRemote = ReplicatedStorage:WaitForChild("Packet"):WaitForChild("RemoteEvent")

-- ==================== BUFFERS (SUBSTITUÍDOS) ====================
-- Soco (LMB)
local PUNCH_BUFFER = buffer.fromstring("\005\003lmb\000\000\000\000\000")
-- Chute alto (Q)
local HIGHKICK_BUFFER = buffer.fromstring("\005\bkeypress\v\001q\000\000\000\000")
-- Chute baixo (E)
local LOWKICK_BUFFER = buffer.fromstring("\005\bkeypress\v\001e\000\000\000\000")
-- Parry / Bloqueio (F) – agora usando a tecla que você enviou
local PARRY_PRESS = buffer.fromstring("\005\bkeypress\v\001f\000\000\000\000")
local PARRY_RELEASE = buffer.fromstring("\005\bkeyrelease\v\001f\000\000\000\000")

-- ==================== CONFIGURAÇÕES (FORÇA ITADORI) ====================
local DETECTION_RANGE = 60
local ATTACK_RANGE = 8
local KITER_ATTACK_RANGE = 15
local FACING_THRESHOLD = 0.5

-- Parry ultra-rápido (reatividade insana)
local BASE_PARRY_COOLDOWN = 0.0
local BASE_PARRY_PRESS_DURATION = 0.2
local MIN_PARRY_PRESS = 0.15
local MAX_PARRY_PRESS = 0.3
local PARRY_RECOVERY = 0.0
local THREAT_SPEED = 3
local THREAT_DISTANCE = 20
local PREDICTIVE_PARRY_DISTANCE = 15
local WINDUP_ANIMATION_THRESHOLD = 1.0
local ACCELERATION_THRESHOLD = 10

-- Aproximação (mais agressiva)
local FOLLOW_SPEED = 28   -- mais rápido
local FOLLOW_RANGE = KITER_ATTACK_RANGE

-- Cooldowns de ataque reduzidos (ataques mais rápidos = mais "força")
local PUNCH_COOLDOWN_NORMAL = 0.005
local PUNCH_COOLDOWN_FAST = 0.002
local KICK_COOLDOWN_NORMAL = 0.005
local KICK_COOLDOWN_FAST = 0.002
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
    lastVelocity = Vector3.zero,
    lastVelocityTime = 0,
}

-- ==================== ESTADO ====================
local lastPunchTime = 0
local lastKickTime = 0
local sharinganActive = false
local sharinganEndTime = 0
local comboStep = 1
local currentCombo = {}

-- Parry
local lastParryTime = 0
local isParrying = false
local parryReleaseAt = 0
local parryRecoveryUntil = 0
local postParryCounter = false
local currentParryCooldown = BASE_PARRY_COOLDOWN
local currentParryPressDuration = BASE_PARRY_PRESS_DURATION

-- Aproximação
local approachEnabled = true
local enemyBlockEndTime = 0

-- ==================== OBSERVADOR DE COMBOS ====================
local COMBO_TIMEOUT = 1.2
local MIN_COMBO_LENGTH = 2

local currentTarget = nil
local activeAnims = {}
local currentSequence = {}
local lastAttackObserved = 0
local detectedCombos = {}
local learnedComboFunctions = {}
local comboCount = {}

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
    ["Soco"] = "punch",
    ["Chute Alto"] = "highkick",
    ["Chute Baixo"] = "lowkick",
    ["Chute"] = "highkick",
    ["Ataque"] = "punch",
    ["MOVE"] = "punch",
}

-- ==================== UI (sem alterações) ====================
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
Instance.new("UIStroke", sharinganButton).Color = Color3.fromRGB(255,100,100)
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
Instance.new("UIStroke", approachButton).Color = Color3.fromRGB(0,200,0)
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

local observerFrame = Instance.new("Frame")
observerFrame.Size = UDim2.new(0, 200, 0, 170)
observerFrame.Position = UDim2.new(0.02, 0, 0.55, 0)
observerFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
observerFrame.BackgroundTransparency = 0.25
observerFrame.BorderSizePixel = 1
observerFrame.BorderColor3 = Color3.fromRGB(255,255,255)
observerFrame.Active = true
observerFrame.Draggable = true
observerFrame.Parent = screenGui

local observerTitle = Instance.new("TextLabel")
observerTitle.Size = UDim2.new(1, 0, 0, 20)
observerTitle.BackgroundColor3 = Color3.fromRGB(40,40,40)
observerTitle.BackgroundTransparency = 0.2
observerTitle.TextColor3 = Color3.new(1,1,1)
observerTitle.Text = "Combos Aprendidos"
observerTitle.Font = Enum.Font.SourceSansBold
observerTitle.TextSize = 14
observerTitle.Parent = observerFrame

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, 0, 0, 16)
statusLabel.Position = UDim2.new(0, 0, 0, 20)
statusLabel.BackgroundColor3 = Color3.fromRGB(30,30,30)
statusLabel.BackgroundTransparency = 0.3
statusLabel.TextColor3 = Color3.fromRGB(255,200,100)
statusLabel.Text = "Nenhum inimigo"
statusLabel.Font = Enum.Font.SourceSans
statusLabel.TextSize = 12
statusLabel.Parent = observerFrame

local lastActionLabel = Instance.new("TextLabel")
lastActionLabel.Size = UDim2.new(1, 0, 0, 16)
lastActionLabel.Position = UDim2.new(0, 0, 0, 36)
lastActionLabel.BackgroundColor3 = Color3.fromRGB(20,20,20)
lastActionLabel.BackgroundTransparency = 0.3
lastActionLabel.TextColor3 = Color3.fromRGB(150,255,150)
lastActionLabel.Text = "Última ação: --"
lastActionLabel.Font = Enum.Font.SourceSans
lastActionLabel.TextSize = 12
lastActionLabel.Parent = observerFrame

local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Size = UDim2.new(1, 0, 1, -52)
scrollFrame.Position = UDim2.new(0, 0, 0, 52)
scrollFrame.BackgroundColor3 = Color3.fromRGB(15,15,15)
scrollFrame.BackgroundTransparency = 0.5
scrollFrame.BorderSizePixel = 0
scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
scrollFrame.ScrollBarThickness = 4
scrollFrame.Parent = observerFrame

local listLayout = Instance.new("UIListLayout")
listLayout.Parent = scrollFrame
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 2)

local toggleObserverButton = Instance.new("TextButton")
toggleObserverButton.Size = UDim2.new(0, 24, 0, 24)
toggleObserverButton.Position = UDim2.new(1, -28, 0, -28)
toggleObserverButton.BackgroundColor3 = Color3.fromRGB(80,80,80)
toggleObserverButton.BackgroundTransparency = 0.3
toggleObserverButton.TextColor3 = Color3.new(1,1,1)
toggleObserverButton.Text = "–"
toggleObserverButton.Font = Enum.Font.SourceSansBold
toggleObserverButton.TextSize = 16
toggleObserverButton.Parent = screenGui

local observerVisible = true
toggleObserverButton.Activated:Connect(function()
    observerVisible = not observerVisible
    observerFrame.Visible = observerVisible
    if observerVisible then
        toggleObserverButton.Position = UDim2.new(1, -28, 0, -28)
    else
        toggleObserverButton.Position = UDim2.new(1, -28, 0.9, -28)
    end
end)

local function updateObserverUI()
    for _, child in ipairs(scrollFrame:GetChildren()) do
        if child:IsA("TextLabel") then
            child:Destroy()
        end
    end

    if not comboCount then return end

    local sorted = {}
    for combo, count in pairs(comboCount) do
        table.insert(sorted, {combo = combo, count = count})
    end
    table.sort(sorted, function(a,b) return a.count > b.count end)

    for i, entry in ipairs(sorted) do
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 0, 20)
        label.BackgroundColor3 = Color3.fromRGB(25,25,25)
        label.BackgroundTransparency = 0.4
        label.TextColor3 = Color3.new(1,1,1)
        label.Text = ("%d. %s  (%dx)"):format(i, entry.combo, entry.count)
        label.Font = Enum.Font.SourceSans
        label.TextSize = 12
        label.TextWrapped = true
        label.Parent = scrollFrame
    end

    local totalHeight = #sorted * 22
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, math.max(totalHeight, 100))
end

-- ==================== FUNÇÕES DO OBSERVADOR ====================
local function resetComboObserver(newTarget)
    currentTarget = newTarget
    activeAnims = {}
    currentSequence = {}
    lastAttackObserved = 0
    if newTarget then
        local plr = Players:GetPlayerFromCharacter(newTarget)
        statusLabel.Text = plr and plr.Name or newTarget.Name
    else
        statusLabel.Text = "Nenhum inimigo"
    end
end

local function finalizeLearnedCombo()
    if #currentSequence >= MIN_COMBO_LENGTH then
        local comboStr = table.concat(currentSequence, " > ")
        comboCount[comboStr] = (comboCount[comboStr] or 0) + 1

        if not table.find(detectedCombos, comboStr) then
            table.insert(detectedCombos, comboStr)
            print("⚔️ Aprendido combo do inimigo: " .. comboStr)

            local newCombo = {}
            local valid = true
            for _, attackType in ipairs(currentSequence) do
                local funcName = attackFunctionMap[attackType]
                local func = nil
                if funcName == "punch" then func = executePunch
                elseif funcName == "highkick" then func = executeHighKick
                elseif funcName == "lowkick" then func = executeLowKick
                else func = executePunch end
                if func then
                    table.insert(newCombo, func)
                else
                    valid = false
                    break
                end
            end
            if valid and #newCombo >= 2 then
                table.insert(learnedComboFunctions, newCombo)
            end
        end
        updateObserverUI()
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
                        lastActionLabel.Text = "Última ação: " .. classified
                    end
                end
            end
        else
            activeAnims[track] = nil
        end
    end

    for track in pairs(activeAnims) do
        if not track.IsPlaying or not track.Parent then
            activeAnims[track] = nil
        end
    end
end

-- ==================== FUNÇÕES DE ATAQUE ====================
function executePunch()
    pcall(function() packetRemote:FireServer(PUNCH_BUFFER) end)
end

function executeHighKick()
    pcall(function() packetRemote:FireServer(HIGHKICK_BUFFER) end)
end

function executeLowKick()
    pcall(function() packetRemote:FireServer(LOWKICK_BUFFER) end)
end

-- ==================== COMBOS PRÉ-DEFINIDOS (ESTILO TEKKEN / ITADORI) ====================
-- Sequências agressivas com mistura de socos e chutes altos/baixos
local fallbackCombos = {
    {executeHighKick, executePunch, executeHighKick, executePunch, executeLowKick},
    {executePunch, executeHighKick, executePunch, executeLowKick, executeHighKick},
    {executeLowKick, executePunch, executeHighKick, executePunch, executeHighKick},
    {executePunch, executePunch, executeHighKick, executePunch, executeLowKick},
    {executeHighKick, executeLowKick, executePunch, executeHighKick, executePunch},
    {executePunch, executeHighKick, executeLowKick, executePunch, executeHighKick},
    {executePunch, executePunch, executePunch, executeHighKick}, -- socos rápidos + chute alto
    {executeHighKick, executePunch, executePunch, executeLowKick},
    {executeLowKick, executePunch, executeHighKick, executePunch},
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
    if now > enemyStats.attackWindow then enemyStats.attackCount = 0 end

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

    if now - enemyStats.lastVelocityTime > 0.05 then
        enemyStats.lastVelocity = targetRoot.Velocity
        enemyStats.lastVelocityTime = now
    end

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

-- ==================== DECISÃO DE PARRY (ULTRA RÁPIDA) ====================
local function shouldParry(enemyChar, myRoot)
    if not enemyChar or not myRoot then return false end
    local targetRoot = enemyChar:FindFirstChild("HumanoidRootPart") or enemyChar:FindFirstChild("Torso")
    if not targetRoot then return false end

    if tick() < parryRecoveryUntil then return false end

    local dist = (myRoot.Position - targetRoot.Position).Magnitude
    local threatLevel = sharinganActive and 2.5 or 1.0

    if isEnemyAttackingNow(enemyChar) then
        local hum = enemyChar:FindFirstChildOfClass("Humanoid")
        if hum then
            for _, track in ipairs(hum:GetPlayingAnimationTracks()) do
                local anim = track.Animation
                if anim and track.IsPlaying then
                    local name = string.lower(anim.AnimationId)
                    if name:find("attack") or name:find("punch") or name:find("kick") or name:find("soco") or name:find("chute") or name:find("hit") then
                        if track.TimePosition <= WINDUP_ANIMATION_THRESHOLD * track.Length and dist <= 25 * threatLevel then
                            enemyStats.lastAttackTime = tick()
                            return true
                        end
                    end
                end
            end
        end
        if dist <= 12 then
            enemyStats.lastAttackTime = tick()
            return true
        end
    end

    local vel = targetRoot.Velocity
    if vel then
        local speed = vel.Magnitude
        if speed > THREAT_SPEED then
            local dirToMe = (myRoot.Position - targetRoot.Position).Unit
            if vel.Unit:Dot(dirToMe) > 0.05 and dist <= THREAT_DISTANCE * threatLevel then
                return true
            end
        end

        local now = tick()
        if enemyStats.lastVelocity and enemyStats.lastVelocityTime and (now - enemyStats.lastVelocityTime) > 0.05 then
            local deltaV = (vel - enemyStats.lastVelocity).Magnitude
            local deltaT = now - enemyStats.lastVelocityTime
            local accel = deltaV / deltaT
            if accel > ACCELERATION_THRESHOLD then
                local dirToMe = (myRoot.Position - targetRoot.Position).Unit
                if vel.Unit:Dot(dirToMe) > 0.03 and dist <= THREAT_DISTANCE * threatLevel then
                    return true
                end
            end
        end
        enemyStats.lastVelocity = vel
        enemyStats.lastVelocityTime = now
    end

    if dist <= PREDICTIVE_PARRY_DISTANCE * threatLevel then
        local toMe = (myRoot.Position - targetRoot.Position).Unit
        local facing = targetRoot.CFrame.LookVector:Dot(toMe)
        if facing > 0.05 and not isEnemyBlockingNow(enemyChar) then
            return true
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
        if isParrying then
            pcall(function() packetRemote:FireServer(PARRY_RELEASE) end)
            isParrying = false
        end
        return
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
        if isParrying then
            pcall(function() packetRemote:FireServer(PARRY_RELEASE) end)
            isParrying = false
        end
        if humanoid then humanoid.WalkSpeed = 16 end
        return
    end

    local targetRoot = target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Torso")
    if not targetRoot then return end

    if target ~= currentTarget then
        resetComboObserver(target)
    end
    observeEnemyCombos(target)

    updateEnemyStats(target, myRoot)

    if isEnemyBlockingNow(target) then
        enemyBlockEndTime = tick() + getEnemyBlockRemainingTime(target)
    else
        enemyBlockEndTime = 0
    end

    if sharinganActive then
        currentParryCooldown = 0.0
        currentParryPressDuration = MAX_PARRY_PRESS
    elseif enemyStats.playStyle == "aggressive" then
        currentParryCooldown = 0.0
        currentParryPressDuration = MAX_PARRY_PRESS
    elseif enemyStats.playStyle == "kiter" then
        currentParryCooldown = 0.0
        currentParryPressDuration = BASE_PARRY_PRESS_DURATION
    else
        currentParryCooldown = 0.0
        currentParryPressDuration = BASE_PARRY_PRESS_DURATION
    end

    local distToEnemy = (myRoot.Position - targetRoot.Position).Magnitude

    local shouldApproach = false
    if approachEnabled and not isParrying and not shouldParry(target, myRoot) then
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

    if shouldParry(target, myRoot) then
        if not isParrying and (tick() - lastParryTime >= currentParryCooldown) then
            lastParryTime = tick()
            pcall(function() packetRemote:FireServer(PARRY_PRESS) end)
            isParrying = true
            parryReleaseAt = tick() + currentParryPressDuration
            postParryCounter = false
            print("🛡️ Parry ultra-rápido!")
        end
        return
    end

    if postParryCounter then
        postParryCounter = false
        executePunch()
        print("⚡ Contra-ataque pós-parry!")
        return
    end

    if not isParrying and (tick() - enemyStats.lastAttackTime) < 0.8 then
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

    if not canAttack(targetRoot, myRoot) then return end

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

print("🧠 Auto parry ultra (tecla F) + combos estilo Itadori/Tekken ativados!")
local addonName, ns = ...
RPC = {}
RPC.DebugMode = false

-- ----------------------------------------------------------------------------
-- 配置与变量
-- ----------------------------------------------------------------------------
local RPC_VERSION = "0.1.8"

-- ----------------------------------------------------------------------------
-- 数据导入
-- ----------------------------------------------------------------------------
-- 从 ns.Data 导入数据，保持本地变量引用以便后续代码使用
local BuffDefs = ns.Data.BuffDefs
local CCS10Specs = ns.Data.CCS10Specs
local CS23Specs = ns.Data.CS23Specs
local CCS10DetectionPool = ns.Data.CCS10DetectionPool
local ClassOrder = ns.Data.ClassOrder
local ClassNamesCN = ns.Data.ClassNamesCN
local SpecNamesCN = ns.Data.SpecNamesCN
local HeuristicRules = ns.Data.HeuristicRules

-- 将 BuffDefs 挂载到 RPC 表上，保持接口一致性 (如果有外部调用)
RPC.BuffDefs = BuffDefs

local function GetSpellIcon(id)
    local _, _, icon = GetSpellInfo(id)
    return icon
end

local function GetUnitRole(unit)
    if _G.UnitGroupRolesAssigned then return _G.UnitGroupRolesAssigned(unit) end
    return "NONE"
end

-- ----------------------------------------------------------------------------
-- 数据驱动表 (已移至 data.lua)
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- CSS10 数据定义 (已移至 data.lua)
-- ----------------------------------------------------------------------------
-- local CCS10Specs (imported from data.lua)

-- ----------------------------------------------------------------------------
-- CS23 数据定义 (已移至 data.lua)
-- ----------------------------------------------------------------------------
-- local CS23Specs (imported from data.lua)

-- ----------------------------------------------------------------------------
-- 检测池定义 (已移至 data.lua)
-- ----------------------------------------------------------------------------
-- local CCS10DetectionPool (imported from data.lua)

-- ----------------------------------------------------------------------------
-- 核心辅助函数 (定义顺序关键：Helpers -> GetSpecCount -> GetPoolCount)
-- ----------------------------------------------------------------------------

-- 1. Buff 名称缓存
local SpellCache = {}
local function GetSpellName(id)
    if not id then return nil end
    if SpellCache[id] then return SpellCache[id] end
    local name = GetSpellInfo(id)
    if name then SpellCache[id] = name end
    return name
end

-- 2. 检测单位是否有指定 ID 的 Buff
local function UnitHasBuff(unit, spellIDs, checkOwn)
    if not spellIDs then return false end
    if type(spellIDs) == "number" then spellIDs = {spellIDs} end
    
    local i = 1
    while true do
        local name, _, _, _, _, _, _, source, _, _, spellId = UnitAura(unit, i, "HELPFUL")
        if not name then break end
        
        -- Check Source if required
        local sourceMatch = true
        if checkOwn then
            if not source or not UnitIsUnit(source, unit) then
                sourceMatch = false
            end
        end
        
        if sourceMatch then
            for _, id in ipairs(spellIDs) do
                if spellId == id then return true end
                if name == GetSpellName(id) then return true end
            end
        end
        i = i + 1
    end
    return false
end

-- 3. 启发式专精检测 (数据驱动版)
local function CheckSpecHeuristic(unit, class, specIndex)
    if not specIndex then return true end -- Class match only
    
    local classRules = HeuristicRules[class]
    if not classRules then return false end
    
    local specRules = classRules[specIndex]
    if not specRules then return false end
    
    local role = GetUnitRole(unit)
    
    -- 遍历规则组 (OR 关系: 只要有一组满足即返回 true)
    for _, conditions in ipairs(specRules) do
        local match = true
        
        -- 遍历组内条件 (AND 关系: 所有条件都必须满足)
        -- 1. Role
        if match and conditions.role and conditions.role ~= role then
            match = false
        end

        -- 1.5. Not Role
        if match and conditions.notRole and conditions.notRole == role then
            match = false
        end
        
        -- 2. PowerType
        if match and conditions.powerType then
            if UnitPowerType(unit) ~= conditions.powerType then match = false end
        end
        
        -- 3. Not PowerType
        if match and conditions.notPowerType then
            if UnitPowerType(unit) == conditions.notPowerType then match = false end
        end
        
        -- 4. Buffs (Has ANY of the list)
        if match and conditions.buffs then
            if not UnitHasBuff(unit, conditions.buffs, conditions.checkOwn) then match = false end
        end
        
        -- 5. No Buffs (Has NONE of the list)
        if match and conditions.noBuffs then
            if UnitHasBuff(unit, conditions.noBuffs) then match = false end
        end
        
        -- 6. Min HP

        if match and conditions.minHP then
            if UnitHealthMax(unit) <= conditions.minHP then match = false end
        end
        
        -- 7. Min Mana
        if match and conditions.minMana then
            if UnitPowerMax(unit, 0) <= conditions.minMana then match = false end
        end
        
        -- 8. Max Mana
        if match and conditions.maxMana then
            if UnitPowerMax(unit, 0) >= conditions.maxMana then match = false end
        end
        
        if match then return true end
    end
    
    return false
end

-- 4. 专精统计函数 (包含 Inspect 逻辑)
local SpecCache = {} -- [unitGUID] = {class=class, spec=specIndex, timestamp=time()}

-- ----------------------------------------------------------------------------
-- Inspect Queue 逻辑 (Move up to be available for GetSpecCount)
-- ----------------------------------------------------------------------------
local InspectQueue = {}
local InspectFrame = CreateFrame("Frame")
InspectFrame:Hide()
InspectFrame:SetScript("OnUpdate", function(self, elapsed)
    self.timer = (self.timer or 0) + elapsed
    if self.timer > 1.0 then -- Inspect one every 1 second
        self.timer = 0
        if #InspectQueue > 0 then
            local unit = table.remove(InspectQueue, 1)
            if UnitExists(unit) and CanInspect(unit) then
                NotifyInspect(unit)
            end
        else
            self:Hide()
        end
    end
end)

local function QueueInspectUnit(unit)
    if not unit then return end
    
    -- Check if already in queue to avoid duplicates
    for _, u in ipairs(InspectQueue) do
        if UnitIsUnit(u, unit) then return end
    end
    
    table.insert(InspectQueue, unit)
    InspectFrame:Show()
end

-- 缓存清理事件
local CacheEventFrame = CreateFrame("Frame")
CacheEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
CacheEventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
CacheEventFrame:RegisterEvent("GROUP_LEFT")
CacheEventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" or event == "GROUP_LEFT" then
        SpecCache = {}
        InspectQueue = {} -- Clear queue
        InspectFrame:Hide()
    elseif event == "GROUP_ROSTER_UPDATE" then
        -- 清理不在队伍中的成员缓存
        if not IsInGroup() then
            SpecCache = {}
            InspectQueue = {}
            InspectFrame:Hide()
            return
        end
        
        local currentGUIDs = {}
        local numGroupMembers = GetNumGroupMembers()
        local inRaid = IsInRaid()
        
        for i = 1, numGroupMembers do
            local unit = "raid" .. i
            if not inRaid then
                if i == 1 then unit = "player" else unit = "party" .. (i - 1) end
            end
            if UnitExists(unit) then
                currentGUIDs[UnitGUID(unit)] = true
                
                -- Auto-queue new members if not cached
                if not SpecCache[UnitGUID(unit)] and not UnitIsUnit(unit, "player") then
                     QueueInspectUnit(unit)
                end
            end
        end
        
        for guid in pairs(SpecCache) do
            if not currentGUIDs[guid] then
                SpecCache[guid] = nil
            end
        end
    end
end)

-- 3. 辅助检测函数
local function IsUnitSpecMatch(unit, classFileName, specIndex)
    if not UnitExists(unit) then return false end
    local _, unitClass = UnitClass(unit)
    if unitClass ~= classFileName then return false end
    
    -- 0. Role Override (One-vote confirmation / 一票确定)
    -- 优先级最高：如果职责是坦克，且检测目标是该职业的坦克专精，直接返回 true
    local role = GetUnitRole(unit)
    
    -- DKT Special: Frost Presence (48266) -> Treat as Tank Role equivalent for Spec checks
    -- 如果开启冰脸，强制认定为DKT (Spec 1)，且排除输出DK (Spec 2/3)
    if unitClass == "DEATHKNIGHT" and UnitHasBuff(unit, {48266}) then
        if specIndex == 1 then return true end
        if specIndex == 2 or specIndex == 3 then return false end
    end
    
    if role == "TANK" then
        -- Positive Match: Tank Spec
        if (unitClass == "PALADIN" and specIndex == 2) or
           (unitClass == "WARRIOR" and specIndex == 3) or
           (unitClass == "DEATHKNIGHT" and specIndex == 1) then
            return true
        end
        
        -- Negative Match: Exclude DPS Specs for Tank Role
        -- 如果职责是坦克，则绝不应被识别为该职业的输出专精 (避免双亮)
        if (unitClass == "PALADIN" and (specIndex == 1 or specIndex == 3)) or
           (unitClass == "WARRIOR" and (specIndex == 1 or specIndex == 2)) or
           (unitClass == "DEATHKNIGHT" and (specIndex == 2 or specIndex == 3)) then
            return false
        end

        -- Druid Special: Bear (Spec 2) matches Tank Role
        if unitClass == "DRUID" and specIndex == 2 then
             return true
        end
    end

    -- DPS DK Special Override: Role=DAMAGER or Blood(48263)/Unholy(48265) -> DPS DK
    if unitClass == "DEATHKNIGHT" and (specIndex == 2 or specIndex == 3) then
         if role == "DAMAGER" or UnitHasBuff(unit, {48263, 48265}) then
             return true
         end
    end


    if not specIndex then return true end
    
    -- Special handling for player to use direct API
    if UnitIsUnit(unit, "player") then
        -- WotLK Classic: 基于天赋投入点数判断
        local maxPoints = -1
        local bestSpec = 1
        
        for i = 1, 3 do
             local points = 0
             if GetTalentTabInfo then
                 _, _, points = GetTalentTabInfo(i)
             end
             points = points or 0
             
             if points > maxPoints then
                 maxPoints = points
                 bestSpec = i
             end
        end
        
        return bestSpec == specIndex
    end
    
    local guid = UnitGUID(unit)
    local cached = SpecCache[guid]
    
    -- 1. Cache Check
    if cached and cached.class == classFileName and cached.spec then
        return cached.spec == specIndex
    end
    
    -- 2. Inspect API Check
    local id = GetInspectSpecialization(unit)
    if id and id > 0 then
        local classID = select(3, UnitClass(unit))
        local foundSpecIndex = nil
        for s = 1, 4 do
            local _, _, _, _, _, _, specID = GetSpecializationInfoForClassID(classID, s)
            if specID == id then
                foundSpecIndex = s
                break
            end
        end
        
        if foundSpecIndex then
            SpecCache[guid] = {class=classFileName, spec=foundSpecIndex, timestamp=time()}
            return foundSpecIndex == specIndex
        end
    end
    
    -- 3. Heuristic Check
    if CheckSpecHeuristic(unit, classFileName, specIndex) then
        if not UnitIsUnit(unit, "player") then QueueInspectUnit(unit) end
        return true
    end
    
    -- 4. Fail & Queue
    if not UnitIsUnit(unit, "player") then QueueInspectUnit(unit) end
    return false
end

-- 4. 专精统计函数
local function GetSpecCount(classFileName, specIndex)
    local count = 0
    local numGroupMembers = GetNumGroupMembers and GetNumGroupMembers() or 0
    
    if numGroupMembers == 0 then
        -- Solo case
        if IsUnitSpecMatch("player", classFileName, specIndex) then count = 1 end
    else
        local inRaid = IsInRaid and IsInRaid()
        for i = 1, numGroupMembers do
            local unit = "raid" .. i
            if not inRaid then
                if i == 1 then unit = "player" else unit = "party" .. (i - 1) end
            end
            
            if IsUnitSpecMatch(unit, classFileName, specIndex) then
                count = count + 1
            end
        end
    end
    return count
end

-- 获取符合检测池规则的成员列表
local function GetPoolMembers(poolKey, primaryClass, primarySpec)
    local members = {}
    local pool = CCS10DetectionPool[poolKey]
    if not pool then return members end
    
    local numGroupMembers = GetNumGroupMembers and GetNumGroupMembers() or 0
    
    local function CheckAndAdd(unit)
        if UnitExists(unit) then
            for _, rule in ipairs(pool) do
                if IsUnitSpecMatch(unit, rule.class, rule.spec) then
                    local name = UnitName(unit)
                    local _, class = UnitClass(unit)
                    local color = RAID_CLASS_COLORS[class]
                    if color then
                        name = string.format("|cff%02x%02x%02x%s|r", color.r*255, color.g*255, color.b*255, name)
                    end
                    
                    local isSubstitute = false
                    if primaryClass and class ~= primaryClass then
                        isSubstitute = true
                    elseif primarySpec and rule.spec and primarySpec ~= rule.spec then
                        isSubstitute = true
                    end
                    
                    if isSubstitute then
                        local specName = ""
                        if rule.spec and SpecNamesCN[class] and SpecNamesCN[class][rule.spec] then
                            specName = SpecNamesCN[class][rule.spec]
                        else
                            specName = ClassNamesCN[class] or class
                        end
                        name = name .. " (" .. specName .. "替代)"
                    end
                    
                    table.insert(members, name)
                    return true -- Found match for this unit
                end
            end
        end
        return false
    end

    if numGroupMembers == 0 then
        -- Solo
        CheckAndAdd("player")
    else
        local inRaid = IsInRaid and IsInRaid()
        for i = 1, numGroupMembers do
            local unit = "raid" .. i
            if not inRaid then
                if i == 1 then unit = "player" else unit = "party" .. (i - 1) end
            end
            CheckAndAdd(unit)
        end
    end
    return members
end

-- 5. 检测池统计函数
local function GetPoolCount(poolKey)
    if GetPoolMembers then
        local members = GetPoolMembers(poolKey)
        return #members
    end
    return 0
end

-- ----------------------------------------------------------------------------
-- UI 框架构建
-- ----------------------------------------------------------------------------
local MainFrame = CreateFrame("Frame", "RPC_MainFrame", UIParent, "BackdropTemplate")
MainFrame:SetWidth(260) 
MainFrame:SetHeight(430) -- Increased height for role stats
MainFrame:SetPoint("CENTER")
MainFrame:SetMovable(true)
MainFrame:EnableMouse(true)
MainFrame:RegisterForDrag("LeftButton")
MainFrame:SetFrameStrata("DIALOG") 
MainFrame:SetClampedToScreen(true)
MainFrame:SetScript("OnDragStart", MainFrame.StartMoving)
MainFrame:SetScript("OnDragStop", MainFrame.StopMovingOrSizing)

MainFrame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    tile = true, tileSize = 16, edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 }
})
MainFrame:SetBackdropColor(0, 0, 0, 0.8)
MainFrame:SetBackdropBorderColor(0, 0, 0, 0.3)
MainFrame:Hide()

local TitleBar = CreateFrame("Frame", nil, MainFrame, "BackdropTemplate")
TitleBar:SetPoint("TOPLEFT", MainFrame, "TOPLEFT", 1, -1)
TitleBar:SetPoint("TOPRIGHT", MainFrame, "TOPRIGHT", -1, -1)
TitleBar:SetHeight(25)
TitleBar:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = nil,
    tile = true, tileSize = 16, edgeSize = 0,
    insets = { left = 0, right = 0, top = 0, bottom = 0 }
})
TitleBar:SetBackdropColor(0.1, 0.1, 0.1, 0.9)

local Title = TitleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
Title:SetPoint("CENTER", TitleBar, "CENTER", 0, 0)
Title:SetText("ahhz's RPC " .. RPC_VERSION)

local CloseButton = CreateFrame("Button", nil, TitleBar, "UIPanelCloseButton")
CloseButton:SetPoint("RIGHT", TitleBar, "RIGHT", 2, 1)
CloseButton:SetWidth(35) 
CloseButton:SetHeight(35)
CloseButton:SetScript("OnClick", function() MainFrame:Hide() end)

-- 职业统计区域
local ClassFrame = CreateFrame("Frame", nil, MainFrame)
ClassFrame:SetPoint("TOP", MainFrame, "TOP", 0, -25)
ClassFrame:SetWidth(250)
ClassFrame:SetHeight(60)

-- local ClassOrder (imported from data.lua)
-- local ClassNamesCN (imported from data.lua)
-- local SpecNamesCN (imported from data.lua)

local ClassIcons = {}
local CELL_WIDTH = 250 / 5
local CELL_HEIGHT = 60 / 2

for i, class in ipairs(ClassOrder) do
    local frame = CreateFrame("Frame", nil, ClassFrame, "BackdropTemplate")
    local row = math.floor((i - 1) / 5)
    local col = (i - 1) % 5
    
    frame:SetWidth(CELL_WIDTH)
    frame:SetHeight(CELL_HEIGHT)
    frame:SetPoint("TOPLEFT", ClassFrame, "TOPLEFT", col * CELL_WIDTH, -row * CELL_HEIGHT)
    
    local color = RAID_CLASS_COLORS[class]
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    frame:SetBackdropColor(color.r, color.g, color.b, 0.5)
    frame:SetBackdropBorderColor(0, 0, 0, 1)
    
    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER")
    text:SetJustifyH("CENTER")
    local font, _, flags = text:GetFont()
    text:SetFont(font, 14, flags)
    text:SetText(ClassNamesCN[class])
    frame.classText = text
    frame.count = 0

    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("当前" .. ClassNamesCN[class] .. " " .. (self.count or 0) .. " 人", 1, 1, 1)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    ClassIcons[class] = frame
end

-- CCS10 区域
-- 2026-02-17 0.1.6-版本3：专精检测功能待查、验。
local CCS10Title = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
CCS10Title:SetPoint("TOPLEFT", ClassFrame, "BOTTOMLEFT", 0, -10)
CCS10Title:SetText("25人保底配置")
local font, _, flags = CCS10Title:GetFont()
CCS10Title:SetFont(font, 14, flags)
CCS10Title:SetJustifyH("LEFT")

local CCS10Frame = CreateFrame("Frame", nil, MainFrame)
CCS10Frame:SetPoint("TOPLEFT", ClassFrame, "BOTTOMLEFT", 0, -30)
CCS10Frame:SetWidth(250)
CCS10Frame:SetHeight(25)
local BUFF_CELL_WIDTH = 250 / 10
local BUFF_CELL_HEIGHT = 25

-- CS23 区域
local CS23Title = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
CS23Title:SetPoint("TOPLEFT", CCS10Frame, "BOTTOMLEFT", 0, -10)
CS23Title:SetText("23人宝库推荐配置")
local font, _, flags = CS23Title:GetFont()
CS23Title:SetFont(font, 14, flags)
CS23Title:SetJustifyH("LEFT")

local CS23Frame = CreateFrame("Frame", nil, MainFrame)
CS23Frame:SetPoint("TOPLEFT", CCS10Frame, "BOTTOMLEFT", 0, -30)
CS23Frame:SetWidth(250)
CS23Frame:SetHeight(75) -- 3 rows

local CS23_CELL_WIDTH = 250 / 10
local CS23_CELL_HEIGHT = 25

-- Role Stats Frame (Moved below CS23Frame)
local RoleStatsFrame = CreateFrame("Frame", nil, MainFrame)
RoleStatsFrame:SetPoint("TOPLEFT", CS23Frame, "BOTTOMLEFT", 0, -10)
RoleStatsFrame:SetWidth(250)
RoleStatsFrame:SetHeight(40) -- Increased height for 2 lines

local RoleStatsText = RoleStatsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
local font, _, flags = RoleStatsText:GetFont()
RoleStatsText:SetFont(font, 14, flags)
RoleStatsText:SetPoint("TOPLEFT", RoleStatsFrame, "TOPLEFT", 0, 0)
RoleStatsText:SetJustifyH("LEFT")

local StatusStatsText = RoleStatsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
StatusStatsText:SetFont(font, 14, flags)
StatusStatsText:SetPoint("TOPLEFT", RoleStatsText, "BOTTOMLEFT", 0, -2)
StatusStatsText:SetJustifyH("LEFT")

-- 调试模式开关
local DebugCheckButton = CreateFrame("CheckButton", nil, MainFrame, "ChatConfigCheckButtonTemplate")
DebugCheckButton:SetPoint("TOPLEFT", RoleStatsFrame, "BOTTOMLEFT", 0, 0)
DebugCheckButton:SetSize(24, 24)
DebugCheckButton.tooltip = "显示详细的检测名单"
DebugCheckButton:SetScript("OnClick", function(self)
    RPC.DebugMode = self:GetChecked()
end)

local DebugCheckLabel = DebugCheckButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
DebugCheckLabel:SetPoint("LEFT", DebugCheckButton, "RIGHT", 5, 0)
DebugCheckLabel:SetText("调试模式")

local function UpdateRoleStats()
    local numGroupMembers = 0
    if GetNumGroupMembers then
        numGroupMembers = GetNumGroupMembers()
    elseif IsInRaid and IsInRaid() then
        numGroupMembers = GetNumRaidMembers()
    elseif IsInGroup and IsInGroup() then
        numGroupMembers = GetNumPartyMembers() + 1
    elseif GetNumPartyMembers and GetNumPartyMembers() > 0 then
        numGroupMembers = GetNumPartyMembers() + 1
    end
    
    local tank, healer, dps = 0, 0, 0
    local online, afk, offline, dead = 0, 0, 0, 0
    
    if numGroupMembers > 0 then
        local inRaid = IsInRaid and IsInRaid()
        for i = 1, numGroupMembers do
            local unit = "raid" .. i
            if not inRaid then
                if i == 1 then unit = "player" else unit = "party" .. (i - 1) end
            end
            if UnitExists(unit) then
                -- Role stats
                local role = GetUnitRole(unit)
                if role == "TANK" then tank = tank + 1
                elseif role == "HEALER" then healer = healer + 1
                elseif role == "DAMAGER" then dps = dps + 1 end
                
                -- Status stats
                if UnitIsDeadOrGhost(unit) then
                    dead = dead + 1
                end
                
                if not UnitIsConnected(unit) then
                    offline = offline + 1
                elseif UnitIsAFK(unit) then
                    afk = afk + 1
                else
                    online = online + 1
                end
            end
        end
    else
        -- Solo
        local role = GetUnitRole("player")
        if role == "TANK" then tank = 1
        elseif role == "HEALER" then healer = 1
        elseif role == "DAMAGER" then dps = 1 end
        
        if UnitIsDeadOrGhost("player") then dead = 1 end
        if UnitIsAFK("player") then afk = 1 else online = 1 end
        
        numGroupMembers = 1
    end
    
    local tankIcon = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:14:14:0:0:64:64:0:19:22:41|t"
    local healerIcon = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:14:14:0:0:64:64:20:39:1:20|t"
    local dpsIcon = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:14:14:0:0:64:64:20:39:22:41|t"
    
    RoleStatsText:SetText(string.format("在团%d人:  %s%d  %s%d  %s%d", numGroupMembers, tankIcon, tank, healerIcon, healer, dpsIcon, dps))
    StatusStatsText:SetText(string.format("正常%d人，暂离%d人，离线%d人，死亡%d人", online, afk, offline, dead))
end

local BuffCells = {}
for i, specData in ipairs(CCS10Specs) do
    local cell = CreateFrame("Frame", nil, CCS10Frame, "BackdropTemplate")
    cell:SetWidth(BUFF_CELL_WIDTH)
    cell:SetHeight(BUFF_CELL_HEIGHT)
    cell:SetPoint("LEFT", (i - 1) * BUFF_CELL_WIDTH, 0)
    
    cell:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    cell:EnableMouse(true)
    cell:SetBackdropColor(0, 0, 0, 0.5)
    cell:SetBackdropBorderColor(0, 0, 0, 1)
    
    local icon = cell:CreateTexture(nil, "ARTWORK")
    icon:SetSize(21, 21)
    icon:SetPoint("CENTER")
    icon:SetTexture(specData.icon)
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    cell.icon = icon
    
    icon:SetDesaturated(true)
    icon:SetVertexColor(0.5, 0.5, 0.5, 1)
    
    cell:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        
        -- 此处 GetPoolCount 已正确定义
        local count = 0
        if specData.key and GetPoolCount then
             count = GetPoolCount(specData.key)
        end
        
        GameTooltip:SetText(specData.name .. " (检测到 " .. count .. " 人)", 1, 1, 1)
        
        if specData.desc then
            GameTooltip:AddLine(specData.desc, 1, 0.82, 0)
        end
        
        if specData.key and CCS10DetectionPool and CCS10DetectionPool[specData.key] then
             GameTooltip:AddLine(" ")
             GameTooltip:AddLine("检测规则:", 0.8, 0.8, 0.8)
             for _, rule in ipairs(CCS10DetectionPool[specData.key]) do
                 local desc = rule.class
                 if rule.spec then desc = desc .. " (专精" .. rule.spec .. ")" end
                 GameTooltip:AddLine("- " .. desc, 0.6, 0.6, 0.6)
             end
             
             if GetPoolMembers and RPC.DebugMode then
                 local members = GetPoolMembers(specData.key, specData.class, specData.spec)
                 if #members > 0 then
                     GameTooltip:AddLine(" ")
                     GameTooltip:AddLine("调试模式名单:", 0.8, 0.8, 0.8)
                     for _, name in ipairs(members) do
                         GameTooltip:AddLine("- " .. name, 1, 1, 1)
                     end
                 end
             end
        end
        
        GameTooltip:Show()
    end)
    cell:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    BuffCells[i] = cell
end
CCS10Frame.cells = BuffCells

local CS23Cells = {}
for i, specData in ipairs(CS23Specs) do
    local cell = CreateFrame("Frame", nil, CS23Frame, "BackdropTemplate")
    local row = math.floor((i - 1) / 10)
    local col = (i - 1) % 10
    
    cell:SetWidth(CS23_CELL_WIDTH)
    cell:SetHeight(CS23_CELL_HEIGHT)
    cell:SetPoint("TOPLEFT", col * CS23_CELL_WIDTH, -row * CS23_CELL_HEIGHT)
    
    cell:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    cell:EnableMouse(true)
    cell:SetBackdropColor(0, 0, 0, 0.5)
    cell:SetBackdropBorderColor(0, 0, 0, 1)
    
    local icon = cell:CreateTexture(nil, "ARTWORK")
    icon:SetSize(21, 21)
    icon:SetPoint("CENTER")
    icon:SetTexture(specData.icon)
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    cell.icon = icon
    
    icon:SetDesaturated(true)
    icon:SetVertexColor(0.5, 0.5, 0.5, 1)
    
    cell:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        
        local count = 0
        if specData.key and GetPoolCount then
             count = GetPoolCount(specData.key)
        end
        
        GameTooltip:SetText(specData.name .. " (检测到 " .. count .. " 人)", 1, 1, 1)
        
        if specData.desc then
            GameTooltip:AddLine(specData.desc, 1, 0.82, 0)
        end
        
        if specData.key and CCS10DetectionPool and CCS10DetectionPool[specData.key] then
             GameTooltip:AddLine(" ")
             GameTooltip:AddLine("检测规则:", 0.8, 0.8, 0.8)
             for _, rule in ipairs(CCS10DetectionPool[specData.key]) do
                 local desc = rule.class
                 if rule.spec then desc = desc .. " (专精" .. rule.spec .. ")" end
                 GameTooltip:AddLine("- " .. desc, 0.6, 0.6, 0.6)
             end
             
             if GetPoolMembers and RPC.DebugMode then
                 local members = GetPoolMembers(specData.key, specData.class, specData.spec)
                 if #members > 0 then
                     GameTooltip:AddLine(" ")
                     GameTooltip:AddLine("调试模式名单:", 0.8, 0.8, 0.8)
                     for _, name in ipairs(members) do
                         GameTooltip:AddLine("- " .. name, 1, 1, 1)
                     end
                 end
             end
        end
        
        GameTooltip:Show()
    end)
    cell:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    CS23Cells[i] = cell
end
CS23Frame.cells = CS23Cells

-- ----------------------------------------------------------------------------
-- 更新逻辑
-- ----------------------------------------------------------------------------
local function UpdateClassCounts()
    local counts = {}
    for _, class in ipairs(ClassOrder) do
        counts[class] = 0
    end
    
    -- Update Role Stats
    if UpdateRoleStats then UpdateRoleStats() end

    local numMembers = 0
    local isRaid = false
    local isGroup = false
    
    if IsInRaid and IsInRaid() then
        isRaid = true
    elseif GetNumRaidMembers and GetNumRaidMembers() > 0 then
        isRaid = true
    end

    if IsInGroup and IsInGroup() then
        isGroup = true
    elseif GetNumPartyMembers and GetNumPartyMembers() > 0 then
        isGroup = true
    end

    if isRaid then
        if GetNumGroupMembers then
            numMembers = GetNumGroupMembers()
        elseif GetNumRaidMembers then
            numMembers = GetNumRaidMembers()
        end
        
        for i = 1, numMembers do
            local class
            if GetRaidRosterInfo then
                local _, _, _, _, _, classFileName = GetRaidRosterInfo(i)
                class = classFileName
            end
            
            if not class and UnitClass then
                _, class = UnitClass("raid" .. i)
            end
            
            if class then
                class = string.upper(class)
                if counts[class] then
                    counts[class] = counts[class] + 1
                end
            end
        end
    elseif isGroup then
        if GetNumGroupMembers then
            numMembers = GetNumGroupMembers() - 1
        elseif GetNumPartyMembers then
            numMembers = GetNumPartyMembers()
        end
        
        for i = 1, numMembers do
            local _, class = UnitClass("party" .. i)
            if class then 
                class = string.upper(class)
                if counts[class] then
                    counts[class] = counts[class] + 1
                end
            end
        end
        local _, class = UnitClass("player")
        if class then
            class = string.upper(class)
            if counts[class] then
                counts[class] = counts[class] + 1
            end
        end
    else
        local _, class = UnitClass("player")
        if class then
            class = string.upper(class)
            if counts[class] then
                counts[class] = counts[class] + 1
            end
        end
    end

    for class, frame in pairs(ClassIcons) do
        local count = counts[class] or 0
        frame.count = count
        if frame.classText then
            frame.classText:SetText(ClassNamesCN[class] .. count)
        end
    end
end

local function UpdateCCS10Grid()
    if not CCS10Frame or not CCS10Frame.cells then return end
    
    for i, cell in ipairs(CCS10Frame.cells) do
        local specData = CCS10Specs[i]
        if specData and specData.key then
            local count = GetPoolCount(specData.key)
            local icon = cell.icon
            
            if icon then
                if count > 0 then
                    icon:SetDesaturated(false)
                    icon:SetVertexColor(1, 1, 1, 1)
                else
                    icon:SetDesaturated(true)
                    icon:SetVertexColor(0.5, 0.5, 0.5, 1)
                end
            end
        end
    end
end

local function UpdateCS23Grid()
    if not CS23Frame or not CS23Frame.cells then return end
    
    local keyUsageCount = {}

    for i, cell in ipairs(CS23Frame.cells) do
        local specData = CS23Specs[i]
        if specData and specData.key then
            local totalAvailable = GetPoolCount(specData.key)
            local currentUsage = (keyUsageCount[specData.key] or 0) + 1
            keyUsageCount[specData.key] = currentUsage

            local icon = cell.icon
            
            if icon then
                if totalAvailable >= currentUsage then
                    icon:SetDesaturated(false)
                    icon:SetVertexColor(1, 1, 1, 1)
                else
                    icon:SetDesaturated(true)
                    icon:SetVertexColor(0.5, 0.5, 0.5, 1)
                end
            end
        end
    end
end

-- ----------------------------------------------------------------------------
-- 事件监听
-- ----------------------------------------------------------------------------
local EventFrame = CreateFrame("Frame")
EventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
EventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
EventFrame:RegisterEvent("INSPECT_READY")
EventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
EventFrame:RegisterEvent("CHARACTER_POINTS_CHANGED")
EventFrame:RegisterEvent("SPELLS_CHANGED")
EventFrame:RegisterEvent("UNIT_AURA")

EventFrame:SetScript("OnEvent", function(self, event, unit)
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        if UpdateClassCounts then pcall(UpdateClassCounts) end
        -- QueueInspect is not defined, removing call
        if UpdateCCS10Grid then pcall(UpdateCCS10Grid) end
        if UpdateCS23Grid then pcall(UpdateCS23Grid) end
    elseif event == "INSPECT_READY" then
        if UpdateCCS10Grid then pcall(UpdateCCS10Grid) end
        if UpdateCS23Grid then pcall(UpdateCS23Grid) end
    elseif event == "PLAYER_TALENT_UPDATE" or event == "CHARACTER_POINTS_CHANGED" or event == "SPELLS_CHANGED" then
        if UpdateClassCounts then pcall(UpdateClassCounts) end
        if UpdateCCS10Grid then pcall(UpdateCCS10Grid) end
        if UpdateCS23Grid then pcall(UpdateCS23Grid) end
    elseif event == "UNIT_AURA" then
        if unit == "player" then
            if UpdateCCS10Grid then pcall(UpdateCCS10Grid) end
            if UpdateCS23Grid then pcall(UpdateCS23Grid) end
        end
    end
end)

-- ----------------------------------------------------------------------------
-- Slash 命令
-- ----------------------------------------------------------------------------
SLASH_RPC1 = "/rpc"
SlashCmdList["RPC"] = function(msg)
    if MainFrame:IsShown() then 
        MainFrame:Hide() 
        print("RPC: Hidden")
    else 
        MainFrame:Show() 
        print("RPC: Shown")
        -- 安全调用更新
        if UpdateClassCounts then
            local success, err = pcall(UpdateClassCounts)
            if not success then
                print("RPC Error (Class): " .. tostring(err))
            end
        end
        if UpdateCCS10Grid then
            local success, err = pcall(UpdateCCS10Grid)
            if not success then
                print("RPC Error (Grid): " .. tostring(err))
            end
        end
        if UpdateCS23Grid then
            local success, err = pcall(UpdateCS23Grid)
            if not success then
                print("RPC Error (CS23 Grid): " .. tostring(err))
            end
        end
    end
end

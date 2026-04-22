local addonName, ns = ...
-- ============================================================================
-- 所有状态均为文件局部变量，不向全局空间写入任何非必要变量
-- ============================================================================
local RPC2_VERSION = "0.2.0"
local DebugMode = false

-- 数据导入
local CCS10Specs        = ns.Data.CCS10Specs
local CS23Specs         = ns.Data.CS23Specs
local CCS10DetectionPool = ns.Data.CCS10DetectionPool
local ClassOrder        = ns.Data.ClassOrder
local ClassNamesCN      = ns.Data.ClassNamesCN
local SpecNamesCN       = ns.Data.SpecNamesCN
local HeuristicRules    = ns.Data.HeuristicRules

-- ============================================================================
-- 核心辅助函数
-- ============================================================================

local SpellCache = {}
local function GetSpellName(id)
    if not id then return nil end
    if SpellCache[id] then return SpellCache[id] end
    local name = GetSpellInfo(id)
    if name then SpellCache[id] = name end
    return name
end

local function GetUnitRole(unit)
    if _G.UnitGroupRolesAssigned then return _G.UnitGroupRolesAssigned(unit) end
    return "NONE"
end

-- 检测单位是否有指定 Buff（按 ID 或名称）
local function UnitHasBuff(unit, spellIDs, checkOwn)
    if not spellIDs then return false end
    if type(spellIDs) == "number" then spellIDs = {spellIDs} end
    local i = 1
    while true do
        local name, _, _, _, _, _, _, source, _, _, spellId = UnitAura(unit, i, "HELPFUL")
        if not name then break end
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

-- 检测单条规则组（AND 关系）是否满足
local function CheckConditionGroup(unit, conditions, role)
    if conditions.role and conditions.role ~= role then return false end
    if conditions.notRole and conditions.notRole == role then return false end
    if conditions.powerType then
        if UnitPowerType(unit) ~= conditions.powerType then return false end
    end
    if conditions.notPowerType then
        if UnitPowerType(unit) == conditions.notPowerType then return false end
    end
    if conditions.buffs then
        if not UnitHasBuff(unit, conditions.buffs, conditions.checkOwn) then return false end
    end
    if conditions.noBuffs then
        if UnitHasBuff(unit, conditions.noBuffs) then return false end
    end
    if conditions.minHP then
        if UnitHealthMax(unit) <= conditions.minHP then return false end
    end
    if conditions.minMana then
        if UnitPowerMax(unit, 0) <= conditions.minMana then return false end
    end
    if conditions.maxMana then
        if UnitPowerMax(unit, 0) >= conditions.maxMana then return false end
    end
    return true
end

-- 启发式专精检测：只检测单个 specIndex 是否匹配（OR 组）
local function CheckSpecHeuristic(unit, class, specIndex)
    if not specIndex then return true end
    local classRules = HeuristicRules[class]
    if not classRules then return false end
    local specRules = classRules[specIndex]
    if not specRules then return false end
    local role = GetUnitRole(unit)
    for _, conditions in ipairs(specRules) do
        if CheckConditionGroup(unit, conditions, role) then return true end
    end
    return false
end

-- 排他专精评估：对一个单位只产生唯一 spec 结果
-- 遍历该职业所有专精的启发式规则，返回第一个匹配的 specIndex，或 nil
local function EvaluateUnitSpec(unit, class)
    local classRules = HeuristicRules[class]
    if not classRules then return nil end
    local role = GetUnitRole(unit)
    for s = 1, 3 do
        local specRules = classRules[s]
        if specRules then
            for _, conditions in ipairs(specRules) do
                if CheckConditionGroup(unit, conditions, role) then
                    return s
                end
            end
        end
    end
    return nil
end

-- ============================================================================
-- 专精缓存与 Inspect 状态机
-- ============================================================================
-- SpecCache[guid] = { class, spec, confirmed }
--   confirmed=true  : 由 Inspect API 确认，不再扫描
--   confirmed=false : 启发式估计，等待 Inspect 确认

local SpecCache = {}

-- Inspect 状态机：queue + pending + current
local Inspect = {
    queue       = {},       -- { unit, guid } 的列表
    pending     = {},       -- [guid]=true，已在队列或正在检查中
    current     = nil,      -- 当前正在 inspect 的 unit string
    currentGUID = nil,      -- 当前 inspect 的 GUID
    timer       = 0,
    interval    = 1.5,      -- 每次 inspect 间隔（秒）
}

local InspectFrame = CreateFrame("Frame")
InspectFrame:Hide()

local function QueueInspectUnit(unit)
    if not unit or not UnitExists(unit) then return end
    if UnitIsUnit(unit, "player") then return end
    local guid = UnitGUID(unit)
    if not guid then return end
    -- 已确认 → 跳过
    local cached = SpecCache[guid]
    if cached and cached.confirmed then return end
    -- 已在队列中 → 跳过
    if Inspect.pending[guid] then return end
    Inspect.pending[guid] = true
    table.insert(Inspect.queue, {unit=unit, guid=guid})
    InspectFrame:Show()
end

InspectFrame:SetScript("OnUpdate", function(self, elapsed)
    Inspect.timer = Inspect.timer + elapsed
    if Inspect.timer < Inspect.interval then return end
    Inspect.timer = 0
    if #Inspect.queue > 0 then
        local entry = table.remove(Inspect.queue, 1)
        -- 检查该成员是否已在上次出队后被确认
        local cached = SpecCache[entry.guid]
        if cached and cached.confirmed then
            Inspect.pending[entry.guid] = nil
        elseif UnitExists(entry.unit) and CanInspect(entry.unit) then
            Inspect.current     = entry.unit
            Inspect.currentGUID = entry.guid
            NotifyInspect(entry.unit)
        else
            Inspect.pending[entry.guid] = nil
        end
        if #Inspect.queue == 0 then self:Hide() end
    else
        self:Hide()
    end
end)

-- INSPECT_READY 处理：将结果写入缓存并标记为 confirmed
local function OnInspectReady(eventGUID)
    local unit     = Inspect.current
    local unitGUID = Inspect.currentGUID

    -- 事件可能携带 GUID（retail/高版本），尝试用其定位
    if eventGUID and eventGUID ~= "" and eventGUID ~= unitGUID then
        unit     = nil
        unitGUID = eventGUID
        local numMembers = GetNumGroupMembers and GetNumGroupMembers() or 0
        local inRaid = IsInRaid and IsInRaid()
        for i = 1, numMembers do
            local u = inRaid and ("raid"..i) or (i==1 and "player" or "party"..(i-1))
            if UnitExists(u) and UnitGUID(u) == eventGUID then
                unit = u
                break
            end
        end
    end

    -- 清理 current 状态
    if Inspect.currentGUID then
        Inspect.pending[Inspect.currentGUID] = nil
    end
    Inspect.current     = nil
    Inspect.currentGUID = nil

    if not unit or not UnitExists(unit) then return end
    if not unitGUID then unitGUID = UnitGUID(unit) end

    local _, unitClass = UnitClass(unit)
    if not unitClass then return end

    -- 优先：GetInspectSpecialization（Cata+/retail）
    local specID = GetInspectSpecialization and GetInspectSpecialization(unit)
    if specID and specID > 0 then
        local classID = select(3, UnitClass(unit))
        if classID then
            for s = 1, 4 do
                local info = {GetSpecializationInfoForClassID(classID, s)}
                if info[7] == specID then
                    SpecCache[unitGUID] = {class=unitClass, spec=s, confirmed=true}
                    return
                end
            end
        end
    end

    -- 回落：WotLK 天赋投入点数（GetTalentTabInfo with isInspect=true）
    if GetTalentTabInfo then
        local maxPts = -1
        local bestSpec = nil
        for i = 1, 3 do
            local _, _, pts = GetTalentTabInfo(i, true)
            pts = pts or 0
            if pts > maxPts then
                maxPts  = pts
                bestSpec = i
            end
        end
        if bestSpec and maxPts >= 0 then
            SpecCache[unitGUID] = {class=unitClass, spec=bestSpec, confirmed=true}
        end
    end
end

-- ============================================================================
-- 专精匹配：主函数
-- ============================================================================

-- 玩家自身：通过天赋投入点数直接确定
local function GetPlayerSpec()
    local maxPts = -1
    local bestSpec = 1
    for i = 1, 3 do
        local pts = 0
        if GetTalentTabInfo then
            local _, _, p = GetTalentTabInfo(i)
            pts = p or 0
        end
        if pts > maxPts then
            maxPts   = pts
            bestSpec = i
        end
    end
    return bestSpec
end

-- 职责排他判断：根据 LFG 职责直接确定专精，返回 specIndex 或 nil
-- 规则：标记为坦克的成员只能匹配其职业的坦克专精，其他专精排除
local TankSpecByClass = {
    PALADIN     = 2,
    WARRIOR     = 3,
    DEATHKNIGHT = 1,
    DRUID       = 2,
}
local function GetExclusiveSpecFromRole(unit, class)
    -- DK 血色存在灵气 → 强制 spec=1
    if class == "DEATHKNIGHT" and UnitHasBuff(unit, {48266}) then
        return 1
    end
    local role = GetUnitRole(unit)
    if role == "TANK" then
        return TankSpecByClass[class]  -- 无法坦克的职业返回 nil
    end
    if role == "HEALER" then
        -- 治疗职责：排除已知纯输出专精（不做正向确认，因治疗专精需更细致判断）
        return nil
    end
    return nil
end

-- IsUnitSpecMatch：单位是否匹配指定职业+专精
-- specIndex=nil 表示只检查职业
local function IsUnitSpecMatch(unit, classFileName, specIndex)
    if not UnitExists(unit) then return false end
    local _, unitClass = UnitClass(unit)
    if unitClass ~= classFileName then return false end

    -- 玩家自身：天赋点直接确定（权威）
    if UnitIsUnit(unit, "player") then
        if not specIndex then return true end
        return GetPlayerSpec() == specIndex
    end

    -- 职责排他检查（最高优先级）
    local roleSpec = GetExclusiveSpecFromRole(unit, unitClass)
    if roleSpec then
        if not specIndex then return true end
        return roleSpec == specIndex
    end

    -- 如果是坦克职责但上面没有匹配，这个职业没有定义坦克专精
    local role = GetUnitRole(unit)
    if role == "TANK" and TankSpecByClass[unitClass] then
        -- 有定义坦克专精但未命中，说明逻辑不一致，返回 false
        if not specIndex then return true end
        return false
    end

    -- 仅查询职业
    if not specIndex then
        QueueInspectUnit(unit)
        return true
    end

    local guid = UnitGUID(unit)

    -- 已确认缓存（Inspect API 结果）→ 权威答案，不再扫描
    local cached = SpecCache[guid]
    if cached and cached.confirmed and cached.class == unitClass then
        return cached.spec == specIndex
    end

    -- 尝试实时 Inspect API（可能已有数据，但尚未收到事件）
    local specID = GetInspectSpecialization and GetInspectSpecialization(unit)
    if specID and specID > 0 then
        local classID = select(3, UnitClass(unit))
        if classID then
            for s = 1, 4 do
                local info = {GetSpecializationInfoForClassID(classID, s)}
                if info[7] == specID then
                    SpecCache[guid] = {class=unitClass, spec=s, confirmed=true}
                    return s == specIndex
                end
            end
        end
    end

    -- 未确认缓存（启发式估计）→ 直接使用，不重新计算
    if cached and not cached.confirmed and cached.class == unitClass then
        QueueInspectUnit(unit)
        return cached.spec == specIndex
    end

    -- 排他启发式评估：对该单位计算唯一 spec，缓存为未确认
    local hSpec = EvaluateUnitSpec(unit, unitClass)
    if hSpec then
        SpecCache[guid] = {class=unitClass, spec=hSpec, confirmed=false}
        QueueInspectUnit(unit)
        return hSpec == specIndex
    end

    -- 无法判断，加入检测队列等待 Inspect
    QueueInspectUnit(unit)
    return false
end

-- ============================================================================
-- 组成员迭代辅助
-- ============================================================================

local function IterateGroupMembers(callback)
    local numMembers = GetNumGroupMembers and GetNumGroupMembers() or 0
    if numMembers == 0 then
        callback("player")
        return
    end
    local inRaid = IsInRaid and IsInRaid()
    for i = 1, numMembers do
        local unit = inRaid and ("raid"..i) or (i==1 and "player" or "party"..(i-1))
        if UnitExists(unit) then callback(unit) end
    end
end

-- ============================================================================
-- 查询函数
-- ============================================================================

local function GetPoolMembers(poolKey, primaryClass, primarySpec)
    local members = {}
    local pool = CCS10DetectionPool[poolKey]
    if not pool then return members end

    IterateGroupMembers(function(unit)
        for _, rule in ipairs(pool) do
            if IsUnitSpecMatch(unit, rule.class, rule.spec) then
                local name = UnitName(unit)
                local _, class = UnitClass(unit)
                local color = RAID_CLASS_COLORS[class]
                if color then
                    name = string.format("|cff%02x%02x%02x%s|r",
                        color.r*255, color.g*255, color.b*255, name)
                end
                local isSubstitute = false
                if primaryClass and class ~= primaryClass then
                    isSubstitute = true
                elseif primarySpec and rule.spec and primarySpec ~= rule.spec then
                    isSubstitute = true
                end
                if isSubstitute then
                    local specName
                    if rule.spec and SpecNamesCN[class] then
                        specName = SpecNamesCN[class][rule.spec]
                    end
                    specName = specName or ClassNamesCN[class] or class
                    name = name .. " (" .. specName .. "替代)"
                end
                table.insert(members, name)
                return  -- 每个成员只计入一次
            end
        end
    end)
    return members
end

local function GetPoolCount(poolKey)
    return #GetPoolMembers(poolKey)
end
local MainFrame = CreateFrame("Frame", "RPC2_MainFrame", UIParent, "BackdropTemplate")
MainFrame:SetWidth(260)
MainFrame:SetHeight(430)
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
Title:SetText("RPC2 " .. RPC2_VERSION)
local CloseButton = CreateFrame("Button", nil, TitleBar, "UIPanelCloseButton")
CloseButton:SetPoint("RIGHT", TitleBar, "RIGHT", 2, 1)
CloseButton:SetWidth(35)
CloseButton:SetHeight(35)
CloseButton:SetScript("OnClick", function() MainFrame:Hide() end)
local OptionsFrame = CreateFrame("Frame", "RPC2_OptionsFrame", UIParent, "BackdropTemplate")
OptionsFrame:SetSize(450, 300)
OptionsFrame:SetPoint("CENTER")
OptionsFrame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    tile = true, tileSize = 16, edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 }
})
OptionsFrame:SetBackdropColor(0, 0, 0, 0.85)
OptionsFrame:SetBackdropBorderColor(0, 0, 0, 0.3)
OptionsFrame:Hide()
local OptTitle = OptionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
OptTitle:SetPoint("TOP", 0, -12)
OptTitle:SetText("RPC2 设置")
local OptClose = CreateFrame("Button", nil, OptionsFrame, "UIPanelCloseButton")
OptClose:SetPoint("TOPRIGHT", OptionsFrame, "TOPRIGHT", 2, 2)
OptClose:SetWidth(35)
OptClose:SetHeight(35)
OptClose:SetScript("OnClick", function() OptionsFrame:Hide() end)
local SButton = CreateFrame("Button", nil, TitleBar, "UIPanelButtonTemplate")
SButton:SetSize(22, 18)
SButton:SetPoint("RIGHT", CloseButton, "LEFT", -4, 0)
SButton:SetText("S")
SButton:SetScript("OnClick", function() if OptionsFrame:IsShown() then OptionsFrame:Hide() else OptionsFrame:Show() end end)
local ClassFrame = CreateFrame("Frame", nil, MainFrame)
ClassFrame:SetPoint("TOP", MainFrame, "TOP", 0, -25)
ClassFrame:SetWidth(250)
ClassFrame:SetHeight(60)
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
local CS23Title = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
CS23Title:SetPoint("TOPLEFT", CCS10Frame, "BOTTOMLEFT", 0, -10)
CS23Title:SetText("23人宝库推荐配置")
local font, _, flags = CS23Title:GetFont()
CS23Title:SetFont(font, 14, flags)
CS23Title:SetJustifyH("LEFT")
local CS23Frame = CreateFrame("Frame", nil, MainFrame)
CS23Frame:SetPoint("TOPLEFT", CCS10Frame, "BOTTOMLEFT", 0, -30)
CS23Frame:SetWidth(250)
CS23Frame:SetHeight(75)
local CS23_CELL_WIDTH = 250 / 10
local CS23_CELL_HEIGHT = 25
local RoleStatsFrame = CreateFrame("Frame", nil, MainFrame)
RoleStatsFrame:SetPoint("TOPLEFT", CS23Frame, "BOTTOMLEFT", 0, -10)
RoleStatsFrame:SetWidth(250)
RoleStatsFrame:SetHeight(40)
local RoleStatsText = RoleStatsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
local font, _, flags = RoleStatsText:GetFont()
RoleStatsText:SetFont(font, 14, flags)
RoleStatsText:SetPoint("TOPLEFT", RoleStatsFrame, "TOPLEFT", 0, 0)
RoleStatsText:SetJustifyH("LEFT")
local StatusStatsText = RoleStatsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
StatusStatsText:SetFont(font, 14, flags)
StatusStatsText:SetPoint("TOPLEFT", RoleStatsText, "BOTTOMLEFT", 0, -2)
StatusStatsText:SetJustifyH("LEFT")
local DebugCheckButton = CreateFrame("CheckButton", nil, MainFrame, "ChatConfigCheckButtonTemplate")
DebugCheckButton:SetPoint("TOPLEFT", RoleStatsFrame, "BOTTOMLEFT", 0, 0)
DebugCheckButton:SetSize(24, 24)
DebugCheckButton.tooltip = "显示详细的检测名单"
DebugCheckButton:SetScript("OnClick", function(self)
    DebugMode = self:GetChecked()
end)
local DebugCheckLabel = DebugCheckButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
DebugCheckLabel:SetPoint("LEFT", DebugCheckButton, "RIGHT", 5, 0)
DebugCheckLabel:SetText("调试模式")

-- ============================================================================
-- 通用 Tooltip 构建辅助
-- ============================================================================
local function BuildSpecTooltip(specData)
    local count = GetPoolCount(specData.key)
    GameTooltip:SetText(specData.name .. " (检测到 " .. count .. " 人)", 1, 1, 1)
    if specData.desc then
        GameTooltip:AddLine(specData.desc, 1, 0.82, 0)
    end
    local pool = CCS10DetectionPool[specData.key]
    if pool then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("检测规则:", 0.8, 0.8, 0.8)
        for _, rule in ipairs(pool) do
            local cn = ClassNamesCN[rule.class] or rule.class
            local sn = rule.spec and SpecNamesCN[rule.class] and SpecNamesCN[rule.class][rule.spec]
            local desc = sn and (sn .. "(" .. cn .. ")") or cn
            GameTooltip:AddLine("- " .. desc, 0.6, 0.6, 0.6)
        end
        if DebugMode then
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
end

-- ============================================================================
-- CCS10 格子
-- ============================================================================
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
        BuildSpecTooltip(specData)
    end)
    cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
    BuffCells[i] = cell
end
CCS10Frame.cells = BuffCells

-- ============================================================================
-- CS23 格子
-- ============================================================================
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
        BuildSpecTooltip(specData)
    end)
    cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
    CS23Cells[i] = cell
end
CS23Frame.cells = CS23Cells

-- ============================================================================
-- 更新函数
-- ============================================================================

local function UpdateRoleStats()
    local numGroupMembers = GetNumGroupMembers and GetNumGroupMembers() or 0
    local tank, healer, dps = 0, 0, 0
    local online, afk, offline, dead = 0, 0, 0, 0
    if numGroupMembers > 0 then
        IterateGroupMembers(function(unit)
            local role = GetUnitRole(unit)
            if role == "TANK" then tank = tank + 1
            elseif role == "HEALER" then healer = healer + 1
            elseif role == "DAMAGER" then dps = dps + 1 end
            if UnitIsDeadOrGhost(unit) then dead = dead + 1 end
            if not UnitIsConnected(unit) then offline = offline + 1
            elseif UnitIsAFK(unit) then afk = afk + 1
            else online = online + 1 end
        end)
    else
        numGroupMembers = 1
        local role = GetUnitRole("player")
        if role == "TANK" then tank = 1
        elseif role == "HEALER" then healer = 1
        elseif role == "DAMAGER" then dps = 1 end
        if UnitIsDeadOrGhost("player") then dead = 1 end
        if UnitIsAFK("player") then afk = 1 else online = 1 end
    end
    local tankIcon   = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:14:14:0:0:64:64:0:19:22:41|t"
    local healerIcon = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:14:14:0:0:64:64:20:39:1:20|t"
    local dpsIcon    = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:14:14:0:0:64:64:20:39:22:41|t"
    RoleStatsText:SetText(string.format("在团%d人:  %s%d  %s%d  %s%d",
        numGroupMembers, tankIcon, tank, healerIcon, healer, dpsIcon, dps))
    StatusStatsText:SetText(string.format("正常%d人，暂离%d人，离线%d人，死亡%d人", online, afk, offline, dead))
end

local function UpdateClassCounts()
    local counts = {}
    for _, class in ipairs(ClassOrder) do counts[class] = 0 end
    IterateGroupMembers(function(unit)
        local _, class = UnitClass(unit)
        if class then
            class = string.upper(class)
            if counts[class] then counts[class] = counts[class] + 1 end
        end
    end)
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
            local icon = cell.icon
            if icon then
                if GetPoolCount(specData.key) > 0 then
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
            local total         = GetPoolCount(specData.key)
            local currentUsage  = (keyUsageCount[specData.key] or 0) + 1
            keyUsageCount[specData.key] = currentUsage
            local icon = cell.icon
            if icon then
                if total >= currentUsage then
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

local function UpdateAll()
    if not MainFrame:IsShown() then return end
    pcall(UpdateRoleStats)
    pcall(UpdateClassCounts)
    pcall(UpdateCCS10Grid)
    pcall(UpdateCS23Grid)
end

-- ============================================================================
-- 节流机制：短时间内多个事件只触发一次 UI 更新
-- ============================================================================
local updatePending = false
local UPDATE_DELAY  = 0.3   -- 秒

local ThrottleFrame = CreateFrame("Frame")
ThrottleFrame:Hide()
ThrottleFrame.elapsed = 0
ThrottleFrame:SetScript("OnUpdate", function(self, delta)
    self.elapsed = self.elapsed + delta
    if self.elapsed >= UPDATE_DELAY then
        self:Hide()
        self.elapsed = 0
        updatePending = false
        UpdateAll()
    end
end)

local function ScheduleUpdate()
    if not updatePending then
        updatePending = true
        ThrottleFrame.elapsed = 0
        ThrottleFrame:Show()
    end
end

-- ============================================================================
-- 缓存管理：成员变化时清理离队成员、入队新成员
-- ============================================================================
local function OnRosterChanged()
    if not IsInGroup() then
        SpecCache = {}
        Inspect.queue   = {}
        Inspect.pending = {}
        Inspect.current     = nil
        Inspect.currentGUID = nil
        InspectFrame:Hide()
        return
    end
    local currentGUIDs = {}
    IterateGroupMembers(function(unit)
        local guid = UnitGUID(unit)
        if guid then
            currentGUIDs[guid] = true
            if not SpecCache[guid] and not UnitIsUnit(unit, "player") then
                QueueInspectUnit(unit)
            end
        end
    end)
    -- 清理离队成员缓存
    for guid in pairs(SpecCache) do
        if not currentGUIDs[guid] then
            SpecCache[guid] = nil
        end
    end
    -- 清理离队成员的 pending 状态
    for guid in pairs(Inspect.pending) do
        if not currentGUIDs[guid] then
            Inspect.pending[guid] = nil
        end
    end
end

-- ============================================================================
-- 事件监听（单一 EventFrame）
-- ============================================================================
local EventFrame = CreateFrame("Frame")
EventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
EventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
EventFrame:RegisterEvent("GROUP_LEFT")
EventFrame:RegisterEvent("INSPECT_READY")
EventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
EventFrame:RegisterEvent("CHARACTER_POINTS_CHANGED")
EventFrame:RegisterEvent("UNIT_AURA")

EventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_ENTERING_WORLD" then
        -- 重置所有缓存
        SpecCache = {}
        Inspect.queue   = {}
        Inspect.pending = {}
        Inspect.current     = nil
        Inspect.currentGUID = nil
        InspectFrame:Hide()
        ScheduleUpdate()

    elseif event == "GROUP_ROSTER_UPDATE" then
        OnRosterChanged()
        ScheduleUpdate()

    elseif event == "GROUP_LEFT" then
        SpecCache = {}
        Inspect.queue   = {}
        Inspect.pending = {}
        Inspect.current     = nil
        Inspect.currentGUID = nil
        InspectFrame:Hide()
        ScheduleUpdate()

    elseif event == "INSPECT_READY" then
        -- arg1 可能是 GUID（高版本 WoW），也可能为 nil（WotLK）
        pcall(OnInspectReady, arg1)
        ScheduleUpdate()

    elseif event == "PLAYER_TALENT_UPDATE" or event == "CHARACTER_POINTS_CHANGED" then
        -- 玩家天赋变化，重置玩家自身（天赋 API 会直接给出结果，无需缓存）
        ScheduleUpdate()

    elseif event == "UNIT_AURA" then
        -- arg1 = unit string（如 "raid5"）
        -- 只对尚未确认专精的成员使启发式缓存失效；
        -- 已确认的成员不触发任何更新，节省资源
        if not arg1 then return end
        local guid = UnitGUID(arg1)
        if not guid then return end
        local cached = SpecCache[guid]
        local invalidated = false
        if cached and not cached.confirmed then
            SpecCache[guid] = nil  -- 强制下次重新评估启发式
            invalidated = true
        end
        -- 仅在玩家自身灵气变化，或未确认成员灵气变化时安排更新
        if UnitIsUnit(arg1, "player") or invalidated then
            ScheduleUpdate()
        end
    end
end)

-- ============================================================================
-- Slash 命令（WoW 要求的全局变量）
-- ============================================================================
SLASH_RPC2_1 = "/rpc2"
SlashCmdList["RPC2"] = function(msg)
    local m = msg and string.lower(msg) or ""
    if m == "opt" or m == "options" then
        if OptionsFrame:IsShown() then OptionsFrame:Hide() else OptionsFrame:Show() end
        return
    end
    if MainFrame:IsShown() then
        MainFrame:Hide()
        print("RPC2: Hidden")
    else
        MainFrame:Show()
        print("RPC2: Shown")
        UpdateAll()
    end
end

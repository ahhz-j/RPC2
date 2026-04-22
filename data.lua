local addonName, ns = ...
ns.Data = {}
ns.Data.BuffDefs = {
    [1]  = { key="10ap", name="10%攻击强度", providers={ {class="SHAMAN", spec=2}, {class="HUNTER", spec=2}, {class="DEATHKNIGHT", spec=1} } },
    [2]  = { key="13sp", name="13%法术易伤", providers={ {class="DRUID", spec=1}, {class="DEATHKNIGHT", spec=3}, {class="WARLOCK"} } },
    [3]  = { key="haste", name="20%近战攻速", providers={ {class="SHAMAN", spec=2}, {class="DEATHKNIGHT", spec=2} } },
    [4]  = { key="3dmg", name="3%伤害加成", providers={ {class="PALADIN", spec=3}, {class="MAGE", spec=1}, {class="HUNTER", spec=1} } },
    [5]  = { key="3haste", name="3%急速加成", providers={ {class="PALADIN", spec=3}, {class="DRUID", spec=1} } },
    [6]  = { key="3crit", name="3%爆击易伤", providers={ {class="PALADIN", spec=3}, {class="SHAMAN", spec=1}, {class="ROGUE", spec=1} } },
    [7]  = { key="3hit", name="3%法术命中", providers={ {class="DRUID", spec=1}, {class="PRIEST", spec=3} } },
    [8]  = { key="bleed", name="30%流血伤害", providers={ {class="WARRIOR", spec=1}, {class="DRUID", spec=2} } },
    [9]  = { key="4phys", name="4%物理易伤", providers={ {class="WARRIOR", spec=1}, {class="ROGUE", spec=2} } },
    [10] = { key="5spellhaste", name="5%法术急速", providers={ {class="SHAMAN"} } },
    [11] = { key="5spellcrit", name="5%法术爆击", providers={ {class="DRUID", spec=1}, {class="PRIEST", spec=3} } },
    [12] = { key="5physcrit", name="5%物理暴击", providers={ {class="WARRIOR", spec=2}, {class="DRUID", spec=2} } },
    [13] = { key="6heal", name="6%受疗加成", providers={ {class="PALADIN", spec=2}, {class="DRUID", spec=3} } },
    [14] = { key="-physhit", name="降低物理命中", providers={ {class="DRUID", spec=1}, {class="HUNTER"} } },
    [15] = { key="thunder", name="减攻速", providers={ {class="PALADIN", spec=3}, {class="PALADIN", spec=2}, {class="WARRIOR"}, {class="DEATHKNIGHT", spec=1}, {class="DRUID", spec=2} } },
    [16] = { key="majorarmor", name="20%破甲", providers={ {class="WARRIOR"}, {class="ROGUE"} } },
    [17] = { key="minorarmor", name="5%破甲", providers={ {class="DRUID", spec=1}, {class="WARLOCK"} } },
    [18] = { key="stragi", name="力量/敏捷", providers={ {class="PALADIN"}, {class="SHAMAN"}, {class="DEATHKNIGHT"} } },
    [19] = { key="bloodlust", name="英勇/嗜血", providers={ {class="SHAMAN"} } },
    [20] = { key="ap", name="固定AP", providers={ {class="PALADIN"}, {class="WARRIOR"} } },
    [21] = { key="int", name="智力", providers={ {class="MAGE"} } },
    [22] = { key="sp", name="固定法强", providers={ {class="SHAMAN"}, {class="WARLOCK", spec=2} } },
    [23] = { key="kings", name="全属性(王者)", providers={ {class="PALADIN"} } },
    [24] = { key="spirit", name="精神", providers={ {class="PRIEST", spec=1}, {class="PRIEST", spec=2} } },
    [25] = { key="stamina", name="耐力", providers={ {class="PRIEST", spec=1}, {class="PRIEST", spec=2} } },
    [26] = { key="health", name="生命上限", providers={ {class="WARRIOR"}, {class="WARLOCK"} } },
    [27] = { key="motw", name="全属性(爪子)", providers={ {class="DRUID"} } },
    [28] = { key="demo", name="减AP", providers={ {class="WARRIOR"}, {class="DRUID"}, {class="PALADIN"} } },
}
ns.Data.CCS10Specs = {
    { name = "奶骑", class = "PALADIN", spec = 1, icon = "Interface\\Icons\\Spell_Holy_HolyBolt", key = "hpal", desc = "强效力量/智慧祝福，光环掌握" }, 
    { name = "惩戒", class = "PALADIN", spec = 3, icon = "Interface\\Icons\\Spell_Holy_AuraOfLight", key = "ret", desc = "3%伤害, 3%急速, 3%暴击" },
    { name = "武器", class = "WARRIOR", spec = 1, icon = "Interface\\Icons\\Ability_Warrior_OffensiveStance", key = "arms", desc = "4%物理易伤, 30%流血伤害" }, 
    { name = "狂暴", class = "WARRIOR", spec = 2, icon = "Interface\\Icons\\Ability_Warrior_InnerRage", key = "fury", desc = "5%物理暴击" },
    { name = "奶萨", class = "SHAMAN", spec = 3, icon = "Interface\\Icons\\Spell_Nature_MagicImmunity", key = "rsham", desc = "治疗之泉/法力之泉, 嗜血" },
    { name = "增强", class = "SHAMAN", spec = 2, icon = "Interface\\Icons\\Spell_Nature_LightningShield", key = "enh", desc = "20%近战攻速, 10%攻击强度" },
    { name = "鸟德", class = "DRUID", spec = 1, icon = "Interface\\Icons\\Spell_Nature_StarFall", key = "bal", desc = "3%法术命中, 5%法术爆击" },
    { name = "法师", class = "MAGE", icon = "Interface\\Icons\\Spell_Holy_MagicalSentry", key = "mage", desc = "奥术光辉(智力)" }, 
    { name = "恶魔", class = "WARLOCK", spec = 2, icon = "Interface\\Icons\\Spell_Shadow_Metamorphosis", key = "demo", desc = "法术强度, 13%法术易伤" }, 
    { name = "戒律", class = "PRIEST", spec = 1, icon = "Interface\\Icons\\Spell_Holy_PowerWordShield", key = "disc", desc = "真言术:韧(耐力), 精神祷言" } 
}
ns.Data.CS23Specs = {
    { name = "防骑", class = "PALADIN", spec = 2, icon = "Interface\\Icons\\Spell_Holy_DevotionAura", key = "cs23_prot_pal", desc = "防骑" },
    { name = "DKT", class = "DEATHKNIGHT", spec = 1, icon = "Interface\\Icons\\Spell_Deathknight_FrostPresence", key = "cs23_dkt", desc = "鲜血DK坦克" },
    { name = "防战", class = "WARRIOR", spec = 3, icon = "Interface\\Icons\\Ability_Warrior_DefensiveStance", key = "cs23_prot_war", desc = "防战" },
    { name = "盗贼", class = "ROGUE", icon = "Interface\\Icons\\ClassIcon_Rogue", key = "cs23_rogue", desc = "任意天赋盗贼" },
    { name = "盗贼", class = "ROGUE", icon = "Interface\\Icons\\ClassIcon_Rogue", key = "cs23_rogue", desc = "任意天赋盗贼" },
    { name = "惩戒", class = "PALADIN", spec = 3, icon = "Interface\\Icons\\Spell_Holy_AuraOfLight", key = "cs23_ret", desc = "惩戒骑" },
    { name = "输出DK", class = "DEATHKNIGHT", icon = "Interface\\Icons\\Spell_Deathknight_UnholyPresence", key = "cs23_dps_dk", desc = "冰/邪DK" },
    { name = "输出战", class = "WARRIOR", icon = "Interface\\Icons\\Ability_Warrior_InnerRage", key = "cs23_dps_war", desc = "武器/狂暴战" },
    { name = "增强萨", class = "SHAMAN", spec = 2, icon = "Interface\\Icons\\Spell_Nature_LightningShield", key = "cs23_enh", desc = "增强萨" },
    { name = "元素萨", class = "SHAMAN", spec = 1, icon = "Interface\\Icons\\Spell_Nature_Lightning", key = "cs23_ele", desc = "元素萨" },
    { name = "猫德", class = "DRUID", spec = 2, icon = "Interface\\Icons\\Ability_Druid_CatForm", key = "cs23_cat", desc = "野性德鲁伊(猫)" },
    { name = "鸟德", class = "DRUID", spec = 1, icon = "Interface\\Icons\\Spell_Nature_StarFall", key = "cs23_bal", desc = "平衡德" },
    { name = "术士", class = "WARLOCK", icon = "Interface\\Icons\\ClassIcon_Warlock", key = "cs23_warlock", desc = "任意天赋术士" },
    { name = "术士", class = "WARLOCK", icon = "Interface\\Icons\\ClassIcon_Warlock", key = "cs23_warlock", desc = "任意天赋术士" },
    { name = "暗牧", class = "PRIEST", spec = 3, icon = "Interface\\Icons\\Spell_Shadow_ShadowWordPain", key = "cs23_spriest", desc = "暗影牧师" },
    { name = "猎人", class = "HUNTER", icon = "Interface\\Icons\\ClassIcon_Hunter", key = "cs23_hunter", desc = "任意天赋猎人" },
    { name = "猎人", class = "HUNTER", icon = "Interface\\Icons\\ClassIcon_Hunter", key = "cs23_hunter", desc = "任意天赋猎人" },
    { name = "奶萨", class = "SHAMAN", spec = 3, icon = "Interface\\Icons\\Spell_Nature_MagicImmunity", key = "cs23_rsham", desc = "恢复萨满" },
    { name = "奶骑", class = "PALADIN", spec = 1, icon = "Interface\\Icons\\Spell_Holy_HolyBolt", key = "cs23_hpal", desc = "神圣骑士" },
    { name = "奶德", class = "DRUID", spec = 3, icon = "Interface\\Icons\\Spell_Nature_HealingTouch", key = "cs23_rdruid", desc = "恢复德鲁伊" },
    { name = "戒律", class = "PRIEST", spec = 1, icon = "Interface\\Icons\\Spell_Holy_PowerWordShield", key = "cs23_disc", desc = "戒律牧师" },
    { name = "法师", class = "MAGE", icon = "Interface\\Icons\\ClassIcon_Mage", key = "cs23_mage", desc = "任意天赋法师" },
    { name = "法师", class = "MAGE", icon = "Interface\\Icons\\ClassIcon_Mage", key = "cs23_mage", desc = "任意天赋法师" }
}
ns.Data.CCS10DetectionPool = {
    hpal = { {class="PALADIN", spec=1} },
    ret = { {class="PALADIN", spec=3} },
    arms = { {class="WARRIOR", spec=1}, {class="ROGUE", spec=2}, {class="DRUID", spec=2} },
    fury = { {class="WARRIOR", spec=2}, {class="DRUID", spec=2} },
    rsham = { {class="SHAMAN", spec=3} },
    enh = { {class="SHAMAN", spec=2}, {class="DEATHKNIGHT", spec=2} },
    bal = { {class="DRUID", spec=1}, {class="PRIEST", spec=3} },
    mage = { {class="MAGE"} },
    demo = { {class="WARLOCK", spec=2}, {class="SHAMAN", spec=1} },
    disc = { {class="PRIEST", spec=1}, {class="PRIEST", spec=2} },
    cs23_prot_pal = { {class="PALADIN", spec=2} },
    cs23_dkt = { {class="DEATHKNIGHT", spec=1} },
    cs23_prot_war = { {class="WARRIOR", spec=3} },
    cs23_rogue = { {class="ROGUE"} },
    cs23_ret = { {class="PALADIN", spec=3} },
    cs23_dps_dk = { {class="DEATHKNIGHT", spec=2}, {class="DEATHKNIGHT", spec=3} },
    cs23_dps_war = { {class="WARRIOR", spec=1}, {class="WARRIOR", spec=2} },
    cs23_enh = { {class="SHAMAN", spec=2} },
    cs23_ele = { {class="SHAMAN", spec=1} },
    cs23_cat = { {class="DRUID", spec=2} },
    cs23_bal = { {class="DRUID", spec=1} },
    cs23_warlock = { {class="WARLOCK"} },
    cs23_spriest = { {class="PRIEST", spec=3} },
    cs23_hunter = { {class="HUNTER"} },
    cs23_rsham = { {class="SHAMAN", spec=3} },
    cs23_hpal = { {class="PALADIN", spec=1} },
    cs23_rdruid = { {class="DRUID", spec=3} },
    cs23_disc = { {class="PRIEST", spec=1} },
    cs23_mage = { {class="MAGE"} },
}
ns.Data.ClassOrder = { "WARRIOR", "DEATHKNIGHT", "PALADIN", "DRUID", "SHAMAN", "HUNTER", "ROGUE", "WARLOCK", "MAGE", "PRIEST" }
ns.Data.ClassNamesCN = {
    WARRIOR = "战士", DEATHKNIGHT = "死骑", PALADIN = "圣骑", DRUID = "小德",
    SHAMAN = "萨满", HUNTER = "猎人", ROGUE = "盗贼", WARLOCK = "术士",
    MAGE = "法师", PRIEST = "牧师"
}
ns.Data.SpecNamesCN = {
    PALADIN = { [1]="奶骑", [2]="防骑", [3]="惩戒" },
    PRIEST = { [1]="戒律", [2]="神牧", [3]="暗牧" },
    WARLOCK = { [1]="痛苦", [2]="恶魔", [3]="毁灭" },
    WARRIOR = { [1]="武器", [2]="狂暴", [3]="防战" },
    HUNTER = { [1]="兽王", [2]="射击", [3]="生存" },
    SHAMAN = { [1]="元素", [2]="增强", [3]="奶萨" },
    ROGUE = { [1]="刺杀", [2]="战斗", [3]="敏锐" },
    MAGE = { [1]="奥法", [2]="火法", [3]="冰法" },
    DEATHKNIGHT = { [1]="鲜血", [2]="冰霜", [3]="邪恶" },
    DRUID = { [1]="鸟德", [2]="野德", [3]="奶德" },
}
ns.Data.HeuristicRules = {
    DRUID = {
        [1] = {
            { buffs = {24858} },
            { buffs = {24907}, checkOwn = true },
            { role = "DAMAGER", powerType = 0 }
        },
        [2] = {
            { buffs = {17007}, checkOwn = true },
            { role = "TANK" },
            { role = "DAMAGER", notPowerType = 0 },
            { buffs = {768}, notRole = "HEALER", maxMana = 14000 },
            { buffs = {9634}, notRole = "HEALER", maxMana = 14000 }
        },
        [3] = {
            { role = "HEALER" },
            { buffs = {33891} },
            { buffs = {48438}, checkOwn = true }
        }
    },
    PALADIN = {
        [1] = {
            { minMana = 15000 },
            { role = "HEALER" },
            { buffs = {31821}, checkOwn = true }
        },
        [2] = {
            { role = "TANK" },
            { buffs = {25780}, minHP = 25000 }
        },
        [3] = {
            { role = "DAMAGER" },
            { buffs = {20375, 31869, 53503, 53488} }
        }
    },
    SHAMAN = {
        [1] = {
            { buffs = {30706, 57720}, checkOwn = true },
            { role = "DAMAGER", minMana = 15000 }
        },
        [2] = {
            { buffs = {30811, 30823} },
            { role = "DAMAGER", maxMana = 15000, minMana = 1 }
        },
        [3] = {
            { role = "HEALER" },
            { buffs = {16190}, checkOwn = true },
            { buffs = {974, 61295}, checkOwn = true }
        }
    },
    WARLOCK = {
        [2] = {
            { buffs = {47240, 47241}, checkOwn = true },
            { buffs = {19028} }
        }
    },
    DEATHKNIGHT = {
        [1] = {
            { role = "TANK" },
            { buffs = {48266} }
        },
        [2] = {
             { role = "DAMAGER" },
             { buffs = {48263, 48265} }
        },
        [3] = {
             { role = "DAMAGER" },
             { buffs = {48263, 48265} }
        }
    },
    WARRIOR = {
        [3] = {
            { role = "TANK" },
            { buffs = {71} }
        },
        [2] = {
            { buffs = {29801, 46916} },
            { buffs = {2458}, noBuffs = {52437, 56638} },
            { role = "DAMAGER", noBuffs = {2457, 71, 52437, 56638} }
        },
        [1] = {
            { buffs = {52437, 56638} },
            { buffs = {2457}, noBuffs = {29801, 46916} },
            { role = "DAMAGER", noBuffs = {2458, 71, 29801, 46916} }
        }
    },
    PRIEST = {
        [3] = {
            { buffs = {15473, 34914} },
            { role = "DAMAGER" }
        },
        [1] = {
            { role = "HEALER" },
            { noBuffs = {15473} }
        },
        [2] = {
            { role = "HEALER" },
            { noBuffs = {15473} }
        }
    }
}

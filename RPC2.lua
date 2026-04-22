local TITAN_RPC2_ID = "RPC2"
local TITAN_RPC2_BUTTON = "TitanPanel" .. TITAN_RPC2_ID .. "Button"

local function RPC2_GetPlayerCount()
    local members = GetNumGroupMembers() or 0

    if IsInRaid() then
        return members, "Raid"
    end

    if members > 0 and IsInGroup() then
        return members, "Party"
    end

    return 1, "Solo"
end

function TitanPanelRPC2Button_GetButtonText()
    local members = select(1, RPC2_GetPlayerCount())
    return "RPC2", tostring(members)
end

function TitanPanelRPC2Button_GetTooltipText()
    local members, groupType = RPC2_GetPlayerCount()
    return string.format("%s players: %d", groupType, members)
end

local RPC2Button = CreateFrame("Button", TITAN_RPC2_BUTTON, UIParent, "TitanPanelComboTemplate")
RPC2Button.registry = {
    id = TITAN_RPC2_ID,
    menuText = "Raid Player Counter",
    buttonTextFunction = "TitanPanelRPC2Button_GetButtonText",
    tooltipTitle = "Raid Player Counter",
    tooltipTextFunction = "TitanPanelRPC2Button_GetTooltipText",
    icon = "Interface\\GroupFrame\\UI-Group-LeaderIcon",
    iconWidth = 16,
    savedVariables = {
        ShowIcon = 1,
        ShowLabelText = 1,
        ShowRegularText = 1,
        DisplayOnRightSide = false,
    },
}

RPC2Button:RegisterEvent("PLAYER_ENTERING_WORLD")
RPC2Button:RegisterEvent("GROUP_ROSTER_UPDATE")
RPC2Button:RegisterEvent("RAID_ROSTER_UPDATE")
RPC2Button:SetScript("OnEvent", function(self)
    if TitanPanelButton_UpdateButton then
        TitanPanelButton_UpdateButton(self.registry.id)
    end
end)

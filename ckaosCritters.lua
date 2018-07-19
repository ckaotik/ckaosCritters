local addonName, addon, _ = ...
addon.frame = CreateFrame('Frame')
_G[addonName] = addon

-- GLOBALS: _G, UIParent, PetBattleFrame, C_PetJournal, C_PetBattles, GameTooltip, ITEM_QUALITY_COLORS, PET_TYPE_SUFFIX, ADD_ANOTHER, GREEN_FONT_COLOR_CODE, YELLOW_FONT_COLOR_CODE, GRAY_FONT_COLOR, NORMAL_FONT_COLOR, UIDROPDOWNMENU_INIT_MENU, StaticPopupDialogs, StaticPopup_Show, UnitPopupMenus, UnitPopupShown, UnitIsBattlePet
-- GLOBALS: CreateFrame, PlaySound, IsShiftKeyDown, IsControlKeyDown, IsModifiedClick, PetJournal_UpdatePetLoadOut, IsAddOnLoaded, ChatEdit_GetActiveWindow
-- GLOBALS: math, string, table, ipairs, pairs, next, hooksecurefunc, type, wipe, select, coroutine, strjoin, unpack, print

local MAX_PET_LEVEL = 25
local MAX_ACTIVE_PETS = 3

local strongTypes, weakTypes = {}, {}
-- prepare effectiveness chart
for i = 1, C_PetJournal.GetNumPetTypes() do
	if not strongTypes[i] then strongTypes[i] = {} end
	if not   weakTypes[i] then   weakTypes[i] = {} end

	for j = 1, C_PetJournal.GetNumPetTypes() do
		local modifier = C_PetBattles.GetAttackModifier(i, j)
		if modifier > 1 then
			table.insert(strongTypes[i], j)
		elseif modifier < 1 then
			table.insert(weakTypes[i], j)
		end
	end
end

StaticPopupDialogs['MIDGET_PETTEAM_DELETE'] = {
	text = 'Are you sure you want to delete team %d?',
	button1 = _G.OKAY,
	button2 = _G.CANCEL,
	OnAccept = function(self, teamIndex)
		addon.DeleteTeam(teamIndex)
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	showAlert = true,
	preferredIndex = 3,
}
StaticPopupDialogs['MIDGET_PETTEAM_RENAME'] = {
	text = 'Enter a name for team %d.',
	button1 = _G.OKAY,
	button2 = _G.CANCEL,
	OnShow = function(self, teamIndex)
		local team = addon.db.teams[teamIndex]
		self.editBox:SetText(team.name or '')
		self.editBox:SetFocus()
	end,
	OnAccept = function(self, teamIndex)
		local name = self.editBox:GetText()
		if name and name ~= '' then
			addon.db.teams[teamIndex].name = (name and name ~= '') and name or nil
			addon.UpdateTabs()
		end
	end,
	EditBoxOnEnterPressed = function(self)
		local popup = self:GetParent()
		StaticPopupDialogs['MIDGET_PETTEAM_RENAME'].OnAccept(popup, popup.data)
		popup:Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
	hasEditBox = true,
}

local function OnClick(tab, btn)
	PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
	if not tab.teamIndex then
		addon.AddTeam()
		addon.UpdateTabs()
	elseif IsModifiedClick('CHATLINK') and ChatEdit_GetActiveWindow() then
		addon.DumpTeam(tab.teamIndex)
	elseif IsControlKeyDown() and btn == 'RightButton' then
		StaticPopup_Show('MIDGET_PETTEAM_DELETE', tab.teamIndex, nil, tab.teamIndex)
	elseif tab.teamIndex == addon.db.selectedTeam then
		-- refresh active team
		-- addon.SaveTeam(tab.teamIndex)
		addon.UpdateTabs()
	else
		addon.LoadTeam(tab.teamIndex)
	end
end
local function OnDoubleClick(tab, btn)
	StaticPopup_Show('MIDGET_PETTEAM_RENAME', tab.teamIndex, nil, tab.teamIndex)
end
local function ShowTooltip(self) if self.UpdateTooltip then self:UpdateTooltip() end end
local function GetTab(index, noCreate)
	local tab = _G["PetJournalTab"..index]
	if not tab and not noCreate then
		tab = CreateFrame("CheckButton", "$parentTab"..index, _G["PetJournal"], "SpellBookSkillLineTabTemplate", index)
		if index == 1 then
			tab:SetPoint("TOPLEFT", "$parent", "TOPRIGHT", 0, -36)
		else
			tab:SetPoint("TOPLEFT", "$parentTab"..(index-1), "BOTTOMLEFT", 0, -22)
		end

		tab:RegisterForClicks("AnyUp")
		tab:SetScript("OnEnter", ShowTooltip)
		tab:SetScript("OnLeave", GameTooltip_Hide)
		tab:SetScript("OnClick", OnClick)
		tab:SetScript("OnDoubleClick", OnDoubleClick)
	end
	return tab
end

local petTypeNone = '|TInterface\\COMMON\\Indicator-Gray:14:14|t'
-- local petTypeNone = '|TInterface\\COMMON\\ReputationStar:14:14:0:1:32:32:0:16:0:16|t'
-- local petTypeNone = '|TInterface\\COMMON\\friendship-heart:0:0:1:-2|t'
local function GetPetTypeIcon(i)
	if not i or not PET_TYPE_SUFFIX[i] then return petTypeNone end
	return '|TInterface\\PetBattles\\PetIcon-'..PET_TYPE_SUFFIX[i]..':14:14:0:0:128:256:63:102:129:168|t'
end
local function GetPetTypeStrength(petType, seperator)
	if not petType or not strongTypes[petType] then return petTypeNone end
	seperator = seperator or ''

	local strenths = strongTypes[petType]
	local string
	for i, otherType in ipairs(strenths) do
		string = (string and string..seperator or '') .. GetPetTypeIcon(otherType)
	end
	return string or petTypeNone
end
local function GetPetTypeWeakness(petType, seperator)
	if not petType or not strongTypes[petType] then return petTypeNone end
	seperator = seperator or ''

	local weaknesses = weakTypes[petType]
	local string
	for i, otherType in ipairs(weaknesses) do
		string = (string and string..seperator or '') .. GetPetTypeIcon(otherType)
	end
	return string or petTypeNone
end

local function SetTeamTooltip(tab)
	local tooltip = GameTooltip
	      tooltip:SetOwner(tab, 'ANCHOR_RIGHT')

	if not tab.teamIndex then return end
	local team = addon.db.teams[tab.teamIndex]
	local weaknesses = ''

	tooltip:AddDoubleLine(team.name or "Team "..tab.teamIndex, '|TInterface\\PetBattles\\BattleBar-AbilityBadge-Weak:20|t ')
	for i, member in ipairs(team) do
		local petID = member.petID
		local speciesID, customName, level, xp, maxXp, displayID, isFavorite, name, icon, petType = C_PetJournal.GetPetInfoByPetID(petID)
		local _, _, _, _, quality = C_PetJournal.GetPetStats(petID)

		-- ability effectiveness, w/o non-attack-moves
		local ability1 = member[1]
			  ability1 = ability1 and not select(8, C_PetBattles.GetAbilityInfoByID(ability1))
			  					  and select(3, C_PetJournal.GetPetAbilityInfo(ability1)) or nil
		local ability2 = member[2]
			  ability2 = ability2 and not select(8, C_PetBattles.GetAbilityInfoByID(ability2))
			  					  and select(3, C_PetJournal.GetPetAbilityInfo(ability2)) or nil
		local ability3 = member[3]
			  ability3 = ability3 and not select(8, C_PetBattles.GetAbilityInfoByID(ability3))
			  					  and select(3, C_PetJournal.GetPetAbilityInfo(ability3)) or nil

		tooltip:AddDoubleLine(
			string.format("%3$d %1$s %5$s%2$s|r%4$s",
				GetPetTypeIcon(petType),
				customName or name or '',
				level or 0,
				level and level < MAX_PET_LEVEL and ' ('..math.floor(xp/maxXp*100)..'%)' or '',
				ITEM_QUALITY_COLORS[(quality or 1) - 1].hex
			),
			string.format("|TInterface\\PetBattles\\BattleBar-AbilityBadge-Strong:20|t %1$s%2$s%3$s",
				GetPetTypeStrength(ability1),
				GetPetTypeStrength(ability2),
				GetPetTypeStrength(ability3)
			)
		)

		weaknesses = weaknesses .. GetPetTypeWeakness(petType)
	end

	local right = _G[tooltip:GetName() .. 'TextRight1']
	right:SetText(right:GetText() .. weaknesses)
	right:SetFontObject('GameTooltipText') -- right header is too big/bold

	local r, g, b = _G.GRAY_FONT_COLOR:GetRGB()
	tooltip:AddLine('|nDouble click to rename this team.')
	tooltip:AddDoubleLine('SHIFT+Left: link in chat|r', 'CTRL+Right: delete|r', r, g, b, r, g, b)

	tooltip:Show()
end

function addon.AddTeam()
	table.insert(addon.db.teams, {})
	local index = #addon.db.teams
	addon.SaveTeam(index)
	addon.LoadTeam(index)
end
function addon.SaveTeam(index, name)
	index = index or addon.db.selectedTeam
	local team = index and addon.db.teams[index]
	if not team then return end

	-- note: this also prevents setting an empty name
	team.name = (name and name ~= '') and name or team.name
	-- ipairs: clear old pets but keep other team attributes
	for i, member in ipairs(team) do
		wipe(team[i])
		team[i].petID = nil
	end
	for i = 1, MAX_ACTIVE_PETS do
		if not team[i] then team[i] = {} end
		team[i].petID, team[i][1], team[i][2], team[i][3] = C_PetJournal.GetPetLoadOutInfo(i)
	end
end
function addon.DeleteTeam(index)
	if addon.db.teams[index] then
		table.remove(addon.db.teams, index)
		addon.LoadTeam(#addon.db.teams)
		addon:UpdateTabs()
	end
end
function addon.LoadTeam(index)
	local team = addon.db.teams[index]
	if not team then return end
	for i = 1, MAX_ACTIVE_PETS do
		if team[i] and team[i].petID then
			local petID = team[i].petID
			local ability1, ability2, ability3 = team[i][1], team[i][2], team[i][3]

			C_PetJournal.SetPetLoadOutInfo(i, petID, true) -- add true to mark that it's us modifying stuff
			C_PetJournal.SetAbility(i, 1, ability1)
			C_PetJournal.SetAbility(i, 2, ability2)
			C_PetJournal.SetAbility(i, 3, ability3)
		else
			-- make slot empty
			-- FIXME: C_PetJournal.SetPetLoadOutInfo(i, 0) used to work but doesn't any more
		end
	end
	addon.db.selectedTeam = index
	PetJournal_UpdatePetLoadOut()
end
function addon.DumpTeam(index)
	local output = ''
	local team = addon.db.teams[index]
	for i = 1, MAX_ACTIVE_PETS do
		if team[i] and team[i].petID then
			output = output .. C_PetJournal.GetBattlePetLink(team[i].petID)
		end
	end
	-- output = (team.name or 'Team '..index) .. ' ' .. output
	ChatEdit_GetActiveWindow():Insert(output)
end

function addon.UpdateTabs()
	local selected = addon.db.selectedTeam or 1
	for index, team in ipairs(addon.db.teams) do
		local speciesID, _, _, _, _, _, _, _, icon = C_PetJournal.GetPetInfoByPetID(team[1].petID)
		local tab = GetTab(index)
		      tab:SetChecked(index == selected)
		      tab:GetNormalTexture():SetTexture(icon)
		      tab:Show()

		tab.teamIndex = index
		tab.UpdateTooltip = SetTeamTooltip
	end

	local numTeams = #addon.db.teams + 1
	local tab = GetTab(numTeams)
	tab:SetChecked(nil)
	tab:GetNormalTexture():SetTexture("Interface\\GuildBankFrame\\UI-GuildBankFrame-NewTab") -- "Interface\\PaperDollInfoFrame\\Character-Plus"
	tab:Show()

	tab.teamIndex = nil
	tab.tooltip = GREEN_FONT_COLOR_CODE..ADD_ANOTHER

	numTeams = numTeams + 1
	while GetTab(numTeams, true) do
		GetTab(numTeams, true):Hide()
		numTeams = numTeams + 1
	end
end

function addon.Update()
	if not _G['PetJournal']:IsVisible() or addon.paused then return end
	local updateActiveTeam = true
	for i = 1, MAX_ACTIVE_PETS do
		local petID, _, _, _, locked = C_PetJournal.GetPetLoadOutInfo(i)
		if not locked and not petID then
			updateActiveTeam = false
			break
		end
	end
	if updateActiveTeam then addon.SaveTeam() end

	addon.UpdateTabs()
end

-- ================================================
-- add show in journal entry to unit dropdowns
-- ================================================
local function CustomizeDropDowns()
	local dropDown = UIDROPDOWNMENU_INIT_MENU
	local which = dropDown.which
	if which then
		for index, value in ipairs(UnitPopupMenus[which]) do
			if value == 'PET_SHOW_IN_JOURNAL' and not (dropDown.unit and UnitIsBattlePet(dropDown.unit)) then
				UnitPopupShown[1][index] = 0
				break
			end
		end
	end
end

-- ================================================
--  Initialization
-- ================================================
function addon:OnEnable()
	-- setup & update saved variables
	if not _G[addonName..'DB'] then _G[addonName..'DB'] = {} end
	addon.db = _G[addonName..'DB']
	if not addon.db.teams then addon.db.teams = {} end

	-- convert petIDs to WoD GUID
	for teamIndex, team in ipairs(addon.db.teams) do
		for memberIndex = 1, MAX_ACTIVE_PETS do
			local petID = team[memberIndex].petID
			if petID and petID:find('^0x') then
				-- convert petID to WoD format
				team[memberIndex].petID = 'BattlePet-0-'..petID:sub(-12)
			end
		end
	end

	-- selected team variable was moved
	if not addon.db.selectedTeam then
		addon.db.selectedTeam = addon.db.teams.selected
	end
	addon.db.teams.selected = nil

	-- update current set when team changes
	hooksecurefunc('PetJournal_UpdatePetLoadOut', addon.Update)

	-- function UnitPopup_ShowMenu (dropdownMenu, which, unit, name, userData)
	-- hooksecurefunc('UnitPopup_ShowMenu', print)
	-- hooksecurefunc('UnitPopup_HideButtons', CustomizeDropDowns)
	-- table.insert(UnitPopupMenus['TARGET'], #UnitPopupMenus['TARGET'], 'PET_SHOW_IN_JOURNAL')
end

addon.frame:RegisterEvent('ADDON_LOADED')
addon.frame:SetScript('OnEvent', function(self, event, ...)
	if event == 'ADDON_LOADED' and ... == addonName then
		self:UnregisterEvent(event)
		addon:OnEnable()
	elseif addon[event] then
		addon[event](event, ...)
	end
end)

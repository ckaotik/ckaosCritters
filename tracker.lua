local addonName, addon, _ = ...

local MAX_PET_LEVEL, MAX_ACTIVE_PETS = 25, 3

local OBJECTIVE_TRACKER_UPDATE_MODULE_BATTLEPETTEAM = 0x4000 -- TODO
local TRACKER = ObjectiveTracker_GetModuleInfoTable()
TRACKER.updateReasonModule = OBJECTIVE_TRACKER_UPDATE_MODULE_BATTLEPETTEAM
TRACKER.usedBlocks = {}

function TRACKER:OnBlockHeaderClick(block, mouseButton)
	-- TODO
	if IsModifiedClick('CHATLINK') and ChatEdit_GetActiveWindow() then
		local hyperlink = ''
		ChatEdit_InsertLink(hyperlink)
	end
end

function TRACKER:Update()
	TRACKER:BeginLayout()
	for petIndex = 1, MAX_ACTIVE_PETS do
		if not addon.db.trackTeam then break end
		local petID = C_PetJournal.GetPetLoadOutInfo(petIndex)
		if not petID then break end

		local _, customName, level, xp, maxXp, _, _, petName, icon, petType = C_PetJournal.GetPetInfoByPetID(petID)
		local health, maxHealth, _, _, rarity = C_PetJournal.GetPetStats(petID)

		local block = self:GetBlock(petIndex)
		self:SetBlockHeader(block, ('|T%2$s:0|t %1$s'):format(customName or petName, icon))
		local pattern = level == MAX_PET_LEVEL and 'L%d' or 'L%d+%2d%%'
		local line = self:AddObjective(block, petIndex, pattern:format(level, xp/maxXp*100), nil, nil, true, ITEM_QUALITY_COLORS[rarity-1])

		-- abusing timer bar as health bar
		-- cause line to move up into objective line
		local lineSpacing = block.module.lineSpacing
		block.module.lineSpacing = -16
		local timerBar = self:AddTimerBar(block, line, maxHealth, nil)
		timerBar:SetScript('OnUpdate', nil)
		timerBar.Bar:SetMinMaxValues(0, maxHealth)
		timerBar.Bar:SetValue(health)
		block.module.lineSpacing = lineSpacing

		-- low health indicator
		--[[ if maxRank < expansionMaxRank then
			timerBar.Bar:SetStatusBarColor(0.26, 0.42, 1)
		else
			timerBar.Bar:SetStatusBarColor(1, 0, 0)
		end --]]

		-- add block to tracker
		block:SetHeight(block.height)
		if ObjectiveTracker_AddBlock(block) then
			block:Show()
			TRACKER:FreeUnusedLines(block)
		else -- we've run out of space
			block.used = false
			break
		end
	end
	TRACKER:EndLayout()
end

local frame = CreateFrame('Frame')
frame:SetScript('OnEvent', function(self, event, ...)
	ObjectiveTracker_Update(OBJECTIVE_TRACKER_UPDATE_MODULE_BATTLEPETTEAM)
end)

local function InitTracker(self)
	table.insert(self.MODULES, TRACKER)
	self.BlocksFrame.BattlePetTeamHeader = CreateFrame('Frame', nil, self.BlocksFrame, 'ObjectiveTrackerHeaderTemplate')
	TRACKER:SetHeader(self.BlocksFrame.BattlePetTeamHeader, 'Team', 0)

	frame:RegisterEvent('PET_BATTLE_CLOSE') -- after pet battle
	hooksecurefunc('PetJournal_UpdatePetLoadOut', frame:GetScript('OnEvent'))
	ObjectiveTracker_Update(OBJECTIVE_TRACKER_UPDATE_MODULE_BATTLEPETTEAM)
end

hooksecurefunc(addon, 'OnEnable', function(self)
	if ObjectiveTrackerFrame.initialized then
		InitTracker(ObjectiveTrackerFrame)
	else
		hooksecurefunc('ObjectiveTracker_Initialize', InitTracker)
	end
end)

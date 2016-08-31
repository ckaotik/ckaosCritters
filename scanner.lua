local addonName, addon, _ = ...

-- GLOBALS: _G, C_PetJournal, GetBattlePetAbilityHyperlink, PetJournal_UpdatePetLoadOut, StaticPopup_Show, GREEN_FONT_COLOR_CODE
-- GLOBALS: coroutine, pairs, ipairs, wipe, unpack, table, print, strjoin

local MAX_ACTIVE_PETS = 3
local NUM_PET_SKILL_SLOTS = 3
local missingPets = {}
local scanSlot = 1

local scanner, timer = nil, 0
local updateFrame = CreateFrame('Frame')
      updateFrame:Hide()
updateFrame:SetScript('OnUpdate', function(self, elapsed)
	timer = timer + elapsed
	if timer > 2 then
		timer = 0
		if not scanner or not coroutine.resume(scanner) then
			self:SetScript('OnUpdate', nil)
			self:Hide()
			addon.paused = nil
			print('Completed pet scan.')
		end
	end
end)

local function CheckPets()
	local scanSlotPetID, _, _, _, isLocked = C_PetJournal.GetPetLoadOutInfo(scanSlot)
	if isLocked then
		print('Can\'t scan pet IDs because slot is locked')
		return
	end

	local abilityIDs, abilityLevels = {}, {}
	for index = 1, C_PetJournal.GetNumPets() do
		local petID, id, owned, _, level, _, revoked, _, _, _, _, _, _, _, canBattle = C_PetJournal.GetPetInfoByIndex(index)
		if owned and not revoked and canBattle then
			wipe(abilityIDs); wipe(abilityLevels)
			C_PetJournal.GetPetAbilityList(id, abilityIDs, abilityLevels)

			-- check if this one has skills a missing pet had
			local isValid = false
			for _, data in pairs(missingPets) do
				local learnsAllSkills = true
				for i = 1, NUM_PET_SKILL_SLOTS do
					local ability1, ability2 = abilityIDs[i], abilityIDs[i + NUM_PET_SKILL_SLOTS]
					local ability1Level, ability2Level = abilityLevels[i], abilityLevels[i + NUM_PET_SKILL_SLOTS]
					-- primary ability is always selected when secondary is not yet available
					local learnsSkill = data[i] == ability1 or (data[i] == ability2 and level >= ability2Level)
					learnsAllSkills = learnsAllSkills and learnsSkill
				end
				-- skill set matches one of our missing pets'
				if learnsAllSkills then
					isValid = true
					break
				end
			end

			if isValid then
				C_PetJournal.SetPetLoadOutInfo(scanSlot, petID, true)
				PetJournal_UpdatePetLoadOut()

				updateFrame:Show()
				coroutine.yield(scanner)

				local petID, ability1, ability2, ability3 = C_PetJournal.GetPetLoadOutInfo(scanSlot)
				local _, _, _, _, _, _, _, name = C_PetJournal.GetPetInfoByPetID(petID)
				for k, data in pairs(missingPets) do
					local skill1, skill2, skill3 = unpack(data, 1, NUM_PET_SKILL_SLOTS)
					if (skill1 == ability1 or skill1 == 0)
						and (skill2 == ability2 or skill2 == 0)
						and (skill3 == ability3 or skill3 == 0)
						and not tContains(data, petID) then
						table.insert(data, petID)
					end
				end
			end
		end
	end

	-- restore previous pet
	C_PetJournal.SetPetLoadOutInfo(scanSlot, scanSlotPetID, true)
	coroutine.yield(scanner)

	local multipleResults = 'There are ' .. _G.YELLOW_FONT_COLOR_CODE .. 'multiple|r pets that match slot #%d on team "%s": %s'
	local singleResult = _G.GREEN_FONT_COLOR_CODE .. 'Matched|r %3$s to slot #%1$d on team "%2$s".'
	local noResult = 'Your pet in slot %1$s on team "%2$s" ' .. _G.RED_FONT_COLOR_CODE .. 'could not be found|r. Please check %3$s for a match.'

	for k, data in pairs(missingPets) do
		local pets, numOptions = '', 0
		while data[NUM_PET_SKILL_SLOTS + numOptions + 1] do
			numOptions = numOptions + 1
			pets = pets .. C_PetJournal.GetBattlePetLink(data[NUM_PET_SKILL_SLOTS + numOptions]) .. ' '
		end

		if numOptions == 1 then
			-- unique matches can be stored immediately
			print(singleResult:format(data.slot, addon.db.teams[data.team].name or 'Team '..data.team, pets))
			addon.db.teams[data.team][data.slot].petID = data[NUM_PET_SKILL_SLOTS + 1]
		elseif numOptions > 1 then
			-- multiple pets match this description, user must choose
			print(multipleResults:format(data.slot, addon.db.teams[data.team].name or 'Team '..data.team, pets))
		else
			-- search was unsuccessful
			local url = 'http://www.wowhead.com/petspecies?filter=cr=15:15:15;crs=0:0:0;crv=' .. strjoin(':', unpack(data, 1, NUM_PET_SKILL_SLOTS))
			local link = ('|cffffffff|Hbcmurl~%s|h[Wowhead]|h|r'):format(url)
			print(noResult:format(data.slot, addon.db.teams[data.team].name or 'Team '..data.team, link))
		end
	end
	addon.UpdateTabs()
end

StaticPopupDialogs['MIDGET_PETTEAM_SCAN'] = {
	text = 'Some pets could not be found. Do you want to try and find the missing pets?|nCAUTION: This process takes a while.',
	button1 = _G.OKAY,
	button2 = _G.CANCEL,
	OnAccept = function()
		scanner = coroutine.create(CheckPets)
		addon.paused = true
		coroutine.resume(scanner)
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

C_PetJournal.GetBattlePetLink("BattlePet-0-0000078CF747")

addon.frame:RegisterEvent('PET_JOURNAL_TRAP_LEVEL_SET')
function addon.PET_JOURNAL_TRAP_LEVEL_SET(event, ...)
	addon.frame:UnregisterEvent(event)

	for team, pets in ipairs(addon.db.teams) do
		for slot, pet in ipairs(pets) do
			-- print(pet.petID, pet.petID and C_PetJournal.GetBattlePetLink(pet.petID) or nil)
			if pet.petID and not C_PetJournal.GetBattlePetLink(pet.petID) then
				table.insert(missingPets, {team = team, slot = slot})
				for i = 1, NUM_PET_SKILL_SLOTS do
					missingPets[#missingPets][i] = pet[i] or 0
				end
			end
		end
	end

	if #missingPets > 0 then
		-- TODO: trigger on demand, avoid in combat etc.
		StaticPopup_Show('MIDGET_PETTEAM_SCAN')
	end
end

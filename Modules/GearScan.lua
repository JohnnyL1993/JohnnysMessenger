-- Approximate "GearScore"-style estimate + level lookup for whoever's
-- selected in the chat panel. This is NOT a reproduction of the original
-- GearScore addon's exact (never publicly documented) formula - it's a
-- similarly-shaped item-level/quality/slot-weighted estimate, good for a
-- quick "how geared are they" read rather than an authoritative number.
--
-- Whispering someone doesn't put them in range: WoW's inspect API only
-- works on a unit you can actually target/mouseover/party/raid with, so a
-- scan can fail with "not in range" even for someone you're actively
-- chatting with.
JM.GearScan = {}
local GearScan = JM.GearScan

local SLOTS = {
	{ name = "HeadSlot", weight = 1.0 },
	{ name = "NeckSlot", weight = 0.75 },
	{ name = "ShoulderSlot", weight = 1.0 },
	{ name = "BackSlot", weight = 0.75 },
	{ name = "ChestSlot", weight = 1.0 },
	{ name = "WristSlot", weight = 0.75 },
	{ name = "HandsSlot", weight = 1.0 },
	{ name = "WaistSlot", weight = 1.0 },
	{ name = "LegsSlot", weight = 1.0 },
	{ name = "FeetSlot", weight = 1.0 },
	{ name = "Finger0Slot", weight = 0.75 },
	{ name = "Finger1Slot", weight = 0.75 },
	{ name = "Trinket0Slot", weight = 0.75 },
	{ name = "Trinket1Slot", weight = 0.75 },
	{ name = "MainHandSlot", weight = 1.5 },
	{ name = "SecondaryHandSlot", weight = 1.0 },
	{ name = "RangedSlot", weight = 0.5 },
}

-- Epic (purple) is the baseline for current-tier raid gear; other qualities
-- scaled relative to it.
local QUALITY_WEIGHT = {
	[0] = 0.2,  -- Poor
	[1] = 0.6,  -- Common
	[2] = 0.8,  -- Uncommon (green)
	[3] = 0.9,  -- Rare (blue)
	[4] = 1.0,  -- Epic (purple)
	[5] = 1.05, -- Legendary
	[6] = 1.1,  -- Artifact
	[7] = 0.95, -- Heirloom
}

local SCALE = 13 -- tuned so ~ilvl 200 epics land near classic-era "geared" GS numbers
local INSPECT_TIMEOUT = 5

local function FindUnit(name)
	local candidates = { "target", "mouseover", "focus" }
	for i = 1, 4 do
		table.insert(candidates, "party" .. i)
	end
	for i = 1, 40 do
		table.insert(candidates, "raid" .. i)
	end
	for _, unit in ipairs(candidates) do
		if UnitExists(unit) and not UnitIsUnit(unit, "player") then
			local unitName = UnitName(unit)
			if unitName and JM.Store.FormatUserName(unitName) == name then
				return unit
			end
		end
	end
	return nil
end
GearScan.FindUnit = FindUnit

local function ComputeScore(unit)
	local total, totalWeight, emptySlots = 0, 0, 0
	for _, slot in ipairs(SLOTS) do
		local slotId = GetInventorySlotInfo(slot.name)
		local link = GetInventoryItemLink(unit, slotId)
		totalWeight = totalWeight + slot.weight
		if link then
			local _, _, quality, itemLevel = GetItemInfo(link)
			if itemLevel then
				local qWeight = QUALITY_WEIGHT[quality] or 0.7
				total = total + (itemLevel * qWeight * slot.weight)
			end
		else
			emptySlots = emptySlots + 1
		end
	end
	if totalWeight == 0 then
		return 0, emptySlots
	end
	return math.floor((total / totalWeight) * SCALE + 0.5), emptySlots
end

local pending
local ticker = CreateFrame("Frame")
ticker:Hide()
ticker:SetScript("OnUpdate", function(self, elapsed)
	if not pending then
		self:Hide()
		return
	end
	pending.elapsed = pending.elapsed + elapsed
	if pending.elapsed > INSPECT_TIMEOUT then
		self:Hide()
		local cb = pending.callback
		pending = nil
		cb({ ok = false, reason = "inspect_timeout" })
	end
end)

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("INSPECT_READY")
watcher:SetScript("OnEvent", function(self, event, guid)
	if not pending then
		return
	end
	if guid and pending.guid and guid ~= pending.guid then
		return
	end
	ticker:Hide()
	local score, emptySlots = ComputeScore(pending.unit)
	local cb = pending.callback
	local level = pending.level
	pending = nil
	cb({ ok = true, level = level, score = score, emptySlots = emptySlots })
end)

-- callback(result) where result is one of:
--   { ok = true, level = number, score = number, emptySlots = number }
--   { ok = false, reason = "not_found" | "inspect_timeout" }
function GearScan:Scan(name, callback)
	local unit = FindUnit(name)
	if not unit or not CanInspect(unit) then
		callback({ ok = false, reason = "not_found" })
		return
	end

	pending = {
		unit = unit,
		guid = UnitGUID(unit),
		level = UnitLevel(unit),
		callback = callback,
		elapsed = 0,
	}
	ticker:Show()
	NotifyInspect(unit)
end

-- Class-color helpers, trimmed from WIM's Sources\Constants.lua. Uses the
-- client's own RAID_CLASS_COLORS table rather than duplicating color values.
JM.ClassColor = {}
local ClassColor = JM.ClassColor

function ClassColor:GetHex(englishClass)
	local c = englishClass and RAID_CLASS_COLORS[englishClass]
	if not c then
		return "ffffff"
	end
	return string.format("%.2x%.2x%.2x", c.r * 255, c.g * 255, c.b * 255)
end

function ClassColor:ColorName(name, englishClass)
	if not name then
		return ""
	end
	return "|cff" .. self:GetHex(englishClass) .. name .. "|r"
end

-- CHAT_MSG_WHISPER/_INFORM pass the sender's GUID as their 12th argument;
-- resolve it to an English class token via GetPlayerInfoByGUID.
function ClassColor:GetClassByGUID(guid)
	if not guid or guid == "" then
		return nil
	end
	local _, englishClass = GetPlayerInfoByGUID(guid)
	return englishClass
end

function ClassColor:GetMyEnglishClass()
	local _, englishClass = UnitClass("player")
	return englishClass
end

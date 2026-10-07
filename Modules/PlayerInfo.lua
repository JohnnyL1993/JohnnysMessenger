-- Best-effort presence/level/zone for a conversation partner. 3.3.5a has no
-- general "look up any player" API, so this merges whatever the client
-- already knows: friends list, guild roster, current group, and finally the
-- conversation's own session flags (convo.online / convo.away, set by
-- WhisperEngine from whisper traffic and "player not found" errors).
JM.PlayerInfo = {}
local PlayerInfo = JM.PlayerInfo

local friends, guild = {}, {}

-- Localized class name ("Paladin"/"Paladine") -> English token ("PALADIN").
local classTokenByLocalized = {}
local function BuildClassMap()
	for token, localized in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do
		classTokenByLocalized[localized] = token
	end
	for token, localized in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do
		classTokenByLocalized[localized] = token
	end
end

local function StatusFromFlag(flag)
	if not flag or flag == "" then
		return "online"
	end
	if string.find(flag, "DND") or string.find(flag, (CHAT_FLAG_DND or "<DND>"), 1, true) then
		return "dnd"
	end
	if string.find(flag, "AFK") or string.find(flag, (CHAT_FLAG_AFK or "<AFK>"), 1, true) then
		return "afk"
	end
	return "online"
end

local function ScanFriends()
	wipe(friends)
	for i = 1, GetNumFriends() do
		local name, level, class, area, connected, status = GetFriendInfo(i)
		if name then
			friends[JM.Store.FormatUserName(name)] = {
				level = level,
				class = classTokenByLocalized[class],
				zone = area,
				status = connected and StatusFromFlag(status) or "offline",
			}
		end
	end
end

local function ScanGuild()
	wipe(guild)
	if not IsInGuild() then
		return
	end
	for i = 1, GetNumGuildMembers(true) do
		local name, _, _, level, class, zone, _, _, online, status, classFileName = GetGuildRosterInfo(i)
		if name then
			local afkDnd = (status == 1 and "afk") or (status == 2 and "dnd") or nil
			guild[JM.Store.FormatUserName(name)] = {
				level = level,
				class = classFileName or classTokenByLocalized[class],
				zone = zone,
				status = online and (afkDnd or StatusFromFlag(type(status) == "string" and status or nil)) or "offline",
			}
		end
	end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event)
	if event == "FRIENDLIST_UPDATE" then
		ScanFriends()
	elseif event == "GUILD_ROSTER_UPDATE" then
		ScanGuild()
	end
	JM.MainFrame:OnPresenceChanged()
end)

function PlayerInfo:Init()
	BuildClassMap()
	events:RegisterEvent("FRIENDLIST_UPDATE")
	events:RegisterEvent("GUILD_ROSTER_UPDATE")
	events:RegisterEvent("PARTY_MEMBERS_CHANGED")
	events:RegisterEvent("RAID_ROSTER_UPDATE")
	ShowFriends()
	self:RequestGuildRoster()
end

-- GuildRoster() is server-throttled; only ask occasionally (window opens).
local lastGuildRequest = 0
function PlayerInfo:RequestGuildRoster()
	if IsInGuild() and GetTime() - lastGuildRequest > 30 then
		lastGuildRequest = GetTime()
		GuildRoster()
	end
end

local function FromGroup(name)
	if not (UnitInParty(name) or UnitInRaid(name)) then
		return nil
	end
	local _, class = UnitClass(name)
	local status = "online"
	if not UnitIsConnected(name) then
		status = "offline"
	elseif UnitIsAFK(name) then
		status = "afk"
	elseif UnitIsDND(name) then
		status = "dnd"
	end
	return { level = UnitLevel(name), class = class, status = status }
end

-- Returns { status, level, class, zone } with any field possibly nil.
-- status is "online" | "afk" | "dnd" | "offline" | nil (unknown).
function PlayerInfo:Get(name, convo)
	local info = FromGroup(name) or friends[name] or guild[name]
	local result = {}
	if info then
		for k, v in pairs(info) do
			result[k] = v
		end
	end
	if convo then
		result.class = result.class or convo.class
		result.level = result.level or convo.level
		if not result.status then
			if convo.online == false then
				result.status = "offline"
			elseif convo.online then
				result.status = convo.away or "online"
			end
		elseif result.status == "online" and convo.away then
			result.status = convo.away
		end
		-- Remember level/class so an offline contact still shows them.
		if info then
			convo.level = info.level or convo.level
			convo.class = info.class or convo.class
		end
	end
	return result
end

local STATUS_LABELS = { online = "Online", afk = "Away", dnd = "Busy", offline = "Offline" }
function PlayerInfo:StatusLabel(status)
	return STATUS_LABELS[status] or ""
end

-- "80 Paladin" style line from whatever is known.
function PlayerInfo:Describe(info)
	local parts = {}
	if info.level and info.level > 0 then
		table.insert(parts, tostring(info.level))
	end
	if info.class then
		table.insert(parts, (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[info.class]) or info.class)
	end
	local text = table.concat(parts, " ")
	if info.zone and info.zone ~= "" and info.status ~= "offline" then
		text = text ~= "" and (text .. "  |  " .. info.zone) or info.zone
	end
	return text
end

-- Class icon from the character-create sprite sheet (exists on 3.3.5a).
local CLASS_SHEET = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local FALLBACK_COORDS = {
	WARRIOR = { 0, 0.25, 0, 0.25 },
	MAGE = { 0.25, 0.49609375, 0, 0.25 },
	ROGUE = { 0.49609375, 0.7421875, 0, 0.25 },
	DRUID = { 0.7421875, 0.98828125, 0, 0.25 },
	HUNTER = { 0, 0.25, 0.25, 0.5 },
	SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 },
	PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 },
	WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 },
	PALADIN = { 0, 0.25, 0.5, 0.75 },
	DEATHKNIGHT = { 0.25, 0.49609375, 0.5, 0.75 },
}

function PlayerInfo:SetClassIcon(texture, class)
	local coords = class and ((CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]) or FALLBACK_COORDS[class])
	if coords then
		texture:SetTexture(CLASS_SHEET)
		texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
	else
		texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
		texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
end

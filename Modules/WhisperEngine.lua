-- Whisper capture/send, adapted from WIM's Modules\WhisperEngine.lua but
-- feeding JM.Store instead of a per-conversation floating window. By default
-- every whisper-related event is blocked from the default chat frame so this
-- addon's window is the sole surface for whispers (Teams-style DMs, not
-- duplicated into the chat log); the hideFromChat setting turns that off.
JM.Whisper = {}
local WhisperEngine = JM.Whisper

LibStub:GetLibrary("LibChatHandler-1.0"):Embed(WhisperEngine)

function WhisperEngine:Init()
	self:RegisterChatEvent("CHAT_MSG_WHISPER")
	self:RegisterChatEvent("CHAT_MSG_WHISPER_INFORM")
	self:RegisterChatEvent("CHAT_MSG_AFK")
	self:RegisterChatEvent("CHAT_MSG_DND")
	self:RegisterChatEvent("CHAT_MSG_SYSTEM")
end

-- Registered directly as a field (not via colon syntax), so it's called as
-- delegate(self, eventItem, ...) by LibChatHandler - self is the module
-- table here, eventItem is the actual chat-event object to block.
local function BlockController(self, eventItem)
	if JM.Settings:Get("hideFromChat") then
		eventItem:BlockFromChatFrame()
	end
end
WhisperEngine.CHAT_MSG_WHISPER_CONTROLLER = BlockController
WhisperEngine.CHAT_MSG_WHISPER_INFORM_CONTROLLER = BlockController
WhisperEngine.CHAT_MSG_AFK_CONTROLLER = BlockController
WhisperEngine.CHAT_MSG_DND_CONTROLLER = BlockController
-- CHAT_MSG_SYSTEM carries lots of unrelated text; leave it visible in chat.

-- The whisper sound. Messenger always plays it itself (the chat window stays
-- silent if no chat tab shows whispers). Choices: the game's own whisper
-- sound, Messenger's chime, or any sound another addon has registered with
-- LibSharedMedia - ElvUI's "Whisper Alert", for one.
local CHIME = "Interface\\AddOns\\JohnnysMessenger\\Media\\Sounds\\chime.wav"

local function LSM()
	return LibStub and LibStub:GetLibrary("LibSharedMedia-3.0", true)
end

-- { key, label } for every choice available right now. "lsm:<name>" keys
-- point at LibSharedMedia sounds.
function WhisperEngine:GetSoundChoices()
	local list = {
		{ key = "default", label = "WoW whisper" },
		{ key = "chime", label = "Messenger chime" },
	}
	local lsm = LSM()
	if lsm then
		local names = {}
		for _, name in ipairs(lsm:List("sound") or {}) do
			if name ~= "None" then
				table.insert(names, name)
			end
		end
		table.sort(names)
		for _, name in ipairs(names) do
			table.insert(list, { key = "lsm:" .. name, label = name, shared = true })
		end
	end
	return list
end

function WhisperEngine:SoundLabel(key)
	key = key or "default"
	if key == "default" then
		return "WoW whisper"
	elseif key == "chime" then
		return "Messenger chime"
	end
	return string.sub(key, 5)
end

function WhisperEngine:PlayWhisperSound()
	local key = JM.Settings:Get("soundName") or "default"
	local file
	if key == "chime" then
		file = CHIME
	elseif string.sub(key, 1, 4) == "lsm:" then
		local lsm = LSM()
		file = lsm and lsm:Fetch("sound", string.sub(key, 5), true)
	end
	if file and pcall(PlaySoundFile, file, "Master") then
		return
	end
	-- The game sound; with sound effects off it goes out on Master instead.
	if GetCVar("Sound_EnableSFX") == "0" then
		pcall(PlaySoundFile, "Sound\\Interface\\iTellMessage.wav", "Master")
	else
		PlaySound("TellMessage")
	end
end

function WhisperEngine:CHAT_MSG_WHISPER(msg, author, _, _, _, _, _, _, _, _, _, guid)
	local englishClass = JM.ClassColor:GetClassByGUID(guid)
	local convo = JM.Store:AddMessage(author, englishClass, msg, true)
	ChatEdit_SetLastTellTarget(author)
	local name = JM.Store.FormatUserName(author)
	-- No sound while the window is up (you can see the message arrive),
	-- unless "even while the window is open" is ticked.
	local window = _G.JM_MainFrame
	local open = window and window:IsShown()
	if JM.Settings:Get("sound") and convo and not convo.muted and (not open or JM.Settings:Get("soundWhenOpen")) then
		WhisperEngine:PlayWhisperSound()
	end
	-- Pop the window open on the incoming conversation if it's not already
	-- open on something else, same as WIM did for individual whisper windows
	-- - whispers otherwise have no other visible surface since they're
	-- blocked from the default chat frame. If the user is already viewing/
	-- typing to someone else, don't yank them away - just update the list.
	JM.MainFrame:HandleIncomingWhisper(name)
	JM.Minimap:UpdateBadge()
end

-- Whispers typed in the normal chat box (/w, /r): remembered here so the
-- echo below can open that conversation. Whispers other addons send happen
-- with no chat box open, so they never count.
local typedWhispers = {}
hooksecurefunc("SendChatMessage", function(msg, chatType, _, target)
	if chatType ~= "WHISPER" or not target then
		return
	end
	local box = (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()) or ACTIVE_CHAT_EDIT_BOX
	if box and box:IsShown() then
		typedWhispers[JM.Store.FormatUserName(target)] = GetTime()
	end
end)

function WhisperEngine:CHAT_MSG_WHISPER_INFORM(msg, target, _, _, _, _, _, _, _, _, _, guid)
	local englishClass = JM.ClassColor:GetClassByGUID(guid)
	JM.Store:AddMessage(target, englishClass, msg, false)
	ChatEdit_SetLastToldTarget(target)
	local name = JM.Store.FormatUserName(target)
	local typedAt = typedWhispers[name]
	typedWhispers[name] = nil
	if typedAt and GetTime() - typedAt < 10 and JM.Settings:Get("openOnSend") and not InCombatLockdown() then
		JM.MainFrame:Show()
		JM.MainFrame:SelectConversation(name)
		return
	end
	JM.MainFrame:OnMessageReceived(name)
end

-- Their AFK/DND auto-reply: mark them away and show the reply in the thread.
local function AwayReply(flag, label)
	return function(self, msg, author)
		local convo = JM.Store:GetConversation(author)
		if not convo then
			return
		end
		convo.online = true
		convo.onlineAt = time()
		convo.away = flag
		local name = JM.Store.FormatUserName(author)
		local text = name .. " is " .. label
		if msg and msg ~= "" then
			text = text .. ": " .. msg
		end
		JM.Store:AddSystemMessage(name, text)
		JM.MainFrame:OnMessageReceived(name)
	end
end
WhisperEngine.CHAT_MSG_AFK = AwayReply("afk", "away")
WhisperEngine.CHAT_MSG_DND = AwayReply("dnd", "busy (do not disturb)")

-- Turns a GlobalStrings format ("%s has gone offline.") into a match
-- pattern whose first %s is a capture.
local function ToPattern(fmt)
	if not fmt then
		return nil
	end
	local p = string.gsub(fmt, "%%s", "\001")
	p = string.gsub(p, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
	p = string.gsub(p, "\001", "(.-)", 1)
	p = string.gsub(p, "\001", ".-")
	return "^" .. p .. "$"
end

local notFoundPattern, wentOfflinePattern, cameOnlinePattern
function WhisperEngine:CHAT_MSG_SYSTEM(msg)
	notFoundPattern = notFoundPattern or ToPattern(ERR_CHAT_PLAYER_NOT_FOUND_S)
	wentOfflinePattern = wentOfflinePattern or ToPattern(ERR_FRIEND_OFFLINE_S)
	cameOnlinePattern = cameOnlinePattern or ToPattern(ERR_FRIEND_ONLINE_SS)
	local offlineName = notFoundPattern and string.match(msg, notFoundPattern)
	if offlineName then
		local convo = JM.Store:GetConversation(offlineName)
		if convo then
			local name = JM.Store.FormatUserName(offlineName)
			convo.online = false
			convo.onlineAt = time()
			convo.away = nil
			JM.Store:AddSystemMessage(name, name .. " is not online.")
			JM.MainFrame:OnMessageReceived(name)
		end
		return
	end
	-- Friend/guild log-in and log-out notices: update the dot quietly.
	local leftName = wentOfflinePattern and string.match(msg, wentOfflinePattern)
	local joinedName = not leftName and cameOnlinePattern and string.match(msg, cameOnlinePattern)
	local who = leftName or joinedName
	if who then
		local convo = JM.Store:GetConversation(who)
		if convo then
			convo.online = joinedName and true or false
			convo.onlineAt = time()
			convo.away = nil
			JM.MainFrame:OnPresenceChanged()
		end
	end
end

--------------------------------------
--          Sending                 --
--------------------------------------

local splitWords = {}
local function SplitToWords(str, tbl)
	for k in pairs(tbl) do
		tbl[k] = nil
	end
	local i = 1
	for word in string.gmatch(str, "%S+") do
		tbl[i] = word
		i = i + 1
	end
	return i - 1
end

function WhisperEngine:SendWhisper(target, msg)
	if not target or target == "" or not msg or msg == "" then
		return
	end

	if string.len(msg) <= 255 then
		ChatThrottleLib:SendChatMessage("ALERT", "JohnnysMessenger", msg, "WHISPER", nil, target)
		return
	end

	-- Message too long: split on word boundaries into <=254 char chunks.
	local count = SplitToWords(msg, splitWords)
	local chunk = ""
	for i = 1, count + 1 do
		local word = splitWords[i]
		if word and string.len(chunk) + string.len(word) <= 254 then
			chunk = chunk .. word .. " "
		else
			if chunk ~= "" then
				ChatThrottleLib:SendChatMessage("ALERT", "JohnnysMessenger", chunk, "WHISPER", nil, target)
			end
			chunk = (word or "") .. " "
		end
	end
end

--------------------------------------
--   Redirect default whisper UX    --
--------------------------------------

-- Replaces /w, /whisper, /t, /tell so typing them opens this addon's window
-- on that conversation instead of the default whisper edit box.
local origWhisperHandler = SlashCmdList["WHISPER"]
if origWhisperHandler then
	SlashCmdList["WHISPER"] = function(msg, editBox)
		local target, body = string.match(msg or "", "^(%S+)%s*(.*)$")
		if target and target ~= "" then
			JM.MainFrame:Show()
			JM.MainFrame:SelectConversation(JM.Store.FormatUserName(target))
			if body and body ~= "" then
				WhisperEngine:SendWhisper(target, body)
				return
			end
		else
			JM.MainFrame:Show()
		end
		JM.MainFrame:FocusEditBox()
	end
end

-- Reply hotkey ("R" by default) - redirect focus into our window instead of
-- the default chat edit box.
hooksecurefunc("ChatFrame_ReplyTell", function()
	local target = ChatEdit_GetLastTellTarget()
	if target and target ~= "" then
		JM.MainFrame:Show()
		JM.MainFrame:SelectConversation(JM.Store.FormatUserName(target))
		JM.MainFrame:FocusEditBox()
	end
end)

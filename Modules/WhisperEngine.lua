-- Whisper capture/send, adapted from WIM's Modules\WhisperEngine.lua but
-- feeding JM.Store instead of a per-conversation floating window. Every
-- whisper-related event is blocked from the default chat frame so this
-- addon's window is the sole surface for whispers (Teams-style DMs, not
-- duplicated into the chat log).
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
	eventItem:BlockFromChatFrame()
end
WhisperEngine.CHAT_MSG_WHISPER_CONTROLLER = BlockController
WhisperEngine.CHAT_MSG_WHISPER_INFORM_CONTROLLER = BlockController
WhisperEngine.CHAT_MSG_AFK_CONTROLLER = BlockController
WhisperEngine.CHAT_MSG_DND_CONTROLLER = BlockController
-- CHAT_MSG_SYSTEM carries lots of unrelated text; leave it visible in chat.

function WhisperEngine:CHAT_MSG_WHISPER(msg, author, _, _, _, _, _, _, _, _, _, guid)
	local englishClass = JM.ClassColor:GetClassByGUID(guid)
	JM.Store:AddMessage(author, englishClass, msg, true)
	ChatEdit_SetLastTellTarget(author)
	local name = JM.Store.FormatUserName(author)
	-- Pop the window open on the incoming conversation if it's not already
	-- open on something else, same as WIM did for individual whisper windows
	-- - whispers otherwise have no other visible surface since they're
	-- blocked from the default chat frame. If the user is already viewing/
	-- typing to someone else, don't yank them away - just update the list.
	JM.MainFrame:HandleIncomingWhisper(name)
	JM.Minimap:UpdateBadge()
end

function WhisperEngine:CHAT_MSG_WHISPER_INFORM(msg, target, _, _, _, _, _, _, _, _, _, guid)
	local englishClass = JM.ClassColor:GetClassByGUID(guid)
	JM.Store:AddMessage(target, englishClass, msg, false)
	ChatEdit_SetLastToldTarget(target)
	JM.MainFrame:OnMessageReceived(JM.Store.FormatUserName(target))
end

function WhisperEngine:CHAT_MSG_AFK(_, author)
	local convo = JM.Store:GetConversation(author)
	if convo then
		convo.online = true
	end
end
WhisperEngine.CHAT_MSG_DND = WhisperEngine.CHAT_MSG_AFK

local notFoundPattern
function WhisperEngine:CHAT_MSG_SYSTEM(msg)
	notFoundPattern = notFoundPattern or string.gsub(ERR_CHAT_PLAYER_NOT_FOUND_S, "%%s", "(.+)")
	local offlineName = string.match(msg, notFoundPattern)
	if offlineName then
		local convo = JM.Store:GetConversation(offlineName)
		if convo then
			convo.online = false
			JM.MainFrame:OnMessageReceived(JM.Store.FormatUserName(offlineName))
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

-- Plain-data conversation model, decoupled from any UI (WIM fused its window
-- objects and message data together; this keeps them separate so MainFrame
-- is just a view over this store). Shape mirrors WIM's WIM3_History for
-- familiarity: history[realm][character][partnerName] = { class, messages, lastMessageTime }.
JM.Store = {}
local Store = JM.Store

local MAX_MESSAGES = 200
local MAX_AGE = 60 * 60 * 24 * 30 -- 30 days

-- Normalizes a player name to Title Case (e.g. "bob" / "BOB" -> "Bob") so the
-- same person always maps to the same conversation key regardless of how
-- their name arrived (chat event vs. user-typed target).
function Store.FormatUserName(user)
	if user then
		user = string.gsub(user, "[A-Z]", string.lower)
		user = string.gsub(user, "^[a-z]", string.upper)
		user = string.gsub(user, "-[a-z]", string.upper) -- cross-realm names
	end
	return user
end

function Store:Init()
	local realm = GetRealmName()
	local character = UnitName("player")
	local history = JM.db.history
	history[realm] = history[realm] or {}
	history[realm][character] = history[realm][character] or {}
	self.conversations = history[realm][character]

	-- "online" is session state, never persisted as true across a reload.
	for _, convo in pairs(self.conversations) do
		convo.online = false
	end

	self:Prune()
end

function Store:GetConversation(name, create)
	name = Store.FormatUserName(name)
	if not name or name == "" then
		return nil
	end
	local convo = self.conversations[name]
	if not convo and create then
		convo = { messages = {}, unreadCount = 0, lastMessageTime = 0 }
		self.conversations[name] = convo
	end
	return convo
end

function Store:AddMessage(name, englishClass, msg, inbound)
	name = Store.FormatUserName(name)
	if not name or name == "" or not msg then
		return nil
	end
	local convo = self:GetConversation(name, true)
	if englishClass then
		convo.class = englishClass
	end

	local now = time()
	table.insert(convo.messages, {
		msg = msg,
		time = now,
		inbound = inbound,
		class = inbound and (englishClass or convo.class) or nil,
	})
	convo.lastMessageTime = now
	convo.online = true

	while #convo.messages > MAX_MESSAGES do
		table.remove(convo.messages, 1)
	end

	if inbound then
		convo.unreadCount = (convo.unreadCount or 0) + 1
	end

	return convo
end

function Store:MarkRead(name)
	local convo = self:GetConversation(name)
	if convo then
		convo.unreadCount = 0
	end
end

function Store:GetTotalUnread()
	local total = 0
	for _, convo in pairs(self.conversations) do
		total = total + (convo.unreadCount or 0)
	end
	return total
end

function Store:GetSortedConversationList()
	local list = {}
	for name, convo in pairs(self.conversations) do
		table.insert(list, { name = name, convo = convo })
	end
	table.sort(list, function(a, b)
		return (a.convo.lastMessageTime or 0) > (b.convo.lastMessageTime or 0)
	end)
	return list
end

function Store:Prune()
	local cutoff = time() - MAX_AGE
	for _, convo in pairs(self.conversations) do
		if convo.messages then
			while convo.messages[1] and convo.messages[1].time < cutoff do
				table.remove(convo.messages, 1)
			end
			while #convo.messages > MAX_MESSAGES do
				table.remove(convo.messages, 1)
			end
		end
	end
end

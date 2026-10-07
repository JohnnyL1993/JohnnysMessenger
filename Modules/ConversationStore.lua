-- Plain-data conversation model, decoupled from any UI (WIM fused its window
-- objects and message data together; this keeps them separate so MainFrame
-- is just a view over this store). Shape mirrors WIM's WIM3_History for
-- familiarity: history[realm][character][partnerName] = { class, messages, lastMessageTime }.
JM.Store = {}
local Store = JM.Store

-- Limits come from JM.Settings (maxMessages, retentionDays).
local function MaxMessages()
	return JM.Settings:Get("maxMessages") or 200
end

local function MaxAge()
	return (JM.Settings:Get("retentionDays") or 30) * 86400
end

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

	-- "online"/"away" are session state, never persisted across a reload
	-- (nil = unknown, so a fresh session doesn't claim everyone is offline).
	for _, convo in pairs(self.conversations) do
		convo.online = nil
		convo.away = nil
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

local function Trim(convo)
	local max = MaxMessages()
	while #convo.messages > max do
		table.remove(convo.messages, 1)
	end
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
	if inbound then
		-- Sending chat clears AFK/DND in WoW, so a fresh whisper from them
		-- means they're no longer away.
		convo.away = nil
		convo.unreadCount = (convo.unreadCount or 0) + 1
	end

	Trim(convo)
	return convo
end

-- Grey centered line in the thread (AFK/DND auto-replies, "not online").
-- Identical system text within 60s is dropped - an AFK auto-reply comes back
-- on every whisper you send, which would otherwise spam the thread.
function Store:AddSystemMessage(name, text)
	local convo = self:GetConversation(name)
	if not convo or not text then
		return nil
	end
	local now = time()
	for i = #convo.messages, math.max(1, #convo.messages - 5), -1 do
		local m = convo.messages[i]
		if m.kind == "system" and m.msg == text and now - m.time < 60 then
			return nil
		end
	end
	table.insert(convo.messages, { msg = text, time = now, kind = "system" })
	Trim(convo)
	return convo
end

function Store:MarkRead(name)
	local convo = self:GetConversation(name)
	if convo then
		convo.unreadCount = 0
		convo.lastReadTime = time()
	end
end

function Store:MarkAllRead()
	for _, convo in pairs(self.conversations) do
		if (convo.unreadCount or 0) > 0 then
			convo.unreadCount = 0
			convo.lastReadTime = time()
		end
	end
end

-- Flags the trailing run of their messages as unread again.
function Store:MarkUnread(name)
	local convo = self:GetConversation(name)
	if not convo then
		return
	end
	local count, firstTime = 0, nil
	for i = #convo.messages, 1, -1 do
		local m = convo.messages[i]
		if m.inbound then
			count = count + 1
			firstTime = m.time
		elseif m.kind ~= "system" then
			break
		end
	end
	if count == 0 then
		count = 1
	end
	convo.unreadCount = count
	convo.lastReadTime = (firstTime or time()) - 1
end

function Store:RemoveConversation(name)
	name = Store.FormatUserName(name)
	if name then
		self.conversations[name] = nil
	end
end

function Store:GetTotalUnread()
	local total = 0
	for _, convo in pairs(self.conversations) do
		total = total + (convo.unreadCount or 0)
	end
	return total
end

-- Names with unread messages, most recent first (minimap tooltip).
function Store:GetUnreadNames(limit)
	local names = {}
	for _, entry in ipairs(self:GetSortedConversationList()) do
		if (entry.convo.unreadCount or 0) > 0 then
			table.insert(names, entry)
			if limit and #names >= limit then
				break
			end
		end
	end
	return names
end

-- Pinned conversations first, then most recent. Optional case-insensitive
-- name filter for the search box. Empty conversations (opened via "New
-- whisper" but never used) are only listed while they have a draft.
function Store:GetSortedConversationList(filter)
	filter = filter and filter ~= "" and string.lower(filter) or nil
	local list = {}
	for name, convo in pairs(self.conversations) do
		local hasContent = #convo.messages > 0 or (convo.draft and convo.draft ~= "") or convo.keep
		if hasContent and (not filter or string.find(string.lower(name), filter, 1, true)) then
			table.insert(list, { name = name, convo = convo })
		end
	end
	table.sort(list, function(a, b)
		local pa, pb = a.convo.pinned and 1 or 0, b.convo.pinned and 1 or 0
		if pa ~= pb then
			return pa > pb
		end
		return (a.convo.lastMessageTime or 0) > (b.convo.lastMessageTime or 0)
	end)
	return list
end

function Store:Prune()
	local cutoff = time() - MaxAge()
	for name, convo in pairs(self.conversations) do
		convo.keep = nil
		if convo.messages then
			while convo.messages[1] and convo.messages[1].time < cutoff do
				table.remove(convo.messages, 1)
			end
			Trim(convo)
			if #convo.messages == 0 and not convo.pinned and not (convo.draft and convo.draft ~= "") then
				self.conversations[name] = nil
			end
		end
	end
end

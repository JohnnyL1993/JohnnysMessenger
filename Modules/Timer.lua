-- Minimal one-shot timer (3.3.5a has no C_Timer). A single hidden OnUpdate
-- frame drives every pending callback, and only runs while something is
-- actually scheduled.
JM.Timer = {}
local Timer = JM.Timer

local pending = {}
local driver = CreateFrame("Frame")
driver:Hide()

driver:SetScript("OnUpdate", function(self)
	local now = GetTime()
	local i = 1
	while i <= #pending do
		local entry = pending[i]
		if now >= entry.at then
			table.remove(pending, i)
			entry.fn()
		else
			i = i + 1
		end
	end
	if #pending == 0 then
		self:Hide()
	end
end)

function Timer:After(seconds, fn)
	table.insert(pending, { at = GetTime() + (seconds or 0), fn = fn })
	driver:Show()
end

-- Collapses bursts of calls (e.g. OnSizeChanged firing every frame while a
-- window is dragged) into one call `seconds` after the last request.
function Timer:Debounce(seconds, fn)
	local token = 0
	return function()
		token = token + 1
		local mine = token
		Timer:After(seconds, function()
			if mine == token then
				fn()
			end
		end)
	end
end

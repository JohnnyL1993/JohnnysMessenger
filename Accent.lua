-- Shared accent colour for every Johnny addon. Each addon carries this same
-- file (so none depends on another); the first one to load creates the
-- shared JohnnysAccent object and the rest reuse it, so one choice recolours
-- the whole suite. Saved in JohnnysAccentDB, which every Johnny addon
-- declares - the newest saved choice wins when they load.
--
-- Code uses JohnnysAccent.color (an {r, g, b} table, updated in place) and
-- JohnnysAccent.hex ("b9e24a" style, for |cff colour codes).
if not JohnnysAccent then
	local DEFAULT = { 0.725, 0.886, 0.290 }

	JohnnysAccent = {
		color = { DEFAULT[1], DEFAULT[2], DEFAULT[3] },
		stamp = 0,
		hex = "b9e24a",
	}
	local A = JohnnysAccent

	A.PRESETS = {
		{ "Lime (default)", 0.725, 0.886, 0.290 },
		{ "Green", 0.300, 0.850, 0.450 },
		{ "Teal", 0.250, 0.800, 0.750 },
		{ "Blue", 0.300, 0.600, 1.000 },
		{ "Purple", 0.660, 0.450, 1.000 },
		{ "Pink", 1.000, 0.450, 0.750 },
		{ "Red", 1.000, 0.350, 0.350 },
		{ "Orange", 1.000, 0.600, 0.200 },
		{ "Gold", 1.000, 0.820, 0.250 },
		{ "White", 0.920, 0.940, 0.930 },
	}

	local function Clamp(v)
		v = tonumber(v) or 0
		return math.max(0, math.min(1, v))
	end

	local function Apply(r, g, b, stamp)
		A.color[1], A.color[2], A.color[3] = Clamp(r), Clamp(g), Clamp(b)
		A.hex = string.format("%02x%02x%02x", math.floor(A.color[1] * 255 + 0.5), math.floor(A.color[2] * 255 + 0.5), math.floor(A.color[3] * 255 + 0.5))
		A.stamp = stamp or 0
	end

	local function Save()
		JohnnysAccentDB = { r = A.color[1], g = A.color[2], b = A.color[3], stamp = A.stamp, fx = A.fx }
	end

	-- Every addon that loads brings its own copy of JohnnysAccentDB; keep the
	-- newest choice and hand it back, so all of them save the same thing.
	local loader = CreateFrame("Frame")
	loader:RegisterEvent("ADDON_LOADED")
	loader:SetScript("OnEvent", function()
		local db = JohnnysAccentDB
		if type(db) == "table" and tonumber(db.stamp) and db.stamp > A.stamp and db.r and db.g and db.b then
			Apply(db.r, db.g, db.b, db.stamp)
			A.fx = type(db.fx) == "table" and db.fx or A.fx
		end
		Save()
	end)

	function A:Set(r, g, b)
		Apply(r, g, b, time())
		Save()
	end

	-- Saves a change to the effects settings (newest wins across addons).
	function A:Touch()
		A.stamp = time()
		Save()
		if JohnnysFX and JohnnysFX.Refresh then
			JohnnysFX:Refresh()
		end
	end

	StaticPopupDialogs["JOHNNYS_ACCENT_RELOAD"] = {
		text = "Accent colour changed.\n\nReload the UI now so every Johnny addon picks it up?",
		button1 = "Reload",
		button2 = "Later",
		OnAccept = function() ReloadUI() end,
		timeout = 0,
		whileDead = 1,
		hideOnEscape = 1,
	}

	local function Changed()
		StaticPopup_Show("JOHNNYS_ACCENT_RELOAD")
	end

	-- Custom colour through the game's own colour picker.
	function A:ShowPicker()
		local before = { A.color[1], A.color[2], A.color[3] }
		local changed = false
		-- Set the starting colour first: assigning func before it would fire
		-- func straight away and count as a change.
		ColorPickerFrame.func = nil
		ColorPickerFrame.cancelFunc = nil
		ColorPickerFrame:SetColorRGB(A.color[1], A.color[2], A.color[3])
		ColorPickerFrame.hasOpacity = false
		ColorPickerFrame.previousValues = before
		ColorPickerFrame.func = function()
			local r, g, b = ColorPickerFrame:GetColorRGB()
			A:Set(r, g, b)
			changed = true
		end
		ColorPickerFrame.cancelFunc = function()
			A:Set(before[1], before[2], before[3])
			changed = false
		end
		ColorPickerFrame:Hide()
		ColorPickerFrame:Show()
		if not A.pickerHooked then
			A.pickerHooked = true
			ColorPickerFrame:HookScript("OnHide", function()
				if A.pickerChanged and A.pickerChanged() then
					A.pickerChanged = nil
					Changed()
				end
			end)
		end
		A.pickerChanged = function() return changed end
	end

	local menuFrame
	-- Presets plus "Custom..." in a small menu, opened from any Johnny addon.
	function A:ShowMenu()
		menuFrame = menuFrame or CreateFrame("Frame", "JohnnysAccentMenu", UIParent, "UIDropDownMenuTemplate")
		local menu = { { text = "Accent colour (all Johnny addons)", isTitle = 1, notCheckable = 1 } }
		for _, p in ipairs(A.PRESETS) do
			local name, r, g, b = p[1], p[2], p[3], p[4]
			table.insert(menu, {
				text = string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, name),
				checked = math.abs(A.color[1] - r) < 0.01 and math.abs(A.color[2] - g) < 0.01 and math.abs(A.color[3] - b) < 0.01,
				func = function()
					A:Set(r, g, b)
					Changed()
				end,
			})
		end
		local _, class = UnitClass("player")
		local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
		if cc then
			table.insert(menu, {
				text = string.format("|cff%02x%02x%02xMy class colour|r", cc.r * 255, cc.g * 255, cc.b * 255),
				notCheckable = 1,
				func = function()
					A:Set(cc.r, cc.g, cc.b)
					Changed()
				end,
			})
		end
		table.insert(menu, { text = "Custom...", notCheckable = 1, func = function() A:ShowPicker() end })

		-- Effects (apply straight away, no reload).
		local FX = JohnnysFX
		if FX then
			table.insert(menu, { text = "Effects", isTitle = 1, notCheckable = 1 })
			table.insert(menu, {
				text = "Effects on",
				checked = FX:Get("on") and true or false,
				keepShownOnClick = 1,
				func = function() FX:Set("on", not FX:Get("on")) end,
			})
			table.insert(menu, { text = "Selected buttons", isTitle = 1, notCheckable = 1 })
			for _, opt in ipairs({ { "glow", "Soft glow" }, { "chase", "Border chase" }, { "corners", "Corner brackets" }, { "underline", "Underline" }, { "none", "Nothing" } }) do
				table.insert(menu, {
					text = "   " .. opt[2],
					checked = FX:Get("selected") == opt[1],
					func = function() FX:Set("selected", opt[1]) end,
				})
			end
			table.insert(menu, { text = "Extras", isTitle = 1, notCheckable = 1 })
			for _, opt in ipairs({
				{ "pulse", "Pulse on buttons waiting for you" },
				{ "shimmer", "Shimmer on buttons waiting for you" },
				{ "ripple", "Ripple when you click" },
				{ "hover", "Underline when you hover" },
				{ "flash", "Flash when values change" },
				{ "glowText", "Glowing status words" },
			}) do
				local key = opt[1]
				table.insert(menu, {
					text = "   " .. opt[2],
					checked = FX:Get(key) and true or false,
					keepShownOnClick = 1,
					func = function() FX:Set(key, not FX:Get(key)) end,
				})
			end
		end
		table.insert(menu, { text = CANCEL or "Cancel", notCheckable = 1 })
		EasyMenu(menu, menuFrame, "cursor", 0, 0, "MENU")
	end

	SLASH_JOHNNYSACCENT1 = "/jaccent"
	SlashCmdList["JOHNNYSACCENT"] = function()
		A:ShowMenu()
	end
end

--------------------------------------------------------------------------
-- Accent effects (JohnnysFX), shared the same way as the colour: the first
-- Johnny addon to load builds it, the rest reuse it. Every flat button made
-- by a Johnny skin calls JohnnysFX:Attach(btn); from then on the button
-- picks up effects by itself:
--   selected (border in the accent)    -> glow / border chase / corners / underline
--   waiting for you (filled in accent) -> pulse and/or shimmer
--   clicked                             -> ripple
--   hovered                             -> underline slide
-- plus JohnnysFX:Flash(frame) for values that change, and
-- JohnnysFX:GlowText(fontString) for accent status words (WINNER, PINNED).
-- Settings live with the accent colour (JohnnysAccentDB.fx) and change live.
--------------------------------------------------------------------------
if not JohnnysFX then
	local A = JohnnysAccent
	local MEDIA = "Interface\\AddOns\\JohnnysMessenger\\Media\\"
	local WHITE = "Interface\\Buttons\\WHITE8X8"

	JohnnysFX = {}
	local FX = JohnnysFX

	FX.DEFAULTS = {
		on = true,
		selected = "glow", -- glow | chase | corners | underline | none
		pulse = true,
		shimmer = true,
		ripple = true,
		hover = true,
		flash = true,
		glowText = true,
	}

	-- Settings: kept on JohnnysAccent so they're saved alongside the colour.
	function FX:Get(key)
		local s = A.fx or {}
		if s[key] == nil then
			return FX.DEFAULTS[key]
		end
		return s[key]
	end
	function FX:Set(key, value)
		A.fx = A.fx or {}
		A.fx[key] = value
		A:Touch()
	end
	local function On(key)
		return FX:Get("on") and FX:Get(key)
	end

	local function IsAccent(r, g, b)
		local c = A.color
		return r and math.abs(r - c[1]) < 0.02 and math.abs(g - c[2]) < 0.02 and math.abs(b - c[3]) < 0.02
	end

	-- One ticker drives everything; it only runs while something is animating.
	local active = {}
	local clock = 0
	local ticker = CreateFrame("Frame")
	ticker:Hide()
	ticker:SetScript("OnUpdate", function(self, elapsed)
		clock = clock + elapsed
		local any = false
		for obj in pairs(active) do
			if obj:Tick(clock, elapsed) then
				any = true
			else
				active[obj] = nil
			end
		end
		if not any then
			self:Hide()
		end
	end)
	local function Wake(obj)
		active[obj] = true
		ticker:Show()
	end

	local function Tex(parent, layer, file, blend)
		local t = parent:CreateTexture(nil, layer)
		t:SetTexture(file or WHITE)
		if blend then
			t:SetBlendMode(blend)
		end
		t:Hide()
		return t
	end

	--------------------------------------
	--   Buttons                        --
	--------------------------------------

	local Btn = {}
	Btn.__index = Btn
	FX.all = setmetatable({}, { __mode = "k" })

	function Btn:Ensure()
		if self.built then
			return
		end
		self.built = true
		local b = self.btn
		self.glow = Tex(b, "BACKGROUND", MEDIA .. "softglow", "ADD")
		self.glow:SetPoint("TOPLEFT", -10, 10)
		self.glow:SetPoint("BOTTOMRIGHT", 10, -10)
		self.pulse = Tex(b, "BACKGROUND", MEDIA .. "softglow", "ADD")
		self.pulse:SetPoint("TOPLEFT", -12, 12)
		self.pulse:SetPoint("BOTTOMRIGHT", 12, -12)
		self.chase = {}
		for i = 1, 4 do
			self.chase[i] = Tex(b, "OVERLAY", WHITE, "ADD")
		end
		self.corners = {}
		for i = 1, 4 do
			self.corners[i] = Tex(b, "OVERLAY", WHITE)
		end
		self.corners[1]:SetSize(7, 2)
		self.corners[2]:SetSize(2, 7)
		self.corners[3]:SetSize(7, 2)
		self.corners[4]:SetSize(2, 7)
		self.line = Tex(b, "OVERLAY", WHITE)
		self.line:SetHeight(2)
		self.shine = Tex(b, "OVERLAY", MEDIA .. "shimmer", "ADD")
		self.lineFrac = 0
	end

	function Btn:HideAll()
		if not self.built then
			return
		end
		self.glow:Hide()
		self.pulse:Hide()
		for i = 1, 4 do
			self.chase[i]:Hide()
			self.corners[i]:Hide()
		end
		self.line:Hide()
		self.shine:Hide()
	end

	-- Called whenever the button's colours change.
	function Btn:Update()
		local wantSel = self.selected and FX:Get("on") and FX:Get("selected") ~= "none"
		local wantAttn = self.attention and (On("pulse") or On("shimmer"))
		if wantSel or wantAttn or (self.lineFrac or 0) > 0 then
			self:Ensure()
			Wake(self)
		elseif self.built then
			self:HideAll()
		end
	end

	local function Color()
		return A.color[1], A.color[2], A.color[3]
	end

	-- Returns true while it still has something to animate.
	function Btn:Tick(t, elapsed)
		local b = self.btn
		if not b:IsVisible() then
			self:HideAll()
			return false
		end
		local r, g, bl = Color()
		local fxOn = FX:Get("on")
		-- A filled accent button (the view's main action) gets pulse/shimmer
		-- instead of the selected-style effect, so the two don't stack.
		local selStyle = fxOn and self.selected and not self.attention and FX:Get("selected") or "none"
		local busy = false

		-- Selected: glow
		if selStyle == "glow" then
			self.glow:SetVertexColor(r, g, bl, 0.75)
			self.glow:Show()
		else
			self.glow:Hide()
		end

		-- Selected: border chase
		if selStyle == "chase" then
			busy = true
			local w, h = b:GetWidth(), b:GetHeight()
			local P = 2 * (w + h)
			local L = P * 0.22
			local head = (t / 2.2 % 1) * P
			local edges = { { 0, w }, { w, h }, { w + h, w }, { 2 * w + h, h } }
			for i, e in ipairs(edges) do
				local s, len = e[1], e[2]
				local tex = self.chase[i]
				local o1, o2
				for _, shift in ipairs({ 0, P, -P }) do
					local lo, hi = math.max(head - L + shift, s), math.min(head + shift, s + len)
					if hi > lo then
						o1, o2 = lo - s, hi - s
						break
					end
				end
				tex:ClearAllPoints()
				if o1 then
					tex:SetVertexColor(r, g, bl, 1)
					if i == 1 then
						tex:SetPoint("TOPLEFT", b, "TOPLEFT", o1, 0); tex:SetWidth(o2 - o1); tex:SetHeight(2)
					elseif i == 2 then
						tex:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, -o1); tex:SetWidth(2); tex:SetHeight(o2 - o1)
					elseif i == 3 then
						tex:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -o1, 0); tex:SetWidth(o2 - o1); tex:SetHeight(2)
					else
						tex:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, o1); tex:SetWidth(2); tex:SetHeight(o2 - o1)
					end
					tex:Show()
				else
					tex:Hide()
				end
			end
		else
			for i = 1, 4 do
				self.chase[i]:Hide()
			end
		end

		-- Selected: corner brackets
		if selStyle == "corners" then
			busy = true
			local o = 3 + 2 * math.sin(t * 2 * math.pi / 1.6)
			for i = 1, 4 do
				local c = self.corners[i]
				c:SetVertexColor(r, g, bl, 1)
				c:ClearAllPoints()
				if i <= 2 then
					c:SetPoint("TOPLEFT", b, "TOPLEFT", -o, o)
				else
					c:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", o, -o)
				end
				c:Show()
			end
		else
			for i = 1, 4 do
				self.corners[i]:Hide()
			end
		end

		-- Underline: hover (or selected when that's the selected style)
		local wantLine = (selStyle == "underline") or (fxOn and FX:Get("hover") and MouseIsOver(b) and b:IsEnabled() == 1)
		if wantLine or self.lineFrac > 0 then
			busy = true
			local want = wantLine and 1 or 0
			if self.lineFrac < want then
				self.lineFrac = math.min(want, self.lineFrac + elapsed * 4)
			elseif self.lineFrac > want then
				self.lineFrac = math.max(want, self.lineFrac - elapsed * 4)
			end
			if self.lineFrac > 0 then
				self.line:SetVertexColor(r, g, bl, 1)
				self.line:ClearAllPoints()
				self.line:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
				self.line:SetWidth(b:GetWidth() * self.lineFrac)
				self.line:Show()
			else
				self.line:Hide()
			end
		else
			self.line:Hide()
		end

		-- Waiting for you: pulse
		if self.attention and fxOn and FX:Get("pulse") then
			busy = true
			self.pulse:SetVertexColor(r, g, bl, 1)
			self.pulse:SetAlpha(0.15 + 0.85 * (0.5 + 0.5 * math.sin(t * 2 * math.pi / 1.8)))
			self.pulse:Show()
		else
			self.pulse:Hide()
		end

		-- Waiting for you: shimmer
		if self.attention and fxOn and FX:Get("shimmer") then
			busy = true
			local w, h = b:GetWidth(), b:GetHeight()
			local bw = w * 0.5
			local phase = ((t + (self.offset or 0)) % 2.6) / 2.6
			local x = -bw + (w + bw) * (phase / 0.55)
			local l, rr = math.max(x, 0), math.min(x + bw, w)
			if phase <= 0.55 and rr > l then
				self.shine:ClearAllPoints()
				self.shine:SetPoint("TOPLEFT", b, "TOPLEFT", l, 0)
				self.shine:SetWidth(rr - l)
				self.shine:SetHeight(h)
				self.shine:SetTexCoord((l - x) / bw, (rr - x) / bw, 0, 1)
				self.shine:SetVertexColor(1, 1, 1, 0.45)
				self.shine:Show()
			else
				self.shine:Hide()
			end
		else
			self.shine:Hide()
		end

		return busy
	end

	-- Ripple on click, kept inside the button by a clipping scroll frame.
	function Btn:Ripple()
		local b = self.btn
		if not On("ripple") then
			return
		end
		if InCombatLockdown() and b:IsProtected() then
			return
		end
		if not self.clip then
			self.clip = CreateFrame("ScrollFrame", nil, b)
			self.clip:SetAllPoints()
			self.clipChild = CreateFrame("Frame", nil, self.clip)
			self.clip:SetScrollChild(self.clipChild)
			self.ring = self.clipChild:CreateTexture(nil, "OVERLAY")
			self.ring:SetTexture(MEDIA .. "ring")
			self.ring:SetBlendMode("ADD")
			self.ring:Hide()
			self.rippler = { owner = self }
			function self.rippler:Tick(_, elapsed)
				local o = self.owner
				o.rippleAge = (o.rippleAge or 1) + elapsed
				local p = math.min(1, o.rippleAge / 0.6)
				if p >= 1 or not o.btn:IsVisible() then
					o.ring:Hide()
					return false
				end
				local d = math.max(o.btn:GetWidth(), o.btn:GetHeight()) * (0.3 + 2.5 * p)
				local r, g, bl = Color()
				o.ring:SetVertexColor(r, g, bl, 0.8 * (1 - p))
				o.ring:ClearAllPoints()
				o.ring:SetPoint("CENTER", o.clipChild, "BOTTOMLEFT", o.rx, o.ry)
				o.ring:SetWidth(d)
				o.ring:SetHeight(d)
				o.ring:Show()
				return true
			end
		end
		self.clipChild:SetWidth(b:GetWidth())
		self.clipChild:SetHeight(b:GetHeight())
		local scale = b:GetEffectiveScale()
		local cx, cy = GetCursorPosition()
		self.rx, self.ry = cx / scale - (b:GetLeft() or 0), cy / scale - (b:GetBottom() or 0)
		self.rippleAge = 0
		Wake(self.rippler)
	end

	function FX:Attach(btn)
		if not btn or btn.jfx then
			return
		end
		local obj = setmetatable({ btn = btn, offset = math.random() * 2.6 }, Btn)
		btn.jfx = obj
		hooksecurefunc(btn, "SetBackdropBorderColor", function(_, r, g, b)
			local sel = IsAccent(r, g, b) and true or false
			if sel ~= obj.selected then
				obj.selected = sel
				obj:Update()
			end
		end)
		hooksecurefunc(btn, "SetBackdropColor", function(_, r, g, b, a)
			local attn = IsAccent(r, g, b) and (a or 1) > 0.5 and true or false
			if attn ~= obj.attention then
				obj.attention = attn
				obj:Update()
			end
		end)
		local function RippleHook()
			obj:Ripple()
		end
		btn:HookScript("OnMouseDown", RippleHook)
		-- Callers often replace OnMouseDown later (pressed colours); hook the
		-- new one too so the ripple survives.
		hooksecurefunc(btn, "SetScript", function(self, script, fn)
			if script == "OnMouseDown" and fn then
				self:HookScript("OnMouseDown", RippleHook)
			end
		end)
		FX.all[obj] = true
		btn:HookScript("OnEnter", function()
			if On("hover") then
				obj:Ensure()
				Wake(obj)
			end
		end)
		btn:HookScript("OnShow", function()
			obj:Update()
		end)
	end

	--------------------------------------
	--   Flash                          --
	--------------------------------------

	-- Lights a frame up in the accent and fades it out (values going up,
	-- new listings, new messages).
	function FX:Flash(frame)
		if not frame or not On("flash") then
			return
		end
		local f = frame.jfxFlash
		if not f then
			f = { tex = Tex(frame, "ARTWORK", WHITE) }
			f.tex:SetAllPoints()
			function f:Tick(_, elapsed)
				self.left = self.left - elapsed
				if self.left <= 0 then
					self.tex:Hide()
					return false
				end
				local r, g, b = Color()
				self.tex:SetVertexColor(r, g, b, 0.6 * self.left / 0.9)
				self.tex:Show()
				return true
			end
			frame.jfxFlash = f
		end
		f.left = 0.9
		Wake(f)
	end

	--------------------------------------
	--   Glowing text                   --
	--------------------------------------

	-- Soft accent copies behind a font string, pulsing, shown only while
	-- the text itself is in the accent colour.
	function FX:GlowText(fs)
		if not fs or fs.jfxGlow then
			return
		end
		local parent = fs:GetParent()
		local g = { fs = fs, copies = {} }
		fs.jfxGlow = g
		for _, off in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { -1, -1 } }) do
			local c = parent:CreateFontString(nil, "ARTWORK")
			c:SetFont(fs:GetFont())
			c:SetPoint("CENTER", fs, "CENTER", off[1], off[2])
			c:Hide()
			table.insert(g.copies, c)
		end
		local function Refresh()
			local r, gg, b = fs:GetTextColor()
			g.on = IsAccent(r, gg, b) and fs:GetText() and fs:GetText() ~= ""
			for _, c in ipairs(g.copies) do
				c:SetFont(fs:GetFont())
				c:SetText(fs:GetText())
				local cr, cg, cb = Color()
				c:SetTextColor(cr, cg, cb)
			end
			if g.on then
				Wake(g)
			else
				for _, c in ipairs(g.copies) do
					c:Hide()
				end
			end
		end
		function g:Tick(t)
			if not self.on or not On("glowText") or not self.fs:IsVisible() then
				for _, c in ipairs(self.copies) do
					c:Hide()
				end
				return false
			end
			local a = 0.05 + 0.4 * (0.5 + 0.5 * math.sin(t * 2 * math.pi / 2))
			for _, c in ipairs(self.copies) do
				c:SetAlpha(a)
				c:Show()
			end
			return true
		end
		hooksecurefunc(fs, "SetText", Refresh)
		hooksecurefunc(fs, "SetTextColor", Refresh)
		Refresh()
	end

	-- Re-check every attached button after a settings change.
	function FX:Refresh()
		for obj in pairs(FX.all) do
			obj:Update()
		end
	end
end

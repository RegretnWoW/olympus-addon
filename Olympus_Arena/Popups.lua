local _, own = ...; local ns = own.host; if not ns then return end

-- Olympus Arena (the load-on-demand companion): Popups.lua. A stub the arena's core created for the screens to
-- fill. Toasts and alert windows of Olympus's own (never the game's popups).
-- Frames are named OlympusArena... (so /oly photo keeps them); no OnUpdate, no game popup, no
-- UISpecialFrames but through ns.EscapeCloses, no edit box focused but through ns.Focus.
local ArenaUI = own.ArenaUI

local L = ns.L
local Kit = ArenaUI.Kit
local Data = ArenaUI.Data
local Home = ns.ArenaHome

local keeperDialog
function ArenaUI.Innkeeper(name, completed)
	local FT = ns.FarkleTable
	if not FT then return false end
	name = name or FT.Innkeeper()
	if not name then ArenaUI.Say(L.FARKLE_WHY_TRAINING_INN); return false, "training_inn" end
	if completed == nil then completed = FT.TrainingComplete() end
	if not keeperDialog then
		local f = Kit.Frame("OlympusArenaBonesInnkeeper", 460, 290, { title = L.FARKLE_NAME, stack = true })
		f.text = Kit.Text(f, nil, "LEFT")
		f.text:SetPoint("TOPLEFT", 32, -58); f.text:SetWidth(396)
		f.text:SetJustifyV("TOP")
		f.play = Kit.Button(f, 190, 28, L.FARKLE_KEEPER_LEARN, function()
			local keeper = FT.Innkeeper()
			if not keeper then f.text:SetText(L.FARKLE_WHY_TRAINING_INN); return end
			f:Hide()
			if FT.TrainingComplete() then ArenaUI.Farkle("practice")
			else ArenaUI.Farkle("practice", nil, { target = ns.FarkleRules.TARGETS[1], learn = true }) end
		end)
		f.play:SetPoint("BOTTOMLEFT", 24, 22)
		f.next = Kit.Button(f, 190, 28, L.FARKLE_KEEPER_NOT_NOW, function() f:Hide() end)
		f.next:SetPoint("BOTTOMRIGHT", -24, 22)
		keeperDialog = f
	end
	local f = keeperDialog
	ns.SetWindowTitle(f, name)
	if completed then f.text:SetText(L.FARKLE_KEEPER_DONE:format(name))
	else
		local voice = FT.InnkeeperVoice and FT.InnkeeperVoice()
		local flavor = voice and rawget(L, "FARKLE_KEEPER_FLAVOR_" .. voice:upper()) or nil
		f.text:SetText(L.FARKLE_KEEPER_HELLO:format(name, flavor or L.FARKLE_KEEPER_FLAVOR))
	end
	Kit.FitHeight(f, f.text, 58, 74, 290)
	f.play:Show()
	f.play:SetText(completed and L.FARKLE_KEEPER_AGAIN or L.FARKLE_KEEPER_LEARN)
	f.next:SetText(completed and L.FARKLE_KEEPER_FIND or L.FARKLE_KEEPER_NOT_NOW)
	f.next:SetScript("OnClick", function()
		f:Hide()
		if completed and ArenaUI.OpenFind then ArenaUI.OpenFind("b") end
	end)
	f:Show(); f:Raise()
	return f
end
function ArenaUI.InnkeeperFrame() return keeperDialog end
ns.On("BONES_LEARNED", function(name) ArenaUI.Innkeeper(name, true) end)

local function FinancialPlay()
	local C = ns.Compliance
	return type(C) == "table" and type(C.Allows) == "function"
		and (C.Allows("bet", "fight") == true or C.Allows("stake", "fight") == true)
end

-- The pop-ups of the betting window (the owner's rule, 2026-09-30: explanations and rules open as
-- pop-up windows of their own, first on first use, never as overlays inside a game window;
-- parchment and dark ink, 13 px and more, Morpheus titles):
-- - the arena's rules (OlympusArenaRules, the design): the first time the window opens, and
--   before the first action that commits (a bet, a deposit, a challenge, a sign-up, a chat line);
--   I agree / Not now. Viewing needs no yes.
-- - each section's explanation (OlympusArenaHelp): the first time the section opens, and again
--   from the window's help button. Bones's is the Bones tables' own guide where the build has it, the
--   Lottery's its board's own.
-- - the King's letters kept (OlympusArenaLetters), to read again; "preview as others see me"
--   (OlympusArenaPreview).
-- The alert window, the challenge window and the toasts are the core's (ArenaHome.lua): a
-- player who never opened the arena gets them too.

---------------------------------------------------------------------------
-- The rules
---------------------------------------------------------------------------

local rules
local function MakeRules()
	local f = Kit.Frame("OlympusArenaRules", 600, 470, { title = L.ARENA_RULES_TITLE, noClose = true, stack = true })
	f.text = Kit.Text(f, nil, "LEFT")
	f.text:SetPoint("TOPLEFT", 36, -58)
	f.text:SetWidth(528)
	if f.text.SetJustifyV then f.text:SetJustifyV("TOP") end
	f.yes = Kit.Button(f, 170, 26, L.ARENA_RULES_AGREE, function()
		local cb = rawget(f, "onYes")
		f.onYes = nil
		if not ns.Arena.Sim() then ns.Arena.SetRules(true) end
		f:Hide()
		ArenaUI.Refresh()
		if cb then ns.SafeCall("arena rules yes", cb) end
	end)
	f.yes:SetPoint("BOTTOMLEFT", 60, 20)
	f.no = Kit.Button(f, 170, 26, L.ARENA_RULES_NOT_NOW, function()
		f.onYes = nil
		-- (Kept as a no, so the window does not ask again on each open; the next action that
		-- commits asks.)
		if not ns.Arena.Sim() and not ns.Arena.RulesAccepted() then ns.Arena.SetRules(false) end
		f:Hide()
		ArenaUI.Refresh()
	end)
	f.no:SetPoint("BOTTOMRIGHT", -60, 20)
	return f
end
-- The rules' words, one paragraph a rule (English and Portuguese, UIText.lua).
function ArenaUI.RulesText()
	if not FinancialPlay() then
		return table.concat({ "- " .. L.ARENA_RULE_FREE, "- " .. L.ARENA_RULE_8, "- " .. L.ARENA_RULE_9 }, "\n\n")
	end
	local out = {}
	local wallet = ns.Compliance and ns.Compliance.Wallet and ns.Compliance.Wallet()
	for i = 1, 20 do
		local line = rawget(L, "ARENA_RULE_" .. i)
		if not line then break end
		if i ~= 3 or wallet then out[#out + 1] = "- " .. line end
	end
	return table.concat(out, "\n\n")
end
-- Shows the rules; onYes runs once the player says I agree (the action that was waiting for it).
function ArenaUI.ShowRules(onYes)
	rules = rules or MakeRules()
	rules.onYes = type(onYes) == "function" and onYes or nil
	rules.text:SetText(ArenaUI.RulesText())
	Kit.FitHeight(rules, rules.text, 58, 16 + Kit.FOOTER_H + 12, 300)
	rules:Show()
	return rules
end
function ArenaUI.RulesFrame() return rules end

---------------------------------------------------------------------------
-- How to play the Blood Arena (the owner's call, 2026-09-30): the games' How to play, as Bones'
-- and the Lottery's (Games.Popup's frame, Games.InkTab's tabs, dark ink): How it works, Betting,
-- Fees & payouts, Tournaments, from the rules' words; the fee's numbers from the King's settings.
---------------------------------------------------------------------------

local howto
local HW, HH = 680, 560
local HOWTO_PAGES = { "ARENA_HOWTO_WORKS", "ARENA_HOWTO_BETTING", "ARENA_HOWTO_FEES", "ARENA_HOWTO_TOURNEY" }
local function Pct(bp) local p = (tonumber(bp) or 0) / 100 return p == math.floor(p) and tostring(p) or ("%.1f"):format(p) end
-- A page's paragraphs, in order.
function ArenaUI.HowToParas(k)
	if not FinancialPlay() then
		if k == 1 then return { L.ARENA_HOWTO_FREE_WORKS_1, L.ARENA_HOWTO_FREE_WORKS_2, L.ARENA_HOWTO_WORKS_3, L.ARENA_RULE_8, L.ARENA_RULE_9 } end
		if k == 4 then return { L.ARENA_HOWTO_TOURNEY_1, L.ARENA_HOWTO_FREE_TOURNEY_2, L.ARENA_HOWTO_TOURNEY_3 } end
		return {}
	end
	local R = ns.ArenaRoles
	local s = R and R.Settings and R.Settings() or { feeBp = 600, arbBp = 200 }
	local fee, arb = tonumber(s.feeBp) or 600, tonumber(s.arbBp) or 200
	if k == 1 then return { L.ARENA_HOWTO_WORKS_1, L.ARENA_HOWTO_WORKS_2, L.ARENA_HOWTO_WORKS_3, L.ARENA_RULE_8, L.ARENA_RULE_9 } end
	if k == 2 then
		local lines = { L.ARENA_HOWTO_BETTING_1, L.ARENA_RULE_1, L.ARENA_RULE_2, L.ARENA_RULE_6, L.ARENA_RULE_5 }
		if ns.Compliance and ns.Compliance.Wallet and ns.Compliance.Wallet() then table.insert(lines, 4, L.ARENA_RULE_3) end
		return lines
	end
	if k == 3 then
		-- the worked example: 10g on the winner at 2.00x: 10g won, the fee on those 10g only
		local stake, odds = 100000, 2
		local won = stake * (odds - 1)
		local cut = math.floor(won * fee / 10000)
		return { L.ARENA_HOWTO_FEES_1:format(Pct(fee), Pct(fee - arb), Pct(arb)), L.ARENA_HOWTO_FEES_2:format(Pct(fee)),
			L.ARENA_HOWTO_FEES_3:format(Kit.Money(stake), ("%.2fx"):format(odds), Kit.Money(won), Pct(fee), Kit.Money(cut), Kit.Money(stake + won - cut)) }
	end
	return { L.ARENA_HOWTO_TOURNEY_1, L.ARENA_HOWTO_TOURNEY_2, L.ARENA_HOWTO_TOURNEY_3, L.ARENA_RULE_7 }
end
local function HowToPage(k)
	k = math.max(1, math.min(#HOWTO_PAGES, tonumber(k) or 1))
	if not FinancialPlay() and (k == 2 or k == 3) then k = 1 end
	for i, pg in ipairs(howto.pages) do
		pg:SetShown(i == k)
		howto.tabs[i]:SetSelected(i == k)
	end
	howto.page = k
end
function ArenaUI.HowToPlay(page)
	-- The shared lobby/history footer explains the game currently open. Explicit Arena chapter
	-- requests still open that chapter regardless of the remembered section.
	local route = page == nil and ArenaUI.CurrentRoute and ArenaUI.CurrentRoute()
	if route and route.section == "farkle" then
		if ArenaUI.FarkleBoard and ArenaUI.FarkleBoard.ShowGuide then return ArenaUI.FarkleBoard.ShowGuide() end
		return ArenaUI.BoneBoard("guide")
	end
	if route and route.section == "lottery" and ArenaUI.LotteryHowToPlay then return ArenaUI.LotteryHowToPlay() end
	local G = own.Games
	if not (G and G.Popup and G.InkTab) then return ArenaUI.Explain and ArenaUI.Explain("arena", true) end
	if not howto then
		howto = G.Popup("OlympusArenaHowTo", HW, HH, ArenaUI.frame)
		howto.title = howto:CreateFontString(nil, "ARTWORK", Kit.Font("big"))
		howto.title:SetPoint("TOP", 0, -18)
		howto.title:SetText(L.ARENA_HOWTO_TITLE)
		howto.tabs, howto.pages = {}, {}
		for k, key in ipairs(HOWTO_PAGES) do
			howto.tabs[k] = G.InkTab(howto, L[key], 150, function() HowToPage(k) end, 16)
			local pg = CreateFrame("Frame", nil, howto)
			pg:SetAllPoints()
			pg.paras = {}
			howto.pages[k] = pg
		end
		local rule = howto:CreateTexture(nil, "BORDER")
		rule:SetColorTexture(0.25, 0.13, 0.04, 0.3)
		rule:SetPoint("TOPLEFT", 32, -90); rule:SetPoint("TOPRIGHT", -32, -90); rule:SetHeight(1)
		howto.ok = Kit.Button(howto, 140, 30, L.ARENA_HOWTO_OK, function() howto:Hide() end)
		Kit.Fit(howto.ok, 120)
		howto.ok:SetPoint("BOTTOM", 0, 18)
	end
	local money = FinancialPlay()
	local count, tw, gap = money and #HOWTO_PAGES or 2, 150, 8
	local tx, position, need = (HW - count * tw - (count - 1) * gap) / 2, 0, HH
	for k, pg in ipairs(howto.pages) do
		local shown = money or k == 1 or k == 4
		local tab = howto.tabs[k]
		tab:SetShown(shown)
		if shown then
			tab:ClearAllPoints()
			tab:SetPoint("TOPLEFT", howto, "TOPLEFT", tx + position * (tw + gap), -52)
			position = position + 1
		end
		local paras, prev, h = ArenaUI.HowToParas(k), nil, 104
		for i, text in ipairs(paras) do
			local fs = pg.paras[i]
			if not fs then
				fs = Kit.Text(pg, nil, "LEFT")
				fs:SetWidth(HW - 80)
				if fs.SetJustifyV then fs:SetJustifyV("TOP") end
				if prev then fs:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -12) else fs:SetPoint("TOPLEFT", pg, "TOPLEFT", 40, -104) end
				pg.paras[i] = fs
			end
			fs:SetText(text); fs:Show()
			h = h + (tonumber(fs.GetStringHeight and fs:GetStringHeight() or 0) or 0) + 12
			prev = fs
		end
		for i = #paras + 1, #pg.paras do pg.paras[i]:Hide() end
		if shown then need = math.max(need, math.ceil(h + 70)) end
	end
	howto:SetHeight(need)
	HowToPage(page or howto.page or 1)
	howto:ClearAllPoints()
	howto:SetPoint("CENTER", ArenaUI.frame or UIParent, "CENTER", 0, 0)
	howto:Show()
	return howto
end

---------------------------------------------------------------------------
-- A section's explanation, first on first use
---------------------------------------------------------------------------

local help
local EXPLAIN = { arena = { "ARENA_EXPLAIN_ARENA_TITLE", "ARENA_EXPLAIN_ARENA" }, farkle = { "ARENA_EXPLAIN_BONE_TITLE", "ARENA_EXPLAIN_BONE" },
	lottery = { "ARENA_EXPLAIN_LOTTERY_TITLE", "ARENA_EXPLAIN_LOTTERY" } }
local function MakeHelp()
	local f = Kit.Frame("OlympusArenaHelp", 460, 400, { title = "" })
	f.text = Kit.Text(f, nil, "LEFT")
	f.text:SetPoint("TOPLEFT", 32, -58)
	f.text:SetWidth(396)
	if f.text.SetJustifyV then f.text:SetJustifyV("TOP") end
	f.ok = Kit.Button(f, 150, 26, L.ARENA_GOT_IT, function() f:Hide() end)
	f.ok:SetPoint("BOTTOM", 0, 18)
	return f
end
-- Shows a section's explanation (again when `force`), and keeps that it was shown.
function ArenaUI.Explain(section, force)
	local words = EXPLAIN[section]
	if not words then return nil end
	if not force and Kit.Recall("explained:" .. section) then return nil end
	Kit.Remember("explained:" .. section, true)
	-- Bones's guide and the Lottery's are their own packages' (the Bones tables, the Lottery) where the build has
	-- them: those, not ours.
	if section == "farkle" and (type(ArenaUI.Farkle) == "function" or (ns.FarkleTable and ns.FarkleTable.ShowUI)) then
		return ArenaUI.BoneBoard("guide")
	end
	if section == "lottery" and ArenaUI.LotteryBoard then return nil end
	help = help or MakeHelp()
	help.title:SetText(L[words[1]])
	help.text:SetText(section == "arena" and not FinancialPlay() and L.ARENA_EXPLAIN_ARENA_FREE or L[words[2]])
	Kit.FitHeight(help, help.text, 58, 16 + Kit.FOOTER_H + 12, 200)
	help:Show()
	return help
end
function ArenaUI.HelpFrame() return help end

---------------------------------------------------------------------------
-- The King's letters, to read again (the design)
---------------------------------------------------------------------------

local letters
function ArenaUI.LettersPopup()
	if not letters then
		letters = Kit.Frame("OlympusArenaLetters", 380, 360, { title = L.ARENA_LETTERS_TITLE })
		letters.list = Kit.List(letters, 330, 250)
		letters.list:SetPoint("TOPLEFT", 26, -56)
	end
	local lines = {}
	local list = Home.Letters()
	if #list == 0 then lines[1] = { text = L.ARENA_LETTERS_NONE } end
	for _, e in ipairs(list) do
		local entry = e
		lines[#lines + 1] = { text = Home.TitleOf(e.key) or e.key, right = e.at and date and date("%Y-%m-%d", e.at) or "",
			onClick = function() Home.ReadLetter(entry) end }
	end
	letters:Show()
	letters.list:SetLines(lines)
	ArenaUI.lastLetters = lines
	return letters
end

---------------------------------------------------------------------------
-- "Preview as others see me": the portrait with the frame viewers verify, the title, the name
---------------------------------------------------------------------------

local preview
function ArenaUI.PreviewMe()
	if not preview then
		preview = Kit.Frame("OlympusArenaPreview", 320, 300, { title = L.ARENA_PROFILE_PREVIEW })
		-- (the portrait drawn as the player's own, Kit.NewPortrait, as his profile's)
		preview.rig = Kit.NewPortrait(preview, 96)
		preview.portrait = preview.rig.slot
		preview.portrait:SetPoint("TOP", 0, -70)
		preview.name = Kit.Text(preview, "title", "CENTER")
		preview.name:SetPoint("TOP", preview.portrait, "BOTTOM", 0, -34)
		preview.sub = Kit.Text(preview, nil, "CENTER")
		preview.sub:SetPoint("TOP", preview.name, "BOTTOM", 0, -4)
	end
	local PE = ns.ProfileEdit
	local pv = type(PE) == "table" and type(PE.Preview) == "function" and select(2, pcall(PE.Preview)) or nil
	if type(pv) ~= "table" then pv = {} end
	local m = ArenaUI.ProfileModel and ArenaUI.ProfileModel(nil) or {}
	-- (asSeen: his picture as a viewer without him as a unit sees it, his emblem, race or class, never
	-- his own live portrait; his own frame, never his border preview)
	Kit.DrawPortrait(preview.rig, ns.me, { class = m.class, race = m.race, gender = m.gender, emblem = pv.emblem or m.emblem,
		guild = pv.guild or m.guild, honour = pv.honour or m.honour, asSeen = true })
	local nick = pv.nick or m.nick
	preview.name:SetText(Kit.Name(ns.me) .. (nick and nick ~= "" and ("\n\"" .. ns.Codec.Plain(nick) .. "\"") or ""))
	local title = pv.titleText or m.title
	preview.sub:SetText(title and ns.Codec.Plain(title) or "")
	preview:Show()
	return preview
end

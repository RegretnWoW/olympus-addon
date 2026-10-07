local ns, test, eq, WithBorders, BorderUnit, king = ...
test("Treasurer dragon: verified primary pin owns one supplied portrait overlay, never the mail alt or namesake", function()
	local saved = { ns.TREASURER, ns.TREASURER_CHARACTERS, ns.TREASURER_REALM }
	local primary, mail = "Test Treasurer-Realm", "Test Mail-Realm"
	ns.TREASURER, ns.TREASURER_CHARACTERS, ns.TREASURER_REALM = "Test Treasurer", { "Test Treasurer", "Test Mail" }, "Realm"
	local ok, err = pcall(function()
		WithBorders(function(w)
			w.internal("LOGIN")
			w.target(BorderUnit("Test Treasurer", "Olympus II", "Member", 3))
			eq(w.B.TierOf("target"), "treasurer-dragon")
			eq(w.B.TierOfName(primary, nil), "treasurer-dragon", "no caller guild label needed")
			local texture = assert(w.shownTextureOn("TargetFrame.TargetFrameContainer"))
			eq(texture.file, "Interface\\AddOns\\Olympus\\media\\borders\\treasurer-dragon")
			eq(texture.size, "100 95")
			eq(w.B.TierOfName(mail, "Olympus II"), nil)
			eq(w.B.TierOfName("Test Treasurer-Elsewhere", "Olympus II"), nil)
			local computed = w.computed()
			w.B.CensusChanged()
			eq(w.computed(), computed, "unchanged primary pin keeps the cached border")
			ns.TREASURER, ns.TREASURER_CHARACTERS = "Replacement", { "Replacement", "Test Mail" }
			w.B.CensusChanged()
			eq(w.shown("target"), nil, "pin removal invalidates the existing target cache")
			ns.TREASURER, ns.TREASURER_CHARACTERS = "Test Treasurer", { "Test Treasurer", "Test Mail" }
			w.B.CensusChanged()
			eq(w.shown("target"), "treasurer-dragon", "pin restoration refreshes that same target")
			w.target(king)
			ns.TREASURER, ns.TREASURER_CHARACTERS = king.name, { king.name }
			eq(w.B.TierOf("target"), "gold-elite")
		end)
	end)
	ns.TREASURER, ns.TREASURER_CHARACTERS, ns.TREASURER_REALM = unpack(saved, 1, 3)
	if not ok then error(err, 0) end
end)

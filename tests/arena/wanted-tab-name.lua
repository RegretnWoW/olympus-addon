local H = ...
H.test("Wanted tab name: requested label is Wanted in both languages", function()
	for _, locale in ipairs({ "enUS", "ptBR" }) do
		local w = H.World.New()
		local c = w:Client(H.World.NAMES.fighterA)
		c.globals.GetLocale = function() return locale end
		local ns = { L = {} }
		w:As(c, function()
			assert(loadfile(H.ADDON_DIR .. "Locales.lua"))("Olympus", ns)
		end)
		H.eq(ns.L.TAB_WANTED, "Wanted")
	end
end)

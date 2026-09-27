-- A watcher's SavedVariables (WTF/Account/<account>/SavedVariables/Olympus.lua) as the addon writes its
-- Olympus Link inbox (0.9.10): OlympusDB.discord.inbox[R][sender] = { bundle, from, t }. Up to 3 senders
-- per code, 5 entries per sender and 500 in all; nothing is dropped while its code can still be used.
-- Made by tests/fixtures/make-link-vectors.py from link-sample.txt; tests/run.lua checks the addon keeps
-- exactly this, and web/tools/read-inbox.mjs reads it. Throwaway test keys only.
OlympusDB = {
	["discord"] = {
		["inbox"] = {
			["7K3M9QX2TB"] = {
				["Other Player-ClassicBetaPvP"] = {
					["bundle"] = "OLB4~Other Player-ClassicBetaPvP~Olympus II~Alliance~0123456789abcdef~7K3M9QX2TB~d566445acb5aa754~1799990150,council02,Other Councillor-ClassicBetaPvP,c,Ve9KtHyfmmOzaMvm3abHnsLIzK53KZMGVJh3tVmmlWhhxFTvXicCqERVmgZwJANhdJZwzeah6gerL276llfLCw",
					["from"] = "Other Player-ClassicBetaPvP",
					["t"] = 1799990460,
				},
				["Some Player-ClassicBetaPvP"] = {
					["bundle"] = "OLB4~Some Player-ClassicBetaPvP~Olympus II~Alliance~0123456789abcdef~7K3M9QX2TB~5f2f66f046a1db8a~1799990100,council01,Test Councillor-ClassicBetaPvP,r,UDWmhHUQ8mbNq-UNmlkXlHglN_rp7CX8NCgCymo1g9iGLqicTZ0vuB-gPVWsQtu0waD9CaibIakE8IfUVnwDAg",
					["from"] = "Some Player-ClassicBetaPvP",
					["t"] = 1799990400,
				},
			},
		},
		["watch"] = {
			["Test Councillor-ClassicBetaPvP"] = true,
		},
	},
}

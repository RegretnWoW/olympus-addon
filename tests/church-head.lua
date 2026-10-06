local ns, test, eq = ...
local ROOT = debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]church%-head%.lua$") or "./"
local World = assert(loadfile(ROOT .. "tests/church-world.lua"))(ns, ROOT)

test("Church immutable head: marked Apostle stays an Apostle, never acquires root powers", function()
	local w = World.New({ apostles = { "Aldric Vane-Realm" } })
	local old = w:Client(World.HEAD)
	local king = w:Client(World.KING)
	eq(w:As(old, old.Church.HeadName), World.KING)
	eq(w:As(old, old.Church.IsHead, old.name), false)
	eq(w:As(old, old.Church.Role, old.name), "A")
	eq(w:As(old, old.Church.RootCode, old.name), nil)
	eq(w:Act(old, old.Church.NameMissionary, "Own Missionary"), true, "existing Apostle delegation remains")
	eq(w:As(old, old.Church.MayAct, "+", "M", "Foreign Missionary-Realm", "Aldric Vane-Realm", nil, old.name), false)
	eq(w:Act(king, king.Church.NameMissionary, "Foreign Missionary", "Aldric Vane-Realm"), true)
	w:SignedList({}, false, w.clock + 1)
	eq(w:As(old, old.Church.HeadName), World.KING, "absence of marker cannot depose Asmongold")
end)

test("Church immutable head: canonical identity guards are used, not local labels or namesakes", function()
	local w = World.New({})
	local cl = w:Client("Plain Member", { real = true })
	local actual = ns.KingCharacter()
	eq(w:As(cl, cl.Church.HeadName), actual)
	eq(w:As(cl, cl.Church.IsHead, ns.FullName(actual)), true)
	eq(w:As(cl, cl.Church.IsHead, actual .. "-UnrelatedRealm"), false)
	eq(w:As(cl, cl.Church.IsHead, "Asmongold-Realm"), false)
	cl.c.KingCharacter = function() return nil end
	cl.c.IsKingCharacter = function() return false end
	eq(w:As(cl, cl.Church.HeadName), nil)
	eq(w:As(cl, cl.Church.IsHead, World.HEAD), false)
end)

test("Church immutable head: actual people view announces Asmongold without a nomination action", function()
	local w = World.New({})
	local cl = w:Client(World.AUTHOR, { view = true })
	local lines = w:As(cl, cl.View.PeopleLines)
	local head
	for _, line in ipairs(lines) do if line.text == ns.L.CHURCH_HEAD then head = line end end
	assert(head)
	eq(head.right, "Asmongold")
	eq(head.onClick, nil)
	local tooltip = {}
	head.tooltip({ AddLine = function(_, text) tooltip[#tooltip + 1] = text end })
	eq(tooltip[2], ns.L.CHURCH_HEAD_TIP)
end)

local _, ns = ...
local Squads = {}
ns.WarSquads = Squads

-- Small military squads are NOT the War Room's historical capability-post Centuries.
-- WU~1~S~leader~revision~members: a complete bounded assignment, over actual GUILD.
-- WU~1~Q: request current assignments; only current own-guild officers answer.
-- SC~1~room-hash~sequence~words: logged private WHISPER, never a guild broadcast.
Squads.MAX_SOLDIERS, Squads.MAX_LEADERS = 99, 10
Squads.MAX_ROWS, Squads.MAX_GUILDS, Squads.CHAT_MAX = 40, 20, 100
Squads.SEEN_MAX = 1000
local incoming, outgoing, chatRate = {}, {}, {}
local roomCache, roomCacheCount = {}, 0
local memberIndex, indexedRoster, indexedNames, indexedGeneration, indexedAt = {}, nil, nil, nil, nil
local lastRequest = -math.huge
local function Now() return GetServerTime and GetServerTime() or ns.Now() end
local function Clock() return GetTime and GetTime() or ns.Now() end
local function Int(x) return type(x) == "number" and x == math.floor(x) and x >= 0 and x < 2147483648 end
local function Fold(s) return ns.Fold(s) end
local function Full(s)
	if type(s) ~= "string" or #s < 2 or #s > 72 or s:find("[~|,%c]") then return nil end
	return ns.FullName(s)
end
local function Guild()
	local guild = IsInGuild and IsInGuild() and GetGuildInfo("player")
	if ns.IsMember() ~= true or type(guild) ~= "string" or not ns.IsFederation(guild) then return nil end
	local roster = ns.Roster
	return roster and roster.Fresh and roster.Fresh() and guild or nil
end
local function Member(name)
	local full = Full(name)
	if not full or not Guild() then return nil end
	local roster, names = ns.Roster, ns.Roster.byName
	if names[full] then return full end
	if indexedRoster ~= roster or indexedNames ~= names or indexedGeneration ~= roster.generation or indexedAt ~= roster.snapshotAt then
		memberIndex = {}; for known in pairs(names) do memberIndex[Fold(known)] = known end
		indexedRoster, indexedNames, indexedGeneration, indexedAt = roster, names, roster.generation, roster.snapshotAt
	end
	local known = memberIndex[Fold(full)]
	return known and names[known] and known or nil
end
local function Preview()
	local v = ns.ViewAs
	if v and v.Previewing and v.Previewing() then return true end
	if v and v.Available and v.Available() and v.Role and v.Role() ~= "my" then return true end
	return ns.King and ns.King.Preview and ns.King.Preview() == true or false
end
local function Officer(name)
	name = Member(name)
	if not name then return false end
	local rank = ns.Roster.RankOf(name)
	if rank and rank <= ns.CAPTAIN_RANK then return true end
	if ns.War and ns.War.IsWarCouncillor and ns.War.IsWarCouncillor(name) then return true end
	local n = ns.Nominees
	return n and n.IsCorrespondent and n.IsCorrespondent(name, Guild(), "Department of War") == true or false
end
function Squads.CanManage()
	return not Preview() and Officer(ns.me) and not (ns.ChatLocked and ns.ChatLocked()) or false
end
local function Rate(map, key, max, window)
	local now, list = Clock(), map[key] or {}
	map[key] = list
	for i = #list, 1, -1 do if now - list[i] >= window then table.remove(list, i) end end
	if #list >= max then return false end
	list[#list + 1] = now
	return true
end
local function Store(make)
	local guild = Guild()
	if not guild or not ns.rdb then return nil end
	local all = ns.rdb.warSquads
	if all == nil and make then all = {}; ns.rdb.warSquads = all end
	if type(all) ~= "table" then return nil end
	local key, s = Fold(guild), all[Fold(guild)]
	if s == nil and make then
		local count = 0; for _ in pairs(all) do count = count + 1 end
		if count >= Squads.MAX_GUILDS then return nil end
		s = { guild = guild, rows = {}, chats = {} }; all[key] = s
	end
	return type(s) == "table" and s.guild == guild and type(s.rows) == "table" and type(s.chats) == "table" and s or nil
end
local function Room(guild, leader)
	local key = Fold(guild) .. "|" .. Fold(leader)
	if roomCache[key] then return roomCache[key] end
	local digest = ns.Sign.SHA256(key)
	local room = "squad:" .. (digest:sub(1, 12):gsub(".", function(byte) return ("%02x"):format(byte:byte()) end))
	if roomCacheCount < 256 then roomCache[key], roomCacheCount = room, roomCacheCount + 1 end
	return room
end
function Squads.Leaders()
	local guild, list, seen = Guild(), {}, {}
	if not guild then return list end
	local main = ns.IsKingGuild and ns.IsKingGuild(guild)
	local function Add(name)
		local full = Member(name)
		if not full or seen[Fold(full)] or #list >= Squads.MAX_LEADERS then return end
		if main and ns.IsHighCouncillor(full) ~= true then return end
		seen[Fold(full)] = true
		list[#list + 1] = { name = full, index = #list + 1, kind = main and "councillor" or "centurion", room = Room(guild, full) }
	end
	if main then
		-- The verified held blob preserves signed order; the names lookup and alphabetized
		-- Workshop menu cannot supply that order. Neither an unsigned title nor a rank is used.
		local c = ns.rdb.council
		local names = type(c) == "table" and type(c.blob) == "string" and c.blob:match("^HS1~%d+~[^~]*~([^~]*)~%x+$")
		for name in tostring(names or ""):gmatch("[^,]+") do Add(name:gsub("^%s+", ""):gsub("%s+$", "")) end
	else
		local n = ns.Nominees
		local nominees = n and n.ListOf and n.ListOf(guild)
		local master = nominees and Member(nominees.by)
		if not master or ns.Roster.RankOf(master) ~= 0 or not n.Proven or n.Proven(master, guild) ~= true then return list end
		for _, e in ipairs(nominees.entries or {}) do
			if e.role == "centurion" and n.RoleOf(e.name, guild) == "centurion" then Add(e.name) end
		end
	end
	return list
end
local function Leader(name)
	local full = Member(name)
	if not full then return nil end
	for _, e in ipairs(Squads.Leaders()) do if Fold(e.name) == Fold(full) then return e end end
end
local function LeaderRoom(id)
	for _, e in ipairs(Squads.Leaders()) do if e.room == id then return e end end
end
local function Dense(array, max)
	if type(array) ~= "table" then return nil end
	local count, highest = 0, 0
	for key in pairs(array) do
		if not Int(key) or key < 1 or key > max then return nil end
		count, highest = count + 1, math.max(highest, key)
		if count > max then return nil end
	end
	return count == highest and count or nil
end
local function ValidRow(row)
	if type(row) ~= "table" or not Int(row.rev) or not Full(row.leader) or Full(row.leader) ~= row.leader then return false end
	local count = Dense(row.members, Squads.MAX_SOLDIERS)
	if count == nil then return false end
	local seen = {}
	for i = 1, count do
		local name = row.members[i]
		if not Full(name) or Full(name) ~= name or Fold(name) == Fold(row.leader) or seen[Fold(name)] then return false end
		seen[Fold(name)] = true
	end
	return true
end
local function List(leader, members)
	if Dense(members, Squads.MAX_SOLDIERS) == nil then return nil end
	local out, seen = {}, {}
	for i, name in ipairs(members) do
		local full = Member(name)
		if not full or Fold(full) == Fold(leader) or seen[Fold(full)] then return nil end
		seen[Fold(full)], out[i] = true, full
	end
	for key in pairs(members) do if not Int(key) or key < 1 or key > #out then return nil end end
	table.sort(out, function(a, b) return Fold(a) < Fold(b) end)
	return out
end
local function Encode(e) return ("WU~1~S~%s~%d~%s"):format(e.leader, e.rev, table.concat(e.members, ",")) end
local function Changed()
	ns.Fire("SQUADS_CHANGED"); ns.Fire("CHAT_ROOMS_CHANGED")
end
function Squads.Get(name)
	local leader = Leader(name)
	if not leader then return nil end
	local s = Store(false)
	local row = s and s.rows[Fold(leader.name)]
	if not ValidRow(row) or Fold(row.leader) ~= Fold(leader.name) then row = nil end
	leader.soldiers = {}
	for _, soldier in ipairs(row and row.members or {}) do
		local current = Member(soldier)
		if current and Fold(current) ~= Fold(leader.name) then leader.soldiers[#leader.soldiers + 1] = current end
	end
	leader.count, leader.rev, leader.by = #leader.soldiers, row and row.rev, row and row.by
	return leader
end
local function Put(e, sender)
	local s = Store(true)
	if not s then return false, "store" end
	local key, old = Fold(e.leader), s.rows[Fold(e.leader)]
	if old ~= nil and not ValidRow(old) then return false, "store" end
	if old and (e.rev < old.rev or e.rev == old.rev and Encode(e) <= Encode(old)) then return false, "old" end
	if not old then
		local count = 0; for _ in pairs(s.rows) do count = count + 1; if count >= Squads.MAX_ROWS then return false, "limit" end end
		-- Retain older assignments rather than destructively pruning history to make room.
		if count >= Squads.MAX_ROWS then return false, "limit" end
	end
	e.by = sender; s.rows[key] = e
	Changed(); return true
end
local function SendRecord(e)
	if not ValidRow(e) then return false end
	local guild, msg = Guild(), Encode(e)
	local key = "squad:" .. Fold(e.leader)
	local options = { owner = Squads, key = key, permit = function(_, guardKey, dist, target, currentMessage)
		if guardKey ~= key or dist ~= "GUILD" or target ~= nil or #msg <= 255 and currentMessage ~= msg then return false end
		local s = Store(false); local current = s and s.rows[Fold(e.leader)]
		return Guild() == guild and Squads.CanManage() and ValidRow(current) and Encode(current) == msg or false
	end }
	if #msg <= 255 then return ns.Comm.Send("GUILD", msg, options.key, true, false, nil, options) end
	return ns.Comm.SendChunked(msg, true, "GUILD", nil, options)
end
function Squads.Replace(name, members)
	if not Squads.CanManage() then return false, "officer" end
	local leader = Leader(name)
	if not leader then return false, "leader" end
	local list = List(leader.name, members)
	if not list then return false, "members" end
	if not Rate(outgoing, "write", 20, 60) then return false, "rate" end
	local s = Store(true); if not s then return false, "store" end
	local old = s.rows[Fold(leader.name)]
	if old ~= nil and not ValidRow(old) then return false, "store" end
	local rev = math.max(Now(), old and old.rev + 1 or 0)
	if not Int(rev) or rev > Now() + 300 then return false, "revision" end
	local e = { leader = leader.name, members = list, rev = rev }
	if #Encode(e) > ns.Codec.CHUNK * ns.Codec.MAX_CHUNKS then return false, "wire" end
	local ok, why = Put(e, ns.me)
	if not ok then return false, why end
	SendRecord(e); return true
end
function Squads.Assign(leader, soldier)
	local current = Squads.Get(leader)
	if not current then return false, "leader" end
	local full = Member(soldier)
	if not full then return false, "member" end
	for _, member in ipairs(current.soldiers) do if Fold(member) == Fold(full) then return false, "duplicate" end end
	current.soldiers[#current.soldiers + 1] = full
	return Squads.Replace(leader, current.soldiers)
end
function Squads.Remove(leader, soldier)
	local current, full = Squads.Get(leader), Full(soldier)
	if not current or not full then return false, "member" end
	local list = {}; for _, member in ipairs(current.soldiers) do if Fold(member) ~= Fold(full) then list[#list + 1] = member end end
	return Squads.Replace(leader, list)
end
function Squads.Handle(dist, sender, text)
	if dist ~= "GUILD" or not Guild() or type(text) ~= "string" or #text > ns.Codec.CHUNK * ns.Codec.MAX_CHUNKS or not Member(sender) then return false end
	if not Rate(incoming, Fold(sender), 60, 60) then return false end
	if text == "WU~1~Q" then
		if not Squads.CanManage() or not Rate(outgoing, "reply", 1, 60) then return false end
		local s = Store(false)
		local checked = 0
		for key, row in pairs(s and s.rows or {}) do
			checked = checked + 1; if checked > Squads.MAX_ROWS then return false end
			if ValidRow(row) and key == Fold(row.leader) and Leader(row.leader) then SendRecord(row) end
		end
		return true
	end
	if not Officer(sender) then return false end
	local name, revision, raw = text:match("^WU~1~S~([^~]+)~(%d+)~([^~]*)$")
	local leader, rev = name and Leader(name), tonumber(revision)
	if not leader or not Int(rev) or rev > Now() + 300 then return false end
	local members = {}; for member in raw:gmatch("[^,]+") do members[#members + 1] = member end
	local list = List(leader.name, members)
	if not list or table.concat(list, ",") ~= raw then return false end
	return Put({ leader = leader.name, members = list, rev = rev }, Member(sender))
end
function Squads.Request()
	if not Guild() or Clock() - lastRequest < 60 then return false end
	local guild = Guild(); lastRequest = Clock()
	return ns.Comm.Send("GUILD", "WU~1~Q", "squads:query", false, false, nil, { owner = Squads, key = "squads:query",
		permit = function(_, key, dist, target, message)
			return key == "squads:query" and dist == "GUILD" and target == nil and message == "WU~1~Q"
				and Guild() == guild and Member(ns.me) ~= nil
		end })
end
function Squads.CanAccess(room, name)
	if Preview() or not Member(ns.me) then return false end
	local leader, full = LeaderRoom(room), Member(name or ns.me)
	if not leader or not full then return false end
	if Fold(full) == Fold(leader.name) then return true end
	local current = Squads.Get(leader.name)
	for _, soldier in ipairs(current.soldiers) do if Fold(soldier) == Fold(full) then return true end end
	return false
end
local function ChatOn() return ns.db and ns.db.chatRooms == true and not (ns.ChatLocked and ns.ChatLocked()) or false end
local function Chat(room, make)
	local s = Store(make)
	if not s then return nil end
	local chat = s.chats[room]
	if chat == nil and make then
		local count = 0; for _ in pairs(s.chats) do count = count + 1; if count >= Squads.MAX_ROWS then return nil end end
		chat = { seq = 0, lines = {}, seen = {} }; s.chats[room] = chat
	end
	if type(chat) ~= "table" or not Int(chat.seq) or type(chat.seen) ~= "table" then return nil end
	local count = Dense(chat.lines, Squads.CHAT_MAX)
	if count == nil then return nil end
	for i = 1, count do
		local line = chat.lines[i]
		if type(line) ~= "table" or not Full(line.sender) or type(line.text) ~= "string" or #line.text > 150
			or not Int(line.id) or line.id < 1 or not Int(line.t) then return nil end
	end
	local seen = 0
	for name, seq in pairs(chat.seen) do
		seen = seen + 1
		if seen > Squads.SEEN_MAX or not Full(name) or not Int(seq) or seq < 1 then return nil end
	end
	return chat
end
local function Words(text)
	if type(text) ~= "string" then return "" end
	return ns.Cut(ns.Codec.SanitizeChat(ns.Codec.Plain(text)):gsub("~", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""), 150)
end
local function Keep(room, e)
	local chat = Chat(room, true); if not chat then return end
	chat.lines[#chat.lines + 1] = e
	while #chat.lines > Squads.CHAT_MAX do table.remove(chat.lines, 1) end
	ns.Fire("CHAT_ROOM_CHANGED", room)
	if not e.mine then ns.Fire("CHAT_ROOM_LINE", room, e.sender, e.text) end
end
function Squads.ChatHistory(room)
	local out = {}
	if not ChatOn() or not Squads.CanAccess(room) then return out end
	local chat = Chat(room, false)
	local moderation = ns.Moderation
	for _, line in ipairs(chat and chat.lines or {}) do
		if Squads.CanAccess(room, line.sender) and not (moderation and moderation.Hides and moderation.Hides(line.sender, Guild())) then out[#out + 1] = line end
	end
	return out
end
function Squads.ChatSend(room, text)
	if not ChatOn() or not Squads.CanAccess(room) then return false, "access" end
	text = Words(text); if text == "" then return false, "empty" end
	if not Rate(chatRate, "mine", 12, 60) then return false, "rate" end
	local leader, guild = LeaderRoom(room), Guild()
	local squad, chat = Squads.Get(leader.name), Chat(room, true)
	if not chat or not Int(chat.seq) or chat.seq >= 2147483647 then return false, "sequence" end
	chat.seq = chat.seq + 1
	local seq, msg = chat.seq, ("SC~1~%s~%d~%s"):format(room:sub(7), chat.seq, text)
	local recipients = { leader.name }; for _, name in ipairs(squad.soldiers) do recipients[#recipients + 1] = name end
	local kept, queued = false, false
	local function Mine()
		if not kept and Guild() == guild and ChatOn() and Squads.CanAccess(room) then
			kept = true; Keep(room, { sender = ns.me, guild = guild, text = text, t = Now(), mine = true, id = seq })
		end
	end
	for _, recipient in ipairs(recipients) do
		if Fold(recipient) ~= Fold(ns.me) then
			local to = recipient
			local guard = function() return Guild() == guild and ChatOn() and Squads.CanAccess(room) and Squads.CanAccess(room, to) end
			local ok = ns.Comm.Whisper(to, msg, "squad-chat:" .. room .. ":" .. seq .. ":" .. Fold(to), false, true,
				function(sent) if sent and guard() then Mine() end end, { owner = Squads, guard = guard })
			queued = ok or queued
		end
	end
	if #recipients == 1 then Mine(); return true end
	return queued, queued and "ok" or "busy"
end
function Squads.ReceiveChat(dist, sender, text)
	if dist ~= "WHISPER" or type(text) ~= "string" or #text > 255 or not ChatOn() then return false end
	if C_ChatInfo and C_ChatInfo.SendAddonMessageLogged and ns.Comm.DeliveredLogged and not ns.Comm.DeliveredLogged() then return false end
	local hash, sequence, words = text:match("^SC~1~(%x+)~(%d+)~(.+)$")
	local room, seq, full = hash and "squad:" .. hash, tonumber(sequence), Member(sender)
	if not hash or #hash ~= 24 or not Int(seq) or seq < 1 or not full or Fold(full) == Fold(ns.me)
		or Words(words) ~= words or not Squads.CanAccess(room) or not Squads.CanAccess(room, full) then return false end
	if not Rate(chatRate, Fold(full), 24, 60) then return false end
	local chat = Chat(room, true)
	if not chat then return false, "store" end
	if seq <= (chat.seen[Fold(full)] or 0) then return false end
	if chat.seen[Fold(full)] == nil then
		local count = 0; for _ in pairs(chat.seen) do count = count + 1 end
		if count >= Squads.SEEN_MAX then return false, "limit" end
	end
	local admitted, why = ns.Channels.Admit(full, Guild(), words, Clock(), { id = room .. ":" .. Fold(full) .. ":" .. seq, chat = room, line = seq, level = 1 })
	if not admitted then return false, why end
	chat.seen[Fold(full)] = seq
	Keep(room, { sender = full, guild = Guild(), text = words, t = Now(), id = seq }); return true
end
function Squads.ChatInfo(room)
	local leader = LeaderRoom(room)
	if not leader then return nil end
	local format = ns.L and ns.L.SQUAD_CHAT_LABEL or "Squad %d"
	return { id = room, kind = "role", scope = "restricted", label = format:format(leader.index) }
end
local provider = { Info = Squads.ChatInfo, CanAccess = Squads.CanAccess, History = Squads.ChatHistory,
	Send = Squads.ChatSend, ChatOn = ChatOn, IsOpen = function(room) return LeaderRoom(room) ~= nil end,
	Select = function(room) return Squads.CanAccess(room) end,
	Options = function(kind)
		local out = {}; if kind ~= "role" then return out end
		for _, e in ipairs(Squads.Leaders()) do if Squads.CanAccess(e.room) then out[#out + 1] = Squads.ChatInfo(e.room) end end
		return out
	end,
}
Squads.ChatProvider = provider
local function Label(key, fallback) return ns.L and rawget(ns.L, key) or fallback end
function Squads.Lines(query, baseIndent, manage)
	local lines, indent = {}, baseIndent or 0
	local masked = ns.CouncilMasked and ns.CouncilMasked() == true and ns.IsKingGuild(Guild())
	local officer = manage ~= false and Squads.CanManage() and not masked
	for _, e in ipairs(Squads.Leaders()) do
		local squad, hit = Squads.Get(e.name), not query
		if query and not masked then
			hit = ns.Holds(query, e.name)
			for _, name in ipairs(squad.soldiers) do hit = hit or ns.Holds(query, name) end
		end
		if hit then
			local shown = masked and Label("SQUAD_COUNCILLOR", "High Councillor %d"):format(e.index) or ns.Codec.Plain(ns.ShortName(e.name))
			if not masked then shown = (e.kind == "councillor" and Label("SQUAD_LEADER_COUNCIL", "High Councillor — %s") or Label("SQUAD_LEADER_CENTURION", "Centurion — %s")):format(shown) end
			lines[#lines + 1] = { indent = indent, squadLeader = not masked and e.name or nil, text = shown,
				right = Label("SQUAD_COUNT", "%d/99 soldiers"):format(squad.count) }
			if not masked then
				for _, name in ipairs(squad.soldiers) do
					lines[#lines + 1] = { indent = indent + 1, player = name, text = ns.Codec.Plain(ns.ShortName(name)) }
					if officer then
						local soldier, leader = name, e.name
						lines[#lines + 1] = { indent = indent + 2, text = Label("SQUAD_REMOVE", "Remove soldier"),
							onClick = function() return Squads.Remove(leader, soldier) end }
					end
				end
				if squad.count == 0 then lines[#lines + 1] = { indent = indent + 1, text = Label("SQUAD_EMPTY", "No soldiers assigned") } end
				if officer and squad.count < Squads.MAX_SOLDIERS then
					local leader = e.name
					lines[#lines + 1] = { indent = indent + 1, text = Label("SQUAD_ADD", "Assign soldier"), onClick = function()
						if not Squads.CanManage() or not Leader(leader) then return false end
						return ns.ShowDialog("OLYMPUS_WAR_INPUT", Label("SQUAD_ADD", "Assign soldier"), Label("SQUAD_HINT", "Name of a current member of your guild."), { prefix = "squadadd " .. leader .. "|" })
					end }
				end
				if Squads.CanAccess(e.room) then
					local room = e.room
					lines[#lines + 1] = { indent = indent + 1, text = Label("SQUAD_OPEN_CHAT", "Open private squad chat"),
						onClick = function()
							if ns.ChatRooms and ns.ChatRooms.OpenMatter and Squads.CanAccess(room) then return ns.ChatRooms.OpenMatter({ room = room, keep = false }) end
							return false
						end }
				end
			end
		end
	end
	if #lines > 0 then table.insert(lines, 1, { indent = indent, header = true, text = Label("SQUAD_TITLE", "Military squads — your guild") }) end
	return lines
end
if ns.ChatRooms then ns.ChatRooms.RegisterProvider(provider) end
ns.Comm.Handle("WU", Squads.Handle)
ns.Comm.Handle("SC", Squads.ReceiveChat)
-- Event driven only: no per-frame task or periodic enumeration while idle.
ns.On("DATA_CHANGED", function() indexedRoster = nil; Changed(); Squads.Request() end)
ns.On("LOGIN", Squads.Request)

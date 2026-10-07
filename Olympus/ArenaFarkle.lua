local ADDON, ns = ...

-- Farkle's rules (1.2): the Blood Arena's dice game for two players. Every die comes from the
-- server's /roll, never from a client: one /roll 1-46656 is six dice, 1-7776 five, down to 1-6
-- for one, and each client at the table reads the server's line itself. This file only turns
-- those numbers into dice, keeps the score and writes the game down as event codes (the
-- transcript every client at the table compares). Pure functions over the values passed in: no
-- events, no messages, no saved data, no WoW API. The one other file it reads is Sign.lua (its
-- SHA-256, for the chain and the transcript hash), which loads before it. The table's code
-- (witnessing the rolls, the messages, the stakes) and the page build on it, and the tests call
-- it directly.
--
-- One rule set: the constants below (the FarkleRules fields in capitals: RANGES, the TARGET
-- tables, TURN_CAP, TIMEOUTS, HOUSE, SCORES and the rest) are what every client plays by. Nothing
-- may change them at runtime: a change would re-score every live table on this client and split
-- its chain from the other clients'. (Only the tests swap a row, and put it back.)
--
-- Where this API differs from the sketch in the design (this header is the API; the design renames
-- that Farkle.lua to this file):
--   - Best returns points, positions (the design: mask, points); Mask writes positions as the mask.
--   - HouseMove returns positions, act (the design: mask, act).
--   - Expect returns who, phase, left, three values, not one table { who, what, k }. The phases
--     are "open", "roll", "keep" (the design's "choose") and "decide".
--   - CanScore returns nil, not false, for what is not a roll.
--   - TARGETS is the list { 2000, 5000, 10000 } in points. The design's TARGETS, keyed by the wire's
--     target code 2|5|10, is TARGET_BY_CODE here, so TARGETS[code] is always the wrong lookup.
--   - No Fees: money math lives in ArenaMath (the design).
--   - The chain uses SHA-256, not Comm's Hash36 (see "Rules chosen here" at the end).
--
-- Dice
--   FarkleRules.Decode(roll, n) -> { d1, ..., dn } | nil
--     One server roll in 1..6^n as n dice: roll - 1 written in base 6, lowest digit first, each
--     digit + 1 (31337 of 1-46656 is 5 3 1 2 1 5). nil when n is not 1..6 or the roll is not a
--     whole number in 1..6^n. A die keeps its position: the dice set aside are named by it.
--   FarkleRules.Encode(dice) -> roll, n | nil    the roll that decodes to these dice (1 to 6 faces)
--   FarkleRules.RangeK(lo, hi) -> n | nil        how many dice "/roll lo-hi" throws (only 1-6^n;
--                                                the opening's 1-100 is no dice)
--   FarkleRules.RANGES[n]                         6^n, the top of the roll for n dice
--   FarkleRules.Mask(mask) -> text, { positions } | nil
--     A set of dice positions, given as a list ({ 5, 1 }) or as digits ("51"), written the one
--     way the codes use ("15") and as the positions ascending. nil when it is empty, names a
--     position twice or one outside 1..6. (Whether they are dice of the roll is Keep's check.)
-- Scoring: Kingdom Come: Deliverance II's dice (the points are FarkleRules.SCORES, one table the
-- rules read at every call; a row set to false leaves that combination out). A lone 1 is 100 and a
-- lone 5 is 50; three of a kind is the face x 100 (three 1s 1000), and each die past the third
-- doubles it (four 1s 2000, five 4000, six 8000); the runs 1-2-3-4-5 are 500, 2-3-4-5-6 750 and
-- 1-2-3-4-5-6 1500. Nothing else scores: no three pairs, no four and a pair, no bonus for two
-- triplets, and a 2, 3, 4 or 6 scores only in a set of three or more or in a run.
--   FarkleRules.Score(dice) -> points | nil
--     Dice set aside from one roll, scored the best way they split into the combinations, each
--     die used once, the parts added up: four 1s are 2000 (one combination, not three 1s and a
--     1); 1-2-3-4-5-5 is 550 (the run and a 5); 2-3-4-5-6-1 is 1500 (the whole run beats 2-6 and
--     a 1); 1-1-1-5-5-5 is 1500 (two triples); 4-4-4-4-1-1 is 1000. nil when any die fits no
--     combination (2-3-4-5-6-6: the second 6; 2-2-3-3-4-4), or when the list is not 1 to 6 faces
--     of 1..6.
--   FarkleRules.Best(dice) -> points, { positions } | nil
--     The most a roll can score and which dice give it (positions, ascending); 0, {} when it is a
--     Farkle; nil when the list is not a roll. (With the table's points no selection of other
--     faces ties it: 2-3-4-5-6-6 is 750 with its first 6, and 1-1-5-5-6-6 is 300 with the 6s
--     left.)
--   FarkleRules.CanScore(dice) -> true | false | nil  false when nothing in the roll scores (a
--     Farkle: no 1, no 5, no face three times; 2-2-3-3-4-4 is one); nil when the list is not a
--     roll
--   FarkleRules.Farkle(dice) -> true | false | nil    the same question the other way round
--   FarkleRules.HotDice(turn) -> true | false         the last dice set aside were the turn's
--     last ones: the next roll is six dice again, with the turn's points kept
-- A turn (a table; read its fields, change it only through these)
--   FarkleRules.Turn.New() -> turn
--     { points, left, phase, dice, kept, hot, rolls, farkle, lost, banked }
--     points: this turn's so far; left: in "roll" and "decide", the dice the next roll throws,
--     but in "keep" the dice just thrown (how many roll next depends on what he sets aside);
--     dice: the last roll's faces; kept: positions set aside from it (nil until he does); lost:
--     what a Farkle wiped; banked: what a bank scored.
--     phase: "roll" (must roll), "keep" (must set aside scoring dice), "decide" (roll again or
--     bank), "done". In a game, a decision event ("K", below) sets dice aside and rolls on or
--     banks at once, so after "K ... r" the turn is in "roll"; "decide" comes only from Keep.
--   FarkleRules.Turn.Roll(turn, roll) -> dice, farkle | nil, err
--     A server roll of the dice left (1..6^left). A Farkle ends the turn and loses its points.
--   FarkleRules.Turn.Keep(turn, positions) -> points, hot | nil, err
--     Sets aside dice of the last roll by position ({ 1, 4 }); they must all score together.
--     Once per roll: set aside everything wanted in one call (combinations count within a call).
--   FarkleRules.Turn.Bank(turn) -> points | nil, err   ends the turn with its points
-- A game (a table; read its fields, change it only through the functions below)
--   FarkleRules.New(fields) -> game | nil, err
--     fields.target (required): 2000, 5000 or 10000 points (FarkleRules.TARGETS). The table always
--       names it; FarkleRules.TARGET (5000) is only the page's default. The turn cap follows from
--       it (FarkleRules.TURN_CAP: 12, 25 and 45 turns each), the same on every client.
--       The wire carries the target as a code, 2|5|10 (KI, KG): FarkleRules.TARGET_BY_CODE[code]
--       reads it as points, FarkleRules.TARGET_CODE[target] writes it. TARGETS is a list, not
--       keyed by the code: TARGETS[2] is 5000.
--     fields.first: 1 or 2, the seat that starts. Left out, the game opens with the opening
--       rolls (the "O" events below), and the higher roll starts. Practice names it.
--     fields.players: { "Name-Realm", "Name-Realm" }, so moves may name the player instead of
--       his seat (names match in any case).
--     fields.id: the table's id; fields.terms: the table's agreed fields as one line (mode,
--       stake, arbiter, sources, timer, salt: whatever the table agreed). Both go into the head
--       line that starts the chain and the transcript, so two clients that agreed different
--       terms never share a chain. Neither is shown anywhere.
--     fields.hiccup: true for a table that plays the hiccup (the drunk rule, the design). The
--       head line then starts "farkle1h" instead of "farkle1", so a hiccup table and a sober one
--       never share a chain. Left out (or false), levels, "L" and "H" are refused ("sober") and
--       the game is exactly the sober one.
--     err names the field that is wrong: "fields", "target", "first", "players" (two names that
--     differ in more than case, with no "|" or line break), "id" (a string with no "|" or line
--     break), "terms" (a string with no line break), "hiccup" (not a boolean), or "sign"
--     (Sign.lua did not load).
--     game: { players, target, cap, first, current, open, opening = { v1, v2 }, ties,
--     scores = { a, b }, turns = { a, b }, timeouts = { a, b }, turn, queue, ahead, final,
--     capped, sudden, over, winner, reason, last, id, head, events, step, chain, chains,
--     hiccup, level = { a, b }, floor = { a, b }, shakes = { a, b }, pending, handed, lines }
--     open: true until the opening decides who starts (current and first are nil until then);
--     opening: each seat's opening roll this round; ties: opening rounds that tied (the table
--     gives up after FarkleRules.OPENING_TIES, with no fault on anyone);
--     current: the seat (1 or 2) whose turn it is, nil once over; turns: turns each finished;
--     timeouts: turns in a row each lost to the clock; queue: the current player's lines held
--     until the decision they overtook, in the order the server sent them (W3 below); ahead:
--     the other player's lines that came before the event ending this turn, held until his
--     turn starts (below); level: each seat's drunk level (0-3) as his opponent's decisions
--     recorded it; floor: the arbiter's floor under it ("L" events); shakes: Farkles each seat
--     shook off this game; pending: the arbiter's floors named for a later turn (Floor);
--     handed: the step at which the current turn was handed over; lines: how many lines have
--     arrived (each held line carries its number, the server's order); final: the seat whose turn,
--     once over, ends the capped game; capped:
--     true when it was the cap (the reason is then "cap"); sudden: the scores were level then, so the players go on a turn
--     each in the same order until one is ahead; winner: the winning seat (nil for a void);
--     reason: "target", "cap", "concede", "forfeit" or "void"; last: the turn just finished,
--     { who, how = "bank"|"farkle"|"timeout"|"foul", points, lost, dice }; head: the agreed
--     fields line; events: the event codes so far, in logical order; step: how many; chain:
--     the chain after the last of them; chains[i]: the chain after the first i (chains[0] is
--     the head line's).
--   FarkleRules.Apply(game, ev) -> true, note | nil, err
--     What a client at the table witnessed, as an event table or its code (below). A refused
--     event changes nothing, and neither the chain nor the step moves. Notes: "held" (a line
--     that came before the decision it follows, kept until that decision arrives, W3; or the
--     other player's line that came before the bank, Farkle, timeout or foul ending this turn,
--     kept until his turn starts and then taken as its first), "stands" (a roll seen before
--     the player's bank: the bank is read as setting the dice aside and rolling, W4), "tie"
--     (the opening tied: both roll again),
--     "hiccup" (a Farkle on a hiccup table with a chance: his /roll 1-100 is due), "shaken"
--     (the hiccup shook the Farkle off). A roll's range goes in as k (RangeK), so a wrong count
--     is refused with "count", without changing the turn or writing an event.
--   FarkleRules.Floor(game, who, turn, level) -> true, note | nil, err
--     The arbiter's floor under a seat's drunk level (his KL), from that seat's turn number
--     `turn` on (his turns counted from 1). Kept ("pending") until that turn is handed over,
--     then written there as "L<p>:<level>" before its first roll, so every client writes it at
--     the same place. Refused "late" once that turn has an event of its own, "level" for a
--     level that is not 0-3 or a turn that is not a number.
--   FarkleRules.Level(game, who) -> level, percent, shakes | nil
--     The level his next or current turn plays at (the higher of the recorded level and the
--     floor), that turn's hiccup chance in percent (the locked one once the turn has rolled, 0
--     once his shake-offs are spent), and the shake-offs he has left.
--   Moves for a client acting alone (practice, the page's own buttons). They write the same codes
--   as the events: a Keep is written as its "K" once he rolls on or banks, and a set-aside he
--   never acted on (the clock ran out) is not written.
--   FarkleRules.Roll(game, who, roll)       -> dice, farkle | nil, err
--   FarkleRules.Keep(game, who, positions)  -> points, hot | nil, err
--   FarkleRules.Bank(game, who)             -> points | nil, err
--   FarkleRules.Timeout(game, who)          -> true | nil, err   his clock ran out: turn lost
--   FarkleRules.Foul(game, who)             -> nil, err   retained API, never a live penalty
--   FarkleRules.Concede(game, who)          -> true | nil, err   either player, at any time
--   FarkleRules.Void(game)                  -> true | nil, err   nobody wins, nobody owes
--   FarkleRules.Hiccup(game, who, roll)     -> true | false | nil, err   his /roll 1-100 after a
--                                                                Farkle: true shook it off
--   FarkleRules.Expect(game) -> who, phase, left | nil   the seat expected to act, the turn's
--     phase and the dice his next roll must throw (a roll is expected in "roll" and allowed in
--     "decide"). In "keep" left is nil: no roll is due until he sets dice aside, and only then is
--     the count known. In "hiccup" left is nil too: his /roll 1-100 is due. In the opening the
--     phase is "open" and who is the seat whose opening roll is missing, or 0 when both are. nil
--     once the game is over, or for anything not a game.
--   FarkleRules.HouseMove(game) -> positions, act | nil
--     The House's move for the player to act (practice): in "keep" it sets aside Best's dice
--     (the highest-scoring set; on a tie, the lower positions: from 2-3-4-5-6-6 the run and the
--     first 6) and says "b" (bank) or "r" (roll on); in "roll" only "r"; in
--     "decide", nil and the act; in "hiccup" only "h" (press HIC!). It banks at 1,000 points
--     or more, at 550 or more with 3 dice
--     or fewer to roll, at 300 or more with 2 or fewer (FarkleRules.HOUSE); on the game's last
--     turn it banks only when banking wins, and rolls on otherwise. nil in the opening, once
--     over, or for anything not a game.
--   who is the seat (1 or 2) or the player's name as given in fields.players, in any case.
-- Events (the design), each with a code of its own (p is the seat, 1 or 2):
--   { t = "O", p, value [, relayed] }        "O<p>:<value>"          an opening roll (1-100)
--   { t = "R", p, k, value [, relayed] }     "R<p>:<k>:<value>"      a roll of k dice
--   { t = "K", p, mask, act = "r"|"b" [, lvl] }  "K<p>:<mask>:<r|b>[:<lvl>]"  dice set aside, then
--                           roll or bank; lvl (0-3, hiccup tables only) is what p's client saw
--                           of the other seat's drunk level since its last decision, written only
--                           when it changes the recorded level
--   { t = "H", p, value [, relayed] }        "H<p>:<value>"          his hiccup, /roll 1-100
--   { t = "L", p, lvl }                      "L<p>:<lvl>"            the arbiter's floor under seat p's
--                           level, written where his turn is handed over (Floor)
--   { t = "F", p }  "F<p>"  a historical foul (Replay only)     { t = "T", p }  "T<p>"  a timeout
--   { t = "C", p }  "C<p>"  a concession
--   { t = "A", p }  "A<p>"  the third timeout in a row, a forfeit (a "T" that is the third is
--                           written "A", so every client writes it the same way)
--   { t = "V" }     "V"     a void
--   A relayed roll or hiccup (one this client did not see itself, taken during a resync) is
--   written with a trailing "*". The mark stays in game.events but is left out of the chain, the
--   transcript and the hash, so a client that resynced still agrees with the others.
--   FarkleRules.Code(ev) -> code | nil       FarkleRules.Event(code) -> ev | nil
--     Event reads only the one spelling Code writes (no leading zeros, the mask ascending).
-- The chain, the transcript and the hash (the design)
--   FarkleRules.Chain(prev, code) -> chain   8 hex digits: SHA-256 of prev .. "|" .. code. The
--     first link is the SHA-256 of the head line alone. It only detects that two clients
--     diverged; each client's security is its own witnessing.
--   FarkleRules.ChainAt(game, step) -> chain | nil   the chain after the first step events (a
--     lookup in game.chains, so a check of a message's step costs no hashing)
--   FarkleRules.Transcript(game) -> text     the head line, then each event code, one per line
--   FarkleRules.Hash(game) -> hash8          the first 8 hex digits of Sign.SHA256(Transcript)
--   FarkleRules.Replay(fields, codes) -> game | nil, err, index
--     The game rebuilt from its fields and codes (a transcript kept or received): err is New's,
--     "codes", or the refusal of the code at index. A transcript is in logical order, so a roll
--     it would have to hold is refused ("held").
-- For the table's code: hand Apply every roll line of either player whose range is a Farkle
-- range (1-100 in the opening, and on a hiccup table during play), not only the roll Expect
-- names; Apply decides which counts. Every line of a player is taken in the order the server
-- sent it, whenever his decisions reach this client (the queue), so every client writes the same
-- chain whatever the arrival order:
--   - A line from the current player that arrives while his decision is due ("keep"), or behind
--     one that waits, is held until that decision (W3), then taken in order: a roll counts (its
--     count compared with the dice he has left, a wrong count refused) and may itself wait for
--     his next decision; a 1-100 line counts only as the hiccup of a Farkle before it, else it
--     is ignored. Every valid roll counts in turn, so rolling twice cannot replace the first;
--     invalid counts are discarded without costing a turn. At most FarkleRules.HOLD lines wait
--     ("extra" beyond).
--   - The same across a turn: every table message is whispered to each participant in turn
--     (the design, one message every 1.2 s), so the next player can see a bank, or a timeout
--     claim, and roll before that message reaches this client. His lines are held until the turn
--     passes to him, then taken as his turn's first. The first must be a roll of six dice, the
--     count every turn starts with; any other first line of the player not to act is refused
--     ("turn"), so a /roll 6 typed while waiting never costs him his turn. Held lines go when the
--     game ends. The current player's lines still held when his turn ends are read the same way,
--     as the waiting player's.
--   - Only lines are held across a turn. The next player's decision (KK) or claim that arrives
--     before the event ending this turn is refused ("turn"); it carries its step, so the table
--     sees it as a gap (KQ, or a short wait for the missing event) before it reaches Apply.
--     A player's six-dice roll after his own bank (W4) is held as his next turn's first roll
--     where the bank came first, and stands in this turn where the roll came first: the chains
--     differ, and the table's dispute rules settle it. But a roll of his that came after a held
--     line of the other player is after the bank wherever it arrives (the other player rolled
--     because he saw it): it never stands against the bank, and waits for his next turn.
--   - A resync (KR) fills only what this client did not see: a relayed event for a step where
--     this client already wrote its own is compared with it, never applied over it.
--   - The hiccup (hiccup tables): a Farkle of a turn with a chance (Level) leaves the turn in
--     "hiccup" instead of ending it. His first 1-100 line then decides: at or under the chance
--     the Farkle is shaken off (the turn keeps its points and the same dice are thrown again,
--     six after hot dice), otherwise it stands. A dice line before it is ignored ("hiccup"); a
--     timeout or foul claimed then ends the turn as the Farkle it was, with no timeout counted.
--     The chance is fixed at the turn's first roll, from the level recorded before it.
-- Errors (the err above; a refused move changes nothing)
--   "over" the game has ended; "player" who is neither player; "turn" not his turn (for a
--   roll by the player not to act: not six dice);
--   "open" the game is still in its opening (only opening rolls, a concession or a void count);
--   "started" an opening roll once the opening is over; "extra" a second opening roll (W1), or a
--   line past FarkleRules.HOLD held ones; "done" the turn has ended; "range" the roll is not 1..6^k (or 1..100 for an
--   opening roll); "keep" dice must be set aside before rolling again or banking; "roll" a roll
--   is due first (nothing on the table to set aside, or he chose to roll on); "dice" the
--   positions are not distinct dice of the last roll; "score" a die set aside doesn't score;
--   "empty" nothing to bank; "held" a move alone while Apply holds a line (only a decision
--   event settles it); "count" an "A" that is not his third timeout in a row (never during a
--   hiccup); "event" not an event; "game" the game passed is not one made by New (for Turn.*,
--   the turn is not a table); "sober" a level, "L" or "H" on a table without the hiccup;
--   "hiccup" a dice roll while his hiccup is due; "phase" a 1-100 line with no hiccup due;
--   "level" an "L" away from a hand-over, or one that changes nothing; "late" a floor for a
--   turn that has begun.
-- Rules chosen here, and why
--   - The first bank that reaches the target wins immediately, without an answer turn.
--   - The turn cap is a safety net: when both players have had cap turns the higher score wins
--     (level: sudden death, a turn each in the same order until one is ahead).
--   - Invalid actions are refused without losing the turn or points. A turn lost to the clock
--     scores nothing, like a Farkle. Three turns in a row
--     lost to the clock forfeit the game: one rule covers a player who disconnects, leaves the
--     group or walks into an instance. Any other finished turn resets his count. (The table's
--     clock, and its pause while a player reports combat, are the table's; the rules only count
--     the timeouts it claims.)
--   - The chain uses the SHA-256 the transcript hash needs anyway (the design named Comm's
--     Hash36): a rules file keeps off the network layer, and every client computes the chain
--     here the same way.
--   - The next player's six-dice roll that overtakes the message ending the turn before it is
--     held, not refused (the design accepted a roll only when the table expected it from that
--     player). Otherwise the arbiter, the one witness that settles a dispute, would refuse a
--     roll it saw whenever the bank reached it last, which the whisper order makes common. Every
--     client sees the server's roll lines in the same order, and nobody can take a held roll
--     back, so holding gives the roller nothing.
--   - Every held line counts in turn (a queue), not only the first (W1 kept one and refused the
--     rest). With one, a witness that saw two rolls before the decision between them refused
--     the second while one that saw the decision first held it: their chains split. A queue
--     gives every witness the same reading, and the roller still gains nothing, since no roll
--     of his is ever dropped for a better one.
--   - The drunk level (hiccup tables) is written by the OTHER seat's decisions, never by the
--     drinker: a player cannot raise his own. It changes only the seat's next turn, and the
--     arbiter's floor (Floor) is written where a turn is handed over, before its first roll,
--     so neither ever lands in the middle of a turn on one client and not on another.
--   - A missed hiccup is a Farkle, not a timeout: a sober Farkle ends the turn at once, so the
--     drunk player must not pay a timeout, or a step toward the forfeit, for the same dice.
--   - At most FarkleRules.SHAKES shake-offs per seat per game: unlimited, a bold player's edge
--     grew to 60% (the design's calibration), while the House's barely changes at two.

local FarkleRules = {}
ns.FarkleRules = FarkleRules

FarkleRules.DICE = 6
FarkleRules.RANGES = { 6, 36, 216, 1296, 7776, 46656 }   -- /roll 1-RANGES[n] throws n dice
FarkleRules.OPENING = 100                                -- the opening roll is /roll 1-100
FarkleRules.OPENING_TIES = 5                             -- opening rounds tied before the table gives up
FarkleRules.TARGET = 5000                                -- the page's default (New needs one named)
-- The targets the table offers, in points: a list, NOT keyed by the wire's target code.
FarkleRules.TARGETS = { 2000, 5000, 10000 }
-- The wire's target code (KI, KG: 2|5|10) as points, and back.
FarkleRules.TARGET_BY_CODE = { [2] = 2000, [5] = 5000, [10] = 10000 }
FarkleRules.TARGET_CODE = { [2000] = 2, [5000] = 5, [10000] = 10 }
-- Turns each at most, by target: far above a normal game, so it only ends a game two players
-- stall. (Seeded games played with these rules and KCD2's points, 2,000 per target, took 4.4,
-- 9.9 and 19.6 turns each on average; the longest 11, 19 and 29. The players set aside Best's
-- dice and banked at 1,000, or at 300 with 2 dice or fewer to roll, as in the tests' 300 seeded
-- games. The old points gave 4.2, 9.5 and 18.6, and 11, 20 and 31: the longest games did not
-- grow, so the caps stay.)
FarkleRules.TURN_CAP = { [2000] = 12, [5000] = 25, [10000] = 45 }
FarkleRules.TIMEOUTS = 3                                 -- turns in a row lost to the clock forfeit
-- Legacy hiccup: percent of a /roll 1-100. Explicit hiccupRule="bones2" instead reuses
-- the authenticated zero-score throw, rounding these nominal weights to eligible outcomes.
-- Default New/Replay stays legacy so existing transcripts are never reinterpreted.
-- The hiccup (the design): the chance, in percent of a /roll 1-100, that a Farkle is shaken
-- off, by drunk level: sober 0, tipsy 1, drunk 2, completely smashed 3.
FarkleRules.HICCUP = { [0] = 0, 10, 20, 33 }
FarkleRules.HICCUP_ROLL = 100                            -- the hiccup is /roll 1-100
FarkleRules.SHAKES = 2                                   -- shake-offs each seat has per game
FarkleRules.HOLD = 12                                    -- lines one witness holds for a player at most
-- The House banks once its turn holds at least `points` with at most `left` dice to roll next.
FarkleRules.HOUSE = {
	{ points = 1000, left = 6 },
	{ points = 550, left = 3 },
	{ points = 300, left = 2 },
}

-- The points: the dice of Kingdom Come: Deliverance II, the base game's rules (not its special
-- dice, badges or cheating); the owner's decision of 2026-09-30, replacing the common rule set
-- with its three pairs, four and a pair, two triplets and flat four to six of a kind. A row set to
-- false or 0 (anything not a table), or a value in a row set to false or to nothing above 0, is
-- left out.
FarkleRules.SCORES = {
	single = { [1] = 100, [5] = 50 },                   -- a lone 1 or 5
	triple = { 1000, 200, 300, 400, 500, 600 },          -- three of a kind, by face: face x 100, three 1s 1000
	-- four, five and six of a kind: the face's three of a kind times this (each die past the third
	-- doubles it: four 3s 600, five 1200, six 2400; six 1s 8000). A face whose three of a kind is
	-- left out has none of these either.
	kind = { [4] = 2, [5] = 4, [6] = 8 },
	-- the runs, keyed by their faces (one die of each): they count in any dice set aside that
	-- hold them, next to other combinations (1-2-3-4-5-5 is 550). There are no others: 1-2-3-4
	-- or 1-3-4-5-6 is no run.
	run = { ["12345"] = 500, ["23456"] = 750, ["123456"] = 1500 },
}

local floor = math.floor

local function Int(x) return type(x) == "number" and x % 1 == 0 end
local function Value(v) return type(v) == "number" and v > 0 and v or nil end
-- A drunk level the table knows (0-3: a row of FarkleRules.HICCUP).
local function Lvl(x) return Int(x) and FarkleRules.HICCUP[x] ~= nil end

-- A list of 1 to 6 faces (a roll, or dice set aside from one): how many of each face, and how
-- many dice. nil for anything else, a table with holes or extra keys included.
local function Counts(dice)
	if type(dice) ~= "table" then return nil end
	local n = #dice
	if n < 1 or n > FarkleRules.DICE then return nil end
	local keys = 0
	for _ in pairs(dice) do keys = keys + 1 end
	if keys ~= n then return nil end
	local c = { 0, 0, 0, 0, 0, 0 }
	for i = 1, n do
		local f = dice[i]
		if not Int(f) or f < 1 or f > 6 then return nil end
		c[f] = c[f] + 1
	end
	return c, n
end

-- A row of FarkleRules.SCORES, or nil when it is set to false, 0 or anything else not a table.
local function Row(name)
	local row = FarkleRules.SCORES[name]
	return type(row) == "table" and row or nil
end

-- The points for m dice of face f taken as one combination (a lone 1 or 5; three, four, five or
-- six of a kind), or nil.
local function Unit(f, m)
	if m == 1 then
		local single = Row("single")
		return Value(single and single[f])
	end
	local triples = m >= 3 and Row("triple")
	local triple = triples and Value(triples[f])
	if not triple or m == 3 then return triple or nil end
	local kind = Row("kind")
	local times = Value(kind and kind[m])
	return times and triple * times
end

-- The runs the table scores now (the rows are read at every call, like the rest), each as
-- { points, n (its dice), c (its dice counted like Counts') }. A key that is not faces 1 to 6 is
-- no run.
local function Runs()
	local run, list = Row("run"), {}
	if not run then return list end
	for faces, points in pairs(run) do
		points = Value(points)
		if points and type(faces) == "string" and faces ~= "" and not faces:find("[^1-6]") then
			local c = { 0, 0, 0, 0, 0, 0 }
			for i = 1, #faces do
				local f = faces:byte(i) - 48
				c[f] = c[f] + 1
			end
			list[#list + 1] = { points = points, n = #faces, c = c }
		end
	end
	return list
end

-- Are the dice counted in r all among those counted in c?
local function Holds(c, r)
	for f = 1, 6 do
		if c[f] < r[f] then return false end
	end
	return true
end

local function Higher(a, b)
	if b and (not a or b > a) then return b end
	return a
end

-- The best points for the dice counted in c (n of them), every die used once; nil when some
-- die fits no combination. A split either holds a run, and each run that fits is tried with the
-- rest split the same way, or it has none, and then the lowest face left goes in a lone die or a
-- set of its face, each tried in turn. So every split is seen, and six dice make a few dozen
-- steps at most. (runs: Runs(), read once by the caller.)
local function Split(c, n, runs)
	if n == 0 then return 0 end
	local best
	for i = 1, #runs do
		local run = runs[i]
		if Holds(c, run.c) then
			for f = 1, 6 do c[f] = c[f] - run.c[f] end
			local rest = Split(c, n - run.n, runs)
			for f = 1, 6 do c[f] = c[f] + run.c[f] end
			if rest then best = Higher(best, run.points + rest) end
		end
	end
	local f = 1
	while c[f] == 0 do f = f + 1 end
	local k = c[f]
	for m = 1, k do
		local points = Unit(f, m)
		if points then
			c[f] = k - m
			local rest = Split(c, n - m, runs)
			c[f] = k
			if rest then best = Higher(best, points + rest) end
		end
	end
	return best
end

-- The first 8 hex digits of the SHA-256 of text; nil when Sign.lua did not load.
local function Hex8(text)
	local sign = ns.Sign
	if not (sign and sign.SHA256) then return nil end
	local a, b, c, d = sign.SHA256(text):byte(1, 4)
	return ("%02x%02x%02x%02x"):format(a, b, c, d)
end

-- A code without its relay mark: what the chain, the transcript and the hash see.
local function Bare(code)
	return (code:gsub("%*$", ""))
end

---------------------------------------------------------------------------
-- Dice
---------------------------------------------------------------------------

-- Lowest base-6 digit first: a roll of 1-6 (one die) reads the same as the die, and the n dice
-- of 1..6^n are independent and fair when the server's roll is.
function FarkleRules.Decode(roll, n)
	local top = Int(n) and FarkleRules.RANGES[n]
	if not top or not Int(roll) or roll < 1 or roll > top then return nil end
	local v, dice = roll - 1, {}
	for i = 1, n do
		dice[i] = v % 6 + 1
		v = floor(v / 6)
	end
	return dice
end

function FarkleRules.Encode(dice)
	local c, n = Counts(dice)
	if not c then return nil end
	local v, place = 0, 1
	for i = 1, n do
		v = v + (dice[i] - 1) * place
		place = place * 6
	end
	return v + 1, n
end

-- The range carries the dice count, so a roll commits to how many dice it throws before anyone
-- sees it (with one range for all, a client could roll first and then say how many it had).
function FarkleRules.RangeK(lo, hi)
	if lo ~= 1 or not Int(hi) then return nil end
	for n, top in ipairs(FarkleRules.RANGES) do
		if top == hi then return n end
	end
	return nil
end

function FarkleRules.Mask(mask)
	local list = {}
	if type(mask) == "string" then
		if #mask < 1 or #mask > FarkleRules.DICE or mask:find("[^1-6]") then return nil end
		for i = 1, #mask do list[i] = tonumber(mask:sub(i, i)) end
	elseif type(mask) == "table" then
		local n = #mask
		if n < 1 or n > FarkleRules.DICE then return nil end
		local keys = 0
		for _ in pairs(mask) do keys = keys + 1 end
		if keys ~= n then return nil end
		for i = 1, n do
			local p = mask[i]
			if not Int(p) or p < 1 or p > FarkleRules.DICE then return nil end
			list[i] = p
		end
	else
		return nil
	end
	table.sort(list)
	for i = 2, #list do
		if list[i] == list[i - 1] then return nil end
	end
	return table.concat(list), list
end

---------------------------------------------------------------------------
-- Scoring
---------------------------------------------------------------------------

function FarkleRules.Score(dice)
	local c, n = Counts(dice)
	if not c then return nil end
	return Split(c, n, Runs())
end

-- Every selection of the roll (63 for six dice), the highest score kept, the first found on a
-- tie. With the table's points no selection of other faces ties the best; a run of five in six
-- dice can leave out either of two dice of one face (2-3-4-5-6-6), and then the lower position
-- is kept. With other points the first found is kept too.
function FarkleRules.Best(dice)
	if not Counts(dice) then return nil end
	local n, runs = #dice, Runs()
	local top, pick = 0, {}
	for mask = 1, 2 ^ n - 1 do
		local c, at, m = { 0, 0, 0, 0, 0, 0 }, {}, mask
		for i = 1, n do
			if m % 2 == 1 then
				c[dice[i]] = c[dice[i]] + 1
				at[#at + 1] = i
			end
			m = floor(m / 2)
		end
		local points = Split(c, #at, runs)
		if points and points > top then top, pick = points, at end
	end
	return top, pick
end

-- Whatever scores is made of combinations, so a roll scores when one of them fits in it: a lone
-- die, a set of one face or a run. (Every roll decides a Farkle, so this stays cheaper than
-- Best.) With the table's points a roll is a Farkle exactly when it has no 1, no 5 and no face
-- three times: every run holds a 1 or a 5.
function FarkleRules.Farkle(dice)
	local c = Counts(dice)
	if not c then return nil end
	for f = 1, 6 do
		for m = 1, c[f] do
			if Unit(f, m) then return false end
		end
	end
	for _, run in ipairs(Runs()) do
		if Holds(c, run.c) then return false end
	end
	return true
end

function FarkleRules.CanScore(dice)
	local farkle = FarkleRules.Farkle(dice)
	if farkle == nil then return nil end
	return not farkle
end

function FarkleRules.HotDice(turn)
	return type(turn) == "table" and turn.hot == true
end

---------------------------------------------------------------------------
-- A turn
---------------------------------------------------------------------------

local Turn = {}
FarkleRules.Turn = Turn

function Turn.New()
	return { points = 0, left = FarkleRules.DICE, phase = "roll", rolls = 0, hot = false }
end

-- Ordered outcomes of the original server throw are equiprobable. Condition on actual
-- zero-score throws, not sums: sums have unequal multiplicities. Never include 1 or 5.
local reuseSignature, reuseCache = nil, {}
local function ScoreSignature(value)
	if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
	local keys, parts = {}, {}
	for key in pairs(value) do keys[#keys + 1] = key end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	for _, key in ipairs(keys) do parts[#parts + 1] = ScoreSignature(key) .. "=" .. ScoreSignature(value[key]) end
	return "{" .. table.concat(parts, ";") .. "}"
end
local function ReuseOutcomes(n, wanted)
	if not Int(n) or n < 1 or n > 6 then return nil end
	local signature = ScoreSignature(FarkleRules.SCORES)
	if signature ~= reuseSignature then reuseSignature, reuseCache = signature, {} end
	local cached = reuseCache[n]
	if cached then return cached.total, wanted and cached.ranks[table.concat(wanted)] or nil end
	local dice, faces, total, ranks = {}, { 2, 3, 4, 6 }, 0, {}
	local function Visit(pos)
		if pos > n then
			if FarkleRules.Farkle(dice) == true then
				total = total + 1
				ranks[table.concat(dice)] = total
			end
			return
		end
		for _, face in ipairs(faces) do dice[pos] = face; Visit(pos + 1) end
	end
	Visit(1)
	reuseCache[n] = { total = total, ranks = ranks }
	return total, wanted and ranks[table.concat(wanted)] or nil
end

local function ReuseChance(dice, chance)
	if not Counts(dice) or FarkleRules.Farkle(dice) ~= true then return nil, "dice" end
	local total, rank = ReuseOutcomes(#dice, dice)
	if not rank then return nil, "dice" end
	local wins = floor(total * chance / 100 + 0.5)
	return rank <= wins, rank, wins, total
end

function FarkleRules.HiccupOdds(n, lvl)
	if not Lvl(lvl) then return nil, "level" end
	local total = ReuseOutcomes(n)
	if not total then return nil, "count" end
	if total == 0 then return 0, 0, 0 end
	local wins = floor(total * FarkleRules.HICCUP[lvl] / 100 + 0.5)
	return wins, total, 100 * wins / total
end

function FarkleRules.HiccupReuse(dice, lvl)
	if not Lvl(lvl) then return nil, "level" end
	return ReuseChance(dice, FarkleRules.HICCUP[lvl])
end

function Turn.Roll(t, roll)
	if type(t) ~= "table" then return nil, "game" end
	if t.phase == "done" then return nil, "done" end
	if t.phase == "keep" then return nil, "keep" end
	local dice = FarkleRules.Decode(roll, t.left)
	if not dice then return nil, "range" end
	t.dice, t.kept, t.hot = dice, nil, false
	t.rolls = t.rolls + 1
	if FarkleRules.Farkle(dice) then
		t.farkle, t.lost, t.points = true, t.points, 0
		t.phase = "done"
		return dice, true
	end
	t.phase = "keep"
	return dice, false
end

-- Positions, not faces: two 5s of one roll are two different dice, and the table's messages
-- name them the same way on every client.
function Turn.Keep(t, positions)
	if type(t) ~= "table" then return nil, "game" end
	if t.phase == "done" then return nil, "done" end
	if t.phase ~= "keep" then return nil, "roll" end
	if type(positions) ~= "table" then return nil, "dice" end
	local n = #positions
	if n < 1 or n > #t.dice then return nil, "dice" end
	local keys = 0
	for _ in pairs(positions) do keys = keys + 1 end
	if keys ~= n then return nil, "dice" end
	local seen, faces, kept = {}, {}, {}
	for i = 1, n do
		local p = positions[i]
		if not Int(p) or p < 1 or p > #t.dice or seen[p] then return nil, "dice" end
		seen[p] = true
		kept[i] = p
	end
	table.sort(kept)
	for i = 1, n do faces[i] = t.dice[kept[i]] end
	local points = FarkleRules.Score(faces)
	if not points then return nil, "score" end
	t.points = t.points + points
	t.left = t.left - n
	t.kept = kept
	if t.left == 0 then
		-- hot dice: every die set aside, so all six go back in the cup and the points stay
		t.left, t.hot = FarkleRules.DICE, true
	end
	t.phase = "decide"
	return points, t.hot
end

-- A bank needs dice set aside from the last roll: nobody banks without looking at his roll.
-- (A turn in "roll" with points is one whose player chose to roll on: he rolls first.)
function Turn.Bank(t)
	if type(t) ~= "table" then return nil, "game" end
	if t.phase == "done" then return nil, "done" end
	if t.phase == "keep" then return nil, "keep" end
	if t.phase == "roll" and t.points > 0 then return nil, "roll" end
	if t.phase ~= "decide" or t.points <= 0 then return nil, "empty" end
	t.banked = t.points
	t.phase = "done"
	return t.points
end

---------------------------------------------------------------------------
-- Event codes and the chain
---------------------------------------------------------------------------

local ONE_SEAT = { F = true, T = true, C = true, A = true }

function FarkleRules.Code(ev)
	if type(ev) ~= "table" then return nil end
	local t, p = ev.t, ev.p
	if t == "V" then return "V" end
	if p ~= 1 and p ~= 2 then return nil end
	local star = ev.relayed and "*" or ""
	if t == "O" then
		local v = ev.value
		if not Int(v) or v < 1 or v > FarkleRules.OPENING then return nil end
		return ("O%d:%d%s"):format(p, v, star)
	elseif t == "R" then
		local k, v = ev.k, ev.value
		local top = Int(k) and FarkleRules.RANGES[k]
		if not top or not Int(v) or v < 1 or v > top then return nil end
		return ("R%d:%d:%d%s"):format(p, k, v, star)
	elseif t == "K" then
		local text = FarkleRules.Mask(ev.mask)
		if not text or (ev.act ~= "r" and ev.act ~= "b") then return nil end
		if ev.lvl ~= nil and not Lvl(ev.lvl) then return nil end
		return ("K%d:%s:%s%s"):format(p, text, ev.act, ev.lvl and (":" .. ev.lvl) or "")
	elseif t == "H" then
		local v = ev.value
		if not Int(v) or v < 1 or v > FarkleRules.HICCUP_ROLL then return nil end
		return ("H%d:%d%s"):format(p, v, star)
	elseif t == "L" then
		if not Lvl(ev.lvl) then return nil end
		return ("L%d:%d"):format(p, ev.lvl)
	elseif ONE_SEAT[t] then
		return t .. p
	end
	return nil
end

-- Only the spelling Code writes: the event read back must write the same code.
function FarkleRules.Event(code)
	if type(code) ~= "string" or #code > 16 then return nil end
	if code == "V" then return { t = "V" } end
	local t, p, rest = code:match("^([ORKFTCAHL])([12])(.*)$")
	if not t then return nil end
	p = tonumber(p)
	local ev
	if t == "O" then
		local v, star = rest:match("^:(%d+)(%*?)$")
		if v then ev = { t = t, p = p, value = tonumber(v), relayed = star == "*" or nil } end
	elseif t == "R" then
		local k, v, star = rest:match("^:(%d):(%d+)(%*?)$")
		if k then ev = { t = t, p = p, k = tonumber(k), value = tonumber(v), relayed = star == "*" or nil } end
	elseif t == "K" then
		local mask, act, lvl = rest:match("^:(%d+):([rb])$")
		if not mask then mask, act, lvl = rest:match("^:(%d+):([rb]):(%d)$") end
		if mask then ev = { t = t, p = p, mask = mask, act = act, lvl = tonumber(lvl) } end
	elseif t == "H" then
		local v, star = rest:match("^:(%d+)(%*?)$")
		if v then ev = { t = t, p = p, value = tonumber(v), relayed = star == "*" or nil } end
	elseif t == "L" then
		local lvl = rest:match("^:(%d)$")
		if lvl then ev = { t = t, p = p, lvl = tonumber(lvl) } end
	elseif rest == "" then
		ev = { t = t, p = p }
	end
	if not ev or FarkleRules.Code(ev) ~= code then return nil end
	return ev
end

function FarkleRules.Chain(prev, code)
	if type(prev) ~= "string" or type(code) ~= "string" then return nil end
	return Hex8(prev .. "|" .. Bare(code))
end

---------------------------------------------------------------------------
-- A game
---------------------------------------------------------------------------

-- A name, id or line that goes into the head line: no line break (it would split the
-- transcript), and no "|" where a field follows (it would move the field boundaries).
local function Clean(s, bar)
	return type(s) == "string" and not s:find("\n", 1, true) and not (bar and s:find("|", 1, true))
end

function FarkleRules.New(fields)
	if type(fields) ~= "table" then return nil, "fields" end
	local target = fields.target
	-- every target the table offers has a cap, and no other target has one
	local cap = target ~= nil and FarkleRules.TURN_CAP[target]
	if not cap then return nil, "target" end
	local first = fields.first
	if first ~= nil and first ~= 1 and first ~= 2 then return nil, "first" end
	local players = {}
	if fields.players ~= nil then
		local p = fields.players
		if type(p) ~= "table" or not Clean(p[1], true) or not Clean(p[2], true)
			or p[1] == "" or p[2] == "" or p[1]:lower() == p[2]:lower() then
			return nil, "players"
		end
		players = { p[1], p[2] }
	end
	local id, terms = fields.id, fields.terms
	if id ~= nil and not Clean(id, true) then return nil, "id" end
	if terms ~= nil and not Clean(terms, false) then return nil, "terms" end
	local hiccup = fields.hiccup
	if hiccup ~= nil and type(hiccup) ~= "boolean" then return nil, "hiccup" end
	local hiccupRule = fields.hiccupRule
	if hiccupRule ~= nil and (hiccupRule ~= "bones2" or not hiccup) then return nil, "hiccupRule" end
	-- the rule set's name starts the head line: a hiccup table plays other rules than a sober one
	local head = table.concat({
		hiccupRule == "bones2" and "farkle2h" or (hiccup and "farkle1h" or "farkle1"), id or "", target, (players[1] or ""):lower(),
		(players[2] or ""):lower(), first or "", terms or "",
	}, "|")
	local chain = Hex8(head)
	if not chain then return nil, "sign" end
	return {
		players = players,
		target = target,
		cap = cap,
		first = first,
		current = first,
		open = first == nil,
		opening = {},
		ties = 0,
		scores = { 0, 0 },
		turns = { 0, 0 },
		timeouts = { 0, 0 },
		turn = Turn.New(),
		queue = {},
		ahead = {},
		hiccup = hiccup == true,
		hiccupRule = hiccupRule,
		level = { 0, 0 },
		floor = { 0, 0 },
		shakes = { 0, 0 },
		pending = { {}, {} },
		handed = first and 0 or nil,
		lines = 0,
		sudden = false,
		over = false,
		id = id,
		head = head,
		events = {},
		step = 0,
		chain = chain,
		chains = { [0] = chain },
	}
end

-- A realm's names are unique whatever their case, and a name reaches the table in more than one
-- spelling (the server's roll line, a message, the page), so names are compared in lower case.
local function Seat(game, who)
	if who == 1 or who == 2 then return who end
	if type(who) == "string" then
		who = who:lower()
		for i = 1, 2 do
			local name = game.players[i]
			if name and name:lower() == who then return i end
		end
	end
	return nil
end

-- What New made (a table dropped by the table's code arrives here as nil).
local function IsGame(game)
	return type(game) == "table" and type(game.turn) == "table" and type(game.players) == "table"
		and type(game.events) == "table" and type(game.head) == "string" and type(game.chains) == "table"
end

local function Actor(game, who)
	if not IsGame(game) then return nil, "game" end
	if game.over then return nil, "over" end
	local p = Seat(game, who)
	if not p then return nil, "player" end
	if game.open then return nil, "open" end
	if p ~= game.current then return nil, "turn" end
	return p
end

-- Writes an accepted event down (its code, with any relay mark) and moves the chain, keeping
-- each link so that ChainAt never hashes.
local function Record(game, ev)
	local code = FarkleRules.Code(ev)
	game.events[#game.events + 1] = code
	game.step = #game.events
	game.chain = FarkleRules.Chain(game.chain, code)
	game.chains[game.step] = game.chain
end

-- The dice set aside by the page's Keep become a decision once he rolls on or banks.
local function Commit(game, p, act)
	local t = game.turn
	if t.pending then
		t.pending = nil
		Record(game, { t = "K", p = p, mask = t.kept, act = act })
	end
end

local function Finish(game, winner, reason)
	game.over, game.winner, game.reason = true, winner, reason
	game.current = nil
	game.queue, game.ahead, game.pending = {}, {}, { {}, {} }
end

-- Seat p's drunk level for his next turn: the higher of what his opponent's decisions recorded
-- and the arbiter's floor.
local function LevelOf(game, p)
	local a, b = game.level[p], game.floor[p]
	return a > b and a or b
end

-- The arbiter's floor under seat p, written where p's turn was just handed over (and only when
-- it changes the floor: one spelling for every client).
local function SetFloor(game, p, lvl)
	if game.current ~= p or game.step ~= game.handed then return nil, "level" end
	if lvl == game.floor[p] then return nil, "level" end
	game.floor[p] = lvl
	Record(game, { t = "L", p = p, lvl = lvl })
	game.handed = game.step
	return true
end

-- Seat p's turn is handed over: the floors named for it are written here, before its first
-- roll, the one place every client reaches in the same order whatever the messages' order.
local function HandOver(game, p)
	game.handed = game.step
	local n, keep = game.turns[p] + 1, {}
	for _, f in ipairs(game.pending[p]) do
		if f.turn <= n then
			if f.lvl ~= game.floor[p] then SetFloor(game, p, f.lvl) end
		else
			keep[#keep + 1] = f
		end
	end
	game.pending[p] = keep
end

-- A line of the player not to act: it can have overtaken the message ending this turn (a bank,
-- a timeout or foul claim), which reaches this client later than the other player. A turn starts
-- with six dice, so only a roll of six starts his held lines, and every later line of his waits
-- behind it, in order, until his turn starts (EndTurn takes them).
local function Ahead(game, line)
	local a = game.ahead
	if #a == 0 then
		if line.t ~= "R" or line.k ~= FarkleRules.DICE then return nil, "turn" end
	elseif #a >= FarkleRules.HOLD then
		return nil, "extra"
	end
	a[#a + 1] = line
	return true, "held"
end

local Rolled, Drain

-- A turn of seat p is over (banked, farkled, lost to the clock or to a foul): count it, then
-- see whether the game ends here, else hand the dice to the other player, and take the lines he
-- sent before this (his turn's first roll, and whatever followed it).
local function EndTurn(game, p, how)
	local t, o = game.turn, 3 - p
	local points = how == "bank" and t.banked or 0
	if how ~= "bank" and how ~= "farkle" then
		-- lost to the clock or a foul: like a Farkle, the turn's points go
		t.lost, t.points = t.points, 0
	end
	t.phase = "done"
	game.scores[p] = game.scores[p] + points
	game.turns[p] = game.turns[p] + 1
	game.timeouts[p] = how == "timeout" and game.timeouts[p] + 1 or 0
	game.last = { who = p, how = how, points = points, lost = t.lost or 0, dice = t.dice }
	if game.timeouts[p] >= FarkleRules.TIMEOUTS then return Finish(game, o, "forfeit") end
	if how == "bank" and game.scores[p] >= game.target then return Finish(game, p, "target") end
	if not game.final then
		if game.turns[1] >= game.cap and game.turns[2] >= game.cap then
			game.final, game.capped = p, true
		end
	end
	if game.final == p then
		local mine, theirs = game.scores[p], game.scores[o]
		if mine ~= theirs then
			return Finish(game, mine > theirs and p or o, game.capped and "cap" or "target")
		end
		game.sudden = true                 -- level: one more turn each, in the same order
	end
	game.current = o
	game.turn = Turn.New()
	HandOver(game, o)
	-- his held lines start his turn; p's lines still held are now the waiting player's
	local rest = game.queue
	game.queue, game.ahead = game.ahead, {}
	for _, line in ipairs(rest) do Ahead(game, line) end
	Drain(game)
end

-- The turn is lost (the clock or a foul): the third timeout in a row is written as a forfeit.
-- While his hiccup is due, the Farkle simply stands: a sober Farkle would have ended the turn
-- at once, so no timeout counts.
local function Lose(game, p, how)
	game.turn.pending = nil
	if game.turn.phase == "hiccup" then
		Record(game, { t = how == "timeout" and "T" or "F", p = p })
		return EndTurn(game, p, "farkle")
	end
	local kind = "F"
	if how == "timeout" then
		kind = game.timeouts[p] + 1 >= FarkleRules.TIMEOUTS and "A" or "T"
	end
	Record(game, { t = kind, p = p })
	EndTurn(game, p, how)
end

-- A roll of seat p (his turn) that counts now, not held. Every roll that is written comes
-- through here, whoever calls, so it refuses (-> nil, err) with nothing written unless a roll is
-- due: not while he must set dice aside ("keep") or roll his hiccup ("hiccup"), nor once the
-- turn is over ("done"), nor outside 1..6^k ("range"). A roll that counts throws the dice with
-- the right count (-> true, nil, dice, farkle); a wrong count is refused before any state changes.
-- On a hiccup table a Farkle with a chance left waits for his hiccup (-> true,
-- "hiccup", dice, true).
function Rolled(game, p, k, value, relayed)
	local t = game.turn
	if t.phase == "keep" or t.phase == "done" or t.phase == "hiccup" then return nil, t.phase end
	local top = Int(k) and FarkleRules.RANGES[k]
	if not top or not Int(value) or value < 1 or value > top then return nil, "range" end
	if k ~= t.left then return nil, "count" end
	Commit(game, p, "r")
	-- the hiccup's chance is fixed at the turn's first roll, from the level recorded before it
	if t.rolls == 0 then t.chance = game.hiccup and FarkleRules.HICCUP[LevelOf(game, p)] or 0 end
	-- the checks above are Turn.Roll's own, so it takes the roll
	local dice, farkle = Turn.Roll(t, value)
	Record(game, { t = "R", p = p, k = k, value = value, relayed = relayed })
	if farkle then
		if t.chance > 0 and game.shakes[p] < FarkleRules.SHAKES then
			if game.hiccupRule == "bones2" then
				local saved = ReuseChance(dice, t.chance)
				if saved then
					game.shakes[p] = game.shakes[p] + 1
					t.points, t.lost, t.farkle, t.phase = t.lost, nil, nil, "roll"
					return true, "shaken", dice, farkle
				end
				EndTurn(game, p, "farkle")
				return true, nil, dice, farkle
			end
			t.phase = "hiccup"             -- his /roll 1-100 decides whether it stands
			return true, "hiccup", dice, farkle
		end
		EndTurn(game, p, "farkle")
	end
	return true, nil, dice, farkle
end

-- His hiccup (/roll 1-100 after a Farkle): at or under the turn's chance the Farkle is shaken
-- off, the turn keeps its points and the same dice are thrown again (six after hot dice);
-- otherwise it stands and the turn ends.
local function Shake(game, p, value, relayed)
	local t = game.turn
	Record(game, { t = "H", p = p, value = value, relayed = relayed })
	if value <= t.chance then
		game.shakes[p] = game.shakes[p] + 1
		t.points, t.lost, t.farkle, t.phase = t.lost, nil, nil, "roll"
		return true, "shaken"
	end
	EndTurn(game, p, "farkle")
	return true
end

-- A line of the current player with nothing held before it: a roll counts if a roll is due, a
-- 1-100 line only as the hiccup of the Farkle before it.
local function Take(game, line)
	if line.t == "H" then
		if game.turn.phase ~= "hiccup" then return nil, "phase" end
		return Shake(game, game.current, line.value, line.relayed)
	end
	return Rolled(game, game.current, line.k, line.value, line.relayed)
end

-- The lines held for the current player, taken in the server's order once no decision is due
-- before them: each counts, waits again for his next decision, or is ignored. The note is the
-- first counted line's.
function Drain(game)
	local first
	while not game.over do
		local q = game.queue
		if #q == 0 or game.turn.phase == "keep" then break end
		local line = table.remove(q, 1)
		local ok, note = Take(game, line)
		if ok and first == nil then first = note or false end
	end
	return first or nil
end

-- A line of the current player as it arrives: while his decision is due, or behind lines held
-- for one, it waits (W3); otherwise it is taken now.
local function Line(game, line)
	local q = game.queue
	if #q == 0 and game.turn.phase ~= "keep" then return Take(game, line) end
	-- a 1-100 line waits only behind a roll held before it (it may be that Farkle's hiccup)
	if line.t == "H" and #q == 0 then return nil, "phase" end
	if #q >= FarkleRules.HOLD then return nil, "extra" end
	q[#q + 1] = line
	return true, "held"
end

local function Opening(game, p, value, relayed)
	if not game.open then return nil, "started" end
	if not Int(value) or value < 1 or value > FarkleRules.OPENING then return nil, "range" end
	if game.opening[p] then return nil, "extra" end
	game.opening[p] = value
	Record(game, { t = "O", p = p, value = value, relayed = relayed })
	local a, b = game.opening[1], game.opening[2]
	if not (a and b) then return true end
	if a == b then
		game.ties = game.ties + 1
		game.opening = {}
		return true, "tie"
	end
	local first = a > b and 1 or 2
	game.open, game.first, game.current = false, first, first
	HandOver(game, first)
	return true
end

-- A decision: the dice set aside, then roll on or bank, with what his client saw of the other
-- seat's drunk level since his last decision (lvl, hiccup tables: it counts from that seat's
-- next turn). Lines held before it (W3) are taken right after it; a roll held before a bank
-- stands and the bank reads as rolling on (W4).
local function Decide(game, p, mask, act, lvl)
	local t = game.turn
	if t.phase ~= "keep" then return nil, "roll" end
	local _, list = FarkleRules.Mask(mask)
	if not list then return nil, "dice" end
	local points, why = Turn.Keep(t, list)
	if not points then return nil, why end
	if lvl then game.level[3 - p] = lvl end
	-- only a roll held before the bank stands against it (W4). A 1-100 line is no roll, and a
	-- roll that came after a held line of the other player was thrown after the bank (he rolled
	-- because he saw it): it waits for this player's next turn instead.
	local after = game.ahead[1] and game.ahead[1].seq
	local roll = false
	local i = 1
	while i <= #game.queue do
		local line = game.queue[i]
		if after and line.seq > after then break end
		if line.t == "R" then
			if line.k == t.left then roll = true break end
			-- Its count became known only after Keep: discard an invalid held roll, not the bank.
			table.remove(game.queue, i)
		else i = i + 1 end
	end
	if act == "b" and not roll then
		Turn.Bank(t)
		Record(game, { t = "K", p = p, mask = t.kept, act = "b", lvl = lvl })
		EndTurn(game, p, "bank")
		return true
	end
	Record(game, { t = "K", p = p, mask = t.kept, act = "r", lvl = lvl })
	t.phase = "roll"                       -- he rolls on: the next thing he does is roll
	local note = Drain(game)
	if act == "b" then note = "stands" end
	return true, note
end

local KINDS = { O = true, R = true, K = true, T = true, C = true, A = true, V = true,
	H = true, L = true }

function FarkleRules.Apply(game, ev)
	if not IsGame(game) then return nil, "game" end
	if type(ev) == "string" then ev = FarkleRules.Event(ev) end
	if type(ev) ~= "table" or not KINDS[ev.t] then return nil, "event" end
	local kind = ev.t
	if kind == "K" and ev.act ~= "r" and ev.act ~= "b" then return nil, "event" end
	local leveled = kind == "L" or (kind == "K" and ev.lvl ~= nil)
	if leveled and not Lvl(ev.lvl) then return nil, "event" end
	if game.over then return nil, "over" end
	if (leveled or kind == "H") and not game.hiccup then return nil, "sober" end
	if kind == "V" then
		Record(game, ev)
		Finish(game, nil, "void")
		return true
	end
	local p = Seat(game, ev.p)
	if not p then return nil, "player" end
	if kind == "C" then
		Record(game, { t = "C", p = p })
		Finish(game, 3 - p, "concede")
		return true
	end
	if kind == "O" then return Opening(game, p, ev.value, ev.relayed) end
	if game.open then return nil, "open" end
	if kind == "R" or kind == "H" then
		if kind == "H" and game.hiccupRule == "bones2" then return nil, "event" end
		local v, line = ev.value
		if kind == "R" then
			local k = ev.k
			local top = Int(k) and FarkleRules.RANGES[k]
			if not top or not Int(v) or v < 1 or v > top then return nil, "range" end
			line = { t = "R", k = k, value = v, relayed = ev.relayed and true or nil }
		else
			if not Int(v) or v < 1 or v > FarkleRules.HICCUP_ROLL then return nil, "range" end
			line = { t = "H", value = v, relayed = ev.relayed and true or nil }
		end
		-- lines are numbered as they arrive: the server's order, the same on every client
		line.seq = (game.lines or 0) + 1
		local ok, note
		if p ~= game.current then ok, note = Ahead(game, line) else ok, note = Line(game, line) end
		if ok then game.lines = line.seq end
		return ok, note
	end
	if kind == "L" then return SetFloor(game, p, ev.lvl) end
	if p ~= game.current then return nil, "turn" end
	if kind == "K" then
		return Decide(game, p, ev.mask, ev.act, ev.lvl)
	elseif kind == "A" then
		if game.turn.phase == "hiccup" or game.timeouts[p] + 1 < FarkleRules.TIMEOUTS then
			return nil, "count"
		end
		Lose(game, p, "timeout")
	elseif kind == "T" then
		Lose(game, p, "timeout")
	end
	return true
end

function FarkleRules.Floor(game, who, turn, lvl)
	if not IsGame(game) then return nil, "game" end
	if game.over then return nil, "over" end
	if not game.hiccup then return nil, "sober" end
	local p = Seat(game, who)
	if not p then return nil, "player" end
	if not Lvl(lvl) or not Int(turn) then return nil, "level" end
	-- p's turns that have begun (his current one, once it was handed over)
	local begun = game.turns[p] + ((not game.open and game.current == p) and 1 or 0)
	if turn > begun then
		local list = game.pending[p]
		if #list >= FarkleRules.HOLD then return nil, "extra" end
		list[#list + 1] = { turn = turn, lvl = lvl }
		return true, "pending"
	end
	-- its turn has begun: still in time while nothing is written after the hand-over
	if turn == begun and game.current == p and game.step == game.handed then
		if lvl == game.floor[p] then return true end
		return SetFloor(game, p, lvl)
	end
	return nil, "late"
end

function FarkleRules.Level(game, who)
	if not IsGame(game) then return nil end
	local p = Seat(game, who)
	if not p then return nil end
	local lvl = LevelOf(game, p)
	local left = game.hiccup and FarkleRules.SHAKES - game.shakes[p] or 0
	local t, pct = game.turn, 0
	if left > 0 then
		if game.current == p and not game.open and t.rolls > 0 then pct = t.chance or 0
		elseif game.hiccup then pct = FarkleRules.HICCUP[lvl] end
	end
	return lvl, pct, left
end

-- The current seat's nominal chance stays locked even if its recorded drunk level changes.
-- Return the exact conditional odds for the dice actually due, without exposing an extra roll.
function FarkleRules.HiccupTurnOdds(game, who)
	if not IsGame(game) then return nil, "game" end
	local p = Seat(game, who)
	if not p then return nil, "player" end
	if game.hiccupRule ~= "bones2" then return nil, "rule" end
	local _, chance = FarkleRules.Level(game, p)
	local n = game.current == p and not game.open and game.turn.left or 6
	local total = ReuseOutcomes(n)
	if total == 0 then return 0, 0, 0 end
	local wins = floor(total * chance / 100 + 0.5)
	return wins, total, 100 * wins / total
end

function FarkleRules.Roll(game, who, roll)
	local p, err = Actor(game, who)
	if not p then return nil, err end
	-- the page always throws the dice he has left, so its roll is never a foul
	local ok, why, dice, farkle = Rolled(game, p, game.turn.left, roll)
	if not ok then return nil, why end
	return dice, farkle
end

function FarkleRules.Keep(game, who, positions)
	local p, err = Actor(game, who)
	if not p then return nil, err end
	if #game.queue > 0 then return nil, "held" end
	local points, hot = Turn.Keep(game.turn, positions)
	if not points then return nil, hot end
	game.turn.pending = true
	return points, hot
end

function FarkleRules.Bank(game, who)
	local p, err = Actor(game, who)
	if not p then return nil, err end
	local points, why = Turn.Bank(game.turn)
	if not points then return nil, why end
	Commit(game, p, "b")
	EndTurn(game, p, "bank")
	return points
end

function FarkleRules.Hiccup(game, who, roll)
	local p, err = Actor(game, who)
	if not p then return nil, err end
	if not game.hiccup then return nil, "sober" end
	if game.hiccupRule == "bones2" then return nil, "event" end
	if game.turn.phase ~= "hiccup" then return nil, "phase" end
	if not Int(roll) or roll < 1 or roll > FarkleRules.HICCUP_ROLL then return nil, "range" end
	local _, note = Shake(game, p, roll)
	return note == "shaken"
end

function FarkleRules.Timeout(game, who)
	local p, err = Actor(game, who)
	if not p then return nil, err end
	Lose(game, p, "timeout")
	return true
end

function FarkleRules.Foul(game, who)
	local p, err = Actor(game, who)
	if not p then return nil, err end
	return nil, "event"
end

-- Either player may concede, on his turn or not, in the opening too.
function FarkleRules.Concede(game, who)
	if not IsGame(game) then return nil, "game" end
	return FarkleRules.Apply(game, { t = "C", p = Seat(game, who) or 0 })
end

function FarkleRules.Void(game)
	return FarkleRules.Apply(game, { t = "V" })
end

-- In "keep" the turn's left still counts the dice just thrown; what the next roll throws is known
-- once he sets some aside, so nothing is promised until then. In "hiccup" his 1-100 is due.
function FarkleRules.Expect(game)
	if not IsGame(game) or game.over then return nil end
	if game.open then
		local a, b = game.opening[1], game.opening[2]
		return (a and 2) or (b and 1) or 0, "open", nil
	end
	local t = game.turn
	if t.phase == "keep" or t.phase == "hiccup" then return game.current, t.phase, nil end
	return game.current, t.phase, t.left
end
---------------------------------------------------------------------------
-- The House (practice)
---------------------------------------------------------------------------

-- Does seat p's turn end the capped game, unless it ends level?
local function LastTurn(game, p)
	if game.final then return game.final == p end
	return game.turns[p] + 1 >= game.cap and game.turns[3 - p] >= game.cap
end

local function HouseBanks(game, p, points, left)
	if game.scores[p] + points >= game.target then return true end
	if LastTurn(game, p) then return game.scores[p] + points > game.scores[3 - p] end
	for _, row in ipairs(FarkleRules.HOUSE) do
		if points >= row.points and left <= row.left then return true end
	end
	return false
end

function FarkleRules.HouseMove(game)
	if not IsGame(game) or game.over or game.open then return nil end
	local p, t = game.current, game.turn
	if t.phase == "roll" then return nil, "r" end
	if t.phase == "hiccup" then return nil, "h" end
	if t.phase == "decide" then return nil, HouseBanks(game, p, t.points, t.left) and "b" or "r" end
	if t.phase ~= "keep" then return nil end
	local points, pick = FarkleRules.Best(t.dice)
	local left = t.left - #pick
	if left == 0 then left = FarkleRules.DICE end
	return pick, HouseBanks(game, p, t.points + points, left) and "b" or "r"
end

---------------------------------------------------------------------------
-- The transcript
---------------------------------------------------------------------------

function FarkleRules.ChainAt(game, step)
	if not IsGame(game) then return nil end
	if step == nil then step = #game.events end
	if not Int(step) or step < 0 or step > #game.events then return nil end
	return game.chains[step]
end

function FarkleRules.Transcript(game)
	if not IsGame(game) then return nil end
	local lines = { game.head }
	for i, code in ipairs(game.events) do lines[i + 1] = Bare(code) end
	return table.concat(lines, "\n")
end

function FarkleRules.Hash(game)
	local text = FarkleRules.Transcript(game)
	return text and Hex8(text)
end

function FarkleRules.Replay(fields, codes)
	local game, why = FarkleRules.New(fields)
	if not game then return nil, why end
	if type(codes) ~= "table" then return nil, "codes" end
	for i, code in ipairs(codes) do
		local ev = type(code) == "string" and FarkleRules.Event(code)
		local ok, note
		-- Historical F codes remain readable, but no live Apply/Foul can create one.
		if ev and ev.t == "F" then
			if game.hiccupRule == "bones2" then return nil, "event", i end
			local p
			p, note = Actor(game, ev.p)
			if p then Lose(game, p, "foul"); ok = true end
		else ok, note = FarkleRules.Apply(game, type(code) == "string" and code or false) end
		if not ok then return nil, note, i end
		if note == "held" then return nil, "held", i end
	end
	return game
end

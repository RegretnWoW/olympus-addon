local ADDON, ns = ...
local L = ns.L

-- 1.1.6, the compliance gate (Compliance.lua): the line every betting control shows while bets wait
-- for the legal review, region by region, and the Lottery's practice line. English, then pt-BR
-- (the pattern of Locales.lua); Spanish, French and German fall back to English. Each package's
-- refusal words (Kit.Why's prefixes, Bones's, the Lottery's, the matchmaking's, the roles')
-- get the same line for the code "compliance", set at the end from these.

L.COMPLIANCE_WAIT = "Bets are off for now: they wait for a legal compliance review, region by region. The games play for points."
L.COMPLIANCE_WAIT_SHORT = "Bets wait for a compliance review, region by region."
L.COMPLIANCE_LOTTERY_PRACTICE = "Just practice for now: we're doing a compliance review, country by country, to see how a Lottery with real prizes can work in each one. Tickets are free and no gold moves."

if GetLocale and GetLocale() == "ptBR" then
	L.COMPLIANCE_WAIT = "As apostas estão suspensas por enquanto: aguardam uma revisão jurídica de compliance, região por região. Os jogos seguem valendo pontos."
	L.COMPLIANCE_WAIT_SHORT = "Apostas aguardam revisão de compliance, região por região."
	L.COMPLIANCE_LOTTERY_PRACTICE = "Por enquanto é só treino: estamos fazendo uma análise de compliance, país por país, para ver como uma Loteria com prêmios de verdade pode funcionar em cada um. Os bilhetes são grátis e nenhum ouro se move."
end

-- (The refusal "compliance" in each package's words.)
for _, key in ipairs({ "ARENA_REFUSE_COMPLIANCE", "ARENA_WHY_COMPLIANCE", "WALLET_WHY_COMPLIANCE", "MARKETS_WHY_COMPLIANCE",
	"FIGHTS_WHY_COMPLIANCE", "FARKLE_WHY_COMPLIANCE", "MATCH_WHY_COMPLIANCE", "LOTTERY_WHY_COMPLIANCE" }) do
	L[key] = L.COMPLIANCE_WAIT
end
-- (Bones's create panel has one short row for its reason.)
L.FARKLE_B_WHY_COMPLIANCE = L.COMPLIANCE_WAIT_SHORT

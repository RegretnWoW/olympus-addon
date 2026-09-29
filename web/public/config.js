// Olympus Link: the page's settings, the one file to edit when the bot's side changes. The page
// is static (GitHub Pages); the Olympus bot's Worker checks every link and gives the role. Until
// PROOF_URL and DISCORD_CLIENT_ID are filled in, the page says Olympus Link is not open yet.
// When PROOF_URL is set, add its origin to connect-src in index.html's Content-Security-Policy
// (web/test/page.test.mjs checks both).

export const CONFIG = {
	// The bot's POST /proof, the whole address (https://...). It gets {"text", "discordToken"}.
	PROOF_URL: 'PASTE-THE-PROOF-URL-HERE',
	// The bot's Discord application (Developer Portal > OAuth2 > Client ID): digits only. Its OAuth2
	// redirects must list PAGE_URL exactly.
	DISCORD_CLIENT_ID: 'PASTE-THE-DISCORD-CLIENT-ID-HERE',
	// Optional: the token the bot's Worker takes from this page only, sent as "Authorization: Bearer".
	// Anyone can read it here: it lets the bot's keeper switch the page off, it guards nothing.
	SITE_TOKEN: '',
	// The command that gives a code in the Olympus Discord server.
	VERIFY_COMMAND: '/verify',
	// This page's address: the addon's ns.LINK_SITE (Olympus/Link.lua), the QR code's, and the
	// Discord redirect.
	PAGE_URL: 'https://dnl-gentile.github.io/olympus-addon/',
};

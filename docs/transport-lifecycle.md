# Transport lifetimes and compatibility

This change reconciles the transport work from PR #52 and the layer-hop destination work
from PR #51 with the current 1.2 state machine. It fixes queued work outliving its request,
permission or guild session without changing the wire protocol.

## Behaviour

- Comm admits complete transfers, with at most 60 unsent messages. An active transfer and
  urgent work cannot be evicted by unrelated admissions. An impossible admission leaves
  existing work intact. Keyed deduplication keeps the newest pending payload and options; a
  supplied callback replaces the prior callback, while omitting it retains the one waiting.
- At the existing 1.2-second send cadence, an active transfer receives five of every eight
  slots, chat two and other single-message traffic one. A 30-piece transfer finishes
  55.2 seconds after its first piece under continuous competing load; six waiting chat
  pieces receive slots within 28.8 seconds. Empty slots can serve other work. These are
  scheduler bounds in the offline clock, not a guarantee against client stalls or packet
  loss. A stalled transfer is abandoned at 60 seconds instead of sending its stale tail.
- Owners can cancel pending work. Guards run before actual transmission. Completion means
  all local send API calls succeeded; it does **not** mean a remote client acknowledged
  receipt. A failed piece aborts the remaining transfer and does not update the private
  delivery cache.
- Treasury, bank and dues work observes current sharing consent and recipient authority.
  Withdrawal cancels both module outboxes and Comm entries. Old timers cannot revive a
  cancelled transfer after consent is given again. Unchanged books can be shared again
  immediately after withdrawal. Private admission waits for a quiet queue; a timed-out
  attempt leaves retrying to the existing sharing tick.
- Hop has separate queued/sending and waiting-for-response states. LQ and LR response
  clocks start after their successful send, and obsolete queued requests are cancelled.
- A guild change clears peers, election state, guild assemblers, queued work and delayed
  key/census answers from the previous session. Alt membership changes advance the
  existing AL revision, including changes observed at login or just before sending.
- Census decoding rejects zone/class/level distributions exceeding the online population.
  Online counts are bounded by total membership even for an empty guild. Partial and
  privacy-suppressed distributions remain valid.
- Saturated receive admission uses the least recently active sender directly, avoiding a
  3,000-entry scan for every new sender. The 60-message burst, two-per-second refill,
  3,000-sender cap and strictly-over-60-second idle eviction remain unchanged. Live
  admission uses the existing monotonic `GetTime()` clock.

## Contracts retained

No message prefix, field layout, endpoint, receiver timeout, sender cadence, signature
format or persisted-data schema changes. Existing 60-second Codec receivers still assemble
the paced batches. TE keeps its independent messages and reassembly semantics; long TE
lists are submitted in consecutive bounded batches. The maximum transfer size remains
30 Codec fragments. GUILD, CHANNEL and WHISPER routing retains its existing audience.
Chat remains tied to the channel for which the player wrote it (issue #34); a started
channel transfer is cancelled if that audience changes.

The optional trailing completion/options arguments are internal Lua API additions. Callers
without them retain their existing message formats. Normal enqueue, lane selection and
key lookup use linked-list heads and table indexes. Explicit owner cancellation walks
that owner's jobs; a missing channel may walk past blocked channel work.

## Upstream issues

| Item | Treatment |
| --- | --- |
| #23, cross-guild rank trust | Remains the documented trust model. Replacing it needs an agreed authority/protocol change; this patch preserves legitimate cross-guild dues queries. |
| #50, layer invitations; PR #51 | "Always" still auto-invites while alone or in a group containing only hop guests. In an ordinary party or raid it deliberately leaves Blizzard's manual invitation prompt in place and reports `auto-paused`; the report does not establish that broader auto-invite would be safe. |
| #35 and #37, gamepad hangs | Reporter already confirmed the upstream fix. No speculative UI changes. |
| #40, Guild Control taint | No current-client reproduction established; left for an in-game trace. |
| #36, bank federation | Feature proposal, outside these repairs. |
| #33, required checks | Repository administration, outside contributor code changes. |

## Verification

The focused regressions exercise both failures and positive compatibility cases. The
saturated admission test compares registry traversal work, not a live-client frame rate.
Current command results belong in the release handoff; this document does not preserve a
stale pass count from either contributor branch.

Run `bash scripts/check.sh`, `bash tests/check-scripts.sh` and
`node --test web/test/*.test.mjs` from the repository root. The focused suites loaded by
`tests/run.lua` use the real addon functions and cover transfer pressure, cancellation,
send failures, callback reentrancy, channel/guild changes, Hop response clocks, permission
withdrawal, recipient changes, alt revisions and invalid census totals.

Existing immediate-send Hop mocks now invoke successful completion. Treasury mocks model
batch completion, and the multi-client treasury simulation routes batches through real
Comm. The obsolete per-piece-timer recovery assertion is replaced with recipient admission
coverage. Decoder fixtures retain their maximum encoded-length checks; impossible
populations now assert rejection, with a valid population used for round-trip assertions.

Issue #50 remains under-specified. Before changing its safety boundary, capture:

1. The exact addon build and WoW client version where the repeated prompt occurs.
2. Whether the player was alone, in a party made only of addon hop guests, in an ordinary
   party, or in a raid when the prompt appeared.
3. Whether the raid conversion happened before or after enabling "Always", and whether the
   player was leader or assistant; record group size and who was already grouped.
4. The exact dialog/message (or a screenshot), plus the layer line from `/oly status`,
   including whether it says `auto-paused`.
5. Whether the behavior survives `/reload`, and whether the prompt was accepted by mouse,
   keyboard, or gamepad.

Before release, check in the supported WoW client:

1. Exchange a near-limit private book with a stock 1.1.4 receiver, then an older 1.1.2
   receiver, while census, chat and layer requests compete. Verify complete reception and
   usable chat on both clients.
2. Withdraw sharing during an active book/dues/bank send; verify no subsequent private
   piece leaves, the withdrawal arrives, and sharing again restores the current book.
3. Queue LQ and LR behind other traffic, cancel or change zone/group, and verify response
   timeouts start after send and invitations from obsolete requests are not auto-accepted.
4. Move between Olympus guilds and rotate/renumber the channel during pending work. Verify
   the new guild elects its own peers and old channel chat does not move to a new audience.
5. Confirm alt guild changes on another client, including stock 1.1.4 and an older 1.1.2 client.

These client checks are still pending. Offline tests do not establish live FPS, combat
taint behaviour, gamepad interaction, server delivery or real server throttling.

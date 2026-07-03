# Benthyo product roadmap

Living plan from user research and **Round 2 strategy** (retention, B2B revenue, data moat).

## Legend

| Status | Meaning |
|--------|---------|
| ✅ Done | Shipped |
| 🟡 MVP | Basic version live; polish needed |
| 📋 Planned | Not started |
| ⏸ Defer | Intentionally delayed |

---

## Phase 13 — Market-gap opportunities (zero-budget)

Items identified from competitive analysis vs Subsurface, Deepblu, Diveboard.

| # | Feature | Priority | Status |
|---|---------|----------|--------|
| 1 | **Citizen science impact counter** — "Your sightings contributed to X databases" badge shown on profile and sharable as a card. Drives organic sharing with zero infra cost; GBIF/iNat sync already in place. | High | 📋 Planned |
| 2 | **Dive profile UDDF/GPX export** — one-tap share of a dive's depth profile from the log detail screen. The `profile_samples` column already exists in `dive_logs`; just needs serialisation + `Share.shareXFiles`. | High | 📋 Planned |
| 3 | **Multi-photo per sighting** — competitor research shows this is the #1 requested feature on Deepblu/Diveboard forums. Schema: new `sighting_photos` table (id, sighting_id, storage_path, order_index). UI: horizontal photo strip in add-sighting and sighting detail screens. | High | 📋 Planned |
| 4 | **Monthly species leaderboard** — "Most species logged this month" ranked list, computed from `user_life_list` + `sightings`. Zero infra cost (no new tables). Shown on the Discovery screen as a section below Buddy Finder. | Medium | 📋 Planned |
| 5 | **Dive centre embed widget** — a small public HTML snippet using the existing `site_public_card()` RPC so dive centres can paste a live conditions card on their own website. Free B2B lead magnet. Needs a `/embed/site/:id` web route + minimal JS bundle. | Medium | 📋 Planned |

### Competitive positioning summary

| Competitor | Weakness benthyo addresses |
|------------|---------------------------|
| Subsurface / MacDive | Desktop-only, no species ID, no community layer |
| Deepblu | No conservation data, no AI species ID, no B2B tools, no offline support |
| Diveboard | Web-only, no offline, no dive computer BLE sync |

benthyo's primary moats: **mobile-first offline** + **species life list** + **citizen science integration** + **operator B2B tools**.

---

## Phase 12 — Integration follow-ups

| Feature | Status |
|---------|--------|
| On-device CLIP embeddings from species photos | ✅ TFLite + fallback; wired on sighting save |
| Manufacturer BLE GATT parsers (Suunto/Shearwater) | ✅ Nordic UART + FE58/FE26 services |
| Supabase Realtime for buddy DMs | ✅ Migration 023 + mobile subscription |
| Dashboard bundle code-splitting | ✅ Lazy routes; vendor chunks all <500 kB |
| **Production deploy** | 📋 Last step |

---

## Phase 11 — Previously deferred features

| Feature | Status |
|---------|--------|
| Buddy DM / social feed | ✅ Conversations, messages, public feed |
| BLE dive computer sync | ✅ Device registry + BLE scan + import API |
| Operator marketplace | ✅ Listings API + dashboard + mobile browse |
| CLIP/pgvector image search | ✅ 512-d embeddings + HNSW + vector search API |
| **Production deploy** | 📋 Last step |

---

## Phase 10 closure

| Feature | Status |
|---------|--------|
| Apple Watch quick log | ✅ |
| Cert card OCR | ✅ |
| Auto-push GBIF | ✅ |
| Calendar sync | ✅ |
| Photo reverse search (SHA256) | ✅ |
| Operator rental gear QR | ✅ |
| Expert correction queue | ✅ |
| B2C email digest toggle | ✅ |
| iNat sync push queue | ✅ |
| Public API key auth | ✅ |
| Guest briefing QR embed | ✅ |
| Species ID quiz | ✅ |
| Sightings feed corrections | ✅ |
| Trip member invite | ✅ |
| Gear maintenance due alerts | ✅ |
| Conservation alerts | ✅ |
| Depth milestone badges | ✅ |

---

## Strategic pillars

1. **Retention** — surface interval ✅, prep cards ✅, trip recap ✅, email digest ✅, social feed ✅
2. **Data moat** — public API ✅, embeds ✅, DwC export ✅, MCP ✅, vector search ✅
3. **B2B revenue** — CRM ✅, waivers ✅, medical ✅, marketplace ✅, rental gear ✅
4. **Trust** — corrections ✅, expert queue ✅, verification levels ✅

---

## Build tracks

| Track | Status |
|-------|--------|
| A — Mobile retention | ✅ Complete |
| B — Data moat | ✅ Complete |
| C — B2B compliance | ✅ Complete |
| D — Quality / corrections | ✅ Complete |
| E — Social & sync | ✅ Complete |
| F — Infra | Apply migrations **016–023**; deploy 📋 |

---

## Related docs

- [Configuration](./configuration.md)
- [Completion audit](./completion-audit.md)

*Last updated: Phase 12 — integration follow-ups complete except production deploy*

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

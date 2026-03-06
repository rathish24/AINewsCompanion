# Analysis & Confidence – news_companion_plan.md

## My Understanding (Summary)

**Goal:** Turn the current “article text in a bottom sheet” package into **NewsCompanionKit** – an AI-powered companion that, when the user taps an AI icon on an article, produces:

- A **one-line summary**
- **3–5 bullet insights**
- **Why the story matters**
- **Conversational topic chips** (5–6 at a time, from a set of 10 templates)
- Optional **fact-check hints**

**Architecture (5 modules):**

| Module | Responsibility |
|--------|----------------|
| **ArticleFetcher** | URL → extract clean article → **ArticleContent** (title, text, leadImageURL). Prefer internal article API if publisher domain; else Readability-style HTML. Memory + disk cache keyed by URL. |
| **AIClient** | Protocol `AICompleting` (e.g. `complete(prompt:)`). First implementation: **GeminiClient**. Key to be provided by you later – I’ll add a config/placeholder. |
| **ConversationEngine** | ArticleContent → build prompt → AIClient → parse strict JSON → **CompanionResult** (summary, topics, factChecks). Trimming, fallbacks, retry on bad JSON. |
| **Models** | ArticleContent, CompanionResult, Summary (oneLiner, bullets, whyItMatters), TopicChip (title, prompt), FactCheck (claim, whatToVerify). |
| **SwiftUI** | Bottom sheet: skeleton loading (2–3 s target) → one-liner → bullets → why it matters → topic chips; optional “Ask your own question”. Scannable, short, tappable. |

**AI contract:** AI must return strict JSON: `summary` (oneLiner, bullets[], whyItMatters), `topics` [{ title, prompt }], `factChecks` [{ claim, whatToVerify }].

**Execution order (from plan):** Package scaffolding (rename to NewsCompanionKit, models, protocols) → ArticleFetcher (extraction + cache) → GeminiClient + ConversationEngine → SwiftUI integration → Guardrails & fallback UI → Telemetry hooks (you can plug in later).

**Assumptions:**  
- Package renamed to **NewsCompanionKit**; current ArticleBottomSheet code becomes the base and is extended/refactored.  
- “Internal article API” is optional/configurable (no specific API described); I’ll add a protocol or hook so you can plug it in later.  
- **Gemini API key** will be supplied by you later; I’ll use a config (e.g. environment, init parameter, or plist) and never hardcode the key.

---

## Confidence Level

| Area | Level | Notes |
|------|--------|--------|
| **Package rename & module layout** | **9/10** | Clear: NewsCompanionKit, ArticleFetcher, AIClient, ConversationEngine, Models. |
| **Data models & AI JSON contract** | **9/10** | ArticleContent, CompanionResult, Summary, TopicChip, FactCheck and the JSON shape are clearly specified. |
| **ArticleFetcher (extraction + cache)** | **8/10** | Readability-style + cache is clear; “internal article API” is underspecified – I’ll add an optional fetcher protocol. |
| **AIClient + GeminiClient** | **7.5/10** | Protocol and “use Gemini” are clear; exact Gemini API (REST vs SDK, model name) I’ll choose a standard approach and make key configurable. |
| **ConversationEngine (prompt → JSON → CompanionResult)** | **8.5/10** | Build prompt, enforce JSON, parse, retry once on failure – straightforward. |
| **Bottom sheet UX (order, skeleton, chips)** | **9/10** | Display order and “scannable, short, tappable” are clear. |
| **Topic templates (10 defaults, show 5–6)** | **8/10** | List of 10 given; I’ll implement selection/priority so 5–6 show. |
| **Guardrails & fallback UI** | **8/10** | Trim length, timeout, fallback message – clear. |
| **Telemetry / experimentation** | **6/10** | Events and variants are listed; I’ll add hooks/callbacks and stub points; actual analytics left to you. |

**Overall confidence: 8/10** – I’m confident implementing the plan end-to-end with the key as a config you supply later. The only lower-confidence parts are “internal article API” (I’ll make it pluggable) and telemetry (I’ll add integration points).

---

Once you’re happy with this, I’ll delete `PLAN.md`, keep `news_companion_plan.md` as the single plan, and start implementing in the order above.

# AcceptanceCriteria — THE MANUAL: context-aware HTML help
_From the design side (DESIGN-context-manual, 2026-08-03). PARKED: captured, NOT built — a new substantial feature
awaiting the user's go-ahead + prioritisation against the strip device pass / emitter page / SELECT._

## 0. Status
NOT built. The user's idea: a "?" top-right that opens a bundled HTML manual focused on the last-touched control.
Design side AUTHORS the content; Code WIRES the mechanism.

## 1. THE MECHANISM
- Every control registers a stable **doc-anchor ID** in a shared constants registry ("latch" · "keys-chord" ·
  "duck-amount" · "ladder" · "chain-bypass" …). The app tracks `lastTouchedControlID` on any MEANINGFUL interaction
  (not scrolls).
- **"?" top-right** (beside the cog) → an in-app WKWebView loads the bundled `manual.html#<anchor>` → scrolls there,
  with a brief highlight pulse on the landed section.
- Nothing touched this session → opens at CONTENTS. A persistent contents/back affordance in the manual header.

## 2. THE ARTIFACT
- ONE bundled HTML (app-styled: dark surface, mono type, the hue language) — and the SAME file publishes to the web
  as product docs. Write once, ship twice.
- The seal/route generators (already HTML/JS from the design mockups) EMBED as living diagrams — the signatures
  chapter renders real, interactive examples with the shipping algorithm.
- Source of truth: markdown in the repo, built to HTML at build time (hand-HTML acceptable v1).

## 3. THE DISCIPLINE (keeps it alive)
- **THE DOCS TEST**: a CI check that every registered control ID has a matching manual anchor. Missing docs FAIL
  the build — the manual structurally cannot rot behind the UI.

## 4. CONTENT ARCHITECTURE (design authors; Code wires)
- Chapters mirror the surfaces: PERFORM (strips · roles · master · LADDER · macros) · EDIT (mode row · chain ·
  triggers) · THE COG · CONCEPTS (the plain-language laws — GUIDE-touching-things.md is chapter one, already written).
- Per-control micro-sections: 2–4 sentences, anchor-ID'd — the "what does this do" answer first, links deeper after.

## 5. Later, noted not built
- Long-press "?" = "what is this?" mode (the next tap opens that control's section directly — the help cursor).
- In-manual search field.

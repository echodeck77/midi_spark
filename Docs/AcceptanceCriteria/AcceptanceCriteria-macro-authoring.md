# AcceptanceCriteria — THE MACRO AUTHORING FLOW (canonical) (captured 2026-08-06)

**STATUS: ✅ BUILT (2026-09-01 doc reconcile — the macro authoring flow shipped; see CLAUDE.md status).** Design-side + Paul (ferry `INSTRUCTIONS-macro-authoring-canonical.md`).
Supersedes the earlier `INSTRUCTIONS-processor-macro-flow.md` AND **retires the per-group `[AB]` popup** shipped as
M4 (`AcceptanceCriteria-macro-ab-authoring.md`) — the authoring UI is replaced by this GENERIC control-group flow;
the offset ENGINE underneath (M1 fold · M2 AU params · the 24 macro slots) is unchanged and carries over.

## PAUL'S MESSAGE 1 (verbatim)
"I want to write some specific instruction for Claude code regarding the cell edit page (now called processors).
For each processor, I want three buttons at the top. These are "Vel. Mixer" (discussed as "mixer" earlier in this
thread), "Bypass" (complete) and and "Macro". When, Macro is selected, a new page is shown with two instances of
the processor controls (for example, bypass, rate, gate - all controls available to that processor). These top set
of controls are marked Main and the second set are marked Alternative. These are both defaulted to the settings on
the selected processor. Below these are a test macro slider and a test macro button with which they can switch
between settings main and alt to audition their macro controls. Below this is an "add to macro" button, which takes
the user to another view where the 8 macro buttons and 8 macro sliders are listed, along with "Assign" buttons,
spring on/off for sliders, toggle on/off for buttons, and an indicator of whether it is in use (a macro will allow
multiple controls from throughout the app to be applied to it). There will also be an apply/cancel option, both of
which return the user to the processor chain page. Any changes applied to the "main" section will be still apply to
how the user configured that processor in the processor edit page if "apply" was selected. On the processor edit
page, if that page's cancel button is selected then the changes to the macro will be reverted. A separate "Macros"
page will be defined later to further manage this feature."

## PAUL'S MESSAGE 2 (verbatim)
"Thanks. Can you include my original message in your document to Claude code? Some other details: only changed
values will be stored with the macro. If a macro has already been assigned spring or toggle attributes, then this
is fixed and can only be setup on the dedicated macro tab. To avoid confusion, we should differentiate between the
Macro Main Tab (to be defined, but intended as a way to manage all macros in one place) and this page where the
actual changes are applied. Another important note is that this will be useable throughout the app, not just the
processor edit (I used this to illustrate the flow). Other places that come to mind where this can be used are the
recievers, the emmiters and the rack. Therefore it should be built in a way that is generic enough to know this is
about controls rather than processors specifically. Please include this message in your reply to Claude code too,
and add details you think may be relevant."

## THE CONSOLIDATED SPEC (design-side)
- **Vocabulary.** THE MACRO MAIN TAB = the future management surface (all macros in one place — spring/toggle
  attributes, timelines/lanes, renames, unbinding). THE AUTHORING FLOW (this spec) = where changes are made +
  assigned, hosted per control group.
- **1. GENERIC — control groups, not processors.** The flow attaches to any registered CONTROL GROUP: a processor
  slot · a RECEIVER · an EMITTER · a RACK treatment row. Each group registers (id · title · param addresses · a
  panel builder); a MACRO button appears on any registered group's header. (VEL. MIXER + BYPASS stay
  processor-specific chrome; MACRO is universal.)
- **2. THE AUTHORING PAGE** (tap MACRO on a group): two full instances of that group's controls — MAIN above,
  ALTERNATIVE below, both defaulted to current settings. Then a TEST SLIDER (continuous morph) + TEST BUTTON
  (snap) to audition both mover feels live. Then ADD TO MACRO → the assignment view. APPLY / CANCEL return to the
  host page.
- **3. SPARSE DELTAS.** Only CHANGED values are stored: the binding records exactly the params where ALT diverges
  from MAIN at author time (delta = ALT − MAIN per touched param); untouched params carry nothing. Deltas are
  RELATIVE (the offset law) — if MAIN later changes, the delta still applies to the new base. (This is exactly the
  M1 model already built.)
- **4. THE ASSIGNMENT VIEW.** 8 BUTTONS + 8 SLIDERS listed, each with ASSIGN · the mover attribute (spring for
  sliders / toggle for buttons) · an IN-USE indicator (multiple app-wide controls may bind one macro; show source
  chips by domain). FIRST assignment SETS the attribute; thereafter it is FIXED here (read-only, lock glyph, "edit
  on the Macro Main tab"). Timelines are absent here (Macro Main's business).
- **5. MOVER ELIGIBILITY.** A delta containing any DISCRETE change (bypass, enum flip, rack toggle) may bind only
  to BUTTONS (and later step-timelines); SLIDERS take continuous-only deltas. Assignment rows dim the moment a
  discrete is touched in ALT.
- **6. TRANSACTIONS, host-adaptive.** MAIN is REAL — its edits become the group's settings on APPLY. On STAGED
  hosts (the processors page) the flow rides the page transaction (the page's CANCEL reverts macro changes too).
  On LIVE hosts (receivers · emitters · rack) the flow's APPLY commits as ONE undoable step; its CANCEL reverts
  only the flow's own changes. One promise: nothing escapes CANCEL.
- **7. PERSISTENCE (lean YES, confirm).** The ALTERNATIVE set persists on the group in the document — reopening
  MACRO shows the last-authored B; assignment copies the delta to the binding.
- **8. Unchanged underneath.** The offset stack · spring/padlock semantics · AU-param exposure · liveness (§10,
  all domains) · chrome-quiet. The per-group `[AB]` design retires; cross-group composites compose AT THE MACRO
  (the in-use chips are the tell).

## RELATIONSHIP TO WHAT'S BUILT (Code note)
- KEEP: the offset fold `applyMacros` (M1) · macro AU params 400+i (M2) · the 24 `Macro` slots + `macrosResolved`
  + `MacroTarget`/`MacroEmitterTarget` (the binding shapes) · the MACROS tab drive (M3).
- REPLACE: `MacroBindPopup` (the M4 `[AB]` popup on the CHAIN header) → the generic MAIN/ALT authoring page + the
  assignment view, hosted by a CONTROL-GROUP registry so processors/receivers/emitters/rack all reuse it.
- EXTEND the binding model to name its SOURCE DOMAIN per target (for the in-use chips), and add the ALTERNATIVE
  set persisted per group (currently the popup captured A on open + restored it; now B persists).

## OPEN QUESTIONS (Code → design/Paul)
- The CONTROL-GROUP registry shape: is a param-address list + a SwiftUI panel-builder per domain acceptable, or do
  you want a data-only descriptor (so the authoring page renders generically without per-domain view code)?
- ALT persistence (§7) storage: per control-group in the document — for a processor that's `ProcessorSlot`; for a
  receiver/emitter/rack row, a parallel `alt*` field family. Confirm we add a `paramsAlt`-style bag per group.
- Mover-eligibility dimming (§5) needs a per-param DISCRETE/CONTINUOUS classification per domain — I'll derive it
  from each group's descriptor.

# Setting up a FourStep Project in Claude (desktop/web)

This is for the regular Claude app — a **Project**, not Claude Code. A Project has two separate
slots, and the proven practice is to keep them separate: **Custom Instructions** is a short
behavioral prompt (loaded on every turn, so it should stay small), and **Project Knowledge** is
where the actual facts live (uploaded files, retrieved as needed — can hold much more without
taxing every single message). Don't blend them: if the instructions field balloons with facts,
it starts costing context on every turn for no benefit — exactly the mistake CLAUDE.md itself
had made before this restructuring, in a different venue.

## Setup

1. Create a new Project, name it **FourStep** (a dedicated Project, not folded into any other —
   this keeps scope pure the same way CLAUDE.md's own "Scope" section does for Claude Code: 8x8
   State's wider feature set is a different, on-hold product, and a shared Project would blur the
   two).
2. Paste the block below into **Custom Instructions**.
3. Upload both knowledge documents to **Project Knowledge**:
   - `fourstep-claude-project-knowledge-product.md` — the product & design reference.
   - `fourstep-claude-project-knowledge-visual.md` — the visual design language / palette.
4. Optional, once available: real device screenshots. Claude reads images directly inside a
   Project — a handful of actual screenshots of the shipped lane cards, riff grid, and sequencer
   panel would ground design conversations far better than prose alone. Not included here because
   they don't exist yet in a form I can produce — add them when you have them.

## Custom instructions (paste verbatim)

```
You are a product and design thinking partner for FourStep — a four-lane Euclidean-rhythm MIDI
instrument for iPad, shipping as a standalone AUv3 plugin and a standalone app. It began as
"Euclideous," one reserved row inside a larger MIDI-processing plugin called MidiSpark / 8x8
State; FourStep is that feature extracted and released on its own, as a separate app and AU
extension sharing the same audio engine. 8x8 State's wider feature set — the 8x8 grid, rooms,
ferries, macros, the processor chain — is a different product, currently on hold, and out of
scope here unless explicitly asked about.

Ground answers in the uploaded project knowledge — it reflects the real shipped product, not a
proposal. When something isn't covered there, say so plainly rather than inventing specifics (an
exact pixel size, a feature that doesn't exist yet, a roadmap or pricing decision that hasn't
been made). Treat the knowledge files as more authoritative than anything you might otherwise
assume about MIDI instruments or Euclidean sequencers in general.

Be a sounding board, not a yes-man — when a direction has a real tradeoff, name it rather than
validating by default. When an instruction is ambiguous but reasonably inferable, make the call
and say what you assumed rather than stopping to ask; ask only when a decision is genuinely
irreversible or a real toss-up (naming, scope, pricing, anything that's expensive to undo).

This Project is for product thinking, design direction, copy, and planning conversations — not
for editing the Xcode project or Swift source, which happens separately in Claude Code against
the real repository.
```

## Why this shape (the proven-practice reasoning)

- **Short instructions, fuller knowledge** — the instructions field is read on every single turn;
  keep it to behavior and a one-paragraph orientation, not a changing set of facts. Facts belong
  in knowledge files, which are retrieved only when relevant.
- **A dedicated Project, not a shared one** — exactly the same reasoning as CLAUDE.md's own Scope
  section: FourStep and 8x8 State are different products at different stages right now, and
  mixing their context in one place makes both conversations muddier.
- **Update the knowledge docs, not the instructions, when facts change.** If the four-lane model
  grows a fifth facet, or a scope decision changes, re-upload the updated knowledge file — don't
  grow the instructions field to compensate.
- **Keep the knowledge set small and non-redundant.** Two focused documents beat ten overlapping
  ones — this is the same lesson the Euclideous status log learned the hard way (an 8,800-line
  single file that nobody could tell what was still true from what was settled history). If a
  third knowledge document is ever added, make sure it doesn't restate what the first two already
  cover.

# Document Intelligence

## Tony reads for meaning, not text

*Project Diamond, Sprint D6. The foundation for Tony understanding documents.*

Implementation: `tony-alpha/dashboard/core/document-intelligence.ps1`.

## Why meaning, not text

A text extractor turns a PDF into a wall of characters and hands it back. That is not useful —
it just moves the reading problem from the document to the screen. Jake doesn't need GIOK to
*re-type* a document; he needs a chief of staff who has already read it and can say **what it
means for him**.

So Document Intelligence does not summarize. It **reads for meaning** and then **connects that
meaning back to the operating system**:

- It identifies the things that matter — goals, projects, action items, ideas, deadlines, dates,
  people, companies, meetings, risks, decisions, and open questions.
- It compares each finding against the life Jake is building — Identity, Vision, Goals, Mission,
  Core Values, Action Items, Capture, and recent Audits.
- It says the useful thing: *"This goal doesn't exist yet."* *"This action item matches AI-104."*
  *"You captured this same idea before."* *"This may conflict with your Annual Theme."*

That is the difference between an extractor and a chief of staff. An extractor gives you the
document back. Tony tells you what to **do** about it, in the context of everything else he knows.

## Why user approval is always required

**Nothing is written into GIOK automatically. Ever.** The pipeline only reads and proposes.

This is not a limitation — it is the point. GIOK is the single source of truth for Jake's life
and business. If documents could silently inject goals, tasks, and notes, that truth would rot:
duplicated goals, half-relevant tasks, stray captures from every PDF that passed through. The
operating system would fill with noise no one chose.

So every finding becomes a **suggestion** on a **Review Screen**, and every suggestion carries
three explicit actions:

- **Accept** — write it into GIOK (the *only* path that causes a write).
- **Reject** — discard it; nothing happens.
- **Edit** — fix the wording first, then accept.

`Approve-DocumentSuggestion` is the single function in the whole module that writes anything, and
it runs only when the user explicitly approves that one suggestion. Read is automatic; **write is
always a human decision.** This keeps Jake — not a parser — the author of his own system, and it
keeps the "People Matter More Than Money / your brain is for thinking" trust intact: GIOK never
puts words in his mouth.

## What a review returns

`Invoke-DocumentIntelligence` runs the whole pipeline and returns the executive package a chief of
staff would hand you:

- **Executive Summary** — Tony's read, connected to the OS (not a recap of the text).
- **Key Findings** — the identified goals, tasks, ideas, people, dates, risks, decisions, etc.
- **Suggested Goals / Tasks / Projects / Questions** — new items worth adding, deduped against
  what already exists.
- **Potential Conflicts** — where the document points away from the Annual Theme or priorities.
- **Alignment Score** — how well the document fits the life Jake is building, scored by Tony's
  [Decision Framework](Tony_Decision_Framework.md), not by the document itself.
- **Review** — the list of suggestions, each with Accept / Reject / Edit.

## The pipeline

```
1. Read document      Read-Document          (PDF, DOCX, TXT, Markdown)
2. Extract text       per-type extractors    (DOCX unzip; PDF best-effort inflate)
3. Identify meaning   Get-DocumentEntities   (goals, tasks, people, risks, ... - heuristic)
4. Compare to the OS   Compare-DocumentFindings  (dedupe vs Identity/Goals/Actions/Capture)
5. Suggest            (built into the compare step)
6. Review             New-DocumentReview -> Approve / Reject / Edit
```

Supported today: **PDF, DOCX, TXT, Markdown**. Coming next: **images, email, meeting
transcripts** — new readers plug into step 1/2 without touching steps 3–6.

## How future AI improves extraction without changing the workflow

Step 3 (identify meaning) is a **transparent heuristic today** — regex and keyword rules,
deterministic and testable, that need no AI, no API, and no cloud. It is deliberately a clean seam:

- A future model can **replace or enrich the extraction** in steps 2–3 (better entity detection,
  real semantic understanding, scanned-image OCR) while **everything downstream stays identical**.
  The findings still flow into the same comparison, the same suggestions, the same Review Screen.
- The **approval contract never changes.** No matter how smart extraction gets, a document still
  cannot write into GIOK without Jake accepting each suggestion. Smarter reading raises the quality
  of the *proposals*; it never earns the right to *decide*.
- The **output shape is stable** — Executive Summary, Key Findings, the suggestion list with
  Accept/Reject/Edit — so the eventual Review Screen UI and any consumer can be built now against a
  contract that better AI will only make sharper.

This is the Project Diamond pattern again: a value-aligned, honest foundation first; intelligence
plugged into a seam later — never at the cost of the user's control.

## Constraints honored

No cloud sync. No Gmail. No Calendar. No GHL. No automatic writes. Local files only. The module
reads existing GIOK data through the same accessors every other layer uses — it duplicates nothing
and owns nothing but the reading itself.

## Related
- [Tony_Decision_Framework.md](Tony_Decision_Framework.md) — supplies the document's Alignment Score.
- [Tony_Brain.md](Tony_Brain.md) — where document findings will feed Tony's reasoning.
- [05_Capture_System.md](05_Capture_System.md) — where accepted ideas, projects, and questions land.
- [13_Project_Diamond.md](13_Project_Diamond.md) — the standard: meaning over text, approval over automation.

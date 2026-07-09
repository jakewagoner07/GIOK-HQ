# GIOK — Manual Testing Checklist (v0.8 Alpha)

Run through this Sunday night to confirm GIOK works for daily use. Launch via the **GIOK** desktop
icon (or `dashboard/launch-tony.vbs`). Everything is local — nothing leaves the machine.

> Tip: the app writes to JSON files as you use it (that's expected). To start onboarding fresh at
> any time: **Settings → Restart First Conversation**.

## Launch
- [ ] Double-clicking the **GIOK** desktop icon opens the app with **no console window**.
- [ ] The window is dark navy with the GIOK logo, Jake's photo, and the sidebar.
- [ ] Version reads **v0.8 Alpha** at the bottom of the sidebar.

## Tony's First Conversation (first run / after Restart)
- [ ] On first launch (not yet completed), GIOK lands on **Tony's First Conversation**.
- [ ] The utility toolbar is hidden here (immersive).
- [ ] Tony greets you; **Begin ->** advances to Question 2.
- [ ] Each question shows one prompt, an answer box, a progress bar, and **Back / Next**.
- [ ] Typing an answer and pressing **Next** advances; **Back** returns and your text is still there.
- [ ] **Save & Exit** / **Resume Later** leave to Home and your progress is kept.
- [ ] Re-opening shows the resume banner on Home: "Finish your first conversation with Tony ->".
- [ ] Completing the last question shows Tony's thank-you + **"Let's build your operating system"**.
- [ ] Clicking it opens **Home**, and **Identity** now reflects your answers (Vision, Goals, Core
      Values, Mission, Annual Theme, Overview reflection).

## Home (Morning Briefing)
- [ ] Greeting matches time of day; the daily principle is shown.
- [ ] **Today's Priorities**, **Tony Recommends**, and **Today's Snapshot** cards render.
- [ ] Clicking a card opens the matching view ("open >").
- [ ] **+ Capture Something** opens the capture window.
- [ ] Quick links (End of Day Audit, Action Items, Issues, Weekly Review, Roadmap) navigate.

## Sidebar / Navigation
- [ ] Daily tools appear at top: Home, End of Day Audit, Capture, Action Items, Identity, Mission
      Control, AI Workforce, Tony.
- [ ] A dim **COMING SOON** group is below (Non-Negotiables, Family, Health, Financial, Agency,
      Home Projects, Learning) — clicking any shows a "coming soon" page.
- [ ] The active item is highlighted orange.
- [ ] **Ctrl+K** focuses the "Ask Tony" command bar on Home.

## Capture
- [ ] **+ Capture Something** opens a window: free text + optional category, no required fields.
- [ ] **Save to Inbox** adds the item; it appears in the Capture Inbox.
- [ ] Command bar `capture: call Steve` adds a capture.
- [ ] Inbox filters (Unprocessed / Processed / Archived / All) work.
- [ ] Per-item actions work: Mark Processed, -> Action Item (creates a task), -> Goal / -> Reminder,
      Archive, Delete, Restore.

## Action Items
- [ ] The list renders from `action_items.json`.
- [ ] Checking an item strikes it through and saves; unchecking restores.
- [ ] **+ Add** (or Enter) creates a new item; **Delete** removes one.
- [ ] **Archive completed** moves done items to the Archived tab; **Restore** brings one back.

## Identity
- [ ] Overview cards render (Identity Score, Vision/Goal Progress bars, Annual Theme, Core Values,
      Latest Journal, Recent Wins, Tony's Reflection).
- [ ] Section tabs switch (Vision, Goals, Core Values, Mission, Legacy, Annual Theme, Journal,
      Timeline).

## End of Day Audit
- [ ] Reachable from the sidebar, Home quick link, and command bar (`audit`).
- [ ] Score steppers (-/+) change category scores; **Overall** updates as the average.
- [ ] **+ Add win** adds a win; the **x** removes one.
- [ ] Incomplete items show with Move to tomorrow / Keep open / Archive / Delete.
- [ ] Non-negotiable checkboxes toggle and persist.
- [ ] Reflection fields save when you click away.
- [ ] **History** tab shows past audits.

## Mission Control
- [ ] Opens in-app (sidebar) with 8 live panels.
- [ ] **Open Mission Control** (toolbar) opens it in a **separate window**.
- [ ] **Open in New Window** pops the current view into its own window.

## General
- [ ] No screen shows a raw error dialog.
- [ ] Placeholder data is clearly labeled (SAMPLE / "(sample)").
- [ ] The app feels obvious, calm, and fast.

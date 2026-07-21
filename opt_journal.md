# Bionic 02 LLC — OPT Self-Employment Activity Log

> **Purpose:** Contemporaneous record of degree-related work performed under Bionic 02 LLC
> during post-completion OPT. Maintained as evidence of active engagement per SEVP guidance.

| Field | Value |
|-------|-------|
| Name | Danaid Sinani |
| SEVIS ID | N0033174598 |
| EAD category | C03B |
| EAD validity | 2026-07-08 → 2027-07-07 |
| OPT employment start date | 2026-07-21 |
| Business | Bionic 02 LLC (Wyoming) |
| Products | Attention Arsenal (iOS), FinePrint (web) |
| Work location | 255 Nassau Blvd, Garden City, NY 11530 |
| Degree | BA Computer Science, Boston University |

**Degree-connection shortcodes** (BU coursework, use in the `Degree` column):
`SE`=Software Engineering (CASCS 411) ·
`FSD`=Full Stack Dev (CASCS 412) ·
`PL`=Concepts of Programming Languages (CASCS 320) ·
`DS`=Distributed Systems (CASCS 351) ·
`ALG`=Analysis of Algorithms (CASCS 330) ·
`CS`=Comp Systems (CASCS 210)

**Rules for this log:**
- Add entries the day you do the work — not reconstructed later.
- Every row needs verifiable **evidence** (commit hash, PR #, deploy log, App Store update, invoice).
- Weekly totals should match the hours reported in the SEVP Portal.
- Nothing dated before the OPT employment start date above.

---

## How to add a week
Copy the block below, paste it directly under this line, fill it in. Newest week stays on top.

```
### Week of YYYY-MM-DD → YYYY-MM-DD — Total: 0 hrs

| Date | Hrs | Product | Task | Degree | Evidence |
|------|-----|---------|------|--------|----------|
| YYYY-MM-DD | 0 |  |  |  |  |

**Summary:** 
```

---

<!-- ADD NEW WEEKS BELOW THIS LINE -->

### Week of 2026-07-20 → 2026-07-26 — Total: 9.5 hrs

| Date | Hrs | Product | Task | Degree | Evidence |
|------|-----|---------|------|--------|----------|
| 2026-07-21 | 3 | FinePrint | Built GraphQL resolver for contract-category endpoint | FSD, SE | `commit a1b2c3d` |
| 2026-07-21 | __ | Attention Arsenal | Reworked notification scheduling for per-interval nudge timing; added NudgeTimingSection UI; set up OPT activity journal + repo instructions | SE, PL | `commit e842424` |
| 2026-07-22 | 2.5 | Attention Arsenal | Fixed Core Data sync bug; added notification scheduling | PL | `commit e4f5g6h` |
| 2026-07-24 | 4 | FinePrint | Deployed PII anonymization pipeline update | SE | `commit i7j8k9l` + deploy log |

**Summary:** Advanced FinePrint's API layer and shipped a deployment; resolved a persistence bug in Attention Arsenal. All work applied core CS coursework in software engineering and full-stack development.

---

## Expenses

| Date | Item | Amount | Purpose |
|------|------|--------|---------|
| YYYY-MM-DD | Apple Developer Program | $99.00 | iOS distribution (Attention Arsenal) |
| YYYY-MM-DD | Domain — fineprint.dev | $0.00 | Product hosting |

## Milestones

| Date | Milestone |
|------|-----------|
| YYYY-MM-DD | e.g., FinePrint feature X shipped / first paying user / App Store update live |
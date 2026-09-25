# Legacy Accepted Guides

`docs/` began as an informal writing area. Several files were later accepted
and linked by the project, so deleting or bulk-moving the directory would break
useful history and many backlinks.

## Policy

- This directory is **frozen to the classified legacy set below**.
- Do not add new temporary ideas here; use [`notes/inbox/`](../notes/inbox/).
- Do not add new canonical engineering documents here; use [`doc/`](../doc/).
- Update an existing guide in place while active work depends on it.
- Move a guide only when it next receives a substantial revision, and update
  every backlink in the same change.
- A move changes location, not evidence status or provenance.

## Classification

| File | Classification | Eventual home / action |
| --- | --- | --- |
| [`phase3-guide.md`](phase3-guide.md) | Accepted implementation guide | Move to `doc/guides/` when substantially revised |
| [`phase4-uart-guide.md`](phase4-uart-guide.md) | Accepted implementation guide | Move to `doc/guides/` when substantially revised |
| [`phase4-gpio-guide.md`](phase4-gpio-guide.md) | Accepted implementation guide | Move to `doc/guides/` when substantially revised |
| [`phase5-startup-runtime-guide.md`](phase5-startup-runtime-guide.md) | Accepted firmware/runtime guide | Move to `doc/guides/` when substantially revised |
| [`verification_framework.md`](verification_framework.md) | Accepted and actively evolving verification guide | Later move to `doc/verification/` after active UVM work stabilizes |
| [`AIR_POINTER_HANDWRITING_RESEARCH_REPORT.md`](AIR_POINTER_HANDWRITING_RESEARCH_REPORT.md) | Separate product-concept research | Later move to a separate project or `research/concepts/air-pointer/` after review |
| [`INTERVIEW_GUIDE.md`](INTERVIEW_GUIDE.md) | Career/presentation artifact | Later move to `deliverables/interview/` after review |

The table classifies location and authority; it does not claim that every idea
inside a document was implemented.

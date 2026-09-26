# Information Classification and Handling

**Purpose:** decide whether project information may be committed, shared, or
uploaded before disclosure occurs.

**Status:** Accepted governance policy

**Last updated:** 2026-09-26

This policy classifies confidentiality, not technical quality, copyright,
patentability, export status, or license ownership. Publicly disclosed source
can remain proprietary or license-restricted, but it is no longer confidential
merely because the project owns it.

The `DATA-*` names are deliberate. Do not use `L0` through `L3` for
confidentiality because those labels already describe benchmark layers in the
research plan.

## 1. Classification levels

| Class | Meaning and examples | Allowed handling |
| --- | --- | --- |
| `DATA-PUBLIC` | Approved for uncontrolled disclosure: published papers, public references, deliberately released source, sanitized evidence | May be committed and shared, subject to license and provenance rules |
| `DATA-INTERNAL` | Routine unpublished planning, unvalidated analysis, private meeting notes, or non-sensitive operational detail | Only in explicitly approved access-controlled project systems; commit only when the repository/remote is confirmed private for the intended readers |
| `DATA-CONFIDENTIAL` | Unpublished enabling algorithms, detailed propulsion geometry or parameters, pre-publication PPA/control results, customer or partner evidence, cost/BOM data, or other competitively useful material | Keep outside this repository in approved encrypted storage with named access; the repository may retain only a sanitized summary, stable evidence ID, hash, owner, and storage alias |
| `DATA-RESTRICTED` | Credentials/private keys, personal data, contractually restricted material, regulated technical data, or information whose disclosure creates immediate security or legal harm | Use the designated secret manager or compliant restricted store; never place payloads in Git, ordinary phase documents, logs, prompts, or a generic cloud database |

If classification is unresolved, temporarily treat the material as
`DATA-CONFIDENTIAL`. Do not commit, upload, paste into an external AI/cloud
service, or copy it into a general database until the owner records a decision.

## 2. Pre-commit and pre-upload questions

Ask these questions before adding raw data, results, models, documents, images,
waveforms, or prompts to a shared system:

1. Is the exact material already lawfully public, and was this project version
   deliberately approved for public disclosure?
2. Would it let another party reproduce a currently unpublished competitive
   mechanism, model, geometry, tuning method, or measured advantage?
3. Is it intended for a paper, patent review, customer negotiation, investment
   process, or product release that has not yet occurred?
4. Did it come from a customer, collaborator, vendor, employer, NDA, contract,
   licensed dataset, or access-controlled source?
5. Does it contain personal information, precise locations, credentials,
   tokens, private keys, or security-sensitive infrastructure detail?
6. Could aerospace, dual-use, privacy, contractual, or other regulatory rules
   apply even if the author created the material?

Any `yes` or `unknown` blocks the commit/upload until the owner determines the
class and approved storage boundary. Classification does not replace specialist
legal review where patents, contracts, personal data, or regulated technology
may be involved.

## 3. Phase and research recording rule

Before a phase or experiment starts, its requirements state:

- anticipated data class;
- likely confidential/restricted fields;
- what sanitized material may enter the repository;
- the approved external storage alias, if one exists;
- classification owner and next review trigger.

After results exist, `results.md` repeats the classification review because a
routine experiment may unexpectedly create a valuable result. Do not put a
secret path, password, access token, or confidential payload in the phase
package. Use a stable reference such as `EVID-W0-001`, a content hash where
safe, and a non-sensitive storage alias.

Reclassification requires the previous class, new class, owner, date, and
reason. Public release is a deliberate action; age or inactivity does not
automatically declassify material.

## 4. Storage boundaries

- Git history is a disclosure boundary. Deleting a later commit does not prove
  that earlier copies disappeared.
- Passwords, tokens, certificates, and private keys belong in a secret manager,
  never in research tables or `.env` files committed to Git.
- Large confidential artifacts belong in approved encrypted object/file
  storage. A database may index IDs, metadata, ownership, and relationships;
  it is not automatically the right place for file payloads.
- Cloud or AI services are external disclosure boundaries unless their account,
  retention, training, region, access, and contractual terms have been approved
  for the data class.
- Keep at least one independently recoverable encrypted backup for unique
  `DATA-CONFIDENTIAL` or `DATA-RESTRICTED` evidence, with restoration tested in
  proportion to its value.

No cloud research database is required at the current project scale. Revisit
one when structured records, multiple authorized collaborators, cross-device
automation, audit history, or relationship queries justify its security and
maintenance cost.

## 5. Sanitized repository evidence

When raw evidence must remain outside Git, retain only what is safe and useful:

| Field | Example form |
| --- | --- |
| Evidence ID | `EVID-W0-001` |
| Classification | `DATA-CONFIDENTIAL` |
| Owner | role or approved individual |
| Storage alias | non-secret logical name, not a credential-bearing path |
| Integrity | SHA-256 or equivalent, when the hash itself reveals no sensitive content |
| Public summary | conclusion with sensitive values removed or bucketed |
| Reproduction boundary | tools/input classes needed, with restricted inputs referenced by ID |
| Review trigger | publication, patent decision, partner approval, phase closure, or a date |

## 6. Suspected exposure response

If restricted material is accidentally committed or uploaded:

1. stop further sharing and record the affected artifact and boundary;
2. rotate credentials immediately when any secret may be exposed;
3. inform the information owner and determine who could access copies;
4. preserve a non-sensitive incident record and decide whether history cleanup,
   partner notification, or legal/security advice is required;
5. do not claim that deleting the visible file alone removed the exposure.

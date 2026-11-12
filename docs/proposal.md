# DCT OS

**A customized, institution-managed Linux desktop for Dominican College of Tarlac**

| | |
|---|---|
| Proponent | [[TODO: name, program/year]] |
| Proponent's adviser | [[TODO]] |
| Implementing unit | [[TODO: IT Services / Computer Studies]] |
| Document status | Draft for review |
| Date | 11 November 2026 |
| Version | 0.1 |

> **Conventions in this draft.** Anything in `[[TODO: ...]]` is a fact only DCT can
> supply — machine counts, licence holdings, names, budget figures. Do **not**
> let a reader mistake an estimate for a measurement. The technical claims in
> this document are all verifiable from the sources cited in Appendix A.

---

## 1. Project summary

DCT OS is a customized Linux desktop built for Dominican College of Tarlac,
derived from **Ubuntu 24.04 LTS** and packaged for internal institutional use.
It delivers the college's standard application set, institutional identity, and
classroom management tooling in a single reproducible image that the IT office
can deploy, reset, and update without internet-scale bandwidth.

The project does not build a new operating system from scratch. It assembles a
thin, maintainable layer of institutional defaults over a long-term-support base
— the same architecture the college's current desktop (Zorin OS) already uses.
That is what makes the project feasible within a school year and sustainable
afterward.

**Headline outcomes**

| Outcome | Measure |
|---|---|
| One standard classroom image | [[TODO: N]] PCs on an identical, versioned build |
| Faster lab recovery | Trashed PC restored in minutes instead of a reinstall |
| Reduced bandwidth | Updates served from one campus mirror, not [[TODO: N]] upstream clients |
| Institutional identity | College seal, palette and name across boot, login and desktop |

---

## 2. Background and rationale

The college's classroom PCs currently run **Zorin OS**, a desktop Linux
distribution based on Ubuntu 24.04 LTS and supported with security updates until
June 2029 ([Appendix A.1](#appendix-a--sources)).

That choice was sound: Zorin provides a familiar desktop for users coming from
Windows, and it performs well on modest hardware. It is, however, a **general
purpose** distribution. It is not tailored to DCT, it is not configured for
Philippine campus conditions, and it is not something the IT office can rebuild
or audit from source.

Three practical problems follow:

1. **Identity.** Every machine presents a third-party brand to students and
   visitors. There is no institutional identity at boot, login or desktop.
2. **Standardisation.** Two PCs may differ in installed applications, locale
   settings, browser homepage, printer configuration, and desktop defaults. Every
   difference is a support call.
3. **Bandwidth and resilience.** Each machine fetches updates from the public
   internet. In a campus setting that is both slow and fragile; a single upstream
   outage halts patching across the laboratory.

A fourth issue is specific to this proposal's context: the college is running a
desktop it cannot fully own. Zorin's own branding, artwork and some components are
not licensed for modification and redistribution ([Section 10](#10-legal-and-compliance)).
The college can *use* Zorin; it cannot *rebrand* it.

DCT OS addresses all four by building on the same underlying base the college
already runs, but under DCT's own name, configuration, and control.

---

## 3. Problem statement

> DCT's classroom computing environment is functional but generic, inconsistent
> between machines, dependent on external bandwidth for updates, and carries a
> third-party identity that the college cannot lawfully modify. The IT office has
> no reproducible way to rebuild a machine to a known-good state.

---

## 4. Objectives

**General objective.** Design, build, and pilot an institution-branded,
standards-compliant Linux desktop image for DCT's computer laboratories, and
establish a maintainable process for keeping it current.

**Specific objectives**

| # | Objective | Success indicator |
|---|---|---|
| 1 | Produce a bootable DCT OS image on Ubuntu 24.04 LTS | ISO boots in UEFI and legacy mode; installer completes |
| 2 | Apply full institutional branding | `verify-branding.sh` reports zero failures; no third-party marks remain |
| 3 | Package the standard application set | Metapackage installs the full set with one command |
| 4 | Provide an office productivity stack | OnlyOffice default; LibreOffice fallback; Wine present |
| 5 | Deploy a campus update mirror | Lab PCs update from one local host |
| 6 | Enable rapid recovery | A lab PC restored to baseline in under 15 minutes |
| 7 | Document and hand over | Build repo, runbook, and trained maintainer |

---

## 5. Scope

### In scope

- A customized image derived from Ubuntu 24.04 LTS, for **internal DCT deployment only**
- Institutional branding: boot, login, desktop, installer, documentation
- Standard application set and desktop defaults
- A campus-local package mirror
- Lab deployment tooling and a recovery procedure
- Documentation and knowledge transfer to IT staff

### Out of scope

| Excluded | Reason |
|---|---|
| Public release of DCT OS outside DCT | Requires Canonical licensing discussion; unnecessary now |
| Any use of Zorin OS artwork, themes or ISO content | Prohibited by Zorin's terms — see §10 |
| Bundling Microsoft Office | Proprietary; cannot be redistributed |
| Rebuilding Ubuntu packages from source | Not required for internal use under Canonical's IPRights policy |
| Replacing the college's network, LMS, or ERP systems | Separate concerns |
| Windows replacement on administrative (non-lab) workstations | Phase 2 or later |
| Custom firmware boot logo | Impossible without breaking Secure Boot verification |

---

## 6. Technical approach

### 6.1 Architecture

DCT OS is four layers over an untouched base:

```
┌───────────────────────────────────────────────────────────────┐
│  Deployment   campus mirror · imaging · configuration mgmt    │  DCT
├───────────────────────────────────────────────────────────────┤
│  ISO assembly bootable image · branded installer              │  DCT
├───────────────────────────────────────────────────────────────┤
│  Identity +   name, theme, wallpapers, desktop defaults,      │  DCT
│  defaults     browser policy, locale, printer                 │
├───────────────────────────────────────────────────────────────┤
│  Application  the standard install set, one metapackage       │  DCT
│  set                                                          │
├───────────────────────────────────────────────────────────────┤
│  Ubuntu 24.04 LTS + signed boot chain                         │  Canonical
└───────────────────────────────────────────────────────────────┘
```

This is deliberately the same structure Zorin OS uses: a stock Ubuntu 24.04 base
plus **33 `zorin-*` packages** providing desktop defaults, themes, artwork and
wallpapers. Building on the same pattern means DCT OS inherits a decade of
hardening rather than inventing it, and it means the IT office's existing Ubuntu
knowledge transfers directly.

### 6.2 Why not clone Zorin OS

The obvious approach — remaster the existing Zorin installation — is technically
easy and legally unavailable. Zorin's terms prohibit using their marks or creating
derivative works without written consent, and restrict redistribution of modified
images. Building from Ubuntu 24.04 LTS avoids this entirely, because the college
*is* permitted to modify Ubuntu for its own internal use.

### 6.3 Application stack

| Layer | Choice | Rationale |
|---|---|---|
| Office suite (default) | **OnlyOffice Desktop Editors** | Ribbon interface familiar to Word users; strongest `.docx`/`.xlsx`/`.pptx` fidelity on Linux; free and redistributable (AGPLv3) |
| Office suite (fallback) | **LibreOffice** | Already present on the current fleet; broad format support; MPL/LGPL |
| Windows application support | **Wine + winetricks** | Runs legacy Windows software where licensed |
| Microsoft Office | **Supported where licensed** | Not bundled. Installed only on machines DCT holds a licence for [[TODO: confirm whether DCT holds an EES/OVS-ES agreement]] |
| Classroom management | **Epoptes** | Screen broadcast, remote assistance, lab control |
| Recovery | **Timeshift** | Snapshot and rollback without reimaging |
| Browser policy | Firefox enterprise policy | Institutional homepage, LMS bookmarks, telemetry off |

**On "Wine-emulated MS Office":** Wine is a compatibility layer, not an emulator.
Office 2016/2019 runs acceptably under Wine; 2021 is unreliable; Microsoft 365
will not activate. This proposal therefore commits to *support for installing
licensed Microsoft Office*, not to *inclusion of Microsoft Office*. That
distinction protects the college legally and protects the project from an
undeliverable promise.

### 6.4 Secure Boot

[[TODO: replace with measured figures after the Phase 0 audit]]

Zorin OS ships Canonical's signed boot chain (`shim-signed`,
`grub-efi-amd64-signed`, Canonical-signed kernels), so classroom machines are
expected to be booting with Secure Boot **enforced** unless firmware was changed
during installation. This is a hypothesis, not a finding.

DCT OS will **preserve the signed boot chain** rather than replace it. An image
carrying that chain boots whether Secure Boot is on or off, so no firmware change
is required on any machine, and a mixed fleet becomes uniform for free.

The trade-off is one excluded cosmetic item: the firmware-level boot logo is
compiled into the signed bootloader and cannot be replaced. GRUB menus, boot
splash, login screen, desktop and installer branding are all unaffected.

---

## 7. Implementation plan

Five phases over [[TODO: 10]] weeks. Each phase ends in a reviewable artefact.

### Phase 0 — Baseline and approval (1 week)

| Activity | Output |
|---|---|
| Inventory classroom hardware (CPU, RAM, disk, firmware mode) | Hardware register |
| Run firmware / Secure Boot audit on every PC | `docs/baseline/` reports |
| Confirm software licensing position | Licensing memo |
| Obtain written approval to use DCT name and seal | Approval letter |
| Confirm available build workstation / VM capacity | Resource note |

**Gate:** approved branding use, documented licence position, and a measured
firmware baseline.

### Phase 1 — Base image (2 weeks)

| Activity | Output |
|---|---|
| Establish reproducible build pipeline | Build repository |
| Create the application metapackage | Installable package |
| Configure campus mirror | Mirror server |
| Brand the installer | Branded Calamares |

**Gate:** image builds from scratch on a clean machine without manual steps.

### Phase 2 — Branding (2 weeks)

Work through the branding checklist: identity, boot, login, desktop, applications,
installer. Iterate in a virtual machine, then validate against the checklist.

**Gate:** automated branding verification reports zero failures.

### Phase 3 — Pilot (3 weeks)

Deploy to [[TODO: 5–10]] PCs in one laboratory. Run side-by-side with the existing
environment for two weeks. Collect structured feedback from teachers and students.

**Gate:** no blocking defects; user acceptance recorded.

### Phase 4 — Rollout and handover (2 weeks)

| Activity | Output |
|---|---|
| Deploy to remaining laboratories | Production fleet |
| Train IT staff | Training session + runbook |
| Transfer repository and credentials | Handover record |
| Schedule first maintenance rebuild | Maintenance calendar |

**Gate:** IT staff can independently build, deploy and recover a machine.

---

## 8. Deliverables

| # | Deliverable | Form |
|---|---|---|
| 1 | DCT OS installation image | Hybrid UEFI/BIOS ISO, versioned |
| 2 | Reproducible build repository | Git repository with build scripts |
| 3 | Branding asset pack | Vector sources, licensed for institutional use |
| 4 | Campus package mirror | Configured server |
| 5 | Deployment and recovery runbook | Document |
| 6 | Branding verification tool | Automated check, runs before every release |
| 7 | Firmware baseline register | Per-machine audit records |
| 8 | Licensing memo | Document |
| 9 | Training session and materials | Session + slides |
| 10 | Project report | Final academic submission |

---

## 9. Resource requirements

### Personnel

| Role | Responsibility | Effort |
|---|---|---|
| Project lead (student) | Design, build, documentation | [[TODO]] hrs/week |
| Adviser | Technical review, academic supervision | [[TODO]] hrs/week |
| IT Services liaison | Lab access, deployment, handover | [[TODO]] hrs/week |
| Faculty representative | Requirements, pilot feedback | [[TODO]] hrs/week |

### Infrastructure

| Item | Specification | Status |
|---|---|---|
| Build workstation | 8 GB RAM, 60 GB free disk, virtualisation | [[TODO]] |
| Test VM capacity | 2–3 VMs concurrently | [[TODO]] |
| Mirror server | Existing lab server, 100 GB storage | [[TODO]] |
| USB media | 8 GB × [[TODO]] | [[TODO]] |
| Pilot laboratory | [[TODO: room]] | [[TODO]] |

### Software cost

All components are free and open source. There is **no per-seat licence cost**
for the operating system, desktop, office suite, classroom management or imaging
tools. Any Microsoft Office licensing is the college's existing arrangement and
is not part of this project's cost.

---

## 10. Legal and compliance

| Item | Position |
|---|---|
| Ubuntu modification for internal use | **Permitted** by Canonical's IPRights policy |
| Redistribution of modified Ubuntu | **Not proposed.** Internal deployment only |
| Using the name "DCT OS" | Permitted with college approval; must not imply Canonical or Zorin endorsement |
| Zorin OS name, artwork, ISO | **Not used.** Prohibited without written consent |
| GPL / AGPL packages | Redistributed with licence notices intact; source available on request |
| Microsoft Office | Not bundled; installed only where licensed |
| Fonts | Open-licensed (SIL OFL) only |
| Institutional name and seal | Requires written approval from the college |

The About screen and documentation will state: *"DCT OS is built on Ubuntu 24.04
LTS. Not affiliated with Zorin OS or Canonical. Ubuntu is a trademark of Canonical
Ltd. Zorin OS is a trademark of Zorin OS Technologies Ltd."*

---

## 11. Risk register

| # | Risk | L | I | Mitigation | Owner |
|---|---|---|---|---|---|
| R1 | Branding approval delayed | M | H | Start Phase 0 immediately; use placeholder assets meanwhile | Lead |
| R2 | Microsoft Office expectations exceed licensing | **H** | H | OnlyOffice as default; Office framed as "supported where licensed"; confirm EES/OVS-ES in Phase 0 | Adviser |
| R3 | Legacy hardware cannot run the GNOME desktop | M | M | Phase 0 hardware inventory; lighter desktop variant as fallback | Lead |
| R4 | Firmware in legacy/CSM mode on some PCs | M | M | Measured in Phase 0; UEFI-only image would not boot there — plan firmware switch during deployment | IT |
| R5 | Secure Boot state inconsistent across fleet | M | L | Preserve signed boot chain; image boots in all states; change no firmware | Lead |
| R6 | Single-maintainer dependency | **H** | M | Repository, runbook, and a named deputy trained in Phase 4 | Adviser |
| R7 | Campus bandwidth slows builds | H | L | Local mirror; Phase 1 establishes it early | IT |
| R8 | Authored image drifts from upstream security updates | M | H | Rebuild on each Ubuntu point release; unattended security updates | Lead |
| R9 | Scope creep toward a public distribution | M | M | Scope section is explicit; defer to a separate future proposal | Adviser |
| R10 | Unlicensed asset (font, image) ships in the image | L | H | Automated branding check rejects non-open assets; licensing memo | Lead |

---

## 12. Evaluation

| Metric | Baseline | Target |
|---|---|---|
| Lab PCs on a standard image | [[TODO]] % | 100 % of in-scope labs |
| Time to restore a lab PC to baseline | [[TODO]] hours | < 15 minutes |
| Upstream update bandwidth per month | [[TODO]] GB | − [[TODO]] % |
| Support tickets: "cannot open .docx" | [[TODO]] /month | − [[TODO]] % |
| Branding verification failures at release | n/a | 0 |
| IT staff able to rebuild unaided | 0 | ≥ 2 people |

Evaluation will use pre/post comparison over one semester, plus a structured
satisfaction survey of pilot users.

---

## 13. Sustainability and handover

A school project that ends when the student graduates is a liability. Three
commitments prevent that:

1. **The image is reproducible.** Anyone with the repository and a build machine
   can rebuild the system from upstream sources. No undocumented manual steps.
2. **The branding is a payload, not a hand-edited ISO.** Changing the college seal
   or a colour is a one-line edit plus a rebuild, not an archaeology exercise.
3. **Maintenance is scheduled.** A rebuild is planned for each Ubuntu 24.04 point
   release, with security updates applied automatically in between.

Handover requires a named primary and deputy maintainer, and a successful
supervised rebuild performed by IT staff without the project lead present.

---

## 14. Budget

| Item | Qty | Unit cost | Total |
|---|---|---|---|
| Personnel time | [[TODO]] | — | [[TODO]] |
| USB flash drives | [[TODO]] | [[TODO]] | [[TODO]] |
| Mirror server storage | [[TODO]] | [[TODO]] | [[TODO]] |
| Printing and documentation | [[TODO]] | — | [[TODO]] |
| **Software licences** | — | **0** | **0** |

---

## Appendix A — Sources

1. **Zorin OS technical details** — base system, support window, and the published
   installed-package list used to verify the boot chain and package architecture.
   <https://zorin.com/os/details>
2. **Zorin OS Terms of Service** — trademark and derivative-work restrictions.
   <https://zorin.com/legal/terms/>
3. **Canonical IPRights policy** — permission to modify Ubuntu for internal
   organisational use; restrictions on redistributing modified images.
   <https://canonical.com/legal/intellectual-property-policy>
4. **Ubuntu 24.04 LTS release and support lifecycle** — standard support to 2029,
   extended support thereafter. <https://ubuntu.com/about/release-cycle>
5. **OnlyOffice licensing** — AGPLv3 desktop editors.
   <https://www.onlyoffice.com/>
6. **Wine** — LGPL compatibility layer. <https://www.winehq.org/>

## Appendix B — Baseline audit procedure

Run on each classroom PC before any change:

```
make baseline
# or, naming the file after the asset tag:
./scripts/audit-secureboot.sh docs/baseline/lab1-pc01.txt
```

Read-only; makes no changes. Records boot mode, Secure Boot state, setup mode,
signed boot chain packages, enrolled Machine Owner Keys, and firmware boot
entries. Each report ends with a machine-readable summary line suitable for the
firmware register.

## Appendix C — Glossary

| Term | Meaning |
|---|---|
| **Secure Boot** | Firmware feature that verifies each boot stage is cryptographically signed before running it |
| **Signed boot chain** | Vendor-signed sequence: firmware → shim → bootloader → kernel |
| **MOK** | Machine Owner Key — the sanctioned way to add a key for third-party drivers |
| **Metapackage** | A package that installs nothing itself but pulls in a defined set of others |
| **Live-build** | Tool that assembles a bootable distribution image from a package list |
| **Compatibility layer** | Software translating one OS's system calls to another; Wine is one, not an emulator |
| **PXE** | Network boot, allowing PCs to be imaged without physical media |

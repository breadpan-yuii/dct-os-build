# Licensing — what you can and cannot put in Dominican OS

Not legal advice. Enough to keep a school project out of trouble and to answer
the questions an IT reviewer will ask.

## The one-line version

**Dominican OS is an internally deployed institutional image built on Ubuntu 24.04 LTS.**
Say that in the proposal and most of this document becomes irrelevant. The
problems only start if you call it a public distribution or derive it from
Zorin's ISO.

---

## 1. Zorin OS

Zorin OS is free to download, install and use. What you may **not** do is use
their name, logo, or ship a modified copy of their ISO:

> You may not modify, rent, lease, sell, distribute, or create derivative works
> based on the Services unless we have given prior written consent.
> — [zorin.com/legal/terms](https://zorin.com/legal/terms/)

Their ToS also says the terms "do not apply to any of our products", and that
per-package terms live in `/usr/share/doc/<pkg>/copyright`. So the open-source
*components* inside Zorin are governed by their own licences — but Zorin's own
artwork, themes and trademarks are not yours to reuse.

**Therefore:** do not build Dominican OS from a Zorin ISO. Build from Ubuntu 24.04 LTS
(the same base Zorin 18 uses) and create your own assets. If you want to reuse a
specific Zorin component, read its licence in `/usr/share/doc/<pkg>/copyright`
first, and prefer to reimplement.

Cost of getting this wrong: a takedown request, and an embarrassing correction in
a school document.

## 2. Ubuntu and Canonical

Canonical's [IPRights policy](https://canonical.com/legal/intellectual-property-policy)
permits:

- downloading, installing, updating — free
- **modifying Ubuntu for your organisation's own internal use** — explicitly allowed
- redistributing **unmodified** Ubuntu — allowed

And restricts:

- redistributing a **modified** Ubuntu under Canonical's trademarks — needs a
  licence agreement
- using `Ubuntu`, `Kubuntu`, `Edubuntu` etc. in your name

**Therefore:** internal deployment to DCT-owned machines is squarely permitted.
Name it `Dominican OS`, not `DCT Ubuntu`, and do not use the Ubuntu logo as your own.
Keeping `ID_LIKE=ubuntu` and `UBUNTU_CODENAME=noble` in `/etc/os-release` is
correct and necessary — that is metadata for apt, not branding.

If DCT ever wants to hand the image to another school, that changes the analysis.
Talk to Canonical then, not now.

## 3. GPL / AGPL obligations

Every package you redistribute carries its own licence. Practically:

- `/usr/share/doc/<pkg>/copyright` is already installed by every package. Do not
  delete it. That satisfies the notice requirement.
- You are redistributing binaries, so you must be able to supply **source** on
  request. Two easy options: point to Ubuntu's source archive, or run
  `apt-get source` capability on your campus mirror.
- For your own `dct-os-*` packages, publish the source in the school's Git
  (this repo) and state it in the copyright file. Already done.

## 4. OnlyOffice

- Licence: **AGPLv3**.
- Free to redistribute unmodified, including in an institution image.
- AGPL's network clause does not apply to you: you are distributing software, not
  running a modified OnlyOffice as a public web service.
- If DCT modifies OnlyOffice itself, they must publish those modifications.

**Verdict: safe, and the best default office suite for this project.**

## 5. LibreOffice

MPL/LGPL. Completely fine. Trim locales to shrink the ISO — nothing legal about
that, just size.

## 6. Wine and Microsoft Office — the part that bites

Two separate things:

**Wine** is LGPL. Bundling it is fine. It is a compatibility layer (API
translation), not an emulator — say "Wine compatibility layer" in the proposal,
not "Wine emulated MS Office", because a technical reviewer will notice.

**Microsoft Office** is proprietary. You may not:

- put the installer, ISO, or licence key in your image
- redistribute it to students

You may install it on a machine DCT owns **if** DCT holds a licence for that
machine. Check whether DCT has a Microsoft **EES / OVS-ES** campus agreement —
many Philippine HEIs do, and it often covers staff and lab machines.

If they do, the correct design is a **first-boot helper script** that installs
from DCT-supplied media, run only on licensed machines:

```
dct-office-setup/          # NOT in the ISO
    office-2019-x64.img     # DCT-supplied, kept on the file server
    install.sh              # winetricks + wine tweaks, then run setup
```

Also note: Office 2016/2019 under Wine mostly works; 2021 is unreliable;
Microsoft 365 will not activate. Do not promise any of them as a deliverable.

**Recommended: OnlyOffice as the default, LibreOffice as fallback, Wine present
and configured, Office installation available only where licensed.** Frame it in
the proposal as *"supports installation of licensed Microsoft Office"* — never as
*"includes Microsoft Office"*.

## 7. Fonts

Only ship fonts you can redistribute:

| OK | Not OK |
|---|---|
| Inter (OFL) | Calibri, Arial, Segoe UI |
| JetBrains Mono (OFL) | Most brand/display typefaces |
| Noto, DejaVu, Liberation | Anything from a foundry without a redistribution clause |

If DCT's brand sheet specifies a proprietary typeface, use it only in print
material, and use Inter in the OS.

## 8. DCT's own marks

Using the institutional name and seal on an OS image is a **separate approval**
from "this is a DCT student project". Get it in writing, from whoever owns
communications/branding, and keep the letter in the project file. Add the file to
`payload/assets/`.

## 9. The disclaimer

Put this in the About screen and in the README:

> Dominican OS is built on Ubuntu 24.04 LTS. Not affiliated with Zorin OS or Canonical.
> Ubuntu is a trademark of Canonical Ltd. Zorin OS is a trademark of Zorin OS
> Technologies Ltd.

## Checklist for the proposal

- [ ] Written DCT approval to use the name and seal
- [ ] Documented decision: internal deployment only, not public distribution
- [ ] No Zorin artwork or ISO content anywhere in the build
- [ ] Source offer stated for GPL/AGPL packages
- [ ] MS Office described as "supported where licensed", never "included"
- [ ] Fonts confirmed as OFL or equivalent
- [ ] Disclaimer on the About screen

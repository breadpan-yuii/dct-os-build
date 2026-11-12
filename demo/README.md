# Demo material

Generated files. Do not hand-edit — change `payload/branding/tokens.env` (or the
SVG templates in `scripts/make-demo-mockups.sh`) and re-run:

```bash
make demo
```

## `mockups/`

Five 1920×1080 renders of the branded screens: `grub`, `plymouth`, `installer`,
`login`, `desktop`.

These are **design renders, not screenshots of a running system.** Every slide
caption must say so. See `docs/demo.md` for what each tier of demo lets you
claim.

## Read this first

`docs/demo.md` — the runbook. Tier 0 (these renders) → Tier 1 (branding applied
to a real VM) → Tier 2 (bootable ISO).

Optional Offline Vazirmatn Font Bundling
---------------------------------------
By default, Karen Next 2.1 loads Vazirmatn (Regular 400, Medium 500, Bold 700)
via the `google_fonts` package with bundled SIL-OFL `NotoSansArabic`
(Regular, Medium, Bold) as an immediate offline Persian fallback.

For 100% offline Vazirmatn rendering even on the very first launch without
internet access, run `scripts/fetch_vazirmatn_offline.sh` (or `.ps1`), or place
the official SIL-OFL font files in this directory:
  - Vazirmatn-Regular.ttf
  - Vazirmatn-Medium.ttf
  - Vazirmatn-Bold.ttf

`google_fonts` automatically detects and loads them from `assets/google_fonts/`
without making network requests.

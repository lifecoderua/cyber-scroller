# Asset shortlist (research only, nothing downloaded)

Licenses and URLs were read from the actual pages on 2026-10-16. Re-check the license on the page before
downloading and keep a copy of the license text next to imported files
(for example `assets/third_party/<pack>/LICENSE.txt`).

The game currently uses procedural sprites from ASCII templates at 16x24, so roughly 16-32 px tall humanoids fit
best. The project texture filter is Nearest and the viewport is 360x640 (portrait).

## Shortlist

| Name | Author | URL | License (as shown on page) | Covers | Style / size | Fit |
|---|---|---|---|---|---|---|
| Warped City | ansimuz (Luis Zuno) | https://opengameart.org/content/warped-city | Art: CC0. Bundled music by Pascal Belisle requires credit | 16x16 city tileset, 3-layer parallax background, props/FX, hero with 10 anims (walk, run, shoot, jump, idle, hurt...), 2 animated enemies, 4 vehicles | Cyberpunk, 16x16 tiles, platformer-ready; character sizes not stated on the page (verify) | 5/5 backgrounds and tiles; 3/5 characters (few enemies) |
| Future City 27 | knekko | https://opengameart.org/content/future-city-27 | CC0 | 16x16 tilesheets (clean, gritty, slum), alley tiles, cars, simple characters | Cyberpunk city, 16x16 grid | 4/5 (variety) |
| Cyber City | warlloyd | https://opengameart.org/content/cyber-city | CC0 | Cyberpunk tileset and sprites, sprite templates | 64x64 sprites (too large next to 16x24 runners) | 2/5 |
| Kenney Pixel UI Pack | Kenney | https://kenney.nl/assets/pixel-ui-pack | CC0 | Panels, buttons, UI pieces | Pixel UI, neutral colors (tint with `modulate` for neon) | 4/5 |
| Kenney Fonts | Kenney | https://kenney.nl/assets/kenney-fonts | CC0 (11 files; page does not list names, so verify which pixel fonts are inside) | Pixel/blocky fonts | Pixel | 4/5 |
| Public Pixel Font | GGBotNet | https://opengameart.org/content/public-pixel-font (also https://ggbot.itch.io/public-pixel-font) | CC0 (credit optional) | TTF, 1324 glyphs, 98 languages, monospace on an 8x8 grid | Use at 8/16/32 px; crisp at our 2x scale | 5/5 for UI text |
| Kenney Interface Sounds | Kenney | https://kenney.nl/assets/interface-sounds | CC0 | 100 UI clicks/blips/confirms | Clean, short | 5/5 |
| Kenney Digital Audio | Kenney | https://kenney.nl/assets/digital-audio | CC0 | 60 digital/laser/tone SFX | Digital, 8-bit-ish | 4/5 (hacks, soft casts) |
| Kenney Sci-fi Sounds | Kenney | https://kenney.nl/assets/sci-fi-sounds | CC0 | 70 sci-fi SFX (lasers, engines) | Clean sci-fi | 4/5 (shots, quickhacks) |
| Kenney Impact Sounds | Kenney | https://kenney.nl/assets/impact-sounds | CC0 | 130 impact/foley hits | Realistic | 4/5 (melee, hits) |
| Pynchon (loop) | cinameng (credit: James Gargette) | https://opengameart.org/content/pynchon | CC0 (credit noted, not required) | Short cyberpunk glitch/lo-fi synth loop, MP3 1.3 MB | Moody, loopable | 4/5 (hub/menu) |
| Cool 80's Synth Wave | Pro Sensory (Alex McCulloch) | https://opengameart.org/content/space-synth-wave | CC0 (attribution not required) | Synthwave track, WAV 33.9 MB (convert to OGG) | 80s synthwave, tagged battle | 4/5 (missions) |
| Pixel Platformer | Kenney | https://kenney.nl/assets/pixel-platformer | CC0 | 18x18 tiles, characters, backgrounds | Cute, not cyberpunk | 2/5 (placeholders only) |
| Chrome District | booliebuilds | https://booliebuilds.itch.io/chrome-district | Contradictory: body says CC0 1.0, metadata says CC-BY 4.0 | 20 cyberpunk characters, 8-direction walk cycles only (no attacks) | 56x84 px cells, top-down/ortho views | 1/5 (view, size, unclear license) |

Reviewed and rejected: Cyberpunk Tileset Slim (overcrafted; demo subset of a paid pack), "enemy slave"
(page claims exclusive rights), and OpenGameArt mixes/remixes that combine CC0 with CC-BY tracks (check each page).

## Recommended combo

- **Backgrounds and tiles**: Warped City (parallax + 16x16 tiles), supplemented by Future City 27 for variety
  and alley/slum districts. Both are CC0 and share the 16x16 grid.
- **Characters/enemies**: keep the procedural 16x24 ASCII sprites (they match the tile scale). Optionally use
  Warped City's hero/enemies as extra enemy types or references. No CC0 cyberpunk pack with attack animations at
  16-32 px and a verifiably clean license was found.
- **UI**: Public Pixel Font (CC0, 8x8 grid) for all text, with the Kenney Pixel UI Pack for panels and buttons,
  tinted with the game's neon palette on #0b0b18.
- **SFX**: Kenney Interface Sounds (UI), Digital Audio and Sci-fi Sounds (casts, hacks, shots), Impact Sounds
  (melee, hits, deaths). All CC0 from one author, so the mix is consistent.
- **Music**: Cool 80's Synth Wave for missions, Pynchon for the safehouse hub. Both CC0. Convert to OGG Vorbis;
  the WAV is about 34 MB, too big for web and mobile.
- If Warped City's bundled music is used, credit Pascal Belisle in a credits screen. Not needed for this combo.

## Import notes

- Import pixel art with the Nearest filter, no mipmaps, and VRAM compression off for small sprites (lossy
  compression smears pixels).
- Convert audio to OGG, mono for SFX; keep the web download small.
- Keep a `CREDITS.md` listing every pack, author and license, even for CC0.

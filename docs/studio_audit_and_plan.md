# Viyo Studio: audit and plan for a full AI drama studio

5 Nov 2026. I checked the code in `viyo_ai` (creator_studio.py, studio_ai.py, studio_worker.py, studio_render.py, studio_pricing.py, studio_sfx.py, creator_studio_schema.sql) and the Flutter Studio screens. I checked provider facts against Google's pricing and speech docs today.

No real AI has been tested yet because Gemini billing is blocked. Everything marked "works" below is tested with fake providers and a local database only.

---

## 1. What already works (tested with fakes)

| Area | Status |
|---|---|
| Credits ledger | Works. Purchase and grant lots, a hold before every job, the real cost taken after, the rest returned, a full refund on failure, no double charges (idempotency keys). |
| Job queue | Works. Durable jobs in Postgres, claim, heartbeat and lease. Jobs left by a crashed worker are picked up again after 180 s. Cancel works. Separate lanes for generation and render. A rate limit applies per user. |
| Screenplay | Works. Uses the project's idea, genre, format, length, language and aspect ratio. The creator can edit the script. |
| Breakdown | Works. Finds the characters and splits the script into scenes, each with one visual, the dialogue and a duration. |
| Character portraits | Works. One portrait per character, used as a reference image for every scene image of that character (up to 4 references). |
| Voices | Partial. One Gemini prebuilt voice is picked per character by gender, saved on the character, and reused for every line. One TTS call per line, then the lines are joined. |
| Scene visuals | Works. One image per scene with the character references, or one Omni video clip that starts from that image. |
| Sound | Works. Uploaded background music with ducking under speech, the video clip's own sound kept, and 8 built-in sound effects. |
| Render | Works. FFmpeg slow push-in on stills, burned-in captions, loudness levelled, 9:16 or 16:9, H.264 CRF 19. The finished film goes to Bunny Stream. |
| Download | Works. Bunny's best MP4 or a signed link. Creator downloads from My Productions were tested live. |
| Estimate | Works. A server-side price before every job, shown in credits. |

## 2. Partial or placeholder

- **Video model is out of date.** The code uses `gemini-omni-1.1-flash` at about $0.10/s. Google launched **`gemini-omni-1.2-flash`** today: GA, $0.07/s at 720p, 3–15 s clips, better reference adherence, native dialogue and lip sync. 1.1 requests get routed to 1.2 from 3 Dec 2026. We currently overcharge by about 30% for video.
- **Video ignores the cast.** The video prompt gets the scene's first frame and the character descriptions, but not the character reference images.
- **`series_id` is not used.** Characters belong to one project, so nothing carries over to the next episode.
- **Batch buttons exist per step** (for example "Make 4 portraits"), but there is no single "make my episode" flow.
- **Captions are burned in only.** There is one version per render: no clean copy and no .srt file.

## 3. Missing

- Story concepts ("give me 3 ideas, I pick one").
- Series continuity bible (characters, relationships, events, open storylines, locations).
- Saved locations and wardrobe (looks).
- Shots inside scenes (establishing, close-up, reaction).
- **Automatic background music.** Today the creator must upload their own, which breaks your main rule.
- Automatic sound effect choice. The creator ticks effects by hand.
- Transitions between scenes (cuts only today).
- Production budget: approve one total, pause if it would go over.
- Production presets (Economy / Standard / Premium).
- Publish from Studio to Viyo Watch.
- Clean and captioned downloads, quality options.
- A screen to listen to voices before choosing.
- Rights and licensing notice before production.

## 4. Things that would leave a paying creator stuck: fix before launch

1. **Credits can't be bought.** `checkout_available` is false. Only the admin grant works. On Android, Google Play rules require Play Billing for credits sold inside the app. Lemon Squeezy is only allowed on the website, and the app must not point people to it.
2. **Gemini billing is blocked.** No real image, voice or video has ever been made. This blocks everything.
3. **Running "breakdown" again deletes every scene,** including the scene images and voices already paid for (`studio_worker.do_breakdown`). The files stay in storage but are no longer linked to anything. This must become "add or update" with a confirmation step.
4. **Per-job charging, no production budget.** A creator can run out of credits halfway through an episode.
5. **Silent voice swap.** If a saved voice name is unknown, the line is voiced as the narrator without telling anyone (`do_voice`). It should fail clearly instead.
6. **The breakdown is not given the language.** The language field is dropped from the breakdown brief. The script prompt does get it.
7. **No built-in music.** See section 3.

## 5. Providers: what to use and what it costs (prices checked today on Google's pricing page)

| Need | Choice | Price | Notes |
|---|---|---|---|
| Script, concepts, shot list, music and sound choice | `gemini-3.8-flash` | $0.75 in / $3.75 out per M tokens (**double from 1 Jan 2027**) | Already used |
| Images (portraits, locations, shots) | `gemini-3.1-flash-image` | $0.067 at 1K, $0.101 at 2K | Already used; accepts reference images |
| Voices | `gemini-3.8-flash-tts` | $9 per M audio tokens = **$0.0135 per minute** (**$0.027 from 2027**) | 30 prebuilt voices, 130+ languages including Kinyarwanda, Swahili and French; language is detected automatically |
| Video | `gemini-omni-1.2-flash` | **$0.07/s** at 720p ($0.023 at 360p, $0.104 at 1080p upscaled) | Character and style references, native dialogue and lip sync (Google's claim, untested) |
| Music | `lyria-3.5` (Gemini API) | **$0.08 per song** | Made fresh for each film; carries a SynthID watermark; rights governed by the Gemini API terms (see section 7) |
| Sound effects | Viyo's own synthesised effects + a curated CC0 pack | $0 | No licence risk for synthesised or CC0 files |
| Hosting | Bunny Stream (already used) | about $0.005/GB delivered | — |

Voice is almost free, video is the expensive part, and music by Lyria is cheaper than any music library.

## 6. Voice identity: what Gemini can and can't promise

**What Google's docs say:**
- Prebuilt voice names (Kore, Puck…) are fixed: the same name gives the same voice timbre.
- Delivery still changes from line to line. There is no seed and no way to get identical output twice. Google advises keeping the style instruction empty or reusing one short string so the voice drifts less.
- Emotion goes in `speech_metadata.style` per line, and inline tags like `<sigh>` and `<laugh>` are supported.
- Age, gender and accent should come from the voice choice, not from style text.
- Multi-speaker calls allow at most 2 speakers, so one call per line, as we do now, is right for a cast.

**Designed voices** (`POST /v1beta/voices`, a new voice made from a text description) are possible on 3.8 TTS, but:
- **only 200 per Google project, shared by all Viyo users;**
- they are deleted after a year of not being used.

That cannot be a permanent identity for thousands of characters. **Recommendation:** use prebuilt voices as the permanent identity now, and later offer designed voices only as a small Premium extra. Voice cloning stays out, as you asked.

**Is Gemini enough?** For consistent timbre, yes, if we store the voice and keep style short. We can't promise an identical performance every time; no provider can without cloning. I didn't compare other providers because Gemini meets the need and costs about a cent per minute. If a live listening test fails, I will compare others then.

**The plan** (stage 1 below):
- The character record stores `voice_provider`, `voice_id`, `voice_style` (one short, fixed delivery note), `voice_language`, `voice_locked_at` and a history of changes.
- Each dialogue line can carry an optional `emotion` for that line only.
- Voices are assigned once, when the character is created, and never re-picked: not on breakdown, not on regenerate, not on a new episode.
- A voice gallery with a short sample for each of the 30 voices. The samples are made once by admin for about $0.02 total and cached.
- Changing a voice shows: "Lines already recorded keep the old voice. New and regenerated lines will use the new one. Regenerate N recorded scenes for X credits?"
- An unknown voice makes the job fail with a clear message and returns the credits. No silent swap.
- Tests: the same character in 3 scenes and in episode 2; regenerated dialogue uses the same voice; a voice change is respected; refunds on TTS failure.

## 7. Rights and licensing (honest version)

- **Gemini images, video, voices and Lyria music:** Google's Gemini API terms say Google does not claim ownership of output, and the developer (Viyo) is responsible for how output is used and shared. All of it carries an invisible SynthID watermark. AI-made material may not be protected by copyright in many countries, so we must not tell creators they "own all rights". I could not find a Lyria-specific commercial licence page; **read the current Gemini API terms and Lyria usage policy yourself before launch.**
- **Library music options considered:**
  - Pixabay allows its music inside a bigger work, but not as a downloadable track, and it has no music API.
  - Epidemic Sound's partner API only gives a commercial licence to users with their *own* paid Epidemic subscription, which breaks your "creator never supplies anything" rule. It also needs a contract.
  - **So: Lyria for the music Viyo makes for you, uploads as an option.**
- **Sound effects:** Viyo's synthesised effects plus files we check are CC0. Store the source and licence for every file.
- **Uploads:** keep the "I have the rights" checkbox, which already exists for music.
- **Real people:** the script prompt already forbids real people. Add the same rule to portraits and a check on character names.
- **Notice before production:** "Your film is yours to download and share on any platform. Parts are made by AI (Google). AI-made work may not be protected by copyright. Don't use real people, brands or other people's music."
- **Takedowns:** a "Report" button and a copyright contact (email) on viyo.site/legal, with a remove-and-review flow. Check what exists in Watch before building this.

## 8. Continuity: what the models can and can't do

- Image references keep a face *recognisable* most of the time. Hair, clothes, hands and backgrounds still drift. Omni 1.2 claims better reference adherence, but Google publishes no numbers.
- **No model guarantees the same person in every shot. Viyo must not promise it.**
- What helps:
  - a character sheet (front, ¾ and full-body portraits) per look;
  - a reference image per location;
  - one locked style line for the whole series;
  - short shots;
  - reviewing each shot, with one-click regeneration of a single shot.
- **Lip sync:** Gemini TTS voices and Omni's built-in dialogue are *different voices*. Two ways:
  1. **Economy and Standard:** dialogue over stills or non-speaking video (reaction shots, over-the-shoulder, wide shots). No lip sync is needed, and many short dramas cut this way.
  2. **Premium:** Omni speaking shots with the TTS line given as an audio reference. Google says Omni takes audio cues, but whether it lip-syncs to *our* voice is unknown. **It needs a live test of about $2 before we offer it.**

## 9. Architecture: series → episodes → scenes → shots

New tables, added safely on top of the current ones, with nothing dropped:

- `studio_series`: title, premise, genre, locked visual style, aspect ratio, language, and a continuity bible (rules, relationships, open storylines). An episode summary is added after each episode.
- `studio_characters`: add `series_id`, the voice fields above, and `approved_at`. A character belongs to the series, so episode 2 reuses it.
- `studio_looks`: wardrobe per character (name, description, front, ¾ and full-body references).
- `studio_locations`: name, description, lighting, reference image.
- `studio_shots`: scene, order, type (establishing, wide, medium, close-up, reaction, insert), characters and looks, location, camera, lines, duration, still or video, image or video, approved, version.
- `studio_productions`: preset, approved credits, spent, stage, status. One budget for the episode. Jobs draw from it, and it pauses with a question if the next step would go more than 10% over.

The worker stays as it is, with new job kinds (concepts, location, look, shot image, shot video, music). The render works on shots instead of scenes and adds xfade transitions, an .srt file and a clean version.

## 10. Real cost per episode (90 s, vertical, 8 scenes, about 24 shots, 4 characters, 3 locations, 60 s of dialogue)

| Part | Economy | Standard | Premium |
|---|---|---|---|
| Concepts + script + shot list | $0.08 | $0.08 | $0.08 |
| Character sheets (4 × 3) + 3 locations | $1.00 | $1.00 | $1.00 |
| 24 shot images (1K) | $1.61 | $1.61 | $2.42 (2K) |
| Video shots (720p) | — | 6 × 6 s = $2.52 | 16 × 6 s = $6.72 |
| Voices (60 s) | $0.01 | $0.01 | $0.01 |
| Music (2 Lyria tracks) | $0.16 | $0.16 | $0.16 |
| Sound effects, render, storage, delivery | ~$0.02 | ~$0.02 | ~$0.03 |
| Regeneration allowance (20%) | $0.55 | $1.05 | $2.10 |
| **Provider cost** | **≈ $3.40** | **≈ $6.45** | **≈ $12.50** |
| Credits at 25% margin | ≈ 455 | ≈ 860 | ≈ 1,670 |
| What the creator pays (incl. 6.5% + $0.50 card fee) | ≈ $5.40 | ≈ $9.70 | ≈ $18.40 |

- From 1 Jan 2027, text and voice prices double. That adds less than $0.15 per episode.
- These are calculations from list prices, not measurements. The first live test will check them.
- **Suggested margins:**
  - images, music and render: 25%;
  - video: 35%, because video regenerates more often;
  - a small minimum per episode, so the cheap steps (script, voice) aren't run at a loss on retries.
- **Suggested packages:** 1 episode, 5 episodes (about 10% off) and a series of 10 (about 15% off). Extra regeneration credits are sold separately. **No unlimited video.**

## 11. Plan: stages in order (each one tested, deployed and reported before the next)

| # | Stage | Size |
|---|---|---|
| 0 | **Must-fix:** switch to Omni 1.2 at the new price; breakdown never deletes paid assets; no silent voice swap; pass language to the breakdown; then **one live test (about $3–5, needs your OK)** once Gemini billing works | small |
| 1 | **Permanent voice identity** (section 6): voice gallery, change-with-warning, emotion per line, series carry-over, tests | medium |
| 2 | **Series bible + series characters, looks and locations**, with an approval screen for characters | medium |
| 3 | **Shots**: scenes split into shots, a shot editor on desktop and mobile, single-shot regeneration with the price shown first | large |
| 4 | **Production budget + presets + one "Make my episode" button** with real stage progress (writing → characters → shots → voices → music → mixing → rendering → ready) and a pause on overspend | large |
| 5 | **Automatic music (Lyria) + automatic sound effects** chosen from the scene mood, with a crossfade between tracks, plus preview, swap, volume and off | medium |
| 6 | **Render v2 + publish**: transitions, .srt file, clean and captioned versions, quality options from Bunny, publish to Watch (public or private), rights notice | medium |
| 7 | **Concept generator + new-project wizard** (idea → 3 concepts → choose) | small |
| 8 | **Premium video**: Omni 1.2 reference shots and the lip-sync test | medium, needs a paid test |
| — | **Credit checkout:** Lemon Squeezy on the website now; Play Billing for Android later | separate |

## 12. Delay for now

- Designed and cloned voices (the 200-voice cap, deletion after a year).
- Full-episode AI video.
- 1080p and 4K upscaled video (costs 1.5–3×).
- Lip sync until it's tested.
- Dubbing into several languages.
- Epidemic Sound or other licensed libraries.

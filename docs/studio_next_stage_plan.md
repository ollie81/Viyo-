# Viyo Studio: next stage plan (live validation, music, video audio, episode budget, "Make my episode")

Claude, 6 Nov 2026. Plan only: no code has been changed for this stage yet. I checked the facts below in the code (`viyo_ai`: studio_ai.py, studio_worker.py, studio_render.py, studio_pricing.py, creator_studio.py, creator_studio_schema.sql) and on Google's docs pages today: Omni, music generation, Gemini API terms and available regions.

## What I found today that changes the plan

1. **Omni cannot lip-sync to our voices.** Google's Omni docs say: *"Uploading audio inputs or audio references is unsupported in the current version of the API"* and *"Voice editing is not supported."*
   - There is no way to hand Omni a Gemini TTS line and have the character's mouth match it.
   - Omni's own speech is a voice we don't choose, so it can't be a character's permanent voice.
   - There is no "silent" setting. Audio is steered only by the prompt ("No dialogue", "No extra sound effects"), and Google doesn't promise full silence.
2. **Lyria 3.5 is real and simple.**
   - Model `lyria-3.5`, called with `client.interactions.create`.
   - Output is MP3 by default, 44.1 kHz stereo. Songs run "a couple of minutes", and length is only *influenced* by the prompt.
   - Instrumental is asked for in the prompt ("Instrumental only, no vocals").
   - Each call makes one song; it can't be edited afterwards.
   - The SynthID watermark can't be heard.
   - Price on Google's pricing page: $0.08 per song.
3. **Google's terms (effective 23 Mar 2026):**
   - *"Google won't claim ownership over that content"* and *"You're responsible for your use of generated content, and for the use of that content by anyone you share it with."*
   - There is **no indemnity** and no music-specific rule.
   - Apps may be offered *"within an available region"*. **Rwanda, Kenya, Uganda, Nigeria and Tanzania are all listed.**
   - Users must be 18+.
   - There is no explicit sentence saying "commercial use of output is allowed". That's why the owner should read the terms and the Generative AI Prohibited Use Policy before paid downloads with AI music go live.
4. **The credit ledger can carry an episode budget without being rewritten.** `_studio_hold` already takes credits out of the creator's lots into a hold, and `_studio_settle` returns the unused part to the same lots. A budget is one big hold that the episode's jobs draw from.

---

## 1. Real AI validation (after billing is restored)

**What I'll build first, without spending anything:** `scripts/studio_live_check.py`, run by hand and never by the app.
- **Hard spending cap:** it adds up the estimated cost before every call and stops at **$5.00**, even mid-run.
- **Approval step:** it refuses to run without `--i-approve-spend`.
- **Scope:** it makes one tiny 2-scene production through the *real* worker code (not a copy), so it tests what creators would use.

**What the live check covers:**

| # | Call | What it checks | Est. cost |
|---|---|---|---|
| 1 | Script, gemini-3.8-flash, English + Kinyarwanda | format, language kept, length | ~$0.02 |
| 2 | Breakdown | JSON valid, dialogue not translated, emotions, moods | ~$0.02 |
| 3 | 2 portraits (1K) | face, no text or watermark | $0.13 |
| 4 | 4 scene images with portrait references (1K) + 1 at 2K | is the face recognisable across scenes | ~$0.37 |
| 5 | TTS: every line + 30 voice samples (~6 s each) | right voice, WAV handling, language, style tags | ~$0.05 |
| 6 | Omni 1.2: 2 test clips, 6 s each (see section 3) | quality, real length, real cost, audio | $0.84 |
| 7 | Omni 1.2: 1 clip with 2 portraits as references, 6 s | does the face match the reference | $0.42 |
| 8 | Lyria 3.5: 2 instrumental tracks | instrumental only, length, MP3 decode | $0.16 |
| 9 | FFmpeg render of the whole thing | sync, loudness, captions, music ducking | $0 (our CPU) |
| | **Expected total** | | **≈ $2.00 (hard cap $5)** |

**How costs are measured:**
- I'll record the token counts and seconds that Google returns for every call, and work out cost from Google's list prices.
- The owner then compares the total with the **Google Cloud billing report** the next day, which is the real number.
- Any difference above 10% means the price table gets fixed before anything is sold.

**How quality is inspected:**
- **Pictures and frames:** I can look at the images and frames taken from the videos, and check faces across scenes, stray text and framing.
- **Sound measurements:** I can measure duration, loudness, silence and clipping with ffmpeg.
- **Words and language:** I can check that the words spoken match the script by asking Gemini to transcribe the audio (costs under 1 cent).
- **Listening:** **I cannot listen.** The owner must listen to the voices, music and final film and judge them. I'll make a one-page report with every file, its cost, and what to listen for.

**How it runs:**
- The test runs where the API key lives. Either the owner saves the Gemini key as a secured credential for this cloud environment (the key never appears in chat or code), or I add an admin-only endpoint on Railway that runs the same script.
- **Needs from the owner:** working Gemini billing, approval of the ~$2 test ($5 cap), and the key saved securely.

## 2. Automatic music (Lyria 3.5)

The music upload, ducking under speech, looping and fades already exist (`studio_render.add_music`, creator upload). We build on those; nothing is duplicated.

**Plan:**
1. **Mood per scene, at no extra cost:** add `mood` (fixed list: tense, romantic, sad, hopeful, action, comedic, mysterious, calm) and `sfx` (our 8 effects, at most 2, only when they help) to the breakdown schema. It's the same AI call we already make.
2. **Music plan:** group the scenes into **1 or 2 parts** by mood, for example "tense → hopeful" at the scene where the mood turns. The part lengths come from the scene durations.
3. **New job type `music`**, one per part, with a server-set price of $0.08 per song (from the price table).
   - Prompt: "Instrumental only, no vocals, no lyrics. {mood} cinematic underscore for a {genre} short drama. About {N} seconds. Steady, unobtrusive, leaves room for dialogue."
   - The MP3 is checked (decodes, has sound, is long enough), stored privately, and recorded in the asset history.
   - If Lyria's safety filter refuses it, the creator gets a full refund.
4. **Render:** if a song is longer than its part, it is trimmed with a fade; if shorter, it loops with a crossfade. Two parts are joined with a 2 s crossfade at the scene boundary. The existing ducking under speech stays.
5. **Creator controls:** listen to each track, make a new one (shows the price), switch it off, set the volume (already exists), or upload their own (already exists, and the upload wins).
6. **Safety switch:** music generation stays behind `STUDIO_AI_MUSIC_ENABLED=false` until the live test passes and the owner has read the terms. Before then, the plan falls back to "no music" and **says so in the quote**. It never quietly produces a film without music.
7. **New table `studio_music_tracks`:** project, part start and end scene, mood, prompt, path, seconds, job, status. The single `music_path` that already exists stays for uploads.

**Tests (with fake AI):**
- the Lyria request matches Google's documented shape, read from a fake client;
- mood grouping into 1–2 parts;
- the render with 2 parts and a crossfade, where the music measures quieter under speech;
- refund on failure and on a safety refusal;
- an upload replaces AI music;
- music switched off;
- the safety switch off gives an honest quote.

## 3. Video audio and lip sync

Omni takes no audio input, so the permanent voice system (TTS) and Omni's own speech **cannot both be the character's voice**. Proposed rule: **dialogue always comes from the character's permanent TTS voice.**

**Live comparison (part of the $2 test):** the same 6-second dialogue scene made three ways:
- **A. Omni speaks the line.** Prompt includes the dialogue. This shows lip-sync quality, but with an unknown voice.
- **B. Omni with no dialogue, plus our TTS.** Prompt: "No dialogue. The character listens and reacts, mouth closed. Natural room sound." Omni's audio is replaced by the character's TTS line, our sound effects and music.
- **C. Still image with camera movement, plus our TTS** (Economy). Costs 1/6 of B.

The owner watches all three. My expectations, to be confirmed by the test:
- A will look best but **breaks voice identity** across scenes and episodes, so it can't be used for named characters.
- B will look cinematic with the correct voice, but nobody's mouth matches the words. Editing around that (reaction shots, the speaker turned away, wide shots) is how dubbed and many AI dramas cut.
- C is the cheapest and steadiest.

**Changes after the test (small):**
- In `do_video`, add "No dialogue. No speech." to the prompt for scenes that have lines.
- In `render_scene`, **don't play Omni's audio under dialogue** (today it plays at 30% volume, which could leak stray Omni speech). Keep Omni's audio only on scenes without dialogue, where it's useful ambience.
- Store the decision per scene (`video_audio: native | muted`) so the creator can switch it.
- Nothing in the voice-identity code changes.

**Not promised:** lip-synced talking characters. That waits until Google allows an audio reference, or until another provider with real "lip-sync to this audio" is costed and tested separately.

## 4. Complete episode budget

**The quote, before anything is made.** It comes from the price functions that already exist (`_price` / `pricing.*`), so the quote and the actual charges use the same formulas:

| Stage | Before the script exists | After the breakdown |
|---|---|---|
| Script + breakdown | from the target length | actual |
| Portraits | estimated cast (3–4) | actual cast without a portrait |
| Scene images | about target length ÷ 6 s | actual scenes without a picture |
| AI video | per preset share of scenes | actual scenes chosen for video |
| Voices | about 70% of the runtime as speech | actual lines |
| Music | 1–2 songs | actual parts |
| Sound effects | $0 (ours) | $0 |
| Render + storage + delivery | from runtime | from runtime |
| Allowance for redoing items | 15% of the AI items | same |

**Presets** use what the system can actually do today: one picture or clip per scene. The shots-per-scene stage comes later.
- **Economy:** stills with camera movement, voices, music, sound effects, render, 1K.
- **Standard:** Economy, plus AI video for up to 1 in 4 scenes. The AI picks scenes without dialogue (action, establishing shots).
- **Premium:** Standard, plus 2K images and AI video for up to 3 in 5 scenes.

**What the creator sees before paying:**
- the total in credits;
- each stage's share;
- what's included (all the essential steps) and what's optional;
- the expected length;
- "Up to X credits reserved; unused credits come back";
- the limits (no lip sync, faces may vary slightly);
- whether AI music is on.

**Money mechanics.** New SQL (additions only; existing functions untouched):
- **Table `studio_productions`:** project, owner, preset, quote, approved_credits, reserve_hold_id, reserved_left, spent, status, stage, pause_reason.
- **`studio_approve_production`:** reserves `quote × 1.10` with the existing `_studio_hold` in one step. If the creator lacks credits, they see that **before** anything starts.
- **`studio_create_job` gets an optional `p_production`.** When it's set, the job draws its estimate from `reserved_left` instead of the creator's free credits. If `reserved_left` would go below zero, the job isn't created and the result is `over_budget`.
- **Complete:** `spent += actual`, and `reserved_left += estimate − actual`. **Fail:** `reserved_left += estimate` (full refund to the reserve).
- **Finish or cancel:** `_studio_settle(reserve_hold, spent)` returns every unused credit to the creator's lots, newest first, the same as single jobs today.
- **Re-quote after the breakdown:** if the exact quote is more than **10%** above the approved amount, the episode **pauses**. The creator sees the new total and the reason (for example "your script has 14 scenes, not 9") and can approve the extra, simplify, or stop. If they approve, a second hold is added for the difference.
- **Result:** a creator can never be asked mid-episode to buy something essential without being stopped and shown why first. If they stop, they keep everything made so far and get the unused credits back.

**Tests:**
- reserve, draw, return, settle, and the totals add up;
- over budget pauses, and approving the extra resumes;
- cancel mid-episode returns the remainder;
- a failed job goes back to the reserve;
- double approve gives one reserve;
- not enough credits at approval;
- single jobs (outside an episode) behave exactly as before.

## 5. "Make my episode": how it runs behind the scenes

One button, which starts a **production** that moves through stages. Each stage uses the existing job types, so nothing is rebuilt:

```
quote → approved (credits reserved)
 → script            [optional pause: "Review your script"]
 → breakdown → re-quote (pause if > +10%)
 → portraits         [optional pause: "Approve your cast"]
 → scene images
 → AI video (preset)
 → voices (permanent character voices)
 → music (Lyria, or the creator's upload, or off)
 → sound effects (from the breakdown, no cost)
 → render → saved to Bunny → ready to preview / download / publish
```

- **The driver:** a third worker lane, `production`, wakes every few seconds. For each running episode it looks at the real job states:
  - if a stage has no jobs yet, it creates them, each with an idempotency key based on the episode, stage, item and attempt;
  - if all of a stage's jobs succeeded, it moves to the next stage;
  - if any failed, it retries that item once automatically, then **pauses** with a plain message, for example "Scene 3's picture was refused by the AI. Edit the scene, try again, or skip it".
- **Restart-safe:** the driver keeps nothing in memory. Everything is read from Postgres, and the idempotency keys mean a restart never creates the same job twice.
- **Never skips work already done:** scenes that already have a picture or voice (from earlier manual work or a re-run) aren't made again.
- **Honest progress:** stage names and counts come from real job states, for example "Making scene pictures 5/9". A stage is shown as done only when every one of its jobs succeeded.
- **Controls:** pause, resume, cancel (unused credits come back), and two settings: review the script, approve the cast. Both are on by default. They pause the work but cost nothing.
- **Limits:** at most 1 episode running per creator; the existing 30 open jobs per user still applies. Parallel image calls are spaced out to stay under Google's rate limits.
- **App screen:**
  - one "Make my episode" card: choose a preset, see the quote, approve;
  - a progress timeline with real stages;
  - the pause dialogs;
  - the finished film in preview, download and publish.
  - The current step-by-step screens stay as the "advanced" view.

**Tests (fake AI, real Postgres):**
- idea → downloadable film in one action;
- the driver restarts mid-stage with no duplicates;
- a failure retries once and then pauses;
- the review pauses;
- over budget pauses;
- cancel returns credits;
- existing assets are reused;
- progress never says done for a failed stage;
- app tests for quote and progress.

---

## Order, dependencies and what needs the owner

| Step | What | Needs | Spend |
|---|---|---|---|
| 0 | Merge Stage 0 + 1 (already tested) | Owner runs 2 SQL files, says go | $0 |
| 1 | Build the live-check script with its cap (fake AI tests) | — | $0 |
| 2 | **Live validation** | **Gemini billing + approval + key saved securely** | **~$2 (cap $5)** |
| 3 | Mood and sound effects in the breakdown, music job, two-part music render (behind the switch) | — | $0 |
| 4 | Video audio rule (no Omni audio under dialogue, "No dialogue" prompt) | results of step 2 | $0 |
| 5 | Episode budget SQL + "Make my episode" driver + app screens | owner runs the new SQL | $0 |
| 6 | Second live run: one full 60–90 s episode, all stages | approval | ~$4–7 |
| 7 | Switch AI music on and merge to main | step 6 passed + owner read the terms | $0 |

Nothing new reaches production until its provider has passed a live test (steps 2 and 6). Until then the code is merged behind switches that are off, or stays on the branch.

## Estimated cost per episode (after this stage)

These are the same list-price calculations as in the audit. They're replaced by **measured** numbers after step 2:

| Preset | Our cost | Creator pays (approx.) |
|---|---|---|
| Economy | ~$3.40 | ~$5.40 |
| Standard | ~$6.45 | ~$9.70 |
| Premium | ~$12.50 | ~$18.40 |

The music in these figures (2 × $0.08) was already included.

## Risks

1. **Music rights.** No indemnity, and no explicit "commercial use allowed" sentence. Mitigation: the owner reads the terms; AI music stays off until they have; uploads remain an option.
2. **No lip sync.** Mitigation: the editing approach in section 3, and being clear in the quote.
3. **Native Omni audio may leak speech.** Mitigation: mute it under dialogue.
4. **Lyria song length isn't exact.** Mitigation: trim or loop with crossfades.
5. **Rate limits and refusals from Google.** Mitigation: retry when busy, space out calls, pause with a clear reason (never a silent skip).
6. **Prices change.** Text and TTS double on 1 Jan 2027, which the price table already handles. Re-check the pricing page before launch.
7. **Render time on Railway CPU** for 90 s or more. To be measured in step 6.
8. **I can't judge sound by ear.** The owner listens to every live test.
9. **Buying credits.** There is still no checkout (Lemon Squeezy on the web; Play Billing for Android). Without it, nobody can pay for an episode.

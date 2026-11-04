<!--
2026-11-04-itera-engagement-discovery.md
Created by Amelia Putri Aftiana on 04/11/2026.
-->

# UX Discovery: Keeping stroke rehab sessions engaging (doctor-set duration, up to 90 minutes)

**Scope:** Improve an existing product (Itera, iPad). Exercises, holds, repetitions, calibration and acceptance rules stay exactly as they are. Everything below changes the layer *around* the movement: session structure, presentation, feedback, choice, goals, social support and rewards.

**Session length:** The doctor decides the duration of each session; the maximum is 90 minutes, twice a day. Every recommendation here must therefore **scale to whatever duration is prescribed** (for example 20, 45 or 90 minutes) and must never change it. Where this document says "90 minutes", read it as the worst case.

**Evidence status:** This is based on published research plus a review of the current Itera codebase. It is **not** based on interviews with Itera users. Personas and journeys are hypotheses until they are checked with real stroke survivors and caregivers (see section 8).

**Evidence labels used below**

| Label | Meaning |
| --- | --- |
| 🟢 Strong | Systematic review or meta-analysis in stroke |
| 🟡 Moderate | RCT in stroke, or a robust theory with stroke data |
| 🟠 Emerging | Small or pilot stroke studies, or non-stroke evidence that is plausibly transferable |
| ⚪ Hypothesis | A design inference. Test it before relying on it. |

---

## 1. Problem Brief

- **Problem:** Patients must practise on their own, twice a day, for a duration their doctor sets (up to 90 minutes). The repetitive exercises become boring, and boredom puts adherence, dose and mood at risk. The goal is practice that is fun and interesting but still comfortable for their condition.
- **Affected users:** Stroke survivors doing home hand/arm rehab (primary), family caregivers who set up and support sessions (secondary), and the therapists who prescribe the dose (stakeholder).
- **Current alternatives:** Paper exercise sheets or videos (no feedback), clinic sessions (supervised but rare), commercial games (not built for stroke impairments or fatigue).
- **What Itera already has:** five finger movements plus arm/reach/cup/balance activities, a garden theme where movements move objects into a planter, flowers per completed set, 50 badges, daily streaks, confetti/chime on set completion, an animated rest garden, calm mode, voice commands and a feeling check.
- **Why it still feels boring (diagnosis):**
  1. **The reward loop never changes.** The same object, the same planter and the same chime come every repetition, for 90 minutes. People habituate to a predictable reward quickly.
  2. **The session has no shape.** Sets and rests repeat with no chapters, no midpoint and no visible "how much is left". Fatigue builds and nothing marks progress.
  3. **The patient makes no choices.** Order, theme, sound and pacing are all decided for them. Autonomy is one of the best-supported drivers of motivation in motor learning.
  4. **Practice isn't linked to the patient's own life.** Badges count participation ("50 repetitions") but don't connect to what the person wants back, like holding a cup or buttoning a shirt.
  5. **Practice is solitary.** Nothing involves the caregiver or family emotionally during the session.
  6. **Feedback is about completion, not progress.** The patient rarely hears "you're doing better than before", and positive expectancy is a known motivator.

---

## 2. Why stroke needs different design fundamentals

A general fitness app assumes a healthy, motivated user with spare attention. For stroke survivors, several conditions are common at the same time, and each one changes the design.

| Condition after stroke | How common | What it means for design |
| --- | --- | --- |
| Fatigue | ~50% (Cumming et al., 2016, 🟢) | Treat 90 minutes as several short blocks. Add planned breaks and energy check-ins. Never reward pushing on through fatigue. |
| Depression | ~31% (Hackett & Pickles, 2014, 🟢) | No loss or failure states, no "you broke your streak" shaming, and frequent visible small wins. |
| Apathy (reduced initiation, separate from sadness) | ~1 in 3 (Caeiro et al., 2013, 🟢) | Starting is the hardest part. Make start one tap, let the caregiver prompt, and make the first minutes the easiest and most enjoyable. |
| Spatial neglect | ~30% after unilateral stroke (Esposito et al., 2020, 🟢) | Keep critical information and rewards near the centre. Don't signal progress only at one screen edge. |
| Aphasia | 7–77% depending on how and when it's measured (Frederick et al., 2022) | Use icons, voice and very short text together. Never rely on reading alone. |
| Post-stroke seizure risk | Stroke is a leading cause of seizures in older adults | Respect photosensitivity limits: no more than 3 flashes per second, flashing under ~20% of the screen, and avoid saturated red flashes (Xbox Accessibility Guideline 118). |
| Motor failure feels personal | — | Players blame their own body, not the game, so handle failure "conservatively" and reward all engagement, at least at first (Burke et al., 2010, 🟠). |

**Also different from consumer apps:**
- **No competition between patients.** Abilities differ too much, so leaderboards measure the stroke rather than effort. Compare a patient only with their own earlier self.
- **No time pressure or speed targets.** Itera already follows this. Keep it.
- **Dose belongs to the therapist.** Gamification must never nudge "one more set" beyond what's prescribed. Itera already avoids bonus repetitions.
- **Adult dignity.** Many users are older adults. Playful is fine, childish is not: avoid cartoon voices, baby-talk copy and overly bright, toy-like art.

---

## 3. What the evidence says about games in stroke rehab

- **Serious games beat conventional therapy for the upper limb.** A meta-analysis of 42 RCTs (1,760 participants) found effects on function (SMD 0.47), activity (0.25) and participation (0.66). Games that followed **8 or more neurorehabilitation principles** worked better whatever the hardware (Doumas et al., 2021, 🟢). *Implication: engagement features should be built on rehab principles, not added on top of them.*
- **VR and games are safe, with modest benefit.** Cochrane's 2025 update (190 trials, 7,188 participants) found VR "may slightly improve arm function". The gains were larger when it **added therapy time** to usual care, and adverse events were rare and mild (Cochrane, 2025, 🟢). *Implication: the main benefit of engagement is more practice time, which is exactly Itera's problem.*
- **Three levers drive engagement: choice, reward and clear goals** (Lohse et al., 2013, 🟡 review).
- **Autonomy and positive expectancy improve motivation and learning** (OPTIMAL theory; Wulf & Lewthwaite, 2016, 🟡). In stroke, letting patients choose their difficulty increased use of the more-affected arm on the training device and successful reaches, compared with randomly assigned difficulty. Motor scores improved equally in both groups, and a clinical arm-use test showed no change (Kim et al., 2023, RCT n=26, 🟡). OPTIMAL's motivation claims have also been challenged by later critiques, so treat choice as a well-motivated design lever, not a guaranteed effect.
- **Difficulty scaffolding alone isn't enough.** In a 12-week home RCT, scaffolded game levels did *not* improve adherence over algorithmic difficulty. Intrinsic motivation held steady, adherence varied widely, and the authors suggested testing **narrative, cooperative play or competition** next (Fluet et al., 2024, 🟡). *Implication: Itera's next step should be story, social and choice, not more difficulty tuning.*
- **Real-time sound feedback helps.** Across 23 studies, real-time movement sonification and rhythmic cues improved arm outcomes. Real-time feedback had a larger effect on Fugl-Meyer scores (g 1.3) than rhythmic cueing (0.6) (Ghai, 2018, 🟢).
- **Self-chosen music improves mood and attention.** Daily listening to music the patient chose improved verbal memory and focused attention and reduced depressed mood compared with audiobooks or nothing. This was one RCT (n=60), so it needs replication (Särkämö et al., 2008, 🟡). It is evidence for mood and attention, not motor recovery.
- **Family involvement works.** Family-mediated exercise (35 minutes a day for 8 weeks) improved motor outcomes and community integration, and caregivers reported *less* stress and more empowerment (Galvin et al., 2011, RCT n=40, 🟡).
- **Habits form from consistent cues, and one missed day doesn't derail them.** Automaticity plateaued at around 66 days on average, with wide variation (Gardner, Lally & Wardle, 2012, 🟠 non-stroke).

---

## 4. Personas (hypothesis, not yet validated)

### P1 — Pak Budi, the tired returner (PRIMARY)
- **Context:** 62, six months after a left-hemisphere stroke. Moderate right-hand weakness, mild word-finding difficulty. Practises at home with an iPad on the dining table, morning and afternoon.
- **Goals:** Use his right hand to eat and to hold his grandchild. *Emotional:* feel like himself again, not like a patient. *Social:* not be a burden on his wife.
- **Pain points:** Twenty minutes in, the session feels endless. By minute 50 his hand is tired and he loses focus. Some days starting feels impossible, even though he wants to recover.
- **Workarounds today:** Puts the TV on in the background, skips the afternoon session, or asks his wife to "do it later".
- **Design needs:** Short chapters, a visible finish line, a choice of what's next, his own music, and progress that refers to *his* life.

### P2 — Ibu Sari, the caregiver-coach (SECONDARY)
- **Context:** 58, spouse. Sets up the iPad, adjusts the routine and stays nearby, but also runs the household.
- **Goals:** Make sure he does the therapy without nagging. *Emotional:* feel useful, not like a warden.
- **Pain points:** Constant reminding leads to arguments. She can't tell whether he's really improving.
- **Design needs:** A light-touch way to cheer him on, see progress at a glance, and take part without supervising every repetition.

### P3 — The therapist (STAKEHOLDER, not daily user)
- Sets the dose (sets, reps, rest) and needs to trust that engagement features never change it or encourage overexertion.

---

## 5. Jobs to Be Done

| Type | Job statement |
| --- | --- |
| Functional | When I'm 40 minutes into a session, I want to know how much is left and feel I'm getting somewhere, so I can keep going without giving up. |
| Functional | When my hand gets tired, I want a proper break that doesn't count as failing, so I can finish the session safely. |
| Functional | When I sit down to practise, I want to start with one tap, so the effort of starting doesn't stop me. |
| Emotional | When I practise the same movements every day, I want something new to look forward to, so it doesn't feel like a chore. |
| Emotional | When I finish, I want to see that I'm getting better than I was, so I believe recovery is happening. |
| Emotional | When I choose what to do, I want to feel in control of my recovery, so I feel like an adult, not a patient. |
| Social | When my family sees my progress, I want them to be proud of me, so I feel connected rather than a burden. |
| Social (caregiver) | When he practises, I want to support him without nagging, so we stay partners, not patient and nurse. |

**Opportunity scores (importance minus current satisfaction, estimated):** session shape and progress (very high), novelty over weeks (high), autonomy (high), self-referenced progress (high), caregiver role (medium-high), music (medium).

---

## 6. Journey map: one session (shown at the 90-minute maximum)

### Current state (hypothesis)

| Phase | Doing | Thinking / feeling | Pain |
|---|---|---|---|
| 0–5 min, start | Opens app, calibrates | "Here we go again…" 😐 | Starting effort; apathy |
| 5–20 min | First exercises, garden objects | Mild interest 🙂 | — |
| 20–45 min | Sets → rests → sets | "Same thing again" 😑 | Habituation; no sense of progress |
| 45–75 min | Hand tiring, attention drifting | "How long is left?" 😩 | Fatigue; no midpoint; no choice |
| 75–90 min | Pushing through or stopping early | Relief or guilt 😞 | Early stop feels like failure |
| After | Feeling check, flower, badge | Brief satisfaction 🙂 | The reward isn't tied to life goals |
| Next session | Has to restart from scratch | Dread 😟 | A streak loss could feel punishing |

### Desired state

| Phase | Experience |
|---|---|
| Start | One tap: "Continue your journey." The patient sees today's map, with as many chapters as the prescribed duration needs. They choose the first chapter and the music. |
| Each chapter (~12–15 min) | A clear themed scene with a beginning and end. Movements bring gentle sound and visual responses. Occasional surprise visitors appear. |
| Between chapters | A planned break: energy check (😊 / 😐 / 😴), sip of water, a few lines of an ongoing story or a family voice note. The patient chooses the next chapter. |
| Midpoint | A clear "halfway" celebration, with the map showing what's done. |
| End | The scene completes (the garden blooms, a season changes), plus a self-referenced note ("your hand opened wider than in your first week") and a link to the personal goal. |
| Between sessions | The caregiver sees a postcard. The streak is forgiving. Next time, a new element has been unlocked. |

**Gap analysis:** structure (chapters, map, midpoint), choice (order, theme, music), novelty over time (content rotation and unlocks), meaning (personal goal), social (caregiver and family), and a forgiving habit model.

---

## 7. Recommendations (exercises unchanged)

Ranked by expected impact against effort. Each item lists **what**, **why (evidence)** and **safety guardrails**.

### R1. Divide the session into chapters on a visible journey map ⭐ highest priority
- **What:** Group the prescribed sets into chapters of about 10–15 minutes. The number of chapters comes from the doctor's duration: roughly 2 chapters for 20–30 minutes, 3–4 for 45 minutes, and 5–6 for 90 minutes. A short session still gets a beginning, a midpoint and an ending. Each chapter has a named scene (for example: Morning garden → Rain shower → Seed planting → Butterfly path → Evening fireflies). Show a simple journey map with completed chapters filled in, a "halfway" moment and a clear finish line. The engine's dose stays the same; only the grouping and presentation are new.
- **Why:** Fatigue affects about 50% of survivors, and the guideline explicitly allows splitting the daily 3 hours across the day. Clear goals drive engagement (Lohse 2013). Visible progress toward a near-term end reduces perceived effort (⚪, consistent with goal-gradient findings in other fields).
- **Guardrails:** Chapter breaks are planned rests, not failures. An early stop still fills the map up to the point reached.

### R2. Energy check-ins and "rest is progress" between chapters
- **What:** Between chapters, show a 3-option, icon-based check (fresh / OK / tired / plus a pain flag). If "tired", offer a longer break or a guided breathing scene. If pain is flagged, suggest stopping and telling the therapist.
- **Why:** Fatigue (🟢) and depression (🟢) make a "push through" culture harmful. Rewarding all engagement and handling failure conservatively follows Burke et al. (2010).
- **Guardrails:** Never reward continuing despite a pain flag. Log the flags for the caregiver and therapist report.

### R3. Patient choice: order, theme, music and guide
- **What:** At the start and between chapters, let the patient choose which movement group comes next (from the prescribed list), which scene theme to use, and whether to play their own music. Keep the choices to 2–3 large options, one decision at a time.
- **Why:** Autonomy support (OPTIMAL, 🟡). In stroke, choice increased in-training use of the affected arm (Kim 2023, small RCT, 🟡). Choice is one of Lohse's three levers.
- **Guardrails:** The therapist-set dose and the required exercises stay locked. Choice only reorders. ⚠️ Confirm with the therapist that reordering is acceptable, because a fixed order may matter clinically for some patients.

### R4. Novelty over weeks: rotating worlds and unlocks
- **What:** Add 3–4 calm adult themes (garden, sea shore, night sky, kitchen or market for Indonesian context) and unlock new scene details through cumulative *participation* (sessions completed), not performance. Add rare "visitors" (a bird, a butterfly) that appear occasionally after accepted repetitions, capped at a low frequency.
- **Why:** Fluet 2024 found that difficulty scaffolding alone didn't sustain adherence and suggested narrative and variety (🟡). The habituation diagnosis comes from Itera's current fixed loop (⚪).
- **Guardrails:** Never require better performance to unlock content. Respect calm mode and Reduce Motion. Follow photosensitivity limits. Never place visitors only at one screen edge (neglect).

### R5. A light ongoing story told during rests only
- **What:** A gentle serial story (for example, restoring a family garden or a village through the seasons), shown in 2–3 short lines plus narration during chapter breaks. Each session moves it forward.
- **Why:** Narrative was the next lever suggested by Fluet 2024 (🟠). Delivering it during rests avoids adding cognitive load during movement.
- **Guardrails:** Nothing to read during active practice. Narration plus icons for people with aphasia. The story can never be "lost".

### R6. Self-referenced progress feedback ("better than your past self")
- **What:** At the end of a chapter or session, show a single positive comparison when it is genuinely true, using the existing calibration-range metric and the existing >5% rule. For example: "Your fingers opened wider than in your first week." Also show personal bests. Never show negative comparisons; on days with no gain, praise consistency instead.
- **Why:** Enhanced expectancies improve motivation and learning (OPTIMAL, 🟡). Depression prevalence (🟢) argues for frequent, honest small wins.
- **Guardrails:** Keep README's honesty rule: these are camera estimates, not clinical measures. Wording must not imply recovery claims.

### R7. Real-time movement sound (sonification)
- **What:** A soft musical tone that rises gently as the hand moves toward the target pose and settles as it returns. It is presentation-only and responds to the existing metric. Offer it as an optional "sound garden" mode.
- **Why:** Real-time auditory feedback improved arm outcomes, with a larger effect than rhythmic cueing (Ghai 2018, 🟢). It also makes each repetition feel alive.
- **Guardrails:** Use no rhythm that implies a required speed. Duck the sound under narration through the existing audio owner. Keep volume low and allow it to be turned off.

### R8. Patient-chosen music
- **What:** Let the patient pick a playlist (local files or Apple Music) that plays at low volume and ducks under guidance and counts.
- **Why:** Self-chosen music improved mood and attention after stroke (Särkämö 2008, 🟡).
- **Guardrails:** The voice-command recogniser must still work. Test music together with speech recognition on a physical iPad. Mute automatically on pause.

### R9. Personal goal anchor
- **What:** During setup, the patient and caregiver pick 1–3 life goals from pictures (eating with a spoon, holding a grandchild's hand, praying with both hands, buttoning a shirt). Each exercise shows "this helps with: 🥄". The goal appears at the start and on completion.
- **Why:** Clear goals (Lohse 2013, 🟡). Linking abstract repetitions to valued outcomes supports intrinsic motivation (⚪/🟡).
- **Guardrails:** Avoid promising that the goal *will* be reached. The therapist can review the links between exercises and goals.

### R10. Caregiver and family as cheerleaders
- **What:** (a) Family members record short voice or photo messages that unlock at chapter ends, ("Ayo Pak, sudah setengah jalan!" — "Come on, you're halfway there!"). (b) An optional caregiver co-op tap: the caregiver "waters" the garden and adds a decoration during a break. (c) A daily postcard of the garden to share (builds on the existing share flow).
- **Why:** Family-mediated exercise improved outcomes and *reduced* caregiver stress (Galvin 2011, 🟡). Relatedness is the third need in self-determination theory.
- **Guardrails:** No leaderboards and no comparing patients. Sharing is always opt-in and never includes camera or health data, consistent with Itera's current privacy design.

### R11. Forgiving habit model (replace punishing streaks)
- **What:** Keep the current streak but add a weekly goal (for example, 10 of 14 sessions) and allow automatic "rest days" that don't break it. Help the patient anchor sessions to fixed cues ("after breakfast", "after Dzuhur prayer") and send one gentle reminder at that time.
- **Why:** One missed day doesn't impair habit formation, and automaticity takes about 66 days, with variation (Gardner 2012, 🟠). Depression and apathy (🟢) make visible losses demotivating.
- **Guardrails:** Never show "streak lost" in red or with sad imagery.

### R12. Low-friction start for apathy
- **What:** Home shows one large button, "Continue your journey", and skips straight to calibration when the routine hasn't changed. The first chapter is a familiar, liked scene, and the caregiver can start it remotely or with a notification.
- **Why:** Apathy affects about a third of survivors (🟢), and starting is the main barrier for them.
- **Guardrails:** Keep the existing permission, readiness and calibration safety checks. Only the steps in front of them get shorter.

### How engagement scales with the prescribed duration

The doctor's duration changes *how much* engagement support a session needs, not *what* the patient does. Longer sessions need more rest and variety, not more intense stimulation.

| Prescribed duration | Chapters | Breaks & checks | Variety | Comfort emphasis |
|---|---|---|---|---|
| Short (≈15–30 min) | 2 | One energy check at the midpoint | One theme, one surprise visitor | Quick start and a satisfying ending |
| Medium (≈30–60 min) | 3–4 | A check between every chapter | Theme can change mid-session; one story beat | Patient chooses the next chapter |
| Long (60–90 min, maximum) | 5–6 | Checks between chapters plus one longer "tea break" scene near the middle | Two or more scene changes; story beats in breaks; family message at halfway | Most fatigue protection: bigger breaks offered automatically if "tired" is reported twice |

**Comfort rules at every length**
- Calm visuals and low-volume sound by default. Excitement comes from progress and surprise, not from speed, noise or bright effects.
- The patient can pause, take a longer break or end at any chapter boundary without losing what they've earned.
- A pain flag always suggests stopping and contacting the therapist, whatever the remaining duration.
- Rewards are the same whether the session is 20 or 90 minutes, so a patient with a shorter prescription never feels they're doing "less".

### Do NOT do (anti-patterns for this population)
- Leaderboards or patient-vs-patient competition
- Time limits, speed bonuses or "combo" multipliers
- Losing lives, withering plants or decaying rewards
- Rewards that require exceeding the prescribed dose
- Fast flashing or strobing celebrations, or large saturated red flashes
- Text-heavy story or instructions during active movement
- Childish visuals or copy

---

## 8. Assumptions & Risks

| # | Assumption | Status | How to validate |
|---|---|---|---|
| A1 | Boredom (not pain or confusion) is the main reason sessions are cut short | Unvalidated | 5–8 interviews and diary notes with survivors and caregivers. Log the minute of early stops. |
| A2 | Reordering exercises within a session is clinically acceptable | Unvalidated, **therapist decision** | Therapist review before building R3 |
| A3 | Patients will make choices without decision fatigue | Unvalidated | Usability test with 2–3 options per choice |
| A4 | Family members are willing to record messages | Unvalidated | Caregiver interviews |
| A5 | Music and sonification don't break on-device voice commands | Unvalidated, technical | Physical iPad audio test |
| A6 | Duration is set by the doctor per patient, up to 90 minutes twice a day | Confirmed by product owner | The app reads the prescribed duration and never extends it. Test the chapter design at short (≈20 min) and maximum (90 min) lengths. |
| A7 | Engagement features remain comfortable at every duration | Unvalidated | Watch energy and pain checks at both lengths. Long sessions should get more breaks, not more stimulation. |

**Risks:** Overexertion driven by gamification (mitigated by R2 and dose lock); novelty fading again after a few weeks (mitigated by content rotation and story); development cost of multiple themes (start with one theme plus chapter structure); and evidence gaps, because most game studies in stroke are small, so measure rather than assume.

---

## 9. Success metrics & telemetry plan

All metrics are local-first and consistent with Itera's no-cloud design. For a study, export with consent.

**North star:** Share of prescribed weekly practice minutes actually completed (evidence-credited minutes ÷ prescribed minutes).

| Metric | Type | Target (initial) | Event / source |
|---|---|---|---|
| Sessions completed per week (of 14) | Adherence | +20% vs baseline | `session_finalized{status}` (exists) |
| Minute of voluntary early stop | Leading | Shift later | `session_stopped{elapsed, chapter}` (new) |
| Chapter completion rate | Leading | ≥85% | `chapter_completed{index, theme}` |
| Energy check distribution over time | Guard rail | "Tired" not rising | `energy_check{chapter, level}` |
| Pain flags | **Safety guard rail** | No increase vs baseline | `pain_flag{chapter}` |
| Choice usage | Feature | >50% of sessions use a choice | `choice_made{type}` |
| Intrinsic Motivation Inventory (short, monthly) | Outcome | Stable or rising | In-app 4-item survey |
| Perceived difficulty (exists) | Guard rail | Mostly "just right" | Existing feeling check |

**Experiment:** Itera already has a `gardenActivities` toggle. Use the same approach to compare *chapters + choice* against the current flow in a small within-person crossover (2 weeks each).

**Decision rules:** If pain flags or "tired" ratings rise, roll back the feature. If adherence doesn't change after 4 weeks, interview users before adding more content.

---

## 10. Design principles (summary)

1. **Shape the time.** Whatever the doctor prescribes becomes chapters with a visible finish line.
2. **Rest is progress.** Breaks and energy checks are part of success, never failure.
3. **The patient chooses.** Small, meaningful choices within the prescribed dose.
4. **Better than yesterday-me.** Honest self-comparison only, never against others.
5. **Always something new.** Rotate worlds, story and surprises over weeks.
6. **Linked to life.** Every exercise points to a personal goal.
7. **Together, not supervised.** The caregiver cheers rather than polices.
8. **Gentle by default.** No flashes, no time pressure, no loss states. Centre-weighted, icon, voice and text together.
9. **The prescription is fixed.** Duration and dose come from the doctor. Engagement features never lengthen a session or ask for more.

---

## 11. Recommended next steps

1. **Therapist/doctor review** of A2 (reordering) and of how the prescribed duration is entered into the app, then build **R1 + R2** (chapters, map, energy check) as the first increment, using one theme.
2. **Quick validation:** 5 short sessions with stroke survivors and caregivers, using a clickable mock-up of the journey map and choices.
3. **Second increment:** R3 (choice), R6 (self-progress) and R11 (forgiving streak).
4. **Third increment:** R4/R5 (themes and story), R7/R8 (sound and music), R10 (family messages).
5. Then hand off to technical brainstorming with this document as the requirements anchor (respecting SYSTEM_DESIGN.md: the engine owns progression, and art cannot send progression events).

---

## Sources

- Doumas I, Everard G, Dehem S, Lejeune T. *Serious games for upper limb rehabilitation after stroke: a meta-analysis.* J NeuroEng Rehabil, 2021. https://doi.org/10.1186/s12984-021-00889-1
- Cochrane. *Virtual reality for stroke rehabilitation* (4th update, 2025). https://www.cochrane.org/about-us/news/virtual-reality-gives-stroke-rehab-new-dimension
- Lohse K, Shirzad N, Verster A, Hodges N, Van der Loos HFM. *Video games and rehabilitation: using design principles to enhance engagement in physical therapy.* J Neurol Phys Ther, 2013. https://msl.kin.educ.ubc.ca/publication/video-games-and-rehabilitation-using-design-principles-enhance-engagement-physical-thera
- Burke JW, McNeill MDJ, Charles DK, et al. *Designing engaging, playable games for rehabilitation.* ICDVRAT, 2010. https://oneswitch.org.uk/OS-REPOSITORY/MUSEUM/VARIOUS/VR/ICDArchive2021/2010/P/2010_S07_N02_Burke_etal.pdf
- Wulf G, Lewthwaite R. *Optimizing performance through intrinsic motivation and attention for learning: The OPTIMAL theory of motor learning.* Psychon Bull Rev, 2016. https://digitalscholarship.unlv.edu/kns_fac_articles/123
- Kim S, Shin Y, Jeong Y, et al. *Autonomy support encourages use of more-affected arm post-stroke.* J NeuroEng Rehabil, 2023. https://link.springer.com/article/10.1186/s12984-023-01238-0
- Fluet G, Qiu Q, Gross A, et al. *The influence of scaffolding on intrinsic motivation and autonomous adherence to a game-based, sparsely supervised home rehabilitation program…* J NeuroEng Rehabil, 2024. https://link.springer.com/article/10.1186/s12984-024-01441-7
- Ghai S. *Effects of real-time (sonification) and rhythmic auditory stimuli on recovering arm function post stroke.* Front Neurol, 2018. https://www.frontiersin.org/article/10.3389/fneur.2018.00488/full
- Särkämö T, et al. *Music listening enhances cognitive recovery and mood after middle cerebral artery stroke.* Brain, 2008. https://www.sciencedaily.com/releases/2008/02/080219203554.htm
- Galvin R, Cusack T, O'Grady E, Murphy B, Stokes E. *Family-mediated exercise intervention (FAME).* Stroke, 2011. https://www.tcd.ie/news_events/articles/new-research-shows-stroke-patients-benefit-from-family-involvement-in-exercise-therapy/
- Cumming TB, Packer M, Kramer SF, English C. *The prevalence of fatigue after stroke: a systematic review and meta-analysis.* Int J Stroke, 2016. https://digital.library.adelaide.edu.au/items/8b2247d1-f44d-47c1-a5f2-785f09ace9a8
- Hackett ML, Pickles K. *Part I: frequency of depression after stroke.* Int J Stroke, 2014. https://knowledge.lancashire.ac.uk/id/eprint/11479/
- Caeiro L, Ferro JM, Costa J. *Apathy secondary to stroke: a systematic review and meta-analysis.* Cerebrovasc Dis, 2013. https://www.nationalelfservice.net/publication-types/systematic-review/apathy-secondary-to-stroke-is-more-frequent-than-depression/
- Esposito E, Shekhtman G, Chen P. *Prevalence of spatial neglect post-stroke: a systematic review.* Ann Phys Rehabil Med, 2020. https://www.em-consulte.com/article/1408612/prevalence-of-spatial-neglect-post-stroke-a-system
- Frederick A, et al. *Global rate of post-stroke aphasia.* 2022. https://asha.figshare.com/articles/online_resource/Global_rate_of_post-stroke_aphasia_Frederick_et_al_2022_/21183478
- Gardner B, Lally P, Wardle J. *Making health habitual.* Br J Gen Pract, 2012. https://pmc.ncbi.nlm.nih.gov/articles/PMC3505409/
- Microsoft. *Xbox Accessibility Guideline 118: Photosensitivity.* https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/118
- National Clinical Guideline for Stroke (2023), summary of therapy-intensity recommendation. https://uk.saebo.com/national-stroke-guidelines-2023/

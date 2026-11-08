# Club Tiger Chat Rules

Club Tiger is for adult DePauw students, so chat is **open but with respect**. The filter blocks strong swearing and
the R1-R3 terms, including disguised spellings, and lets mild words (`ass`, `bitch`, `lmao`) through.

This file is the source of truth for the rules. Change it whenever a rule is added or changed (see [How to add or change a rule](#how-to-add-or-change-a-rule)).

## Rules

| #  | Rule | Examples |
|----|------|----------|
| R1 | **No harassment or threats** | repeatedly targeting one player |
| R2 | **No slurs or hate speech** about race, religion, sexuality, gender or disability | racial slurs, homophobic slurs |
| R3 | **No sexual messages** aimed at other players, and no explicit sexual content | propositions, explicit descriptions |
| R4 | **No links** to other sites | `site.com`, `.gg/...`, `site dot com` |
| R5 | **No spamming** | spamming the same message |
| R6 | **No sharing personal information**, yours or anyone else's | phone numbers, addresses, other people's accounts |
| R7 | **No strong swearing**, also when disguised. Mild words are fine | `fuck`, `shit`, `wtf`, `f*ck`, `f u c k` |

## How each rule is enforced

| #  | Automatic (server)                                               | Status     | Handled by people         |
|----|------------------------------------------------------------------|------------|---------------------------|
| R1 | Word filter blocks a short list of harassment terms (`kys`, ...) | **Done**   | Reports (not built yet)   |
| R2 | Word filter blocks slurs                                         | **Done**   | Reports (not built yet)   |
| R3 | Word filter blocks explicit sexual terms and porn spam bait      | **Done**   | Reports (not built yet)   |
| R4 | `containsLink` check rejects links, including porn spam domains  | **Done**   | -                         |
| R5 | Max 48 characters per message, max 3 messages per 3 seconds      | **Done**   | Reports (not built yet)   |
| R6 | None - too varied to filter reliably                             | -          | Reports (not built yet)   |
| R7 | Word filter blocks strong swear words and their abbreviations    | **Done**   | Reports (not built yet)   |

The blocked terms for R1-R3 and R7 are in `server/src/data/blocked_terms.json`. Keep that list short so it is easy to
review.

When the server rejects a message, only the sender sees why (`chat_rejected`). Nobody else sees anything, and the
server logs the user id and matched word.

## What the filter does

- **Checks whole words only**, against a short list of terms for R1-R3 and R7, so normal words that contain a blocked word
  (`class`, `shell`, `therapist`) are never a problem.
- **Normalizes the text first:** ignores capitals, accents and fullwidth letters, reads common leetspeak
  (`th0t` = `thot`) and Cyrillic or Greek look-alike letters (`thоt` with a Cyrillic `о`), and matches stretched
  letters (`kyyys`) and plurals (`slurs` from `slur`).
- **Catches disguised links:** `site . com`, `site dot com`, `site[.]com`, Unicode dots (`site。com`), fullwidth
  text, and porn or cheap endings (`.xxx`, `.cam`, `.to`). Endings that are also English words (`to`, `in`, `top`)
  only count when the dot touches both sides, so `ok . to me` is fine.
- **Undoes disguises, then checks whole words again:**
  - each `*` hides one letter (`f*ck`, `f***`, `th*ts`, `k*ll yourself`); a star used for emphasis (`*hi*`), a
    rating (`5***`) and one letter with one star (`A*`) are left alone
  - `x` hides one letter when the word has 3+ other letters (`fxck`, `thxt`), so `fax`, `boxer` and `taxi` are fine
  - runs of 3+ single letters are joined (`k y s`, `f.u.c.k`); `s h e l l` becomes `shell`, which is fine
- **Doesn't try to catch** words split into pieces (`fu ck`, `k ys`). Those are left to the rules and to reports,
  because joining them caused false alarms.

## Changelog

Newest first. Each entry says what changed, why, and where in the code.

| Date       | Change | Why | Where |
|------------|--------|-----|-------|
| 2026-11-07 | Added R7: strong swearing (`fuck`, `shit`, `damn`, `wtf`, ...) is blocked; mild words stay allowed. The filter now also catches `*` masks, `x` as a hidden letter, and spaced-out letters. | Players got crude words through by censoring or spacing them on purpose. | `server/src/chatFilter.ts`, `server/src/data/blocked_terms.json`, `server/src/test/chatFilter.test.ts`, `server/src/test/lists.test.ts` |
| 2026-10-28 | Built the light filter: whole-word checks against a short R1-R3 list, look-alike letters, and the link check (R4) with porn spam endings and Unicode dots. Casual swearing now gets through. | Viral porn spam links; the old filter blocked swearing the rules allow and caused false alarms. | `server/src/chatFilter.ts`, `server/src/chat.ts`, `server/src/data/blocked_terms.json` |
| 2026-10-24 | Switched to **open chat with rules** and a light filter. Wrote rules R1-R6. Casual swearing is now allowed. | The game is for adults; a strict filter caused false alarms and was hard to maintain. | `CHAT_RULES.md`, TODO in `server/src/chatFilter.ts` |
| 2026-10-22 | Added harassment, slur and sexual terms to the blocked list (`kys`, `thot`, ...); built a dictionary allow list. | Adult-audience policy: block harm, not swearing. | `server/src/data/profanity_list.json`, `allowed_words.json` |
| 2026-10-22 | Planned the link check. | Links in game chat are mostly scams and phishing. | TODO in `server/src/chat.ts` |
| 2026-10-21 | Word filter added, based on the Google profanity list; catches leetspeak, accents, repeated letters, spacing and `*`. | Checkpoint 2: chat with blocked phrases. | `server/src/chatFilter.ts` |
| 2026-10-21 | Message limit (48 characters) and rate limit (3 messages per 3 seconds). | Stop flooding. | `server/src/chat.ts` |

## How to add or change a rule

1. **Add or edit the rule** in the [Rules](#rules) table, with a new number (`R7`, ...). Never reuse an old number.
2. **Decide how it's enforced** and add a row to [How each rule is enforced](#how-each-rule-is-enforced). Prefer
   "reports" over a new filter check unless the case is clear and common.
3. **If the filter changes**, add the terms to the blocked list and add tests to `server/src/test/chatFilter.test.ts`,
   both for what's blocked and for normal messages that must stay allowed.
4. **Add a [Changelog](#changelog) entry** with the date, the change, why, and where in the code.

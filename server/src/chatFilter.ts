// Chat filter (see CHAT_RULES.md): blocks the terms in blocked_terms.json as whole words, including disguised
// spellings (leetspeak, accents, look-alike letters, "*", "x" and spaced-out letters), and rejects links.

import { readFileSync } from "fs";

// Leetspeak characters -> the letter they stand for.
const LEET: Record<string, string> = {"0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s"}
// Cyrillic and Greek letters that look like Latin ones -> the Latin letter. NFKD leaves them alone, so without this
// one Cyrillic letter ("thоt", "site.соm") would get a blocked word or a link past the filter.
const LOOKALIKE: Record<string, string> = {
    "а": "a", "в": "b", "е": "e", "ё": "e", "і": "i", "ї": "i", "ј": "j", "к": "k", "м": "m", "н": "h",
    "о": "o", "р": "p", "с": "c", "т": "t", "у": "y", "х": "x", "ѕ": "s", "ԁ": "d", "ԛ": "q", "ԝ": "w",
    "α": "a", "β": "b", "ε": "e", "ι": "i", "κ": "k", "ν": "v", "ο": "o", "ρ": "p", "τ": "t", "υ": "u", "χ": "x",
}
const LOOKALIKE_CHARS = new RegExp(`[${Object.keys(LOOKALIKE).join("")}]`, "g")

// Loaded and turned into regexes once when the server starts. The path goes through ../src so it also works from
// dist/ after a build.
const BLOCKED_FILE = new URL("../src/data/blocked_terms.json", import.meta.url);
const BLOCKED = (JSON.parse(readFileSync(BLOCKED_FILE, "utf-8")) as string[]).filter((phrase) => cleanText(phrase) !== "")
const BLOCKED_PATTERNS = BLOCKED.map((phrase) => toPattern(phrase))
const VOCAB = [...new Set(BLOCKED.flatMap((phrase) => cleanText(phrase).split(" ")))].filter((word) => word.length >= 3)

// Link endings. Word-like endings are only a link when the dot touches both sides ("leaks.to"), because with spaces
// they are normal English ("polka dot top", "ok . to me").
const TLDS = "com|net|org|edu|gov|io|gg|co|me|ly|xyz|tv|app|dev|info|biz|us|uk|ru|cn|link|site|online|club|shop"
const ADULT_TLDS = "xxx|porn|sex|sexy|adult|cam|webcam"
const WORDLIKE_TLDS = "live|fun|top|vip|click|to|cc|ws|sh|lol|pw|icu|party|fans|tk|ml|ga|cf|gq|su|in"
const DOT = "[.\\u3002]"   // a full stop, or the ideographic full stop "。" spammers use instead
const LINK_PATTERNS = [
    /\bhttps?:\/\//i,                                                                    // http:// or https://
    new RegExp(`\\bwww\\s*${DOT}\\s*\\S`, "i"),                                          // www.something
    // name + dot + ending, dot touching both sides: "site.com", "site[.]com", "site(.)com"
    new RegExp(`\\b[a-z0-9-]+(?:${DOT}|\\[\\.\\]|\\(\\.\\))(?:${TLDS}|${ADULT_TLDS}|${WORDLIKE_TLDS})\\b`, "i"),
    // name + spaced dot or "dot" + ending: "site . com", "site dot com", "site(dot)com". A full stop at the end of a
    // sentence ("ok. me too") has no space before it, so it doesn't count.
    new RegExp(`\\b[a-z0-9-]+(?:\\s+${DOT}\\s+|\\s*(?:\\(dot\\)|\\[dot\\])\\s*|\\s+dot\\s+)(?:${TLDS}|${ADULT_TLDS})\\b`, "i"),
    /\b\d{1,3}(?:\.\d{1,3}){3}\b/,                                                       // IP address, e.g. 192.168.0.1
    /\bdiscord\s*\.?\s*gg\b/i,                                                           // Discord invites, with or without the dot
]

// Turns look-alike Cyrillic and Greek letters into the Latin letters they imitate. Expects lowercase text.
function foldLookalikes(text: string): string {
    return text.replace(LOOKALIKE_CHARS, (c) => LOOKALIKE[c]);
}

// Lowercases, strips accents, and maps look-alike letters and leetspeak to letters. Shared by cleanText and
// cleanKeepStars, which differ only in what they do with the other characters.
function toPlainLetters(text: string): string {
    text = text.toLowerCase()
               .normalize("NFKD")
               .replace(/\p{M}/gu, "")
    text = foldLookalikes(text);
    text = text.replace(/(?<=[a-z0-9@$])!+(?=[a-z0-9@$])/g, "i");    // "sh!t" -> "shit", but "hi!" stays "hi"
    return text.replace(/[013457@$]/g, (c) => LEET[c]);
}

// Turns a message into plain words: letters only, everything else becomes single spaces. "B4áD  w0rd!!" -> "baad word"
function cleanText(text: string): string {
    return toPlainLetters(text).replace(/[^a-z]+/g, " ").trim();
}

// Like cleanText but for one word, and keeps "*" so a masked word ("f*ck") isn't split into "f ck".
function cleanKeepStars(word: string): string {
    return toPlainLetters(word).replace(/[^a-z*]+/g, "");
}

// Builds a whole-word regex for one blocked phrase, so stretched letters ("kyyys") and plurals ("thots") still match.
function toPattern(phrase: string): RegExp {
    const clean = cleanText(phrase);
    let body = ""
    let i = 0
    while (i < clean.length){
        const char = clean[i];
        if (char === " "){
            body += " ";
            i++;
            continue;
        }
        let cntConsecutiveLetter = 0
        while (i + cntConsecutiveLetter < clean.length && clean[i + cntConsecutiveLetter] === char){
            cntConsecutiveLetter++;
        }
        body += `${char}{${cntConsecutiveLetter},}`;
        i += cntConsecutiveLetter;
    }
    const plurals = clean.includes(" ") ? "" : "(?:es|s)?";
    return new RegExp(`(^| )${body}${plurals}( |$)`)
}

// Returns the blocked VOCAB word a disguised word stands for, or the word unchanged. Each "*" hides exactly one
// letter ("f**k", "f***", "th*t"); "x" also counts as a hidden letter when the word has 3+ other letters ("fxck").
// "*hi*" is emphasis, and one letter with one star ("A*", "5*") is too little to tell, so those are left alone.
function unmaskWord(raw: string): string {
    let word = cleanKeepStars(raw);
    if (word.startsWith("*") && word.endsWith("*")) word = word.replace(/^\*+|\*+$/g, "");
    // Letters the player really typed, before leetspeak, so a rating like "5***" has none.
    const typedLetters = (foldLookalikes(raw.toLowerCase().normalize("NFKD")).match(/[a-z]/g) ?? []).length;
    const stars = (word.match(/\*/g) ?? []).length;
    const xs = (word.match(/x/g) ?? []).length;

    let hidden: RegExp;
    if (stars > 0) {
        if (typedLetters === 0 || (word.length - stars < 2 && stars < 2)) return raw;
        hidden = /\*/g;
    } else if (xs > 0) {
        // 3+ other letters, because with 2 "fax" would read as "fag"
        if (word.length - xs < 3) return raw;
        hidden = /x/g;
    } else {
        return raw;
    }
    // Also try each word's plural, so "th*ts" (5 letters) still lines up with "thot" + "s".
    const pattern = new RegExp("^" + word.replace(hidden, "[a-z]") + "$");
    return VOCAB.find((vocabWord) => pattern.test(vocabWord) || pattern.test(vocabWord + "s")) ?? raw;
}

// Glues runs of 3+ single letters into one word: "go k y s lol" -> "go kys lol". cleanText already turns "k.y.s"
// and "k-y-s" into "k y s". 3+ because the shortest blocked words have 3 letters, so "u r" stays apart.
function joinSpacedLetters(clean: string): string {
    return clean.replace(/\b[a-z](?: [a-z]\b){2,}/g, (run) => run.replace(/ /g, ""));
}

// Returns the first blocked phrase whose whole-word pattern matches the cleaned words, or null.
function matchBlocked(words: string): string | null {
    for (let i = 0; i < BLOCKED_PATTERNS.length; i++){
        if (BLOCKED_PATTERNS[i].test(words)){
            return BLOCKED[i];
        }
    }
    return null;
}

// Returns the blocked phrase found in the message (for the server log), or null if the message is fine.
// Checks the message as typed first, then again with "*", "x" and spaced-out letters undone.
export function findBlockedPhrase(text: string): string | null {
    const found = matchBlocked(cleanText(text));
    if (found) return found;
    const rebuilt = joinSpacedLetters(cleanText(text.split(/\s+/).map(unmaskWord).join(" ")));
    return matchBlocked(rebuilt);
}

// Says whether the message contains a link (rule R4). NFKC turns fullwidth letters and dots into plain ones
// ("ｓｉｔｅ．ｃｏｍ" -> "site.com"), and look-alike letters are folded, before the patterns are checked.
export function containsLink(text: string): boolean {
    const plain = foldLookalikes(text.normalize("NFKC").toLowerCase());
    return LINK_PATTERNS.some((pattern) => pattern.test(plain));
}

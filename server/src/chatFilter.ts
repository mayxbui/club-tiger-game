import { readFileSync } from "fs";

// Leetspeak characters -> the letter they stand for.
const LEET: Record<string, string> = {"0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s", "!": "i"}
// Loaded and turned into regexes ONCE when the server starts. Entries that normalize to nothing (emoji) are dropped.
const BLOCKED_FILE = new URL("../src/data/blocked_phrases.json", import.meta.url);
const BLOCKED = (JSON.parse(readFileSync(BLOCKED_FILE, "utf-8")) as string[]).filter((word)=>normalize(word).join(""))
const BLOCKED_PATTERNS = BLOCKED.map((phrase) => toPattern(phrase, true))           
const BLOCKED_INSIDE_PATTERNS = BLOCKED.map((phrase) => toPattern(phrase, false))  

// Lowercases, strips accents, maps leetspeak to letters and turns everything else into single spaces
// "B4áD  w0rd!!" -> "baad word i i"
function cleanText(text: string): string {
    text = text.toLowerCase()
               .normalize("NFKD")
               .replace(/\p{M}/gu, "")
    text = text.replace(/[013457@$!]/g, (c) => LEET[c]);
    return text.replace(/[^a-z]+/g, " ").trim();
}

// cleanText, then join broken pieces of letters  together
// "B4áD  w0rd" -> ["baad", "word"],  "you s uc k" -> ["you", "suck"]
function normalize(text: string, joined: string[] = []): string[] {
    return joinSingleLetters(cleanText(text).split(" "), joined);
}

// Joins runs of single to 2 letters into one word
function joinSingleLetters(words: string[], joined: string[] = []): string[]{
    const result = [];
    let word = 0;
    while (word<words.length){
        let single = word;
        while (single<words.length && words[single].length<=2) single ++;
        const run = words.slice(word, single);
        if(run.length>=2 && run.some((w) => w.length === 1)){
            const joinWord = run.join("");
            result.push(joinWord);
            joined.push(joinWord);
            word = single;
        } else {
            result.push(words[word]);
            word++;
        }
    }
    return result
}

// Builds a regex for one blocked phrase so repeated letters still match
function toPattern(phrase: string, wholeWord: boolean): RegExp {
    const phrase_norm = normalize(phrase).join(wholeWord ? " " : "");
    let body = ''
    let i = 0
    while (i<phrase_norm.length){
        const char = phrase_norm[i];
        if (char === " "){
            body += " ";
            i++;
            continue;
        }
        let cntConsecutiveLetter = 0
        while (i + cntConsecutiveLetter < phrase_norm.length && phrase_norm[i + cntConsecutiveLetter]===char){
            cntConsecutiveLetter++;
        }
        const escapedChar = char.replace(/[.*+?^\${}()|[\]\\]/g, '\\$&');
        body += `${escapedChar}{${cntConsecutiveLetter},}`;
        i+=cntConsecutiveLetter;
    }
    return wholeWord ? new RegExp(`(^| )${body}( |$)`) : new RegExp(body)
}

// Returns the blocked phrase found in the message, or null if the message is fine.
export function findBlockedPhrase(text:string): string | null{
    const joined: string[] = [];
    const words = normalize(text, joined).join(" ");
    const plainWords = cleanText(text);     // before joining, so "you are a ho" isn't hidden inside "aho"

    // Check entire words/phrases
    for (let i = 0; i < BLOCKED_PATTERNS.length; i++){
        if (BLOCKED_PATTERNS[i].test(words) || BLOCKED_PATTERNS[i].test(plainWords)){
            return BLOCKED[i];
        }
    }

    // Check spaced-out letters ("a b a d" -> "abad" contains "bad")
    for (const joinWord of joined){
        for (let i = 0; i < BLOCKED_INSIDE_PATTERNS.length; i++){
            if (normalize(BLOCKED[i]).join("").length >= 3 && BLOCKED_INSIDE_PATTERNS[i].test(joinWord)){
                return BLOCKED[i];
            }
        }
    }

    // Check censored words: each run of "*" or "#" means one or more hidden letters, e.g. "f**"
    for (const rawWord of text.toLowerCase().split(/\s+/)){
        const token = rawWord.replace(/[013457@$]/g, (c) => LEET[c]).replace(/[^a-z*#]/g, "");
        if (!/^[a-z][a-z*#]*[*#]/.test(token)) continue;
        const masked = new RegExp("^" + token.replace(/[*#]+/g, "[a-z]+") + "$");
        const hit = BLOCKED.find((phrase) => !phrase.includes(" ") && phrase.length >= 3 && masked.test(phrase));
        if (hit) return hit;
    }

    return null;
}

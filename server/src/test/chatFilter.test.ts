import test, { describe } from "node:test";
import assert from "node:assert/strict";
import { findBlockedPhrase } from "../chatFilter.js";

// Each message must be blocked (findBlockedPhrase returns the phrase it matched)
function assertBlocked(messages: string[]) {
    for (const message of messages) {
        assert.notEqual(findBlockedPhrase(message), null, `should be blocked: ${JSON.stringify(message)}`);
    }
}

// Each message must get through (findBlockedPhrase returns null)
function assertAllowed(messages: string[]) {
    for (const message of messages) {
        const found = findBlockedPhrase(message);
        assert.equal(found, null, `should be allowed: ${JSON.stringify(message)} (matched "${found}")`);
    }
}

test("block words", () => assert.notEqual(findBlockedPhrase("f* you"),null))

describe("blocks plain words and phrases", () => {
    test("single word", () => assertBlocked(["shit", "arse", "bitches"]));
    test("inside a sentence", () => assertBlocked(["what the shit", "you piece of shit", "holy shit lol"]));
    test("multi-word phrase", () => assertBlocked(["2 girls 1 cup", "fuck you"]));
    test("returns the matched phrase as a string (for the server log)", () => {
        assert.equal(typeof findBlockedPhrase("shit"), "string");
    });
});

describe("caps and accents", () => {
    test("any capitalisation", () => assertBlocked(["SHIT", "ShIt", "SH*T"]));
    test("accents and other marks", () => assertBlocked(["shít", "šhįt", "fück"]));
    test("fullwidth letters", () => assertBlocked(["ｓｈｉｔ"]));
});

describe("leetspeak", () => {
    test("numbers for letters", () => assertBlocked(["sh1t", "5h1t", "4r5e", "b1tch", "4ss"]));
    test("symbols for letters", () => assertBlocked(["$hit", "sh!t", "b!tch", "a$$", "@ss"]));
    test("entries written in leetspeak in the list itself", () => assertBlocked(["2g1c", "a55"]));
    test("leetspeak in a harmless word stays harmless", () => assertAllowed(["cl4ss"]));
});

describe("repeated letters", () => {
    test("stretched words", () => assertBlocked(["shiiiiit", "sssshhhiiittt", "biiiitch", "asssss", "fuuuuck"]));
    test("a shorter word is not the blocked word (as vs ass)", () => assertAllowed(["as"]));
});

describe("spaced-out and broken-up letters", () => {
    test("letters separated by spaces or punctuation", () =>
        assertBlocked(["s h i t", "s.h.i.t", "s-h-i-t", "s_h_i_t", "s,h,i,t", "a s s", "f u c k"]));
    test("pieces of letters", () => assertBlocked(["s h it", "s uc k", "you s uc k", "as s"]));
    test("blocked list entries that are spaced out themselves", () => assertBlocked(["s&m", "a_s_s"]));
    test("normal short words are not glued into false positives", () =>
        assertAllowed(["I am a student", "is it ok", "go to the shop", "i a", "u r", "ok k", "a b", "a s"]));
});

describe("punctuation and whitespace around words", () => {
    test("brackets, quotes and dots", () => assertBlocked(["(shit)", "\"shit\"", "shit.", "...shit...", "oh,shit"]));
    test("newlines and tabs", () => assertBlocked(["shit\nhappens", "\tshit\t"]));
    test("emphasis stars around a real word", () => assertBlocked(["*shit*"]));
});

describe("censored words", () => {
    test("stars or hashes for hidden letters", () => assertBlocked(["sh*t", "s**t", "s##t", "f***", "f** u", "sh*t!"]));
    test("emphasis and stars on their own are fine", () => assertAllowed(["*hi*", "**", "* * *"]));
});

describe("whole words only (Scunthorpe problem)", () => {
    test("blocked word inside a longer word", () => assertAllowed([
        "class", "classic", "assume", "assassin", "glass", "bass", "grass", "passion", "assessment",
        "scunthorpe", "shitake", "cocktail", "cockpit", "peacock", "hancock", "dickens", "butterscotch",
        "analysis", "analog", "canal", "banal", "arsenal", "cumulative", "document", "circumstance",
        "sextant", "sussex", "titanic", "title", "manuscript", "snigger", "raccoon", "grape", "spice",
    ]));
    test("blocked word made by joining two normal words", () => assertAllowed(["therapist", "pen island", "hello kitty"]));
    test("short blocked words only match on their own", () => {
        assertBlocked(["ho", "hoe", "xx", "xxx"]);
        assertAllowed(["shoe", "whole", "echo", "photo", "phone", "who", "box", "x", "shell"]);
    });
});

describe("messages that are fine", () => {
    test("normal chat", () => assertAllowed(["hello", "hello everyone", "very nice day today", "badge"]));
    test("empty, blank or symbols only", () => assertAllowed(["", "   ", "@@@", "12345", "a", "i"]));
    test("a full-length message (48 characters) is checked quickly", () => {
        const start = Date.now();
        findBlockedPhrase("a b c d e f g h i j k l m n o p q r s t u v w x");
        findBlockedPhrase("hello ".repeat(8));
        assert.ok(Date.now() - start < 200, "took too long");
    });
});

// Known gaps: these show up as "todo" in the test output and don't fail the run.
// Remove the { todo } once the filter handles them.
describe("known gaps", () => {
    test("'!' after a word is read as 'i' (shit!!! -> shitiii)", { todo: "only map ! to i between letters" }, () =>
        assertBlocked(["shit!!!", "fuck!"]));
    test("split into pieces of 2+ letters", { todo: "no single letter in the run, so nothing is glued" }, () =>
        assertBlocked(["sh it", "fu ck", "f uck", "fuc k"]));
    test("x as a hidden letter", { todo: "see the boxer/texts trade-off" }, () =>
        assertBlocked(["fxxk", "fxck", "hXe", "shxt"]));
    test("invisible characters inside a word", { todo: "remove zero-width characters in cleanText" }, () =>
        assertBlocked(["sh​it"]));
    test("look-alike letters from other alphabets", { todo: "map Cyrillic і, с, о... to Latin" }, () =>
        assertBlocked(["shіt"]));       // Cyrillic і
    test("plurals of blocked words", { todo: "allow an optional s/es at the end of single words" }, () =>
        assertBlocked(["hoes"]));
    test("spaced-out harmless words that contain a blocked word", { todo: "inside check is too eager" }, () =>
        assertAllowed(["s h e l l", "h e l l o"]));
    test("one letter and a star", { todo: "a* matches any blocked word starting with a" }, () =>
        assertAllowed(["I got an A*", "5*"]));
});

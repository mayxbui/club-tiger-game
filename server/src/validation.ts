// Checks shared by account creation (auth.ts) and profile edits (profile.ts). No database import, so the tests in
// src/test/validation.test.ts can load this file without a DATABASE_URL.

import { findBlockedPhrase } from "./chatFilter.js";

// 3-20 letters, numbers or underscores. Same rule as USERNAME_PATTERN in client/auth/create_account.gd.
const USERNAME_PATTERN = /^[A-Za-z0-9_]{3,20}$/;

// Must match the list sizes in client/player/character_presets.gd (SKIN, HAIR, EYES)
export const SKIN_COUNT = 4;
export const HAIR_COUNT = 6;
export const EYES_COUNT = 5;

// The character options a player picked, each saved as a number (top and bottom come next checkpoint)
export type CharacterSelection = {
    skin?: number;
    hair?: number;
    eyes?: number;
};

// Returns an error message for a bad username, or null if it's fine. Runs the chat filter too, and again with digits
// read as spaces, so "kys123" is caught while "player123" is fine.
export function checkUsername(username: unknown): string | null {
    if (typeof username !== "string" || !USERNAME_PATTERN.test(username.trim())) {
        return "Username must be 3 to 20 letters, numbers, or underscores.";
    }
    const name = username.trim();
    if (findBlockedPhrase(name) !== null || findBlockedPhrase(name.replace(/[0-9]+/g, " ")) !== null) {
        return "That username isn't allowed.";
    }
    return null;
}

// True if value is a whole number from 0 up to (not including) count.
function inRange(value: unknown, count: number): boolean {
    return Number.isInteger(value) && (value as number) >= 0 && (value as number) < count;
}

// Returns an error message for a bad character selection, or null if it's fine. Missing parts are allowed (they
// default to 0 at sign-up); a part that is present must be a whole number inside its option range.
export function checkCharacter(character: unknown): string | null {
    if (typeof character !== "object" || character === null || Array.isArray(character)) {
        return "Invalid character selection.";
    }
    const c = character as Record<string, unknown>;
    if (c.skin !== undefined && !inRange(c.skin, SKIN_COUNT)) return "Invalid skin selection.";
    if (c.hair !== undefined && !inRange(c.hair, HAIR_COUNT)) return "Invalid hair selection.";
    if (c.eyes !== undefined && !inRange(c.eyes, EYES_COUNT)) return "Invalid eyes selection.";
    return null;
}

// ============================== DORM LAYOUT ==============================
export const DORM_WIDTH = 1920;
export const DORM_HEIGHT = 1080;
export const MAX_DORM_ITEMS = 100;
// Layer order (z) must match the clamp in client/dorm/dorm_room.gd.
export const MIN_ITEM_Z = -100;
export const MAX_ITEM_Z = 100;

// Catalog item's limits, as dorm.ts loads them from item_catalog.
export type CatalogLimits = { starterQty: number; minScale: number; maxScale: number };
// Saved layout for dorm items
export type DormItem = { itemId: number; x: number; y: number; z: number; scale: number };

// Checks dorm layout sent by the client. Returns layout, or an error message
export function checkDormLayout(items: unknown, catalog: Map<number, CatalogLimits>):
        { layout: DormItem[] } | { error: string } {
    if (!Array.isArray(items)) return { error: "Invalid layout." };
    if (items.length > MAX_DORM_ITEMS) return { error: `A dorm can hold at most ${MAX_DORM_ITEMS} items.` };
    const placed = new Map<number, number>();   // itemId -> copies in this layout
    const layout: DormItem[] = [];
    for (const raw of items) {
        if (typeof raw !== "object" || raw === null) return { error: "Invalid item." };
        const { itemId, x, y, z, scale } = raw as Record<string, unknown>;
        const limits = Number.isInteger(itemId) ? catalog.get(itemId as number) : undefined;
        if (!limits) return { error: "Unknown item." };
        if (typeof x !== "number" || typeof y !== "number" || !Number.isFinite(x) || !Number.isFinite(y)
            || x < 0 || x > DORM_WIDTH || y < 0 || y > DORM_HEIGHT) {
            return { error: "An item is outside the room." };
        }
        if (typeof scale !== "number" || !Number.isFinite(scale) || scale < limits.minScale || scale > limits.maxScale) {
            return { error: "An item is too big or too small." };
        }
        if (!Number.isInteger(z) || (z as number) < MIN_ITEM_Z || (z as number) > MAX_ITEM_Z) {
            return { error: "Invalid layer order." };
        }
        const copies = (placed.get(itemId as number) ?? 0) + 1;
        if (copies > limits.starterQty) return { error: "You placed more copies of an item than you own." };
        placed.set(itemId as number, copies);
        layout.push({ itemId: itemId as number, x, y, z: z as number, scale });
    }
    return { layout };
}

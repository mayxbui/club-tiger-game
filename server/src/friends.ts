// Friends (#8) and blocks (#9): requests, the friends list, unfriend, stars, block/unblock and the player search.
// The client side is the player card, client/player-card/player_card.gd.
//
// Everything here is PRIVATE: This file must never import from index.ts
//
// Messages (must match client/player-card/player_card.gd):
//   client -> server     friend_request           {username}
//   server -> sender     friend_request_result    {success, error?}
//   server -> addressee  friend_request_received  {requestId, fromUserId, fromUsername}   only if they're online
//   client -> server     friend_respond           {requestId, accept}
//   server -> sender     friend_respond_result    {success, error?}
//   server -> requester  friend_request_answered  {requestId, userId, username, accepted}  only if they're online
//   client -> server     friends_list             {}
//   server -> sender     friends_list_result      {friends: [{userId, username, character, online, starred}],
//                                                  incoming: [{requestId, userId, username, character}],
//                                                  outgoing: [{requestId, userId, username, character}],
//                                                  blocked: [{userId, username, character}]}
//   client -> server     unfriend                 {userId}
//   server -> sender     unfriend_result          {success, error?}
//   server -> other      friend_removed           {userId}                                only if they're online
//   client -> server     star_friend              {userId, starred}
//   server -> sender     star_friend_result       {success, error?, userId, starred}
//   client -> server     block_user / unblock_user  {userId}
//   server -> sender     block_result / unblock_result  {success, error?}
//   client -> server     search_users             {query}
//   server -> sender     search_users_result      {query, users: [{userId, username, character, relation}]}
//                                                  relation: "none" | "friend" | "pending" | "blocked"


import WebSocket from "ws";
import { getWorldUsername, setBlocked } from "./world.js";
import { pool } from "./db.js";

// Sends one JSON message to one socket (own copy, since this file can't import index.ts).
function send(socket: WebSocket, message: unknown){
    socket.send(JSON.stringify(message))
}

// Tells only the sender why their request failed, as a {type, success: false, error} reply (type is
// friend_request_result or friend_respond_result).
function reject(socket: WebSocket, type: string, error: string){
    send(socket,{
        type,
        success: false,
        error,
    });
}

// Rate limit for friend_request: at most 5 per 10 seconds per player
const MAX_REQUESTS = 5;
const RATE_REQUEST = 10 * 1000;
const rateLimit = new Map<number, number[]>();

// Sends a friend request by username: checks it, saves a pending row (or reuses a declined one), replies to the
// sender, and notifies the addressee if they're online.
export async function sendFriendRequest(
    socket: WebSocket,
    userId: number,
    username: unknown,
    findSocket: (id: number) => WebSocket | undefined){
    if (typeof username !== 'string' || username.trim().length === 0 || username.trim().length > 20){
        reject(socket, "friend_request_result", "User not found.");
        return;
    };

    const now = Date.now();
    const times = (rateLimit.get(userId) ?? []).filter((time)=> now - time < RATE_REQUEST);
    if(times.length >= MAX_REQUESTS){
        reject(socket, "friend_request_result", "Too many requests.");
        return;
    }
    times.push(now);
    rateLimit.set(userId,times);

    const result = await pool.query(
        `SELECT id, username FROM users
        WHERE lower(username) = lower($1)`,
        [username.trim()]
    );
    if (result.rows.length === 0){
        reject(socket, "friend_request_result","User not found.");
        return;
    }
    const addresseeId = result.rows[0].id;
    if (addresseeId === userId){
        reject(socket, "friend_request_result", "You can't add yourself.");
        return;
    }

    const blocked = await pool.query(
        `SELECT 1 FROM blocks 
        WHERE (blocker_id = $1 AND blocked_id = $2) 
            OR (blocker_id = $2 AND blocked_id = $1)`,
        [userId, addresseeId]
    );
    if(blocked.rows.length > 0) {
        reject(socket, "friend_request_result", "User not found.");
        return;
    }
    let requestId: number;
    try{
        requestId = (await pool.query(
            `INSERT INTO friendships (requester_id, addressee_id)
            VALUES($1, $2) RETURNING id`,
            [userId, addresseeId]
        )).rows[0].id;
    } catch(err: any){
        if (err.code === "23505"){
            const result = await pool.query(
                `SELECT id, requester_id, status FROM friendships
                WHERE LEAST(requester_id, addressee_id) = LEAST($1,$2) AND
                GREATEST(requester_id, addressee_id) = GREATEST($1,$2)`, 
                [userId, addresseeId]
            );
            const row = result.rows[0];
            if (row.status === 'declined'){
                await pool.query(
                    `UPDATE friendships
                    SET requester_id = $1,  
                        addressee_id = $2,
                        status = 'pending',
                        created_at = now()
                    WHERE id = $3
                    RETURNING id`,
                    [userId, addresseeId, row.id]
                );
                requestId = row.id;
            } else if(row.status === 'pending' && row.requester_id === addresseeId){
                reject(socket, "friend_request_result", "There's a pending request from that player, check your requests.");
                return;
            } else {
                reject(socket, "friend_request_result", "You already sent a request or are friends with this player.");
                return;
            }
        } else if(err.code ==="23514"){
            reject(socket, "friend_request_result", "You can't add yourself.");
            return;
        } else{
            throw err;
        }
    }
    send(socket, {
        type: "friend_request_result",
        success: true
    });

    const other = findSocket(addresseeId);
    if(other){
        send(other, {
            type: "friend_request_received",
            requestId: requestId,
            fromUserId: userId,
            fromUsername: getWorldUsername(socket, userId) ?? (await pool.query(
                `SELECT username FROM users WHERE id = $1`,
                [userId]
            )).rows[0].username,
        });
    }
}

// Accepts or declines a pending request sent to this player (the WHERE checks they're the addressee), then tells
// the requester if they're online.
export async function respondToRequest(socket: WebSocket, userId: number, requestId: unknown, accept: unknown, findSocket: (id: number)=> WebSocket|undefined){
    if (!Number.isInteger(requestId) || typeof requestId !== "number" || requestId <= 0 || typeof accept !== 'boolean'){
        reject(socket, "friend_respond_result", "Invalid request.");
        return;
    };
    const result = await pool.query(
        `UPDATE friendships SET status=$3 WHERE id=$1 AND addressee_id=$2 AND status='pending'
        RETURNING requester_id`,
        [requestId, userId, accept? 'accepted' : 'declined']
    );
    if (result.rowCount === 0){
        reject(socket, "friend_respond_result", "Request not found.");
    } else{
        send(socket, {
            type: "friend_respond_result",
            success: true,
        });
        const other = findSocket(result.rows[0].requester_id);
        if (other) {send(other,{
            type: "friend_request_answered",
            requestId: requestId,
            userId: userId,
            username: getWorldUsername(socket, userId) ?? (await pool.query(`
                SELECT username from users WHERE id = $1`,[userId])).rows[0].username,
            accepted: accept
        })}
    }

}

// Turns a row's skin/hair/eyes columns into the character object the client draws (0 if the row has none).
function characterOf(row: { skin: number | null; hair: number | null; eyes: number | null }) {
    return { skin: row.skin ?? 0, hair: row.hair ?? 0, eyes: row.eyes ?? 0 };
}

// True if the value is a real user id (a positive whole number). Ids come from the client, so they're checked.
function isUserId(value: unknown): value is number {
    return Number.isInteger(value) && (value as number) > 0;
}

// The pair condition used by several queries: the friendships row between $1 and $2, whichever side asked.
const PAIR = `LEAST(requester_id, addressee_id) = LEAST($1, $2) AND GREATEST(requester_id, addressee_id) = GREATEST($1, $2)`;

// Sends the player their friends (with avatar, online status and star; starred first, then by name), pending requests
// (incoming and outgoing) and the players they blocked.
export async function getFriendsList(socket: WebSocket, userId: number, findSocket: (id: number) => WebSocket|undefined){
    const result = await pool.query(
        `SELECT f.id, f.status, f.requester_id, u.id AS other_id, u.username, c.skin, c.hair, c.eyes,
            (s.friend_id IS NOT NULL) AS starred
        FROM friendships f JOIN users u ON u.id = CASE
            WHEN f.requester_id=$1 THEN f.addressee_id
            ELSE f.requester_id END
        LEFT JOIN characters c ON c.user_id = u.id
        LEFT JOIN friend_stars s ON s.user_id = $1 AND s.friend_id = u.id
        WHERE (f.requester_id = $1 OR f.addressee_id=$1) AND f.status <> 'declined'
        ORDER BY starred DESC, lower(u.username)
        `,[userId]
    );
    const friends = [];
    const incoming = [];
    const outgoing = [];

    for (const row of result.rows){
        if (row.status === "accepted") {
            friends.push({
                userId: row.other_id,
                username: row.username,
                character: characterOf(row),
                online: findSocket(row.other_id) !== undefined,
                starred: row.starred
            });
        } else if (row.status === "pending" && row.requester_id === userId){
            outgoing.push({ requestId: row.id, userId: row.other_id, username: row.username, character: characterOf(row) });
        } else {
            incoming.push({ requestId: row.id, userId: row.other_id, username: row.username, character: characterOf(row) });
        }
    }

    const blockedRows = await pool.query(
        `SELECT u.id, u.username, c.skin, c.hair, c.eyes FROM blocks b
        JOIN users u ON u.id = b.blocked_id
        LEFT JOIN characters c ON c.user_id = u.id
        WHERE b.blocker_id = $1 ORDER BY lower(u.username)`,
        [userId]
    );
    const blocked = blockedRows.rows.map((row) => ({ userId: row.id, username: row.username, character: characterOf(row) }));

    send(socket, {
        type: "friends_list_result",
        friends,
        incoming,
        outgoing,
        blocked
    });
}

// Ends a friendship from either side, removes both stars, replies unfriend_result, and tells the other player if they're online so their list updates.
export async function unfriend(socket: WebSocket, userId: number, friendId: unknown, findSocket: (id: number) => WebSocket|undefined){
    if (!isUserId(friendId)) {
        reject(socket, "unfriend_result", "Invalid player.");
        return;
    }
    const result = await pool.query(`DELETE FROM friendships WHERE status = 'accepted' AND ${PAIR}`, [userId, friendId]);
    if (result.rowCount === 0) {
        reject(socket, "unfriend_result", "You aren't friends with that player.");
        return;
    }
    await pool.query(
        `DELETE FROM friend_stars WHERE (user_id = $1 AND friend_id = $2) OR (user_id = $2 AND friend_id = $1)`,
        [userId, friendId]
    );
    send(socket, { type: "unfriend_result", success: true });
    const other = findSocket(friendId);
    if (other) send(other, { type: "friend_removed", userId });
}

// Stars or unstars a friend for this player only (the other player doesn't see it). Only works on accepted friends.
export async function starFriend(socket: WebSocket, userId: number, friendId: unknown, starred: unknown){
    if (!isUserId(friendId) || typeof starred !== "boolean") {
        reject(socket, "star_friend_result", "Invalid request.");
        return;
    }
    if (starred) {
        const isFriend = (await pool.query(`SELECT 1 FROM friendships WHERE status = 'accepted' AND ${PAIR}`,
            [userId, friendId])).rows.length > 0;
        if (!isFriend) {
            reject(socket, "star_friend_result", "You aren't friends with that player.");
            return;
        }
        await pool.query(`INSERT INTO friend_stars (user_id, friend_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
            [userId, friendId]);
    } else {
        await pool.query(`DELETE FROM friend_stars WHERE user_id = $1 AND friend_id = $2`, [userId, friendId]);
    }
    send(socket, { type: "star_friend_result", success: true, userId: friendId, starred });
}

// Blocks a player: saves the block and removes any friendship, request and stars between the two, all in one transaction. 
// Returns block_result; the blocked player doesn't get alert.
export async function blockUser(socket: WebSocket, userId: number, otherId: unknown){
    if (!isUserId(otherId) || otherId === userId) {
        reject(socket, "block_result", "Invalid player.");
        return;
    }
    const client = await pool.connect();
    try {
        await client.query("BEGIN");
        const exists = await client.query(`SELECT 1 FROM users WHERE id = $1`, [otherId]);
        if (exists.rows.length === 0) {
            await client.query("ROLLBACK");
            reject(socket, "block_result", "User not found.");
            return;
        }
        await client.query(`INSERT INTO blocks (blocker_id, blocked_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
            [userId, otherId]);
        await client.query(`DELETE FROM friendships WHERE ${PAIR}`, [userId, otherId]);
        await client.query(
            `DELETE FROM friend_stars WHERE (user_id = $1 AND friend_id = $2) OR (user_id = $2 AND friend_id = $1)`,
            [userId, otherId]
        );
        await client.query("COMMIT");
    } catch (err) {
        await client.query("ROLLBACK");
        throw err;
    } finally {
        client.release();
    }
    send(socket, { type: "block_result", success: true });
    // Hide the two from each other on the map right away (world.ts).
    setBlocked(userId, otherId, true);
}

// Removes this player's block on another player. It doesn't bring back the old friendship.
export async function unblockUser(socket: WebSocket, userId: number, otherId: unknown){
    if (!isUserId(otherId)) {
        reject(socket, "unblock_result", "Invalid player.");
        return;
    }
    await pool.query(`DELETE FROM blocks WHERE blocker_id = $1 AND blocked_id = $2`, [userId, otherId]);
    send(socket, { type: "unblock_result", success: true });
    // Show them to each other again, unless the other player still blocks this one.
    if ((await blockedWith(userId)).has(otherId)) return;
    setBlocked(userId, otherId, false);
}

// Returns the ids of players, if they blocked them or were blocked by them. 
// world.ts hides these players from each other; index.ts loads it when a player joins the map.
export async function blockedWith(userId: number): Promise<Set<number>> {
    const result = await pool.query(
        `SELECT blocker_id, blocked_id FROM blocks WHERE blocker_id = $1 OR blocked_id = $1`,
        [userId]
    );
    return new Set(result.rows.map((row) => (row.blocker_id === userId ? row.blocked_id : row.blocker_id)));
}

// Rate limit for search_users (the client sends it while the player types): at most 10 per 5 seconds per player
const MAX_SEARCHES = 10;
const RATE_SEARCH = 5 * 1000;
const recentSearches = new Map<number, number[]>();

// Finds up to 5 players whose username starts with the query (ignoring capitals), never the player themself, and says
// how each relates to them: "friend", "pending" (a request either way), "blocked" (blocked by this player) or "none". 
// Players who blocked this player are left out, so a block stays private (like "User not found" in requests).
export async function searchUsers(socket: WebSocket, userId: number, query: unknown){
    if (typeof query !== "string") return;
    const text = query.trim();
    // Only username characters, like USERNAME_PATTERN, so the LIKE pattern can't contain "%".
    if (text.length === 0 || text.length > 20 || !/^[A-Za-z0-9_]+$/.test(text)) {
        send(socket, { type: "search_users_result", query, users: [] });
        return;
    }
    const now = Date.now();
    const times = (recentSearches.get(userId) ?? []).filter((time) => now - time < RATE_SEARCH);
    if (times.length >= MAX_SEARCHES) return;
    times.push(now);
    recentSearches.set(userId, times);

    // "_" is a wildcard in LIKE, so it's escaped to match a real underscore.
    const prefix = text.toLowerCase().replace(/_/g, "\\_") + "%";
    const result = await pool.query(
        `SELECT u.id, u.username, c.skin, c.hair, c.eyes,
            EXISTS (SELECT 1 FROM blocks b WHERE b.blocker_id = $1 AND b.blocked_id = u.id) AS blocked_by_me,
            (SELECT f.status FROM friendships f WHERE
                LEAST(f.requester_id, f.addressee_id) = LEAST($1, u.id)
                AND GREATEST(f.requester_id, f.addressee_id) = GREATEST($1, u.id)) AS friendship
        FROM users u LEFT JOIN characters c ON c.user_id = u.id
        WHERE lower(u.username) LIKE $2 AND u.id <> $1
            AND NOT EXISTS (SELECT 1 FROM blocks b WHERE b.blocker_id = u.id AND b.blocked_id = $1)
        ORDER BY lower(u.username) LIMIT 5`,
        [userId, prefix]
    );
    const users = result.rows.map((row) => ({
        userId: row.id,
        username: row.username,
        character: characterOf(row),
        relation: row.blocked_by_me ? "blocked"
            : row.friendship === "accepted" ? "friend"
            : row.friendship === "pending" ? "pending"
            : "none"
    }));
    send(socket, { type: "search_users_result", query, users });
}

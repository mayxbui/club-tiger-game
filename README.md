# Club Tiger

A multiplayer 2D social world built with **Godot 4** and a **TypeScript WebSocket server** backed by **PostgreSQL**.
Players create an account, design their character, and step into a shared campus map where they can walk around,
chat, and decorate their own dorm room and make friends.

The client exports to **Windows, macOS, Linux and the web (HTML5)**, and a GitLab CI pipeline builds and deploys
the web version automatically.


<!-- ## Overview

- **Create account system over WebSockets:** sign-up, sign-in with username *or* email, "remember me" sessions,
  automatic session resume on launch, and logout.
- **Character customization:** skin tone, hairstyle, and eyes chosen at sign-up with a live preview, saved to the
  database and redrawn on every login.
  client never gets to say who it is.
- **Security:**
  - Passwords hashed with **bcrypt**. Session tokens are 256-bit random values, and only their **SHA-256 hashes**
    are stored, so a database leak doesn't hand out live sessions.
  - **Sliding session expiry:** 1 day of inactivity, capped at 30 days for "remember me".
  - Parameterized SQL everywhere. Multi-table writes run in **transactions**.
  - **Generic auth errors** so the server never reveals which usernames or emails exist.
  - **Login rate limiting**, a 16 KB message size cap, and **one active login per account**: signing in elsewhere
    disconnects the older client.
  - Case-insensitive unique usernames, so `May` and `may` can't both exist.
- **Resilient networking:** the client reconnects automatically and resumes the player's session.
- **CI/CD:** GitLab CI exports Windows and web builds with a Godot Docker image and publishes the web build to
  GitLab Pages. -->

# Tech stack

| Layer    | Technology                                                                   |
|----------|------------------------------------------------------------------------------|
| Client   | Godot 4.7 (GDScript), GL Compatibility renderer, `WebSocketPeer`             |
| Server   | Node.js 22, TypeScript, [`ws`](https://github.com/websockets/ws)             |
| Database | PostgreSQL with [`pg`](https://node-postgres.com/) connection pooling        |
| Auth     | `bcryptjs`, Node `crypto` (random tokens + SHA-256)                          |
| CI/CD    | GitLab CI, `barichello/godot-ci` Docker image, GitLab Pages                  |

## Architecture

```
┌──────────────────────┐      JSON over WebSocket       ┌──────────────────────┐      SQL      ┌────────────┐
│  Godot client        │  ───────────────────────────▶  │  Node/TS server      │  ──────────▶  │ PostgreSQL │
│  Network (autoload)  │  ◀───────────────────────────  │  ws + message router │  ◀──────────  │            │
│  Session (autoload)  │                                │  auth / sessions     │               │            │
└──────────────────────┘                                └──────────────────────┘               └────────────┘
```

- **`Network`** (autoload) owns the WebSocket: it polls it, parses JSON, emits `message_received`, and handles
  reconnects plus account-wide events such as being signed out from another device.
- **`Session`** (autoload) holds the signed-in player's data across scene changes.
- The **server** routes each message by `type`, keeps a map from each socket to its user, and answers with
  `<type>_result` messages. Unexpected errors are logged on the server, and the client only gets a generic message.

### Message protocol (current)

| Client → Server   | Server → Client          | Purpose                                                   |
|-------------------|--------------------------|-----------------------------------------------------------|
| `create_account`  | `create_account_result`  | Validate, hash the password, create user + character + dorm |
| `login`           | `login_result`           | Check credentials and issue a session token               |
| `resume_session`  | `resume_session_result`  | Exchange a saved token for the player's profile           |
| `logout`          | `logout_result`          | Revoke the session token                                  |
| —                 | `kicked`                 | The same account signed in on another client              |
| —                 | `error`                  | Malformed message or server error                         |

### Database schema

`users` · `characters` (1:1) · `sessions` (1:many) · `password_resets` · `friendships` and `blocks` (self-joins on
`users`) · `dorms` (1:1) · `item_catalog` and `dorm_items` (furniture placement with position, layer, and scale).
See [`server/sql/schema.sql`](server/sql/schema.sql).


## Project structure

```
club-tiger/
├── project.godot              Godot project (main scene: client/splash_screen.tscn)
├── client/
│   ├── splash_screen.*        Entry screen; auto-resumes a saved session
│   ├── auth/                  Sign-in, create-account, reset-password screens
│   ├── map/                   Shared world map
│   ├── player/                Player scene, character customizer, presets
│   ├── network/               Network and Session autoloads
│   └── assets/                Sprites, fonts, map art
├── server/
│   ├── src/index.ts           WebSocket server and message router
│   ├── src/auth.ts            Account creation and login
│   ├── src/sessions.ts        Session tokens: create, validate, revoke, cleanup
│   ├── src/db.ts              PostgreSQL pool
│   └── sql/schema.sql         Database schema (safe to re-run)
└── .gitlab-ci.yml             Export and deploy pipeline
```

## Running locally

See [`requirements.txt`](requirements.txt) for versions.

### 1. Database
```bash
createuser -P club_tiger
createdb -O club_tiger club_tiger
psql -h localhost -U club_tiger -d club_tiger -f server/sql/schema.sql
```

### 2. Server
```bash
cd server
npm install
cp .env.example .env      # then set DATABASE_URL (and PORT if 3103 is taken)
npm run dev               # auto-reloads on changesn - use `npm run build && npm start` for production
```

### 3. Client
1. Open `project.godot` in **Godot 4.7**.
2. In `client/network/network.gd`, point `url` at your server, e.g. `ws://localhost:3103`.
3. Press **F5**. To test multiplayer on one machine, use *Debug → Customize Run Instances* to launch several
   clients at once.
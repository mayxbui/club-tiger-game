# Club Tiger

## About

**Club Tiger is a cozy online hangout set on a college campus.** Make your own character, step onto the campus map,
and explore it together with everyone else who's online, in real time.

It's a place to unwind between classes, meet new people, and make the campus your own. Soon you'll be able to chat
with other players, add friends, and decorate a dorm room that's all yours.

<!-- A multiplayer 2D social world built with **Godot 4** and a **TypeScript WebSocket server** backed by **PostgreSQL**.
Players create an account, design their character, and step into a shared campus map where they can walk around,
chat, and decorate their own dorm room and make friends. -->

<!-- The client exports to **Windows, macOS, Linux and the web (HTML5)**, and a GitLab CI pipeline builds and deploys the web version automatically. -->

### Features

**Available now**
- **Make it yours:** choose your character's skin tone, hairstyle, and eyes, and see the preview change as you pick.
  Your look is saved and waiting every time you come back.
- **Explore together:** walk around the shared campus map and see other players moving around you.
- **Jump right back in:** sign in with your username or email, and check "Remember me" to skip signing in next time.
- **Never get locked out:** forgot your password? Get a one-time code by email and set a new one.

**Coming soon**
- **Chat** with other players, with a filter to keep conversations friendly
- **Friends**, so you can find the people you meet again
- **Your own dorm room** to decorate with furniture

### Tech stack

| Layer    | Technology                                                          |
|----------|---------------------------------------------------------------------|
| Client   | [Godot 4.7](https://godotengine.org/) (GDScript)                    |
| Server   | Node.js 22, TypeScript                                              |
| Database | PostgreSQL                                                          |
| Auth     | `bcryptjs`, Node `crypto`, `nodemailer`                             |
| CI/CD    | GitLab CI, `barichello/godot-ci` Docker image, GitLab Pages         |

### Project architecture

```
Godot client  <── WebSocket ──>  Node.js server  <──>  PostgreSQL
```

<!-- ### Project structure

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
│   ├── src/auth.ts            Account creation, login, and password reset
│   ├── src/sessions.ts        Session tokens: create, validate, revoke, cleanup
│   ├── src/world.ts           Players on the map and movement sync
│   ├── src/chat.ts            Chat (in progress)
│   ├── src/chatFilter.ts      Chat word filter (in progress)
│   ├── src/data/              Password reset email template
│   ├── src/db.ts              Database connection
│   └── sql/                   Database setup
├── requirements.txt           Tool and package versions
└── .gitlab-ci.yml             Export and deploy pipeline
```
-->


<!-- ## Visuals -->

<!-- Replace with a screenshot or GIF of the game: ![Club Tiger gameplay](docs/screenshot.png) -->
<!-- *Screenshots coming soon.* -->


## Installation

### Requirements
- **Windows 10 or later**, or a modern web browser (Chrome, Firefox, Edge, or Safari)
- An internet connection, since the game connects to the Club Tiger server

<!-- ### Play in the browser
1. Open the Club Tiger web build. Add the GitLab Pages link here -->
<!-- 2. Wait for the game to load. No download is needed. -->

<!-- ### Play on Windows
1. Download the latest Windows build. (Add the download link here)
2. Unzip the folder and run `club-tiger.exe`.
3. If Windows SmartScreen shows a warning, click **More info → Run anyway**. The game isn't code-signed yet. -->


## Usage

1. **Create an account.** Choose a username, enter your email, and pick a password of at least 8 characters.
2. **Design your character.** Pick a skin tone, hairstyle, and eyes. The preview updates as you choose.
3. **Enter the campus.** You'll appear on the shared map with everyone else who's online.
4. **Walk around.** Click anywhere on the map and your character walks there.
5. **Stay signed in.** Check **Remember me** at sign-in and the game logs you back in automatically next time.

Forgot your password? Click **Forgot password?** on the sign-in screen and a one-time code will be emailed to you.


## Project status

Club Tiger is a work in progress.

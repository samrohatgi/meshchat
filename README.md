# MeshChat

An offline, peer-to-peer chat app for iOS. No internet connection, server, or
phone number required — messages travel directly between nearby iPhones over
Bluetooth and peer-to-peer WiFi (via Apple's MultipeerConnectivity
framework), and can relay through other users' devices to reach further than
one direct hop.

This is a **complete Swift/SwiftUI source project**. Compiling it into an
app still has to happen on Apple's toolchain (Xcode) somewhere — that's an
Apple platform rule, not something any tool can route around — but you
don't need to own a Mac to make that happen. Two paths are documented
below:

- **Path A — No Mac needed (recommended if you don't have one):** GitHub
  builds the app for you on a free cloud Mac, and you sideload the result
  onto your iPhone from Windows/Linux using a free tool called Sideloadly.
- **Path B — You have a Mac:** build and install directly from Xcode.

## Path A: Build with GitHub Actions, install with Sideloadly (no Mac required)

### What you need
- A free [GitHub](https://github.com) account.
- A free Apple ID (just your regular iCloud login — no developer account needed for this).
- [Sideloadly](https://sideloadly.io) installed on your Windows or Linux PC.
- Your iPhone and a USB cable.

### A1. Push this project to a GitHub repo
1. Go to github.com → **New repository** → name it `meshchat` → Create.
2. Upload everything in this folder (drag-and-drop works on the repo's
   "Add file → Upload files" page), or if you're comfortable with git:
   ```
   git init
   git add .
   git commit -m "MeshChat"
   git branch -M main
   git remote add origin https://github.com/<your-username>/meshchat.git
   git push -u origin main
   ```

### A2. Let GitHub build the IPA
1. In your repo on GitHub, click the **Actions** tab.
2. You'll see a workflow called **"Build unsigned MeshChat IPA"** — it runs
   automatically on push, or click **Run workflow** to trigger it manually.
3. Wait ~3–5 minutes for it to finish (green checkmark).
4. Click into the completed run → under **Artifacts**, download
   **MeshChat-ipa**. Unzip it — you'll have `MeshChat.ipa`.

This workflow (`.github/workflows/build-ipa.yml`) runs `xcodegen` to turn
`project.yml` into a real `.xcodeproj`, then `xcodebuild` with code signing
turned off, then zips the result into an IPA. All on GitHub's free macOS
runners — nothing installs on your machine for this step.

### A3. Sideload it onto your iPhone
1. Install [Sideloadly](https://sideloadly.io) on your PC and open it.
2. Plug your iPhone in via USB and let it trust the computer.
3. Drag `MeshChat.ipa` into Sideloadly.
4. Enter your Apple ID (a free one is fine — Sideloadly only uses it to
   generate a personal signing certificate, same mechanism Xcode uses).
5. Click **Start**. It signs and installs the app on your phone.
6. On the iPhone: **Settings → General → VPN & Device Management** → trust
   your Apple ID's developer profile the first time you open the app.

**Heads up:** apps signed with a free Apple ID stop opening after **7
days** — that's an Apple limitation on free signing certificates, same as
the Xcode path. Re-sideloading takes under a minute: reopen Sideloadly,
drag the same IPA in again, click Start. A $99/year Apple Developer account
removes this limit if it becomes annoying.

Repeat step A3 on a second iPhone to test messaging between two devices.

---

## Path B: You have a Mac

### What you need

- A Mac with [Xcode](https://apps.apple.com/us/app/xcode/id497799835) installed (free from the Mac App Store).
- A free Apple ID (for a paid $99/year Apple Developer account you also get
  longer-lived installs and TestFlight distribution — see "Installing on
  your iPhone" below).
- Two iPhones to actually test messaging between devices (the iOS Simulator
  cannot do Bluetooth/peer discovery, so you need physical hardware for at
  least the sending side — ideally two real devices).

## 1. Create the Xcode project

1. Open Xcode → **File → New → Project**.
2. Choose **iOS → App**, click Next.
3. Product Name: `MeshChat`. Interface: **SwiftUI**. Language: **Swift**.
   Uncheck "Use Core Data" and "Include Tests" (not needed).
4. Save it anywhere on your Mac.

## 2. Add the source files

1. Delete the default `ContentView.swift` that Xcode generated (keep the
   auto-generated `MeshChatApp.swift` — you'll overwrite it in step 2).
2. In Finder, drag the entire `Sources` folder from this project (`App`,
   `Models`, `Services`, `Views`) into your Xcode project navigator. When
   prompted, choose **"Copy items if needed"** and make sure your app
   target's checkbox is ticked.
3. When it asks about the existing `MeshChatApp.swift`, replace the
   generated one with the one from `Sources/App/MeshChatApp.swift`.

Your project navigator should now have: `App/MeshChatApp.swift`,
`Models/*.swift`, `Services/*.swift`, `Views/*.swift`.

## 3. Add required Info.plist permissions

MultipeerConnectivity uses Bluetooth and local WiFi, both of which require
usage-description strings on iOS 14+, or your app will crash instantly when
it tries to advertise/browse. Select your project → target **MeshChat** →
**Info** tab → add these rows (as **Custom iOS Target Properties**):

| Key | Type | Value |
|---|---|---|
| `NSLocalNetworkUsageDescription` | String | `MeshChat uses your local network to discover and message nearby devices.` |
| `NSBonjourServices` | Array | one item: `_meshchat-p2p._tcp` |
| `NSBluetoothAlwaysUsageDescription` | String | `MeshChat uses Bluetooth to discover and message nearby devices without internet.` |

(The Bonjour service name must exactly match the `serviceType` string in
`MeshManager.swift`, currently `"meshchat-p2p"`.)

## 4. Signing

Select the project in the navigator → target **MeshChat** → **Signing &
Capabilities**:

- Check **"Automatically manage signing"**.
- Under **Team**, pick your Apple ID (add it via Xcode → Settings →
  Accounts if it's not listed yet).
- Xcode will assign a bundle identifier — change it to something unique,
  e.g. `com.yourname.meshchat`, if it conflicts.

## 5. Installing on your iPhone

**Free Apple ID (no cost):**
Plug your iPhone into your Mac (or use wireless debugging), select it as
the run destination in Xcode's toolbar, and click **Run (▶)**. The app
installs directly. On your iPhone, go to **Settings → General → VPN &
Device Management** and trust your developer certificate the first time.
Apps installed this way stop working after **7 days** and need to be
re-installed from Xcode (reconnect and hit Run again) — this is an Apple
platform limitation for free accounts, not something in this app.

**Paid Apple Developer account ($99/year):**
Same steps, but the app keeps working indefinitely, and you can also
distribute it via **TestFlight** so other people can install it without a
cable — useful once you have more than a couple of testers.

Repeat step 5 on a second iPhone to actually test messaging between two
devices.

## Using the app

1. On first launch, pick a display name.
2. Keep Bluetooth and WiFi on. The app automatically discovers and connects
   to any other nearby phone running MeshChat — no pairing code needed.
3. Tap the pencil icon to start a chat with a discovered device, or tap into
   an existing conversation.
4. Messages sent to someone outside direct range are flooded to whichever
   devices you *are* connected to; if one of them is also connected to your
   intended recipient (directly or through further hops), it relays the
   message onward automatically, up to 6 hops.

## Known limitations (by design, given the "no server" constraint)

- **Range**: direct Bluetooth/WiFi-P2P range is roughly 10–100m depending on
  obstacles. Mesh relay extends this only as far as there's a continuous
  chain of other MeshChat users with the app open.
- **No delivery guarantee across the mesh**: this uses simple flood relay
  with a hop limit, not a routing protocol — if there's no continuous chain
  of connected devices from sender to recipient, the message never arrives
  (there's nowhere to store it for later delivery), unlike WhatsApp's
  server-relayed model.
- **No encryption beyond transport**: MultipeerConnectivity sessions use
  `.required` encryption in transit, but there's no end-to-end key exchange
  or at-rest encryption of the local message store, unlike WhatsApp's
  Signal-protocol E2E encryption. Add this if you need it for real use.
- **iOS only**: this project uses MultipeerConnectivity, an Apple-only
  framework. An Android build would need a different transport stack
  (Android's Nearby Connections API or raw BLE/Wi-Fi Direct) and is not
  included here.
- **App must be open**: like most peer-to-peer Bluetooth apps, iOS
  background execution limits mean reliable discovery/relay generally
  requires the app to be in the foreground on relaying devices.

## Project structure

```
project.yml                      - xcodegen spec (generates the .xcodeproj, used by Path A's CI build)
.github/workflows/build-ipa.yml  - GitHub Actions workflow that builds an unsigned IPA on macOS runners
Sources/
  App/MeshChatApp.swift          - app entry point, wires up MeshManager + ChatStore
  Models/
    Peer.swift                   - a discovered/connected device
    ChatMessage.swift            - one message in a conversation
    Conversation.swift           - a peer + its message history
    MeshPacket.swift             - wire format sent over MultipeerConnectivity
  Services/
    MeshManager.swift            - Bluetooth/WiFi P2P transport + flood mesh relay
    ChatStore.swift               - local JSON persistence + message routing
  Views/
    OnboardingView.swift         - first-run display name picker
    ConversationListView.swift   - chat list (home screen)
    NewChatView.swift            - nearby-device picker
    ChatView.swift               - message thread + input bar
    MessageBubble.swift          - individual message bubble
```
# meshchat

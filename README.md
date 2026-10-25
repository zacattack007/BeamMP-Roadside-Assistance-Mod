# BeamMP Roadside Assistance

Player-operated towing and recovery for BeamMP. Players request help for a stranded vehicle, and another player accepts the job and uses their own tow truck to recover it.

The in-game Roadside Assistance app lets players request help, browse open jobs, accept recoveries, and manage their current job with buttons. The mod also provides chat commands, notifications, and a private vehicle locator for the assigned helper. Use your existing tow truck's normal towing controls. There are no automatic repairs, teleports, towing physics changes, or payments.

## Installation

Requires BeamMP Server 3.1.0 or newer.

1. From a release ZIP, merge its `Resources` folder into your BeamMP server folder. Other mods can stay in place.
2. When installing from this repository instead, copy `BeamMP-Roadside-Assistance-Mod/Server/Roadside Assistance` into `Resources/Server`, and copy the ZIP from `BeamMP-Roadside-Assistance-Mod/Client` into `Resources/Client`.
3. Keep `BeamMP-Roadside-Assistance.zip` zipped. Do not install `ClientSource` in `Resources/Client`.
4. Restart the server and reconnect. BeamMP downloads the client ZIP to joining players.
5. In BeamNG, open the **UI Apps** editor, choose **Add App**, select **Roadside Assistance**, then save your layout. Resize or move it as desired.

```text
YourServer/
  Resources/
    Server/
      Roadside Assistance/
        Main.lua
    Client/
      BeamMP-Roadside-Assistance.zip
```

When updating, replace both the existing roadside server script and client ZIP. Keep only one installation of this server plugin: if your older copy uses a different plugin folder name, update that copy instead of running a second copy beside it.

No owner username or admin configuration is needed. All players can request or volunteer to help. This is a separate mod from the Delete Vehicle mod, and can run alongside it.

## In-game app

- **Request roadside help** selects the vehicle you are currently driving.
- **Open requests** shows the live job board with an **Accept job** button on each request.
- **Your request** shows whether you are waiting or which helper is coming, with **Cancel my request**.
- **Your recovery job** provides **Locate vehicle**, **Complete job**, and **Release job**.
- Status and feedback appear inside the panel. The refresh icon reloads the board; it also refreshes automatically every five seconds. Changes made through chat update the panel too.

The server checks button actions using the same ownership and assignment rules as chat commands. The app disables actions while disconnected or while you already have a conflicting request/job. A request cooldown is shown on the request button.

If the app stays on "Waiting for server", confirm both parts of the mod were updated, restart, and reconnect. You can always use the chat commands below. The app does not open a separate desktop application.

## Commands

| Command | Purpose |
| --- | --- |
| `/assist` | Request help for the vehicle you are currently driving. |
| `/assist <vehicle_id>` | Request help for a specific vehicle you own. Also works without automatic client selection. |
| `/assist vehicles` | List your own vehicle IDs and request commands. |
| `/assist list` | Show open requests and their job IDs. |
| `/assist accept <job_id>` | Accept one open request and mark its vehicle on your screen. |
| `/assist status` | Show your own request or accepted job and its assigned helper. |
| `/assist locate` | Refresh the marker for your accepted job. |
| `/assist complete` | Mark your accepted job finished and notify the requesting player. |
| `/assist release` | Give up your accepted job so another helper can take it. |
| `/assist cancel` | Cancel your own request or pending vehicle selection. |
| `/assist help` | Show help privately. |

**Job IDs and vehicle IDs are different.** If someone requests help for vehicle ID 0 and receives job #4, the helper uses `/assist accept 4`.

## Typical job

1. The stranded player enters their vehicle and types `/assist`.
2. The server announces the new request with an accept command.
3. A tow operator types `/assist accept 4`, using the announced job number.
4. The requesting player is told who accepted. The helper sees an orange beacon and label on the exact stranded vehicle, with its owner, IDs, and distance from the camera.
5. The helper drives there and operates their tow truck normally.
6. When recovery is done, the helper types `/assist complete`. Both players receive confirmation and the marker clears.

Each player can have one active request **or** one accepted job. Only one helper can accept each request. You cannot accept your own job. Helpers must explicitly mark completion; the mod does not detect towing or recovery success. Any player can volunteer; truck model restrictions are not imposed.

There is a 30-second cooldown between successful requests. Server owners can adjust `REQUEST_COOLDOWN` at the top of `Server/Main.lua`.

## Locator and cleanup

The assigned helper's marker follows the target vehicle for up to ten minutes. Use `/assist locate` to refresh it. The label can be drawn through scenery, but you still need to look toward it. Existing GPS navigation and camera controls are unchanged.

The target vehicle must be spawned locally. If it is queued in BeamMP, apply the queued vehicles and use `/assist locate` again. If no target is available after five seconds, the client explains this and stops its marker. A missing client ZIP means automatic selection and visual markers will not work; install it and reconnect. You can still submit a request with `/assist <vehicle_id>`.

- Cancelled or completed jobs clear the helper's marker and assignment.
- If the helper disconnects or releases the job, it reopens for others.
- If the requesting player disconnects or removes the stranded vehicle, their request is cancelled.
- A five-second maintenance check also catches vehicle removal by other mods.
- Job state is held in memory. A server restart or plugin reload clears the board; players must request again. A reload sends a marker-clear event to connected clients.

## Testing

Solo: install both parts, add the UI app, spawn a vehicle, and test the request/cancel buttons. Also try `/assist`, `/assist status`, `/assist list`, and `/assist cancel`. You can also test `/assist vehicles` and explicit vehicle requests. Your own job cannot be accepted for a solo tow test.

With two players: request assistance, accept it from the second player, check the marker identifies the correct vehicle, perform a tow, and complete the job. Also test release/re-accept, cancellation, vehicle deletion, and disconnecting each player during an active assignment.

Automated checks use Python 3 and Lupa:

```text
python -m pip install lupa
python tests/test_server.py
python tests/test_client.py
```

They exercise server behavior in Lua 5.3 and client logic in LuaJIT using mocked BeamMP/BeamNG APIs. They do not verify live multiplayer delivery or actual in-game rendering.

## Editing the client

Edit Lua files in `ClientSource`, then run this from the repository root:

```text
python tools/build_client.py
```

Install the rebuilt ZIP from `BeamMP-Roadside-Assistance-Mod/Client` and reconnect. The build includes the Lua extension and all UI app assets. The `ClientSource`, `tools`, and `tests` folders do not go in the server's `Resources/Client` folder.

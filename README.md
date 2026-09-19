# CraftScanner

C++ DLL mod for **SurrounDead v0.8.0** (UE 5.6.1, UE4SS 3.0.1 Beta).

Press **F2** to see a notification listing all crafting resources across
the entire player inventory — backpack, pockets, worn clothing, and every
special container (MedBag, LunchBox, AmmoTin, WeaponsCase, Toolboxes, Wallet,
Safe, Briefcase) — including nested sub-containers.

## Requirements

- SurrounDead v0.8.0
- UE4SS 3.0.1 Beta (experimental builds only; stable release lacks UE 5.6 signatures)

## Installation

1. Copy the `CraftScanner` folder into
   `...\SurrounDead\Binaries\Win64\ue4ss\Mods\`.
2. Ensure `mods.txt` contains `CraftScanner : 1`.
3. Launch the game, press F2 in a loaded save.

## Configuration

Edit `CraftScanner.ini` in the mod folder. Keybinds require a game restart;
filter values are re-read on each press.

## Building
.\build.ps1 # incremental
.\build.ps1 -Clean # full reconfigure
.\deploy.ps1 # copy to game


## Known limitations

- Item type filters rely on gameplay tag substrings; verify tag names by
  turning on `VerboseLog=1` and inspecting `UE4SS.log`.
- Notification length is bounded by the game UI. Default `MaxLines=40`.
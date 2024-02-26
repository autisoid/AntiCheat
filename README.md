# AntiCheat
VAC doesn't work in Sven Co-op, so we need to develop custom solutions to detect haxxors. This plugin blocks the following hacks:
- AirStuck (a.k.a. Freeze) (Any types: Clumsy, Alt + Space in windowed mode, sc_freeze/sc_freeze2 from sven_internal, sc_speedhack 0 in sven_internal, "New" mode in AirStuck module in oxware)
- Speedhack (Detects as-is, applies huge forgiving conditions to players with bad connection, still in beta. Detection works only with high values like sc_speedhack 50) ( Recommended to use with "clockwindow 0.1" to harden the life of hackers =) )

Feel free to report any false-positives, don't forget to describe "how to reproduce"!

# GE_HUD v1.73205..
A head-up display for emulating Goldeneye. The current example marks all guards in red. The core code and 'guard marking' code is quite seperate, and should be quite easy to adapt to a different purpose, especially using Wyster's libraries (https://forums.the-elite.net/index.php?topic=21141.msg437009#msg437009). That said, future versions will hopefully have a nice interface for selecting what you want to mark and how. 

This (2nd really) version has made substantial changes to the core:
* Updates only when frames are drawn
* Caches camera in advance: no lag even as Bond turns sharply, nor on zoom
* Bond wobble accounted for: The HUD properly (probably) accounts for Bond's aim swaying slightly
* Look-down / up fixed: HUD no longer gets severely warped


*Minor issues*
* Occassionally a draw happens 1 frame earlier than we predicted, and so HUD is behind.
  This mistake does not snowball, and is probably unnoticable when playing in real time.

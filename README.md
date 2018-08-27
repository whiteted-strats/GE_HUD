# GE_HUD v3

A head-up display for emulating Goldeneye. The core code has finally be properly encapsulated, and actually has a nice interface. The best example of how to use this is found in the example, HUD_all_guards.lua. Wyster's libraries (https://forums.the-elite.net/index.php?topic=21141.msg437009#msg437009) are your friend here. The interface supports:
* Simple markers: position, thickness, colour
* Lines, splines, polygons
* Circles: the centerpiece, set center, radius and any normal (up-vector) you like. Drawn as a irregular n-gon, with n and the irregularness varying based on distance and how steep an angle the circle is being viewed at. For efficiency, adjust the coarseness value, a higher value lowering n.

*Minor issues*
* Efficiency: I haven't checked that line clipping is doing it's job. Also circles are made into polygons and then these are clipped. I really should consider them as a whole first, to see if the entire thing is out of view.
* Doesn't draw in cutscenes / Bond's death (a leftover from v1.73..), when it can and should.
* I've only found the matrices for Aztec and Surface 1 (though it's easy to find similar ones on the other levels). This is because of the bigger issue..

*Major issues*
* In lag the HUD dies. Simply put, the right matrix isn't selected on the right frame. This needs looking into but I cba atm. I'll add my matrix finder to this repository.

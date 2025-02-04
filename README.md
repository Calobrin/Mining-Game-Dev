May as well make a README eventually so uh, here we go.

This Github Repository is to track the progress of my development of my game. 
I am making a Mining Game in Godot that will allow players to go into a mines and dig up shiny crystals, rocks, or other valuable minerals just for fun. 
I am inspired by games like Webfishing (and a bit of Atlyss) to make a fairly mindless but chill game just about gathering shiny things in the ground.

In branch 0.02 I set up an interactable 3DSprite/label with an Area3D to detect when the player enters its radius and enables the "E" interact key. When interacting with this sprite it will scene swap into the actual Mines level 1 scene. 
I also set up the interactable sprite to exist within the mines so the player can then leave and return to "town".
Which then caused the obvious problem of appearing at the default player node location so I set up a spawnpoint node that I can name to allow multiple "landing spots" when tranporting from various scenes into town.

I set up a global.gd script that I can use to keep track of the current scene, made a script to attach to town which will detect what scene the player is coming from and move the players location 
to that of the spawnpoint nodes I created that match to what scene they were coming from

Still learning a lot and there is likely a better way to do what I am doing, but hey I am slowly making progress.

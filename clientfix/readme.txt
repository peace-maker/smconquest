=== SM:Conquest client-side fix ===

By installing this fix, you only readd a removed font to the game.
That way plugins are able to use the HudMsg usermessage to print text anywhere on your screen.
You will never notice this on any server other than Conquest ones, since it's normally not supported by CS:S.

This will NOT get you VAC banned. You're able to modify your HUD yourself as you like by editing the clientscheme.res.

Install Instructions:
 1. Copy the conquest folder into your "custom" folder inside your Counter-Strike:Source folder.
  * The full path should look something like 
	C:\Program Files\Steam\SteamApps\common\Counter-Strike Source\cstrike\custom\conquest\resource
 2. Install the Font. (Rightclick conquest.ttf, Install)
 3. Restart Counter-Strike: Source if you have it open.
 4. Join a server running the SM:Conquest plugin.

If have a custom HUD already, paste this block inside the Fonts section:

		"CenterPrintText"
		{
			"1"
			{
				"name"		"conquest"
				"tall"		"38"
				"weight"	"900"
				"range"		"0x0000 0x007F" // Basic Latin
				"antialias"	"1"
			}
		}
/*
 * Handles the flag actions
 * Part of SM:Conquest
 *
 * Thread: https://forums.alliedmods.net/showthread.php?t=154354
 * visit http://www.wcfan.de/
 */
#include <sourcemod> // Just in here for Pawn Studio..
#include <sdktools>
#include <colors>


#define HUDMSG_FADEINOUT 0 // fade in/fade out
#define HUDMSG_FLICKERY 1 // flickery credits
#define HUDMSG_WRITEOUT 2 // write out

#define FLAG_NAME 0
#define FLAG_DEFAULTTEAM 1
#define FLAG_CURRENTTEAM 2
#define FLAG_REQPLAYERS 3
#define FLAG_TIME 4
#define FLAG_POSITION 5
#define FLAG_MINS 6
#define FLAG_MAXS 7
#define FLAG_FLAGENTITY 8
#define FLAG_TRIGGERENTITY 9
#define FLAG_CONQUERTIMER 10
#define FLAG_CONQUERSTARTTIME 11
#define FLAG_LOGICTRIGGERT 12
#define FLAG_LOGICTRIGGERCT 13
#define FLAG_ROTATION 14

new Handle:g_hFlags;
new Handle:g_hPlayersInZone;

new g_iRedHudMsg[4] = {206, 24, 25, 200};
new g_iBlueHudMsg[4] = {25, 128, 194, 200};

new g_iPlayerSpottedOffset = -1;

/**
 * Entity Output Handlers
 */
public EntOut_OnStartTouch(const String:output[], caller, activator, Float:delay)
{
	// Ignore dead players
	if(g_bRoundEnded || activator < 1 || activator > MaxClients || !IsPlayerAlive(activator))
	{
		return;
	}
	
	// Get array index of this trigger
	decl String:sTargetName[64];
	GetEntPropString(caller, Prop_Data, "m_iName", sTargetName, sizeof(sTargetName));
	ReplaceString(sTargetName, sizeof(sTargetName), "scq_zone_", "");
	new iIndex = StringToInt(sTargetName);
	
	//PrintToChatAll("%N entered zone %d", activator, iIndex);
	//PrintToServer("%N entered zone %d", activator, iIndex);
	
	new Handle:hFlag = GetArrayCell(g_hFlags, iIndex);
	
	new iCurrentTeam = GetArrayCell(hFlag, FLAG_CURRENTTEAM);
	
	new Handle:hPlayers = GetArrayCell(g_hPlayersInZone, iIndex);
	
	// Save that player as being in the zone in order of entering
	PushArrayCell(hPlayers, activator);
	
	// Interupt, if enemy is currently conquering that flag
	if(GetConVarBool(g_hCVEnableContest)
	&& GetArrayCell(hFlag, FLAG_CONQUERSTARTTIME) != -1
	&& GetClientTeam(GetArrayCell(hPlayers, 0)) != GetClientTeam(activator))
	{
		// Stop the conquer timer
		new Handle:hConquerTimer = GetArrayCell(hFlag, FLAG_CONQUERTIMER);
		if(hConquerTimer != INVALID_HANDLE)
		{
			KillTimer(hConquerTimer);
			SetArrayCell(hFlag, FLAG_CONQUERTIMER, INVALID_HANDLE);
		}
		
		SetArrayCell(hFlag, FLAG_CONQUERSTARTTIME, -1);
		
		// Log his success :)
		LogPlayerEvent(activator, "triggered", "scq_flag_contested");
		
		// Remove the progress bar
		new iPlayers = GetArraySize(hPlayers);
		new iClient;
		for(new i=0;i<iPlayers;i++)
		{
			iClient = GetArrayCell(hPlayers, i);
			Client_PrintKeyHintText(iClient, "%t", "Contested");
			PrintCenterText(iClient, "%t", "Contested");
			SetEntPropFloat(iClient, Prop_Send, "m_flProgressBarStartTime", 0.0);
			SetEntProp(iClient, Prop_Send, "m_iProgressBarDuration", 0);
		}
		return;
	}
	
	new iTeam = GetClientTeam(activator);
	
	// Don't care, if his team already owns that flag.
	if(iTeam == iCurrentTeam)
		return;
	
	new iRequiredPlayers = GetArrayCell(hFlag, FLAG_REQPLAYERS);
	new iCurrentPlayers = GetArraySize(hPlayers);
	
	new iTime = GetArrayCell(hFlag, FLAG_TIME);
	
	new iTeamCount = GetTeamClientCount(iTeam);
	
	// Enable a team with less players as required to capture that flags
	if(GetConVarBool(g_hCVHandicap) && iTeamCount < iRequiredPlayers)
		iRequiredPlayers = iTeamCount;
	
	// Check if only one team is in the zone now again
	if(GetConVarBool(g_hCVEnableContest) && GetTeamOfPlayersInZone(iIndex) == -1)
	{
		new iClient;
		for(new i=0;i<iCurrentPlayers;i++)
		{
			iClient = GetArrayCell(hPlayers, i);
			Client_PrintKeyHintText(iClient, "%t",  "Contested");
			PrintCenterText(iClient, "%t", "Contested");
		}
	}
	// Not enough players.
	else if(iCurrentPlayers < iRequiredPlayers)
	{
		//PrintToChatAll("Not enough players.");
		new iClient;
		for(new i=0;i<iCurrentPlayers;i++)
		{
			iClient = GetArrayCell(hPlayers, i);
			Client_PrintKeyHintText(iClient, "%t", "Need more players", (iRequiredPlayers-iCurrentPlayers));
		}
	}
	// enough players now?
	else if(iCurrentPlayers == iRequiredPlayers)
	{
		// Start conquer timer
		new Handle:hConquerTimer = CreateTimer(float(iTime), Timer_OnConquerFlag, iIndex, TIMER_FLAG_NO_MAPCHANGE);
		SetArrayCell(hFlag, FLAG_CONQUERTIMER, hConquerTimer);
		SetArrayCell(hFlag, FLAG_CONQUERSTARTTIME, GetTime());
		
		// Play a sound
		if(iTeam == CS_TEAM_T)
		{
			if(strlen(g_sSoundFiles[CSOUND_REDTEAM_STARTS_CONQUERING]) > 0)
				EmitSoundToAll(g_sSoundFiles[CSOUND_REDTEAM_STARTS_CONQUERING], SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_LIBRARY);
		}
		else if(iTeam == CS_TEAM_CT)
		{
			if(strlen(g_sSoundFiles[CSOUND_BLUETEAM_STARTS_CONQUERING]) > 0)
				EmitSoundToAll(g_sSoundFiles[CSOUND_BLUETEAM_STARTS_CONQUERING], SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_LIBRARY);
		}
		
		new iClient;
		// Show it now to all players, if requires more than 1
		if(iRequiredPlayers > 1)
		{
			for(new i=0;i<iCurrentPlayers;i++)
			{
				iClient = GetArrayCell(hPlayers, i);
				SetEntPropFloat(iClient, Prop_Send, "m_flProgressBarStartTime", GetGameTime());
				SetEntProp(iClient, Prop_Send, "m_iProgressBarDuration", iTime);
				Client_PrintKeyHintText(iClient, "");
			}
		}
		else
		{
			SetEntPropFloat(activator, Prop_Send, "m_flProgressBarStartTime", GetGameTime());
			SetEntProp(activator, Prop_Send, "m_iProgressBarDuration", iTime);
		}
	}
	// Show the progressbar with shortend time to all newly joining people
	else if(iCurrentPlayers > iRequiredPlayers)
	{
		new iConquerStartTime = GetArrayCell(hFlag, FLAG_CONQUERSTARTTIME);
		SetEntPropFloat(activator, Prop_Send, "m_flProgressBarStartTime", GetGameTime());
		SetEntProp(activator, Prop_Send, "m_iProgressBarDuration", iTime - GetTime() + iConquerStartTime);
	}

}

public EntOut_OnEndTouch(const String:output[], caller, activator, Float:delay)
{
	// Ignore anything other than players
	if(activator < 1 || activator > MaxClients)
	{
		return;
	}
	
	// Get array index of this trigger
	decl String:sTargetName[64];
	GetEntPropString(caller, Prop_Data, "m_iName", sTargetName, sizeof(sTargetName));
	ReplaceString(sTargetName, sizeof(sTargetName), "scq_zone_", "");
	new iIndex = StringToInt(sTargetName);
	
	//PrintToChatAll("%d left zone %d", activator, iIndex);
	//PrintToServer("%d left zone %d", activator, iIndex);
	
	// Remove him from the zone. This also stops the conquering if there aren't enough players anymore
	RemovePlayerFromZone(activator, iIndex);
	
	// Check if only one team is in the zone now again
	new iOnlyTeam = GetTeamOfPlayersInZone(iIndex);
	
	// There is only one team left
	if(iOnlyTeam != -1)
	{
		new Handle:hFlag = GetArrayCell(g_hFlags, iIndex);
		// Don't care if that team already owns the flag
		if(iOnlyTeam == GetArrayCell(hFlag, FLAG_CURRENTTEAM))
			return;
		
		new iRequiredPlayers = GetArrayCell(hFlag, FLAG_REQPLAYERS);
		
		new Handle:hPlayers = GetArrayCell(g_hPlayersInZone, iIndex);
		
		// Get a random player out of the left over in this area and check how many players are in his team.
		new iTeamCount = GetTeamClientCount(iOnlyTeam);
		
		// Enable a team with less players as required to capture that flags
		if(GetConVarBool(g_hCVHandicap) && iTeamCount < iRequiredPlayers)
			iRequiredPlayers = iTeamCount;
		
		new iCurrentPlayers = GetArraySize(hPlayers), iClient;
		if(iCurrentPlayers >= iRequiredPlayers)
		{
			// Don't restart the timer if this flag is already getting conquered by that team
			if(GetArrayCell(hFlag, FLAG_CONQUERSTARTTIME) != -1)
				return;
			
			new iTime = GetArrayCell(hFlag, FLAG_TIME);
			
			// Start conquer timer
			new Handle:hConquerTimer = CreateTimer(float(iTime), Timer_OnConquerFlag, iIndex, TIMER_FLAG_NO_MAPCHANGE);
			SetArrayCell(hFlag, FLAG_CONQUERTIMER, hConquerTimer);
			SetArrayCell(hFlag, FLAG_CONQUERSTARTTIME, GetTime());
			
			// Play a sound
			if(iOnlyTeam == CS_TEAM_T)
			{
				if(strlen(g_sSoundFiles[CSOUND_REDTEAM_STARTS_CONQUERING]) > 0)
					EmitSoundToAll(g_sSoundFiles[CSOUND_REDTEAM_STARTS_CONQUERING], SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_LIBRARY);
			}
			else if(iOnlyTeam == CS_TEAM_CT)
			{
				if(strlen(g_sSoundFiles[CSOUND_BLUETEAM_STARTS_CONQUERING]) > 0)
					EmitSoundToAll(g_sSoundFiles[CSOUND_BLUETEAM_STARTS_CONQUERING], SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_LIBRARY);
			}
			
			// Show it now to all players
			for(new i=0;i<iCurrentPlayers;i++)
			{
				iClient = GetArrayCell(hPlayers, i);
				SetEntPropFloat(iClient, Prop_Send, "m_flProgressBarStartTime", GetGameTime());
				SetEntProp(iClient, Prop_Send, "m_iProgressBarDuration", iTime);
				Client_PrintKeyHintText(iClient, "");
			}
		}
		else if(iCurrentPlayers < iRequiredPlayers)
		{
			//PrintToChatAll("Not enough players.");
			for(new i=0;i<iCurrentPlayers;i++)
			{
				iClient = GetArrayCell(hPlayers, i);
				Client_PrintKeyHintText(iClient, "%t", "Need more players", (iRequiredPlayers-iCurrentPlayers));
			}
		}
	}
}

/**
 * Timer Callbacks
 */

public Action:Timer_OnConquerFlag(Handle:timer, any:iIndex)
{
	new Handle:hFlag = GetArrayCell(g_hFlags, iIndex);
	SetArrayCell(hFlag, FLAG_CONQUERTIMER, INVALID_HANDLE);
	SetArrayCell(hFlag, FLAG_CONQUERSTARTTIME, -1);
	
	// Flag is theirs - but whom?
	new Handle:hPlayers = GetArrayCell(g_hPlayersInZone, iIndex);
	// Should never happen
	new iNumPlayers = GetArraySize(hPlayers);
	if(iNumPlayers == 0)
		return Plugin_Stop;
	
	new iFlag = GetArrayCell(hFlag, FLAG_FLAGENTITY);
	if(!IsValidEntity(iFlag))
		return Plugin_Stop;
	
	// Get team of first client
	new iTeam = GetClientTeam(GetArrayCell(hPlayers, 0));
	
	new iRequiredPlayers = GetArrayCell(hFlag, FLAG_REQPLAYERS);
	
	new iTeamCount = GetTeamClientCount(iTeam);
	
	// Enable a team with less players as required to capture that flags
	if(GetConVarBool(g_hCVHandicap) && iTeamCount < iRequiredPlayers)
		iRequiredPlayers = iTeamCount;
	
	// Someone just got removed?
	if(iRequiredPlayers > iNumPlayers)
		return Plugin_Stop;
	
	// Set the color of the flag and play the sound
	decl String:sBuffer[64];
	if(iTeam == CS_TEAM_T)
	{
		DispatchKeyValue(iFlag, "skin", "1");
		if(strlen(g_sSoundFiles[CSOUND_REDFLAG_CAPTURED]) > 0)
			EmitSoundToAll(g_sSoundFiles[CSOUND_REDFLAG_CAPTURED], SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_TRAIN);
		GetArrayString(hFlag, FLAG_LOGICTRIGGERT, sBuffer, sizeof(sBuffer));
	}
	else if(iTeam == CS_TEAM_CT)
	{
		DispatchKeyValue(iFlag, "skin", "2");
		if(strlen(g_sSoundFiles[CSOUND_BLUEFLAG_CAPTURED]) > 0)
			EmitSoundToAll(g_sSoundFiles[CSOUND_BLUEFLAG_CAPTURED], SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_TRAIN);
		GetArrayString(hFlag, FLAG_LOGICTRIGGERCT, sBuffer, sizeof(sBuffer));
	}
	else
		return Plugin_Stop;
	
	// Trigger the preset relays in the map like in cq_king
	if(strlen(sBuffer) > 0)
	{
		new iLogicRelay = Entity_FindByName(sBuffer, "logic_relay");
		if(iLogicRelay != INVALID_ENT_REFERENCE)
			AcceptEntityInput(iLogicRelay, "Trigger");
		else
			PrintToChatAll("SM:Conquest Debug: Can't find logic_relay \"%s\" in this map. Adjust the config!", sBuffer);
	}
	
	// That team got the flag now
	SetArrayCell(hFlag, FLAG_CURRENTTEAM, iTeam);
	
	// Get the flag name
	GetArrayString(hFlag, FLAG_NAME, sBuffer, sizeof(sBuffer));
	
	// How much money do player earn?
	new iReward = GetConVarInt(g_hCVCaptureMoney);
	
	new iClient;
	new iScore = GetConVarInt(g_hCVCaptureScore);
	decl String:sClientName[MAX_NAME_LENGTH];
	// Print message to clients
	if(iRequiredPlayers == 1)
	{
		iClient = GetArrayCell(hPlayers, 0);
		// Only one player did this?
		GetClientName(iClient, sClientName, sizeof(sClientName));
		CPrintToChatAllEx(iClient, "%s%t", PREFIX, "Captured a flag", sClientName, sBuffer);
		// Increase frags
		if(iScore > 0)
			Client_SetScore(iClient, Client_GetScore(iClient)+iScore);
		
		// Give player some money
		if(iReward > 0)
			SetEntData(iClient, g_iAccount, GetEntData(iClient, g_iAccount)+iReward);
		
		LogPlayerEvent(iClient, "triggered", "scq_flag_captured");
	}
	// more clients required to get that flag? Give proper credits for all;)
	else
	{
		new String:sPlayerNames[512];
		for(new i=0;i<iRequiredPlayers;i++)
		{
			iClient = GetArrayCell(hPlayers, i);
			
			if(i == iRequiredPlayers-1)
				Format(sPlayerNames, sizeof(sPlayerNames), "%s{green} %T ", sPlayerNames, "and", iClient);
			else if(i > 0)
				Format(sPlayerNames, sizeof(sPlayerNames), "%s{green}, ", sPlayerNames);
			
			Format(sPlayerNames, sizeof(sPlayerNames), "%s{teamcolor}%N", sPlayerNames, iClient);
			// Increase frags
			if(iScore > 0)
				Client_SetScore(iClient, Client_GetScore(iClient)+iScore);
			
			// Give player some money
			if(iReward > 0)
				SetEntData(iClient, g_iAccount, GetEntData(iClient, g_iAccount)+iReward);
			
			LogPlayerEvent(iClient, "triggered", "scq_flag_captured");
		}
		
		CPrintToChatAllEx(iClient, "%s%t", PREFIX, "Multiple captured a flag", sPlayerNames, sBuffer);
	}
	
	// Remove the progress bar
	new iPlayers[iNumPlayers];
	for(new i=0;i<iNumPlayers;i++)
	{
		iClient = GetArrayCell(hPlayers, i);
		iPlayers[i] = iClient;
		SetEntPropFloat(iClient, Prop_Send, "m_flProgressBarStartTime", 0.0);
		SetEntProp(iClient, Prop_Send, "m_iProgressBarDuration", 0);
	}
	
	// Fade the screen of all players who want it in the flag color shortly
	if(GetConVarBool(g_hCVFadeOnConquer))
	{
		// Choose the right color
		new iColor[4];
		if(iTeam == CS_TEAM_T)
			iColor = g_iRedHudMsg;
		else
			iColor = g_iBlueHudMsg;
		
		for(new i=1;i<=MaxClients;i++)
		{
			if(IsClientInGame(i) && g_bFadeClientScreen[i])
			{
				Client_ScreenFade(i, 150, FFADE_IN|FFADE_PURGE, 5, iColor[0], iColor[1], iColor[2], 120, false);
			}
		}
	}
	
	// Check for winning
	new iSize = GetArraySize(g_hFlags), iLastTeam = -1;
	for(new i=0;i<iSize;i++)
	{
		hFlag = GetArrayCell(g_hFlags, i);
		// Not the same team as before? stop here
		if(iLastTeam != -1 && iLastTeam != GetArrayCell(hFlag, FLAG_CURRENTTEAM))
		{
			iLastTeam = -1;
			break;
		}
		iLastTeam = GetArrayCell(hFlag, FLAG_CURRENTTEAM);
	}
	
	// A team controls all flags! They won that round!
	if(iLastTeam > 1)
	{
		if(g_hTerminateRound != INVALID_HANDLE)
		{
			iScore = GetConVarInt(g_hCVTeamScore);
			if(iLastTeam == CS_TEAM_T)
			{
				// End the round with proper reason
				SDKCall(g_hTerminateRound, 5.0, 8);
				// Show the screen overlay of the winning team
				if(GetConVarBool(g_hCVShowWinOverlays))
				{
					Client_SetScreenOverlayForAll("conquest/v1/red_wins.vtf");
				}
				// Play the winning sound
				if(strlen(g_sSoundFiles[CSOUND_REDTEAM_WIN]) > 0)
					EmitSoundToAll(g_sSoundFiles[CSOUND_REDTEAM_WIN], SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_TRAIN);
				
				// Stop any capturing
				for(new c=1;c<=MaxClients;c++)
				{
					RemovePlayerFromAllZones(c);
				}
				
				// Strip losers to knife
				if(GetConVarBool(g_hCVStripLosers))
				{
					for(new i=1;i<=MaxClients;i++)
					{
						if(IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == CS_TEAM_CT)
							Client_RemoveAllWeapons(i, "weapon_knife", true);
					}
				}
				
				// Give the team their points
				if(iScore > 0)
					Team_SetScore(iLastTeam, Team_GetScore(iLastTeam)+iScore);
			}
			else if(iLastTeam == CS_TEAM_CT)
			{
				// End the round with proper reason
				SDKCall(g_hTerminateRound, 5.0, 7);
				// Show the screen overlay of the winning team
				if(GetConVarBool(g_hCVShowWinOverlays))
				{
					Client_SetScreenOverlayForAll("conquest/v1/blue_wins.vtf");
				}
				// Play the winning sound
				if(strlen(g_sSoundFiles[CSOUND_BLUETEAM_WIN]) > 0)
				EmitSoundToAll(g_sSoundFiles[CSOUND_BLUETEAM_WIN], SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_TRAIN);
				
				// Stop any capturing
				for(new c=1;c<=MaxClients;c++)
				{
					RemovePlayerFromAllZones(c);
				}
				
				// Strip losers to knife
				if(GetConVarBool(g_hCVStripLosers))
				{
					for(new i=1;i<=MaxClients;i++)
					{
						if(IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == CS_TEAM_T)
							Client_RemoveAllWeapons(i, "weapon_knife", true);
					}
				}
				
				// Give the team their points
				if(iScore > 0)
					Team_SetScore(iLastTeam, Team_GetScore(iLastTeam)+iScore);
			}
		}
		else
		{
			LogError("Can't TerminateRound. Bad signature.");
		}
	}
	
	return Plugin_Stop;
}

public Action:Timer_OnUpdateStatusPanel(Handle:timer, any:data)
{
	new iFlags = GetArraySize(g_hFlags);
	if(iFlags == 0)
		return Plugin_Continue;
	
	// Only 6 channels supported.
	new bool:bUseHudMsg = true;
	if(iFlags > 6)
		bUseHudMsg = false;
	
	// Always center the hudmsg
	new Float:fScreenStart = 0.5 - 0.05 * (float(iFlags) - 1.0);
	
	new String:sStatusString[512];
	new Handle:hFlag, Handle:hPlayers, iCurrentTeam;
	for(new i=0;i<iFlags;i++)
	{
		if(i > 0)
		{
			Format(sStatusString, sizeof(sStatusString), "%s   ", sStatusString);
		}
		
		hFlag = GetArrayCell(g_hFlags, i);
		// That flag is currently being conquerored by some team
		if(GetArrayCell(hFlag, FLAG_CONQUERSTARTTIME) != -1)
		{
			hPlayers = GetArrayCell(g_hPlayersInZone, i);
			if(GetClientTeam(GetArrayCell(hPlayers, 0)) == CS_TEAM_T)
			{
				Format(sStatusString, sizeof(sStatusString), "%s[r]", sStatusString);
				if(bUseHudMsg)
					PrintHudMsgToAllWhoWant(i, fScreenStart+(i==0?0.0:float(i)*10.0/100.0), 0.01, g_iRedHudMsg, g_iRedHudMsg, HUDMSG_FADEINOUT, 0.0, 0.0, 0.6, 1.0, "A");
			}
			else
			{
				Format(sStatusString, sizeof(sStatusString), "%s[b]", sStatusString);
				if(bUseHudMsg)
					PrintHudMsgToAllWhoWant(i, fScreenStart+(i==0?0.0:float(i)*10.0/100.0), 0.01, g_iBlueHudMsg, g_iBlueHudMsg, HUDMSG_FADEINOUT, 0.0, 0.0, 0.6, 1.0, "A");
			}
		}
		else
		{
			// Show the team that controls that flag
			iCurrentTeam = GetArrayCell(hFlag, FLAG_CURRENTTEAM);
			switch(iCurrentTeam)
			{
				case CS_TEAM_T:
				{
					Format(sStatusString, sizeof(sStatusString), "%s[R]", sStatusString);
					if(bUseHudMsg)
						PrintHudMsgToAllWhoWant(i, fScreenStart+(i==0?0.0:float(i)*10.0/100.0), 0.01, g_iRedHudMsg, g_iRedHudMsg, HUDMSG_FADEINOUT, 0.0, 0.0, 0.6, 1.0, "#");
				}
				case CS_TEAM_CT:
				{
					Format(sStatusString, sizeof(sStatusString), "%s[B]", sStatusString);
					if(bUseHudMsg)
						PrintHudMsgToAllWhoWant(i, fScreenStart+(i==0?0.0:float(i)*10.0/100.0), 0.01, g_iBlueHudMsg, g_iBlueHudMsg, HUDMSG_FADEINOUT, 0.0, 0.0, 0.6, 1.0, "$");
				}
				default:
				{
					Format(sStatusString, sizeof(sStatusString), "%s[-]", sStatusString);
					if(bUseHudMsg)
						PrintHudMsgToAllWhoWant(i, fScreenStart+(i==0?0.0:float(i)*10.0/100.0), 0.01, {255,255,255,200}, {255,255,255,255}, HUDMSG_FADEINOUT, 0.0, 0.0, 0.6, 1.0, "&");
				}
			}
		}
	}
	
	// Only show the hint status text to players who want it
	for(new i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i) && g_bUseHintStatus[i])
		{
			PrintHintText(i, sStatusString);
		}
	}
	
	return Plugin_Continue;
}

/**
 * SDKHook callbacks
 */

// Show enemies on radar, if they're near to a flag controlled by the player's team
public Hook_OnPlayerManagerThinkPost(entity)
{
	// Don't do anything, if no flags for that map -> "disabled"
	new iSize = GetArraySize(g_hFlags);
	if(iSize == 0)
		return;
	
	// Serveradmin don't want this feature?
	if(!GetConVarBool(g_hCVShowOnRadar))
		return;
	
	// Loop through all flags and check for enemies near own flag
	new Handle:hFlag, Handle:hPlayers;
	new iTeam, iNumPlayers, iClient;
	for(new f=0;f<iSize;f++)
	{
		hFlag = GetArrayCell(g_hFlags, f);
		iTeam = GetArrayCell(hFlag, FLAG_CURRENTTEAM);
		
		// Skip this flag, if no team controls it.
		if(iTeam == 0)
			continue;
		
		hPlayers = GetArrayCell(g_hPlayersInZone, f);
		iNumPlayers = GetArraySize(hPlayers);
		
		// Loop through all players and show them in the radar, if they're near a flag
		for(new i=0;i<iNumPlayers;i++)
		{
			iClient = GetArrayCell(hPlayers, i);
			// Show the player, if he's not in the team controlling the flag
			if(GetClientTeam(iClient) != iTeam)
			{
				// Show him
				SetEntData(entity, g_iPlayerSpottedOffset+iClient, 1, 4, true);
			}
		}
	}
}

/**
 * Helper functions
 */

SpawnFlag(iIndex)
{
	// Get all info out of the global array
	new Handle:hFlag = GetArrayCell(g_hFlags, iIndex);
	
	new Float:fVec[3], iTeam;
	// Create the flag
	new iFlag = CreateEntityByName("prop_dynamic");
	if(!IsValidEntity(iFlag))
	{
		SetFailState("Can't create a flag.");
		return;
	}
	
	// Teleport to correct position
	GetArrayArray(hFlag, FLAG_POSITION, fVec, 3);
	new Float:fAngle[3];
	fAngle[1] = GetArrayCell(hFlag, FLAG_ROTATION);
	TeleportEntity(iFlag, fVec, fAngle, NULL_VECTOR);
	
	// Set it's model
	SetEntityModel(iFlag, "models/conquest/flagv2/flag.mdl");
	
	// Set the correct skin
	iTeam = GetArrayCell(hFlag, FLAG_DEFAULTTEAM);
	switch(iTeam)
	{
		case CS_TEAM_T:
		{
			// Red
			DispatchKeyValue(iFlag, "skin", "1");
		}
		case CS_TEAM_CT:
		{
			// Blue
			DispatchKeyValue(iFlag, "skin", "2");
		}
		default:
		{
			// White
			DispatchKeyValue(iFlag, "skin", "0");
		}
	}
	
	// Set the m_iName
	decl String:sTargetName[64];
	Format(sTargetName, sizeof(sTargetName), "scq_flag_%d", iIndex);
	DispatchKeyValue(iFlag, "targetname", sTargetName);
	
	// Spawn
	DispatchSpawn(iFlag);
	ActivateEntity(iFlag);
	
	// Animate
	SetVariantString("flag_idle1");
	AcceptEntityInput(iFlag, "SetAnimation");
	
	// Store the entity index
	SetArrayCell(hFlag, FLAG_FLAGENTITY, iFlag);
	
	// Reset the current team
	SetArrayCell(hFlag, FLAG_CURRENTTEAM, GetArrayCell(hFlag, FLAG_DEFAULTTEAM));
	
	
	// Create Trigger to detect touches
	new iTrigger = CreateEntityByName("trigger_multiple");
	
	if(!IsValidEntity(iTrigger))
	{
		
		SetFailState("Can't create a trigger.");
		return;
	}
	
	DispatchKeyValue(iTrigger, "spawnflags", "1"); // triggers on clients (players) only
	Format(sTargetName, sizeof(sTargetName), "scq_zone_%d", iIndex);
	DispatchKeyValue(iTrigger, "targetname", sTargetName);
	DispatchKeyValue(iTrigger, "wait", "0");
	
	DispatchSpawn(iTrigger);
	ActivateEntity(iTrigger);
	
	TeleportEntity(iTrigger, fVec, NULL_VECTOR, NULL_VECTOR);
	SetEntityModel(iTrigger, "models/conquest/flagv2/flag.mdl");
	
	GetArrayArray(hFlag, FLAG_MINS, fVec, 3);
	SetEntPropVector(iTrigger, Prop_Send, "m_vecMins", fVec);
	GetArrayArray(hFlag, FLAG_MAXS, fVec, 3);
	SetEntPropVector(iTrigger, Prop_Send, "m_vecMaxs", fVec);
	SetEntProp(iTrigger, Prop_Send, "m_nSolidType", 2);
	
	new iEffects = GetEntProp(iTrigger, Prop_Send, "m_fEffects");
	iEffects |= 32;
	SetEntProp(iTrigger, Prop_Send, "m_fEffects", iEffects);
	
	HookSingleEntityOutput(iTrigger, "OnStartTouch", EntOut_OnStartTouch);
	HookSingleEntityOutput(iTrigger, "OnEndTouch", EntOut_OnEndTouch);
	
	SetArrayCell(hFlag, FLAG_TRIGGERENTITY, iTrigger);
}

ParseFlagConfig()
{
	// Close all old flag arrays and timers
	new iSize = GetArraySize(g_hFlags);
	new Handle:hFlag, Handle:hTimer;
	for(new i=0;i<iSize;i++)
	{
		hFlag = GetArrayCell(g_hFlags, i);
		hTimer = GetArrayCell(hFlag, FLAG_CONQUERTIMER);
		if(hTimer != INVALID_HANDLE)
		{
			KillTimer(hTimer);
			hTimer = INVALID_HANDLE;
		}
		CloseHandle(hFlag);
	}
	ClearArray(g_hFlags);
	
	// Close the player list arrays
	iSize = GetArraySize(g_hPlayersInZone);
	for(new i=0;i<iSize;i++)
	{
		hFlag = GetArrayCell(g_hPlayersInZone, i);
		CloseHandle(hFlag);
	}
	ClearArray(g_hPlayersInZone);
	
	new String:sFile[PLATFORM_MAX_PATH], String:sMap[64];
	GetCurrentMap(sMap, sizeof(sMap));
	BuildPath(Path_SM, sFile, sizeof(sFile), "configs/smconquest/%s.cfg", sMap);
	
	if(!FileExists(sFile))
		return;
	
	new Handle:kv = CreateKeyValues("FlagsAreas");
	FileToKeyValues(kv, sFile);
	
	if (!KvGotoFirstSubKey(kv))
	{
		CloseHandle(kv);
		return;
	}
	
	decl String:sBuffer[256];
	new Float:fVec[3];
	do
	{
		hFlag = CreateArray(ByteCountToCells(256));
		
		// A description shown in chat when conquered
		KvGetString(kv, "description", sBuffer, sizeof(sBuffer));
		PushArrayString(hFlag, sBuffer);
		
		// The default team the flag belongs to at spawn
		PushArrayCell(hFlag, KvGetNum(kv, "team", 0));
		// Stores the current team, so at spawn the default
		PushArrayCell(hFlag, KvGetNum(kv, "team", 0));
		
		// How many players are required to conquer that flag?
		PushArrayCell(hFlag, KvGetNum(kv, "num_to_cap", 1));
		
		// How many seconds have the players to stay in the zone alone without an enemy?
		PushArrayCell(hFlag, KvGetNum(kv, "time_to_cap", 5));
		
		// The position of the flag
		KvGetVector(kv, "position", fVec);
		PushArrayArray(hFlag, fVec, 3);
		
		// The bounds of the trigger_multiple around that flag
		KvGetVector(kv, "zonemins", fVec, Float:{-100.0, -100.0, -20.0});
		PushArrayArray(hFlag, fVec, 3);
		
		KvGetVector(kv, "zonemaxs", fVec, Float:{100.0, 100.0, 150.0});
		PushArrayArray(hFlag, fVec, 3);
		
		// Set default flag and trigger entity indexes
		PushArrayCell(hFlag, -1);
		PushArrayCell(hFlag, -1);
		
		// No timer is running for this zone
		PushArrayCell(hFlag, INVALID_HANDLE);
		
		// No starttime of conquer yet
		PushArrayCell(hFlag, -1);
		
		// Triggers set in that map?
		KvGetString(kv, "t_capture_relay", sBuffer, sizeof(sBuffer));
		PushArrayString(hFlag, sBuffer);
		KvGetString(kv, "ct_capture_relay", sBuffer, sizeof(sBuffer));
		PushArrayString(hFlag, sBuffer);
		
		// The angle rotation (yaw)
		PushArrayCell(hFlag, KvGetFloat(kv, "rotation"));
		
		// Add it to the global flags array
		PushArrayCell(g_hFlags, hFlag);
		
		// Push the players array to be at the same index.
		hFlag = CreateArray();
		PushArrayCell(g_hPlayersInZone, hFlag);
	} while(KvGotoNextKey(kv));
	
	CloseHandle(kv);
}

RemoveLeftFlags()
{
	// Remove the entity
	new iMaxEntities = GetMaxEntities();
	decl String:sBuffer[64];
	for(new i=MaxClients;i<iMaxEntities;i++)
	{
		if(IsValidEntity(i)
		&& IsValidEdict(i)
		&& GetEdictClassname(i, sBuffer, sizeof(sBuffer))
		&& (StrEqual(sBuffer, "prop_dynamic", false) || StrEqual(sBuffer, "trigger_multiple", false) || StrEqual(sBuffer, "prop_physics", false))
		&& GetEntPropString(i, Prop_Data, "m_iName", sBuffer, sizeof(sBuffer))
		&& (StrContains(sBuffer, "scq_flag") != -1 || StrContains(sBuffer, "scq_zone") != -1 || StrContains(sBuffer, "scq_ammo") != -1))
			AcceptEntityInput(i, "Kill");
	}
	
	// Reset the array values
	new iSize = GetArraySize(g_hFlags);
	for(new i=0;i<iSize;i++)
	{
		ResetFlag(i);
	}
}

ResetFlag(iIndex)
{
	new Handle:hFlag = GetArrayCell(g_hFlags, iIndex);
	SetArrayCell(hFlag, FLAG_CURRENTTEAM, GetArrayCell(hFlag, FLAG_DEFAULTTEAM));
	
	new iEnt = GetArrayCell(hFlag, FLAG_FLAGENTITY);
	if(iEnt != -1 && IsValidEntity(iEnt))
		AcceptEntityInput(iEnt, "Kill");
	iEnt = GetArrayCell(hFlag, FLAG_TRIGGERENTITY);
	if(iEnt != -1 && IsValidEntity(iEnt))
		AcceptEntityInput(iEnt, "Kill");
	
	SetArrayCell(hFlag, FLAG_FLAGENTITY, -1);
	SetArrayCell(hFlag, FLAG_TRIGGERENTITY, -1);
	
	new Handle:hTimer = GetArrayCell(hFlag, FLAG_CONQUERTIMER);
	if(hTimer != INVALID_HANDLE)
	{
		KillTimer(hTimer);
		SetArrayCell(hFlag, FLAG_CONQUERTIMER, INVALID_HANDLE);
	}
	
	SetArrayCell(hFlag, FLAG_CONQUERSTARTTIME, -1);
	
	// Remove all players
	for(new i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i))
			RemovePlayerFromZone(i, iIndex);
	}
}

// Remove from the touch array and check for requirements
RemovePlayerFromZone(client, iZoneIndex)
{
	new Handle:hPlayers = GetArrayCell(g_hPlayersInZone, iZoneIndex);
	
	// Player touched this flag before?
	new iPlayerIndex = FindValueInArray(hPlayers, client);
	if(iPlayerIndex  != -1)
	{
		new Handle:hFlag = GetArrayCell(g_hFlags, iZoneIndex);
		new iRequiredPlayers = GetArrayCell(hFlag, FLAG_REQPLAYERS);
		
		// Remove the leaving player from the touching list
		RemoveFromArray(hPlayers, iPlayerIndex);
		new iCurrentPlayers = GetArraySize(hPlayers);
		
		// Reset that client
		Client_PrintKeyHintText(client, "");
		SetEntPropFloat(client, Prop_Send, "m_flProgressBarStartTime", 0.0);
		SetEntProp(client, Prop_Send, "m_iProgressBarDuration", 0);
		
		// Not enough players to conquer this flag anymore?
		if(iCurrentPlayers < iRequiredPlayers)
		{
			// Stop the conquer timer
			new Handle:hConquerTimer = GetArrayCell(hFlag, FLAG_CONQUERTIMER);
			if(hConquerTimer != INVALID_HANDLE)
			{
				KillTimer(hConquerTimer);
				SetArrayCell(hFlag, FLAG_CONQUERTIMER, INVALID_HANDLE);
			}
			
			SetArrayCell(hFlag, FLAG_CONQUERSTARTTIME, -1);
			
			// Remove the progress bar
			new iClient;
			new iPlayers[iCurrentPlayers];
			for(new i=0;i<iCurrentPlayers;i++)
			{
				iClient = GetArrayCell(hPlayers, i);
				iPlayers[i] = iClient;
				SetEntPropFloat(iClient, Prop_Send, "m_flProgressBarStartTime", 0.0);
				SetEntProp(iClient, Prop_Send, "m_iProgressBarDuration", 0);
				Client_PrintKeyHintText(iClient, "%t", "Need more players", (iRequiredPlayers-iCurrentPlayers));
			}
		}
	}
}

// Remove him from any touches
RemovePlayerFromAllZones(client)
{
	new iSize = GetArraySize(g_hFlags);
	for(new i=0;i<iSize;i++)
	{
		RemovePlayerFromZone(client, i);
	}
}

GetTeamOfPlayersInZone(iIndex)
{
	new Handle:hPlayers = GetArrayCell(g_hPlayersInZone, iIndex);
	new iCurrentPlayers = GetArraySize(hPlayers), iOnlyTeam = -1, iClient;
	for(new i=0;i<iCurrentPlayers;i++)
	{
		iClient = GetArrayCell(hPlayers, i);
		if(iOnlyTeam != -1 && GetClientTeam(iClient) != iOnlyTeam)
		{
			iOnlyTeam = -1;
			break;
		}
		iOnlyTeam = GetClientTeam(iClient);
	}
	
	return iOnlyTeam;
}

/**
 * Prints a message to a random position on the clients hud
 * NOTE: Does not work in CS:S and DOD:S until clients edit their ClientScheme.
 * This needs to be added to the Fonts section of resource/ClientScheme.res:
 
CenterPrintText
{
   "1"
   {
      "name" "conquest"
      "tall" "38"
      "weight" "900"
      "range" "0x0000 0x007F" // Basic Latin
      "antialias" "1"
   }
}

 *
 * @param clients		An array of clients to show the box to.
 * @param numClients	Number of players in the array.
 * @param channel		channel, must be in range <0,5>
 * @param x				x, must be in range <0.0,1.0>; -1 center in x dimension
 * @param y				y coordinate of the bottom left corner of the first char. -1 for center
 * @param secondColor	RGBA colors for second color
 * @param initColor		RGBA colors for init color
 * @param effect		fade in/fade out, 1 - flickery credits, 2 - write out (training room)
 * @param fadeInTime	fade in, message fade in time - per character in effect 2
 * @param fadeOutTime	fade out, message fade out time
 * @param holdTime		holdtime, stay on the screen for this long
 * @param fxTime		Used by HUDMSG_WRITEOUT (effect 2)
 * @param szMsg			message, max size 512
 * @param ...			Variable number of format parameters.
 * @noreturn
 */

stock PrintHudMsg(clients[], 
				  numClients, 
				  const channel,
				  const Float:x, 
				  const Float:y, 
				  const secondColor[4], 
				  const initColor[4], 
				  effect = HUDMSG_FADEINOUT, 
				  Float:fadeInTime = 1.0, 
				  Float:fadeOutTime = 1.0, 
				  const Float:holdTime, 
				  Float:fxTime = 1.0, 
				  const String:szMsg[], 
				  any:...)
{
	new Handle:hBf = StartMessage("HudMsg", clients, numClients);
		
	BfWriteByte(hBf, channel); //channel
	BfWriteFloat(hBf, x); // x ( -1 = center )
	BfWriteFloat(hBf, y); // y ( -1 = center )
	// second color
	BfWriteByte(hBf, secondColor[0]); //r1
	BfWriteByte(hBf, secondColor[1]); //g1
	BfWriteByte(hBf, secondColor[2]); //b1
	BfWriteByte(hBf, secondColor[3]); //a1 // transparent?
	// init color
	BfWriteByte(hBf, initColor[0]); //r2
	BfWriteByte(hBf, initColor[1]); //g2
	BfWriteByte(hBf, initColor[2]); //b2
	BfWriteByte(hBf, initColor[3]); //a2
	BfWriteByte(hBf, effect); //effect (0 is fade in/fade out; 1 is flickery credits; 2 is write out)
	BfWriteFloat(hBf, fadeInTime); //fadeinTime (message fade in time - per character in effect 2)
	BfWriteFloat(hBf, fadeOutTime); //fadeoutTime
	BfWriteFloat(hBf, holdTime); //holdtime
	BfWriteFloat(hBf, fxTime); //fxtime (effect type(2) used)
	
	decl String:sBuffer[512];
	//SetGlobalTransTarget(client);
	VFormat(sBuffer, sizeof(sBuffer), szMsg, 13);
	
	BfWriteString(hBf, sBuffer); //Message
	EndMessage();
}

/**
 * Prints a message to a random position on one client's hud
 * 
 * Ported from eventscripts vecmath library.
 *
 *
 * @param client		The client to show the text to.
 * @param channel		channel, must be in range <0,5>
 * @param x				x, must be in range <0.0,1.0>; -1 center in x dimension
 * @param y				y coordinate of the bottom left corner of the first char. -1 for center
 * @param secondColor	RGBA colors for second color
 * @param initColor		RGBA colors for init color
 * @param effect		fade in/fade out, 1 - flickery credits, 2 - write out (training room)
 * @param fadeInTime	fade in, message fade in time - per character in effect 2
 * @param fadeOutTime	fade out, message fade out time
 * @param holdTime		holdtime, stay on the screen for this long
 * @param fxTime		Used by HUDMSG_WRITEOUT (effect 2)
 * @param szMsg			message, max size 512
 * @param ...			Variable number of format parameters.
 * @noreturn
 */
stock PrintHudMsgToClient(client,
						  const channel,
						  const Float:x, 
						  const Float:y, 
						  const secondColor[4], 
						  const initColor[4], 
						  effect = HUDMSG_FADEINOUT, 
						  Float:fadeInTime = 1.0, 
						  Float:fadeOutTime = 1.0, 
						  const Float:holdTime, 
						  Float:fxTime = 1.0, 
						  const String:szMsg[], 
						  any:...)
{
	new clients[1];
	clients[0] = client;
	
	decl String:sBuffer[512];
	SetGlobalTransTarget(client);
	VFormat(sBuffer, sizeof(sBuffer), szMsg, 12);
	
	PrintHudMsg(clients, 1, channel, x, y, secondColor, initColor, effect, fadeInTime, fadeOutTime, holdTime, fxTime, sBuffer);
}

/**
 * Prints a message to a random position on all clients hud
 * 
 * Ported from eventscripts vecmath library.
 *
 *
 * @param channel		channel, must be in range <0,5>
 * @param x				x, must be in range <0.0,1.0>; -1 center in x dimension
 * @param y				y coordinate of the bottom left corner of the first char. -1 for center
 * @param secondColor	RGBA colors for second color
 * @param initColor		RGBA colors for init color
 * @param effect		fade in/fade out, 1 - flickery credits, 2 - write out (training room)
 * @param fadeInTime	fade in, message fade in time - per character in effect 2
 * @param fadeOutTime	fade out, message fade out time
 * @param holdTime		holdtime, stay on the screen for this long
 * @param fxTime		Used by HUDMSG_WRITEOUT (effect 2)
 * @param szMsg			message, max size 512
 * @param ...			Variable number of format parameters.
 * @noreturn
 */
stock PrintHudMsgToAll(const channel,
					   const Float:x, 
					   const Float:y, 
					   const secondColor[4], 
					   const initColor[4], 
					   effect = HUDMSG_FADEINOUT, 
					   Float:fadeInTime = 1.0, 
					   Float:fadeOutTime = 1.0, 
					   const Float:holdTime, 
					   Float:fxTime = 1.0, 
					   const String:szMsg[], 
					   any:...)
{
	new total = 0;
	new clients[MaxClients];
	for (new i=1; i<=MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			clients[total++] = i;
		}
	}
	
	decl String:sBuffer[512];
	VFormat(sBuffer, sizeof(sBuffer), szMsg, 11);
	
	PrintHudMsg(clients, total, channel, x, y, secondColor, initColor, effect, fadeInTime, fadeOutTime, holdTime, fxTime, sBuffer);
}

// Respect the clientpref cookie setting
PrintHudMsgToAllWhoWant(const channel,
					   const Float:x, 
					   const Float:y, 
					   const secondColor[4], 
					   const initColor[4], 
					   effect = HUDMSG_FADEINOUT, 
					   Float:fadeInTime = 1.0, 
					   Float:fadeOutTime = 1.0, 
					   const Float:holdTime, 
					   Float:fxTime = 1.0, 
					   const String:szMsg[], 
					   any:...)
{
	new total = 0;
	new clients[MaxClients];
	for (new i=1; i<=MaxClients; i++)
	{
		if (IsClientInGame(i) && g_bUseHUD[i])
		{
			clients[total++] = i;
		}
	}
	
	decl String:sBuffer[512];
	VFormat(sBuffer, sizeof(sBuffer), szMsg, 11);
	
	if(total > 0)
		PrintHudMsg(clients, total, channel, x, y, secondColor, initColor, effect, fadeInTime, fadeOutTime, holdTime, fxTime, sBuffer);
}
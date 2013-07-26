/*
 * Handles the flag administration including adding and editing flags ingame
 * Part of SM:Conquest
 *
 * Thread: https://forums.alliedmods.net/showthread.php?t=154354
 * visit http://www.wcfan.de/
 */
#include <sourcemod>
#include <sdktools>

new g_iPlayerEditsFlag[MAXPLAYERS+2] = {-1,...};
new Handle:g_hDebugZoneTimer = INVALID_HANDLE;

new bool:g_bPlayerRenamesFlag[MAXPLAYERS+2] = {false,...};
new bool:g_bPlayerNamesNewFlag[MAXPLAYERS+2] = {false,...};
new bool:g_bPlayerSetsRequiredPlayers[MAXPLAYERS+2] = {false,...};
new bool:g_bPlayerSetsConquerTime[MAXPLAYERS+2] = {false,...};

new Float:g_fTempFlagPosition[MAXPLAYERS+2][3];
new Float:g_fTempFlagAngle[MAXPLAYERS+2][3];
new Handle:g_hShowTempFlagPosition[MAXPLAYERS+2] = {INVALID_HANDLE,...};

#define NO_POINT 0
#define MINS_POINT 1
#define MAXS_POINT 2

new g_iPlayerEditsVector[MAXPLAYERS+2] = {NO_POINT,...};
new Float:g_fTempZoneVector1[MAXPLAYERS+2][3];
new Float:g_fTempZoneVector2[MAXPLAYERS+2][3];
new Handle:g_hShowTempZone[MAXPLAYERS+2] = {INVALID_HANDLE,...};

new bool:g_bPlayerAddsFlag[MAXPLAYERS+2] = {false,...};

new g_iLaserMaterial = -1;
new g_iHaloMaterial = -1;
new g_iGlowSprite = -1;

/**
 * Menu Creators
 */

ShowFlagAdminMenu(client)
{
	new Handle:hMenu = CreateMenu(Menu_SelectAdminOption);
	SetMenuTitle(hMenu, "SM:Conquest %T", "Administration", client);
	SetMenuExitButton(hMenu, true);
	
	// Abort chat input
	g_bPlayerRenamesFlag[client] = false;
	g_bPlayerNamesNewFlag[client] = false;
	g_bPlayerSetsRequiredPlayers[client] = false;
	g_bPlayerSetsConquerTime[client] = false;
	
	g_iPlayerEditsFlag[client] = -1;
	
	decl String:sBuffer[128];
	new iSize = GetArraySize(g_hFlags);
	Format(sBuffer, sizeof(sBuffer), "%T", "List flags", client);
	AddMenuItem(hMenu, "list", sBuffer, (iSize>0?ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED));
	Format(sBuffer, sizeof(sBuffer), "%T", "Add flag", client);
	AddMenuItem(hMenu, "new", sBuffer);
	
	Format(sBuffer, sizeof(sBuffer), "%T: ", "Debug mode", client);
	if(g_hDebugZoneTimer != INVALID_HANDLE)
		Format(sBuffer, sizeof(sBuffer), "%s%T", sBuffer, "On", client);
	else
		Format(sBuffer, sizeof(sBuffer), "%s%T", sBuffer, "Off", client);
	AddMenuItem(hMenu, "debug", sBuffer);
	
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

ShowFlagListMenu(client)
{
	new iSize = GetArraySize(g_hFlags);
	if(iSize == 0)
	{
		ShowFlagAdminMenu(client);
		return;
	}
	
	// Abort chat input
	g_bPlayerRenamesFlag[client] = false;
	g_bPlayerNamesNewFlag[client] = false;
	g_bPlayerSetsRequiredPlayers[client] = false;
	g_bPlayerSetsConquerTime[client] = false;
	
	g_iPlayerEditsFlag[client] = -1;
	
	new Handle:hMenu = CreateMenu(Menu_SelectFlag);
	SetMenuTitle(hMenu, "SM:Conquest %T", "Flags", client);
	SetMenuExitBackButton(hMenu, true);
	
	new Handle:hFlag;
	decl String:sFlagName[64], String:sFlagIndex[5];
	for(new i=0;i<iSize;i++)
	{
		hFlag = GetArrayCell(g_hFlags, i);
		GetArrayString(hFlag, FLAG_NAME, sFlagName, sizeof(sFlagName));
		IntToString(i, sFlagIndex, sizeof(sFlagIndex));
		AddMenuItem(hMenu, sFlagIndex, sFlagName);
	}
	
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

ShowFlagOptionMenu(client, iFlag)
{
	new Handle:hFlag = GetArrayCell(g_hFlags, iFlag);
	decl String:sBuffer[256];
	GetArrayString(hFlag, FLAG_NAME, sBuffer, sizeof(sBuffer));
	
	// Abort chat input
	g_bPlayerRenamesFlag[client] = false;
	g_bPlayerNamesNewFlag[client] = false;
	g_bPlayerSetsRequiredPlayers[client] = false;
	g_bPlayerSetsConquerTime[client] = false;
	
	g_iPlayerEditsFlag[client] = iFlag;
	
	new Handle:hMenu = CreateMenu(Menu_SelectFlagOption);
	SetMenuTitle(hMenu, "%T", "Edit Flag", client, sBuffer);
	SetMenuExitBackButton(hMenu, true);
	
	Format(sBuffer, sizeof(sBuffer), "%T", "Change position", client);
	AddMenuItem(hMenu, "replace", sBuffer);
	Format(sBuffer, sizeof(sBuffer), "%T", "Rotate", client);
	AddMenuItem(hMenu, "rotate", sBuffer);
	Format(sBuffer, sizeof(sBuffer), "%T", "Teleport to flag", client);
	AddMenuItem(hMenu, "teleport", sBuffer);
	Format(sBuffer, sizeof(sBuffer), "%T", "Change Zone Position 1", client);
	AddMenuItem(hMenu, "zone_1", sBuffer);
	Format(sBuffer, sizeof(sBuffer), "%T", "Change Zone Position 2", client);
	AddMenuItem(hMenu, "zone_2", sBuffer);
	Format(sBuffer, sizeof(sBuffer), "%T", "Rename", client);
	AddMenuItem(hMenu, "rename", sBuffer);
	new iTeam = GetArrayCell(hFlag, FLAG_DEFAULTTEAM);
	if(iTeam == 0)
		Format(sBuffer, sizeof(sBuffer), "%T", "Both", client);
	else
	{
		GetTeamName(iTeam, sBuffer, sizeof(sBuffer));
	}
	Format(sBuffer, sizeof(sBuffer), "%T: %s", "Default Team", client, sBuffer);
	AddMenuItem(hMenu, "team", sBuffer);
	Format(sBuffer, sizeof(sBuffer), "%T: %d", "Required Players", client, GetArrayCell(hFlag, FLAG_REQPLAYERS));
	AddMenuItem(hMenu, "reqplayers", sBuffer);
	Format(sBuffer, sizeof(sBuffer), "%T: %d", "Conquer Time", client, GetArrayCell(hFlag, FLAG_TIME));
	AddMenuItem(hMenu, "time", sBuffer);
	Format(sBuffer, sizeof(sBuffer), "%T", "Change sorting", client);
	AddMenuItem(hMenu, "sort", sBuffer);
	Format(sBuffer, sizeof(sBuffer), "%T", "Delete", client);
	AddMenuItem(hMenu, "delete", sBuffer);
	
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

// Display a menu which rotates the flag around
ShowFlagRotationMenu(client)
{
	new Handle:hFlag = GetArrayCell(g_hFlags, g_iPlayerEditsFlag[client]);
	decl String:sBuffer[256];
	GetArrayString(hFlag, FLAG_NAME, sBuffer, sizeof(sBuffer));
	
	new Handle:hMenu = CreateMenu(Menu_RotateFlag);
	SetMenuTitle(hMenu, "%T", "Rotate flag", client, sBuffer);
	SetMenuExitBackButton(hMenu, true);
	Format(sBuffer, sizeof(sBuffer), "%T", "To the left", client, 1);
	AddMenuItem(hMenu, "left", sBuffer);
	Format(sBuffer, sizeof(sBuffer), "%T", "To the left", client, 10);
	AddMenuItem(hMenu, "leftfast", sBuffer);
	Format(sBuffer, sizeof(sBuffer), "%T", "To the right", client, 1);
	AddMenuItem(hMenu, "right", sBuffer);
	Format(sBuffer, sizeof(sBuffer), "%T", "To the right", client, 10);
	AddMenuItem(hMenu, "rightfast", sBuffer);
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

// Display a menu which sets the position of a flag with different methods
ShowFlagPositionMenu(client)
{
	new Handle:hMenu = CreateMenu(Menu_SetFlagPosition);
	decl String:sBuffer[256];
	// Show a different menu title when adding a flag ;)
	if(g_bPlayerAddsFlag[client])
	{
		SetMenuTitle(hMenu, "%T", "Set new position", client);
	}
	else
	{
		new Handle:hFlag = GetArrayCell(g_hFlags, g_iPlayerEditsFlag[client]);
		GetArrayString(hFlag, FLAG_NAME, sBuffer, sizeof(sBuffer));
		SetMenuTitle(hMenu, "%T", "Edit position", client, sBuffer);
	}
	
	SetMenuExitBackButton(hMenu, true);
	Format(sBuffer, sizeof(sBuffer), "%T", "Where I stand", client);
	AddMenuItem(hMenu, "here", sBuffer);
	Format(sBuffer, sizeof(sBuffer), "%T", "Where I aim at", client);
	AddMenuItem(hMenu, "aim", sBuffer);
	Format(sBuffer, sizeof(sBuffer), "%T", "Save", client);
	AddMenuItem(hMenu, "save", sBuffer);
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

// Display a menu with a list of all flags and the option to reorder.
ShowFlagSortMenu(client)
{
	new Handle:hFlag = GetArrayCell(g_hFlags, g_iPlayerEditsFlag[client]);
	decl String:sBuffer[256];
	GetArrayString(hFlag, FLAG_NAME, sBuffer, sizeof(sBuffer));
	
	new Handle:hMenu = CreateMenu(Menu_SetFlagSort);
	SetMenuTitle(hMenu, "%T", "Insert before", client, sBuffer);
	SetMenuExitBackButton(hMenu, true);
	
	new iSize = GetArraySize(g_hFlags);
	decl String:sIndex[5];
	for(new i=0;i<iSize;i++)
	{
		hFlag = GetArrayCell(g_hFlags, i);
		GetArrayString(hFlag, FLAG_NAME, sBuffer, sizeof(sBuffer));
		IntToString(i, sIndex, sizeof(sIndex));
		
		// Don't select the next item, since it's already at the position before it..
		// Don't make the first item selectable either
		if(i == 0 || i == g_iPlayerEditsFlag[client]+1)
			AddMenuItem(hMenu, sIndex, sBuffer, ITEMDRAW_DISABLED);
		else
			AddMenuItem(hMenu, sIndex, sBuffer);
	}
	
	// Only show the latest button, if there is a choice
	if(iSize > 1)
	{
		// Possible to set as latest
		Format(sBuffer, sizeof(sBuffer), "%T", "Latest", client);
		if(g_iPlayerEditsFlag[client] == iSize-1)
			AddMenuItem(hMenu, "latest", sBuffer, ITEMDRAW_DISABLED);
		else
			AddMenuItem(hMenu, "latest", sBuffer);
	}
	
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

// Display a menu which edits the 2 different points of the mins & maxs of the trigger_multiple
ShowFlagZoneEditMenu(client, const iZone)
{
	g_iPlayerEditsVector[client] = iZone;
	
	new Handle:hFlag = GetArrayCell(g_hFlags, g_iPlayerEditsFlag[client]);
	
	// Start the visualisation
	if(g_hShowTempZone[client] == INVALID_HANDLE)
	{
		// Save the current zones temporaly
		GetArrayArray(hFlag, FLAG_MINS, g_fTempZoneVector1[client], 3);
		GetArrayArray(hFlag, FLAG_MAXS, g_fTempZoneVector2[client], 3);
		
		new Handle:hDataPack = CreateDataPack();
		WritePackCell(hDataPack, client);
		WritePackCell(hDataPack, iZone);
		ResetPack(hDataPack);
		g_hShowTempZone[client] = CreateTimer(1.0, Timer_OnShowTempZone, hDataPack, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE|TIMER_DATA_HNDL_CLOSE);
		TriggerTimer(g_hShowTempZone[client]);
	}
	
	
	decl String:sBuffer[256];
	GetArrayString(hFlag, FLAG_NAME, sBuffer, sizeof(sBuffer));
	
	new Handle:hMenu = CreateMenu(Menu_ChangeFlagZoneBounds);
	SetMenuTitle(hMenu, "%T", "Change zone", client, sBuffer);
	SetMenuExitBackButton(hMenu, true);
	Format(sBuffer, sizeof(sBuffer), "%T", "Add to", client, "X");
	AddMenuItem(hMenu, "ax", sBuffer);
	Format(sBuffer, sizeof(sBuffer), "%T", "Subtract from", client, "X");
	AddMenuItem(hMenu, "sx", sBuffer);
	Format(sBuffer, sizeof(sBuffer), "%T", "Add to", client, "Y");
	AddMenuItem(hMenu, "ay", sBuffer);
	Format(sBuffer, sizeof(sBuffer), "%T", "Subtract from", client, "Y");
	AddMenuItem(hMenu, "sy", sBuffer);
	Format(sBuffer, sizeof(sBuffer), "%T", "Add to", client, "Z");
	AddMenuItem(hMenu, "az", sBuffer);
	Format(sBuffer, sizeof(sBuffer), "%T", "Subtract from", client, "Z");
	AddMenuItem(hMenu, "sz", sBuffer);
	Format(sBuffer, sizeof(sBuffer), "%T", "Save", client);
	AddMenuItem(hMenu, "save", sBuffer);
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

/**
 * Menu Handlers
 */

public Menu_SelectAdminOption(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}
	else if(action == MenuAction_Select)
	{
		decl String:sInfo[256];
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
		
		// List all given flags
		if(StrEqual(sInfo, "list"))
		{
			ShowFlagListMenu(param1);
		}
		// Add a new flag.
		else if(StrEqual(sInfo, "new"))
		{
			// First set the position, type a name afterwards and use the default settings for the other options
			g_bPlayerAddsFlag[param1] = true;
			ShowFlagPositionMenu(param1);
		}
		// Toggle debug mode
		else if(StrEqual(sInfo, "debug"))
		{
			if(g_hDebugZoneTimer == INVALID_HANDLE)
			{
				g_hDebugZoneTimer = CreateTimer(3.0, Timer_OnShowZones, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
				TriggerTimer(g_hDebugZoneTimer);
			}
			else
			{
				KillTimer(g_hDebugZoneTimer);
				g_hDebugZoneTimer = INVALID_HANDLE;
			}
			ShowFlagAdminMenu(param1);
		}
	}
}

public Menu_SelectFlag(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}
	else if(action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack)
		{
			ShowFlagAdminMenu(param1);
		}
	}
	else if(action == MenuAction_Select)
	{
		decl String:sInfo[256];
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
		new iIndex = StringToInt(sInfo);
		
		ShowFlagOptionMenu(param1, iIndex);
	}
}

public Menu_SelectFlagOption(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}
	else if(action == MenuAction_Cancel)
	{
		g_iPlayerEditsFlag[param1] = -1;
		if(param2 == MenuCancel_ExitBack)
		{
			ShowFlagListMenu(param1);
		}
	}
	else if(action == MenuAction_Select)
	{
		decl String:sInfo[256];
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
		
		decl String:sBuffer[256];
		new Handle:hFlag;
		hFlag = GetArrayCell(g_hFlags, g_iPlayerEditsFlag[param1]);
		
		// Move the flag to a different position.
		if(StrEqual(sInfo, "replace"))
		{
			ShowFlagPositionMenu(param1);
		}
		
		// Rotate the flag
		else if(StrEqual(sInfo, "rotate"))
		{
			ShowFlagRotationMenu(param1);
		}
		
		// Admin wants to go to the flag
		else if(StrEqual(sInfo, "teleport"))
		{
			new Float:fOrigin[3];
			GetArrayArray(hFlag, FLAG_POSITION, fOrigin, 3);
			fOrigin[2] += 10.0;
			TeleportEntity(param1, fOrigin, NULL_VECTOR, NULL_VECTOR);
			ShowFlagOptionMenu(param1, g_iPlayerEditsFlag[param1]);
		}
		
		// Change the trigger mins
		else if(StrEqual(sInfo, "zone_1"))
		{
			ShowFlagZoneEditMenu(param1, MINS_POINT);
		}
		
		// Change the trigger maxs
		else if(StrEqual(sInfo, "zone_2"))
		{
			ShowFlagZoneEditMenu(param1, MAXS_POINT);
		}
		
		// Admin wants to rename the flag
		else if(StrEqual(sInfo, "rename"))
		{
			GetArrayString(hFlag, FLAG_NAME, sBuffer, sizeof(sBuffer));
			g_bPlayerRenamesFlag[param1] = true;
			CPrintToChat(param1, "%s%t", PREFIX, "Type new name", sBuffer);
		}
		
		// Toggle through the different teams
		else if(StrEqual(sInfo, "team"))
		{
			new iTeam = GetArrayCell(hFlag, FLAG_DEFAULTTEAM);
			
			// Basically skip "1" and restart at 3.
			if(iTeam == 0)
				iTeam = CS_TEAM_T;
			else if(++iTeam > CS_TEAM_CT)
				iTeam = 0;
			
			SetArrayCell(hFlag, FLAG_DEFAULTTEAM, iTeam);
			
			// Save the new team to config
			DumpFlagDataToFile();
			
			// Reshow the option menu
			ShowFlagOptionMenu(param1, g_iPlayerEditsFlag[param1]);
		}
		
		// Admin wants to change the amount of players required to conquer this flag
		else if(StrEqual(sInfo, "reqplayers"))
		{
			GetArrayString(hFlag, FLAG_NAME, sBuffer, sizeof(sBuffer));
			new iRequiredPlayers = GetArrayCell(hFlag, FLAG_REQPLAYERS);
			g_bPlayerSetsRequiredPlayers[param1] = true;
			CPrintToChat(param1, "%s%t", PREFIX, "Type players required", sBuffer, iRequiredPlayers);
		}
		
		// Admin wants to change the time in seconds it requires a player to stay near the flag to conquer it
		else if(StrEqual(sInfo, "time"))
		{
			GetArrayString(hFlag, FLAG_NAME, sBuffer, sizeof(sBuffer));
			new iTime = GetArrayCell(hFlag, FLAG_TIME);
			g_bPlayerSetsConquerTime[param1] = true;
			CPrintToChat(param1, "%s%t", PREFIX, "Type conquer time", sBuffer, iTime);
		}
		
		// Change the sorting of the flags to adjust the status panel order
		else if(StrEqual(sInfo, "sort"))
		{
			ShowFlagSortMenu(param1);
		}
		
		// Admin wants to delete the flag
		else if(StrEqual(sInfo, "delete"))
		{
			GetArrayString(hFlag, FLAG_NAME, sBuffer, sizeof(sBuffer));
			
			new Handle:hMenu = CreateMenu(Menu_ConfirmDelete);
			SetMenuTitle(hMenu, "%T", "Delete confirm", param1, sBuffer);
			SetMenuExitButton(hMenu, false);
			Format(sBuffer, sizeof(sBuffer), "%T", "Yes", param1);
			AddMenuItem(hMenu, "yes", sBuffer);
			Format(sBuffer, sizeof(sBuffer), "%T", "No", param1);
			AddMenuItem(hMenu, "no", sBuffer);
			DisplayMenu(hMenu, param1, MENU_TIME_FOREVER);
		}
	}
}

public Menu_RotateFlag(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}
	else if(action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack)
		{
			ShowFlagOptionMenu(param1, g_iPlayerEditsFlag[param1]);
		}
		else
		{
			g_iPlayerEditsFlag[param1] = -1;
		}
	}
	else if(action == MenuAction_Select)
	{
		decl String:sInfo[256];
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
		
		new Float:fRotation;
		
		// Rotate the flag
		if(StrEqual(sInfo, "left"))
			fRotation = -1.0;
		else if(StrEqual(sInfo, "leftfast"))
			fRotation = -10.0;
		else if(StrEqual(sInfo, "right"))
			fRotation = 1.0;
		else if(StrEqual(sInfo, "rightfast"))
			fRotation = 10.0;
		
		new Handle:hFlag = GetArrayCell(g_hFlags, g_iPlayerEditsFlag[param1]);
		new iEnt = GetArrayCell(hFlag, FLAG_FLAGENTITY);
		
		new Float:fAngle[3];
		fAngle[1] = Float:GetArrayCell(hFlag, FLAG_ROTATION) + fRotation;
		
		if(fAngle[1] < 0.0)
			fAngle[1] += 360.0;
		else if(fAngle[1] > 360.0)
			fAngle[1] -= 360.0;
		
		TeleportEntity(iEnt, NULL_VECTOR, fAngle, NULL_VECTOR);
		
		SetArrayCell(hFlag, FLAG_ROTATION, fAngle[1]);
		
		// Save to config file
		DumpFlagDataToFile();
		
		ShowFlagRotationMenu(param1);
	}
}

// Handle delete Yes/No question
public Menu_ConfirmDelete(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}
	else if(action == MenuAction_Cancel)
	{
		// This menu doesn't have an exit/back button, so no need to handle
		g_iPlayerEditsFlag[param1] = -1;
	}
	else if(action == MenuAction_Select)
	{
		decl String:sInfo[256];
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
		
		// Abort if he changed his mind
		if(StrEqual(sInfo, "no"))
		{
			ShowFlagOptionMenu(param1, g_iPlayerEditsFlag[param1]);
			CPrintToChat(param1, "%s%t", PREFIX, "Deletion aborted");
			return;
		}
		
		// Remove all touching players
		for(new i=1;i<=MaxClients;i++)
		{
			if(IsClientInGame(i))
				RemovePlayerFromZone(i, g_iPlayerEditsFlag[param1]);
		}
		
		new Handle:hFlag = GetArrayCell(g_hFlags, g_iPlayerEditsFlag[param1]);
		
		// Get the flagname to be used in confirmation
		decl String:sFlagName[64];
		GetArrayString(hFlag, FLAG_NAME, sFlagName, sizeof(sFlagName));
		
		// Remove the entities
		AcceptEntityInput(GetArrayCell(hFlag, FLAG_FLAGENTITY), "Kill");
		AcceptEntityInput(GetArrayCell(hFlag, FLAG_TRIGGERENTITY), "Kill");
		
		// Kill any related timers
		ResetFlag(g_iPlayerEditsFlag[param1]);
		
		// Remove the flag from the array
		// This will remove it from the HUD as well
		RemoveFromArray(g_hFlags, g_iPlayerEditsFlag[param1]);
		
		// Update the config file
		DumpFlagDataToFile();
		
		// Confirm and show the flag list menu again
		CPrintToChat(param1, "%s%t", PREFIX, "Delete confirmation", sFlagName);
		g_iPlayerEditsFlag[param1] = -1;
		ShowFlagListMenu(param1);
	}
}

public Menu_SetFlagPosition(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}
	else if(action == MenuAction_Cancel)
	{
		if(g_hShowTempFlagPosition[param1] != INVALID_HANDLE)
		{
			KillTimer(g_hShowTempFlagPosition[param1]);
			g_hShowTempFlagPosition[param1] = INVALID_HANDLE;
		}
		
		ClearVector(g_fTempFlagPosition[param1]);
		ClearVector(g_fTempFlagAngle[param1]);
		
		if(param2 == MenuCancel_ExitBack)
		{
			if(g_bPlayerAddsFlag[param1])
				ShowFlagAdminMenu(param1);
			else
				ShowFlagOptionMenu(param1, g_iPlayerEditsFlag[param1]);
		}
		else
		{
			g_iPlayerEditsFlag[param1] = -1;
			g_bPlayerAddsFlag[param1] = false;
		}
	}
	else if(action == MenuAction_Select)
	{
		decl String:sInfo[256];
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
		
		new Handle:hFlag;
		if(StrEqual(sInfo, "save"))
		{
			if(IsNullVector(g_fTempFlagPosition[param1]))
			{
				CPrintToChat(param1, "%s%t", PREFIX, "First set position");
				ShowFlagPositionMenu(param1);
				return;
			}
			
			// Fix for model floating into the ground
			g_fTempFlagPosition[param1][2] += 20.0;
			
			// He is adding a new flag
			if(g_bPlayerAddsFlag[param1])
			{
				// Ask him for a name
				CPrintToChat(param1, "%s%t", PREFIX, "Type description");
				g_bPlayerNamesNewFlag[param1] = true;
			}
			// He is editing an existing flag
			else
			{
				hFlag = GetArrayCell(g_hFlags, g_iPlayerEditsFlag[param1]);
				
				SetArrayArray(hFlag, FLAG_POSITION, g_fTempFlagPosition[param1], 3);
				SetArrayCell(hFlag, FLAG_ROTATION, g_fTempFlagAngle[param1][1]);
				
				// Set the new positions
				new iEnt = GetArrayCell(hFlag, FLAG_FLAGENTITY);
				if(iEnt != -1 && IsValidEdict(iEnt))
				{
					TeleportEntity(iEnt, g_fTempFlagPosition[param1], g_fTempFlagAngle[param1], NULL_VECTOR);
				}
				iEnt = GetArrayCell(hFlag, FLAG_TRIGGERENTITY);
				if(iEnt != -1 && IsValidEdict(iEnt))
				{
					TeleportEntity(iEnt, g_fTempFlagPosition[param1], NULL_VECTOR, NULL_VECTOR);
				}
				
				DumpFlagDataToFile();
				
				if(g_hShowTempFlagPosition[param1] != INVALID_HANDLE)
				{
					KillTimer(g_hShowTempFlagPosition[param1]);
					g_hShowTempFlagPosition[param1] = INVALID_HANDLE;
				}
				
				ClearVector(g_fTempFlagPosition[param1]);
				ClearVector(g_fTempFlagAngle[param1]);
				
				ShowFlagOptionMenu(param1, g_iPlayerEditsFlag[param1]);
			}
			return;
		}
		// He wants to place the flag at his origin
		else if(StrEqual(sInfo, "here"))
		{
			GetClientAbsOrigin(param1, g_fTempFlagPosition[param1]);
			GetClientEyeAngles(param1, g_fTempFlagAngle[param1]);
			g_fTempFlagAngle[param1][0] = 0.0;
			g_fTempFlagAngle[param1][2] = 0.0;
		}
		// He wants to place the flag where he aims
		else if(StrEqual(sInfo, "aim"))
		{
			new Float:fOrigin[3], Float:fAngle[3];
			
			GetClientEyePosition(param1, fOrigin);
			GetClientEyeAngles(param1, fAngle);
			
			TR_TraceRayFilter(fOrigin, fAngle, MASK_PLAYERSOLID, RayType_Infinite, TraceRayNoPlayers, param1);
			if(!TR_DidHit())
			{
				CPrintToChat(param1, "%s%t", PREFIX, "Aim at solid");
				ShowFlagPositionMenu(param1);
				return;
			}
			
			// Keep the old rotation
			g_fTempFlagAngle[param1][0] = 0.0;
			// There is no old rotation when adding a new flag;)
			if(g_bPlayerAddsFlag[param1])
				g_fTempFlagAngle[param1][1] = 0.0;
			else
			{
				hFlag = GetArrayCell(g_hFlags, g_iPlayerEditsFlag[param1]);
				g_fTempFlagAngle[param1][1] = GetArrayCell(hFlag, FLAG_ROTATION);
			}
				
			g_fTempFlagAngle[param1][2] = 0.0;
			
			TR_GetEndPosition(g_fTempFlagPosition[param1]);
		}
		
		// Start showing the new position with a beam temporaly
		if(g_hShowTempFlagPosition[param1] == INVALID_HANDLE)
			g_hShowTempFlagPosition[param1] = CreateTimer(1.0, Timer_OnShowTempPosition, param1, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		
		TriggerTimer(g_hShowTempFlagPosition[param1]);
		
		ShowFlagPositionMenu(param1);
	}
}

public Menu_SetFlagSort(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}
	else if(action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack)
		{
			ShowFlagOptionMenu(param1, g_iPlayerEditsFlag[param1]);
		}
		else
		{
			g_iPlayerEditsFlag[param1] = -1;
		}
	}
	else if(action == MenuAction_Select)
	{
		decl String:sInfo[64];
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
		
		// Store the current handles
		new Handle:hFlag = GetArrayCell(g_hFlags, g_iPlayerEditsFlag[param1]);
		new Handle:hPlayers = GetArrayCell(g_hPlayersInZone, g_iPlayerEditsFlag[param1]);
		
		// Admin wants to set the flag as the latest (most right)
		if(StrEqual(sInfo, "latest"))
		{
			// Remove flag from current index
			RemoveFromArray(g_hFlags, g_iPlayerEditsFlag[param1]);
			// and add it to the end of the array
			new iNew = PushArrayCell(g_hFlags, hFlag);
			
			// Same for the player array
			RemoveFromArray(g_hPlayersInZone, g_iPlayerEditsFlag[param1]);
			PushArrayCell(g_hPlayersInZone, hPlayers);
			
			// Save the current edited index, since the global array is modified in the loop below
			new iEdited = g_iPlayerEditsFlag[param1];
			
			// Update the edit array to keep other editing admins on the correct flag!
			for(new i=1;i<=MaxClients;i++)
			{
				// Ignore players, who don't edit flags atm
				if(g_iPlayerEditsFlag[i] == -1)
					continue;
				
				// This admin is editing the same flag
				if(g_iPlayerEditsFlag[i] == iEdited)
					g_iPlayerEditsFlag[i] = iNew;
				// This admin is editing a later flag. Since we removed one before, we have to lower the index here
				else if(g_iPlayerEditsFlag[i] > iEdited)
					g_iPlayerEditsFlag[i]--;
			}
			
			// Write to config file
			DumpFlagDataToFile();
			
			// Update the targetnames, since they store the flag index either
			new iSize = GetArrayCell(g_hFlags, g_iPlayerEditsFlag[param1]);
			new iEnt;
			for(new i=iEdited;i<iSize;i++)
			{
				hFlag = GetArrayCell(g_hFlags, i);
				iEnt = GetArrayCell(hFlag, FLAG_FLAGENTITY);
				if(iEnt != -1 && IsValidEdict(iEnt))
				{
					Format(sInfo, sizeof(sInfo), "scq_flag_%d", i);
					SetEntPropString(iEnt, Prop_Data, "m_iName", sInfo);
				}
				iEnt = GetArrayCell(hFlag, FLAG_TRIGGERENTITY);
				if(iEnt != -1 && IsValidEdict(iEnt))
				{
					Format(sInfo, sizeof(sInfo), "scq_zone_%d", i);
					SetEntPropString(iEnt, Prop_Data, "m_iName", sInfo);
				}
			}
			
			ShowFlagSortMenu(param1);
			
			return;
		}
		
		// The index of the flag one wants to insert the current flag before
		new iInsertBefore = StringToInt(sInfo)-1;
		
		// Save the current edited index, since the global array is modified in the loop below
		new iEdited = g_iPlayerEditsFlag[param1];
		
		// shift all entries one up, so the position before the one we selected is free
		ShiftArrayUp(g_hFlags, iInsertBefore);
		// Remove the old entry. Since we just shifted the array one up, we have to increase the index, if the flag is currently placed later.
		RemoveFromArray(g_hFlags, (iEdited >= iInsertBefore?iEdited+1:iEdited));
		// Set the new empty cell to the removed one
		SetArrayCell(g_hFlags, iInsertBefore, hFlag);
		
		// Same for the player array
		ShiftArrayUp(g_hPlayersInZone, iInsertBefore);
		RemoveFromArray(g_hPlayersInZone, (iEdited >= iInsertBefore?iEdited+1:iEdited));
		SetArrayCell(g_hPlayersInZone, iInsertBefore, hPlayers);
		
		// Update the edit array to keep other editing admins on the correct flag!
		for(new i=1;i<=MaxClients;i++)
		{
			if(g_iPlayerEditsFlag[i] == -1)
				continue;
			
			// This admin is editing the same flag
			if(g_iPlayerEditsFlag[i] == iEdited)
				g_iPlayerEditsFlag[i] = iInsertBefore;
			// This admin edits a flag, which is between the shifted one and the pre-edit flag position.
			// We shifted this area, so increase the index!
			// We don't have to mind the ones higher the pre-edit position, since we remove that cell, so the index is -1
			else if(g_iPlayerEditsFlag[i] >= iInsertBefore && g_iPlayerEditsFlag[i] < iEdited)
				g_iPlayerEditsFlag[i]++;
			// This admin edits a flag, which is under the pre-edited and the shifted one.
			// We removed the pre-edited and don't insert a new one to replace here, so we need to lower the index
			else if(g_iPlayerEditsFlag[i] < iEdited && g_iPlayerEditsFlag[i] < iInsertBefore)
				g_iPlayerEditsFlag[i]--;
		}
		
		// Update the targetnames, since they store the flag index either
		new iSize = GetArrayCell(g_hFlags, g_iPlayerEditsFlag[param1]);
		new iEnt;
		for(new i=(iEdited<iInsertBefore?iEdited:iInsertBefore);i<iSize;i++)
		{
			hFlag = GetArrayCell(g_hFlags, i);
			iEnt = GetArrayCell(hFlag, FLAG_FLAGENTITY);
			if(iEnt != -1 && IsValidEdict(iEnt))
			{
				Format(sInfo, sizeof(sInfo), "scq_flag_%d", i);
				SetEntPropString(iEnt, Prop_Data, "m_iName", sInfo);
			}
			iEnt = GetArrayCell(hFlag, FLAG_TRIGGERENTITY);
			if(iEnt != -1 && IsValidEdict(iEnt))
			{
				Format(sInfo, sizeof(sInfo), "scq_zone_%d", i);
				SetEntPropString(iEnt, Prop_Data, "m_iName", sInfo);
			}
		}
		
		// Write to config file
		DumpFlagDataToFile();
		
		ShowFlagSortMenu(param1);
	}
}

// Edit the flag 
public Menu_ChangeFlagZoneBounds(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}
	else if(action == MenuAction_Cancel)
	{
		if(g_hShowTempZone[param1] != INVALID_HANDLE)
		{
			KillTimer(g_hShowTempZone[param1]);
			g_hShowTempZone[param1] = INVALID_HANDLE;
		}
		
		g_iPlayerEditsVector[param1] = NO_POINT;
		ClearVector(g_fTempZoneVector1[param1]);
		ClearVector(g_fTempZoneVector2[param1]);
		if(param2 == MenuCancel_ExitBack)
		{
			ShowFlagOptionMenu(param1, g_iPlayerEditsFlag[param1]);
		}
		else
		{
			g_iPlayerEditsFlag[param1] = -1;
		}
	}
	else if(action == MenuAction_Select)
	{
		decl String:sInfo[64];
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
		
		// Save the new coordinates to the file and the adt_array
		if(StrEqual(sInfo, "save"))
		{
			new Handle:hFlag = GetArrayCell(g_hFlags, g_iPlayerEditsFlag[param1]);
			
			if(g_iPlayerEditsVector[param1] == MINS_POINT)
				SetArrayArray(hFlag, FLAG_MINS, g_fTempZoneVector1[param1], 3);
			else if(g_iPlayerEditsVector[param1] == MAXS_POINT)
				SetArrayArray(hFlag, FLAG_MAXS, g_fTempZoneVector2[param1], 3);
			
			// resize the flag and spawn
			new iEnt = GetArrayCell(hFlag, FLAG_TRIGGERENTITY);
			if(iEnt != -1 && IsValidEdict(iEnt))
			{
				SetEntPropVector(iEnt, Prop_Send, "m_vecMins", g_fTempZoneVector1[param1]);
				SetEntPropVector(iEnt, Prop_Send, "m_vecMaxs", g_fTempZoneVector2[param1]);
			}
			
			// Write to config file
			DumpFlagDataToFile();
		}
		// Add to the x axis
		else if(StrEqual(sInfo, "ax"))
		{
			if(g_iPlayerEditsVector[param1] == MINS_POINT)
				g_fTempZoneVector1[param1][0] += 5.0;
			else if(g_iPlayerEditsVector[param1] == MAXS_POINT)
				g_fTempZoneVector2[param1][0] += 5.0;
		}
		// Add to the y axis
		else if(StrEqual(sInfo, "ay"))
		{
			if(g_iPlayerEditsVector[param1] == MINS_POINT)
				g_fTempZoneVector1[param1][1] += 5.0;
			else if(g_iPlayerEditsVector[param1] == MAXS_POINT)
				g_fTempZoneVector2[param1][1] += 5.0;
		}
		// Add to the z axis
		else if(StrEqual(sInfo, "az"))
		{
			if(g_iPlayerEditsVector[param1] == MINS_POINT)
				g_fTempZoneVector1[param1][2] += 5.0;
			else if(g_iPlayerEditsVector[param1] == MAXS_POINT)
				g_fTempZoneVector2[param1][2] += 5.0;
		}
		// Subtract from the x axis
		else if(StrEqual(sInfo, "sx"))
		{
			if(g_iPlayerEditsVector[param1] == MINS_POINT)
				g_fTempZoneVector1[param1][0] -= 5.0;
			else if(g_iPlayerEditsVector[param1] == MAXS_POINT)
				g_fTempZoneVector2[param1][0] -= 5.0;
		}
		// Subtract from the y axis
		else if(StrEqual(sInfo, "sy"))
		{
			if(g_iPlayerEditsVector[param1] == MINS_POINT)
				g_fTempZoneVector1[param1][1] -= 5.0;
			else if(g_iPlayerEditsVector[param1] == MAXS_POINT)
				g_fTempZoneVector2[param1][1] -= 5.0;
		}
		// Subtract from the z axis
		else if(StrEqual(sInfo, "sz"))
		{
			if(g_iPlayerEditsVector[param1] == MINS_POINT)
				g_fTempZoneVector1[param1][2] -= 5.0;
			else if(g_iPlayerEditsVector[param1] == MAXS_POINT)
				g_fTempZoneVector2[param1][2] -= 5.0;
		}
		
		// Show the zone immediately
		TriggerTimer(g_hShowTempZone[param1]);
		
		ShowFlagZoneEditMenu(param1, g_iPlayerEditsVector[param1]);
	}
}

/**
 * Timer Callbacks
 */
public Action:Timer_OnShowZones(Handle:timer, any:data)
{
	new iSize = GetArraySize(g_hFlags);
	new Handle:hFlag, Float:fMins[3], Float:fMaxs[3], Float:fOrigin[3], Float:fFirstPoint[3], Float:fSecondPoint[3];
	new clients[MaxClients], total = 0;
	for(new i=0;i<iSize;i++)
	{
		hFlag = GetArrayCell(g_hFlags, i);
		GetArrayArray(hFlag, FLAG_MINS, fMins, 3);
		GetArrayArray(hFlag, FLAG_MAXS, fMaxs, 3);
		GetArrayArray(hFlag, FLAG_POSITION, fOrigin, 3);
		
		fFirstPoint[0] = fOrigin[0] + fMins[0];
		fFirstPoint[1] = fOrigin[1] + fMins[1];
		fFirstPoint[2] = fOrigin[2] + fMins[2];
		
		fSecondPoint[0] = fOrigin[0] + fMaxs[0];
		fSecondPoint[1] = fOrigin[1] + fMaxs[1];
		fSecondPoint[2] = fOrigin[2] + fMaxs[2];
		
		// Only show the boxes to players who aren't currently editing this box
		total = 0;
		for (new c=1; c<=MaxClients; c++)
		{
			if (IsClientInGame(c) && g_hShowTempZone[c] == INVALID_HANDLE)
			{
				clients[total++] = c;
			}
		}
		
		Effect_DrawBeamBox(clients, total, fFirstPoint, fSecondPoint, g_iLaserMaterial, g_iHaloMaterial, 0, 30, 3.0, 5.0, 5.0, 2, 1.0, {255,0,0,255}, 0);
	}
	
	return Plugin_Continue;
}

// Show the temporary new position of the flag this player edits
public Action:Timer_OnShowTempPosition(Handle:timer, any:client)
{
	new Float:fOrigin[3];
	fOrigin = g_fTempFlagPosition[client];
	fOrigin[2] += 120.0;
	TE_SetupBeamPoints(g_fTempFlagPosition[client], fOrigin, g_iLaserMaterial, g_iHaloMaterial, 0, 30, 1.0, 5.0, 5.0, 1, 1.0, {255,0,0,255}, 0);
	TE_SendToClient(client);
	return Plugin_Continue;
}

// Show the temporary changed zone to the client editing
// When this timer runs, the above debug timer skips this client.
public Action:Timer_OnShowTempZone(Handle:timer, any:data)
{
	new client = ReadPackCell(data);
	new iZone = ReadPackCell(data);
	ResetPack(data);
	
	new Handle:hFlag = GetArrayCell(g_hFlags, g_iPlayerEditsFlag[client]);
	new Float:fOrigin[3], Float:fMins[3], Float:fMaxs[3], Float:fFirstPoint[3], Float:fSecondPoint[3];
	
	if(iZone == MINS_POINT)
	{
		fMins = g_fTempZoneVector1[client];
		GetArrayArray(hFlag, FLAG_MAXS, fMaxs, 3);
	}
	else if(iZone == MAXS_POINT)
	{
		GetArrayArray(hFlag, FLAG_MINS, fMins, 3);
		fMaxs = g_fTempZoneVector2[client];
	}
	
	GetArrayArray(hFlag, FLAG_POSITION, fOrigin, 3);
	
	fFirstPoint[0] = fOrigin[0] + fMins[0];
	fFirstPoint[1] = fOrigin[1] + fMins[1];
	fFirstPoint[2] = fOrigin[2] + fMins[2];
	
	fSecondPoint[0] = fOrigin[0] + fMaxs[0];
	fSecondPoint[1] = fOrigin[1] + fMaxs[1];
	fSecondPoint[2] = fOrigin[2] + fMaxs[2];
	
	
	if(iZone == MINS_POINT)
		TE_SetupGlowSprite(fFirstPoint, g_iGlowSprite, 1.0, 1.0, 100);
	else
		TE_SetupGlowSprite(fSecondPoint, g_iGlowSprite, 1.0, 1.0, 100);
	TE_SendToClient(client);
	
	Effect_DrawBeamBoxToClient(client, fFirstPoint, fSecondPoint, g_iLaserMaterial, g_iHaloMaterial, 0, 30, 1.0, 5.0, 5.0, 1, 1.0, {255,0,0,255}, 0);
	
	return Plugin_Continue;
}

/**
 * Command Handlers
 */
public Action:Command_FlagAdmin(client, args)
{
	ShowFlagAdminMenu(client);
	return Plugin_Handled;
} 

public Action:Command_Say(client, args)
{
	// This player just added a new flag
	if (g_bPlayerNamesNewFlag[client])
	{
		// get the name
		new String:sFlagName[64];
		GetCmdArgString(sFlagName, sizeof(sFlagName));
		StripQuotes(sFlagName);
		
		g_bPlayerNamesNewFlag[client] = false;
		
		// Changed his mind?
		if(StrEqual(sFlagName, "!stop"))
		{
			CPrintToChat(client, "%s%t", PREFIX, "Stop naming");
			
			if(g_hShowTempFlagPosition[client] != INVALID_HANDLE)
			{
				KillTimer(g_hShowTempFlagPosition[client]);
				g_hShowTempFlagPosition[client] = INVALID_HANDLE;
			}
			
			ClearVector(g_fTempFlagPosition[client]);
			ClearVector(g_fTempFlagAngle[client]);
			return Plugin_Handled;
		}
		
		new Handle:hFlag = CreateArray(ByteCountToCells(256));
		
		// A description shown in chat when conquered
		PushArrayString(hFlag, sFlagName);
		
		// The default team the flag belongs to at spawn
		PushArrayCell(hFlag, 0);
		// Stores the current team, so at spawn the default
		PushArrayCell(hFlag, 0);
		
		// How many players are required to conquer that flag?
		PushArrayCell(hFlag, 1);
		
		// How many seconds have the players to stay in the zone alone without an enemy?
		PushArrayCell(hFlag, 5);
		
		// The position of the flag
		PushArrayArray(hFlag, g_fTempFlagPosition[client], 3);
		
		// The bounds of the trigger_multiple around that flag
		PushArrayArray(hFlag, Float:{-100.0, -100.0, -20.0}, 3);
		
		PushArrayArray(hFlag, Float:{100.0, 100.0, 150.0}, 3);
		
		// Set default flag and trigger entity indexes
		PushArrayCell(hFlag, -1);
		PushArrayCell(hFlag, -1);
		
		// No timer is running for this zone
		PushArrayCell(hFlag, INVALID_HANDLE);
		
		// No starttime of conquer yet
		PushArrayCell(hFlag, -1);
		
		// Triggers set in that map?
		PushArrayString(hFlag, "");
		PushArrayString(hFlag, "");
		
		// The angle rotation (yaw)
		PushArrayCell(hFlag, g_fTempFlagAngle[client][1]);
		
		// Add it to the global flags array
		new iIndex = PushArrayCell(g_hFlags, hFlag);
		
		// Push the players array to be at the same index.
		hFlag = CreateArray();
		PushArrayCell(g_hPlayersInZone, hFlag);
		
		if(g_hShowTempFlagPosition[client] != INVALID_HANDLE)
		{
			KillTimer(g_hShowTempFlagPosition[client]);
			g_hShowTempFlagPosition[client] = INVALID_HANDLE;
		}
		
		ClearVector(g_fTempFlagPosition[client]);
		ClearVector(g_fTempFlagAngle[client]);
		
		ResetFlag(iIndex);
		SpawnFlag(iIndex);
		
		CPrintToChat(client, "%s%t", PREFIX, "Add confirmation", sFlagName);
		
		// Save to config file
		DumpFlagDataToFile();
		
		// He's editing that flag now.
		ShowFlagOptionMenu(client, iIndex);
		
		// Don't show the name in chat
		return Plugin_Handled;
	}
	// This player is renaming a flag
	else if(g_bPlayerRenamesFlag[client])
	{
		// get the name
		new String:sFlagName[64];
		GetCmdArgString(sFlagName, sizeof(sFlagName));
		StripQuotes(sFlagName);
		
		g_bPlayerRenamesFlag[client] = false;
		
		if(StrEqual(sFlagName, "!stop"))
		{
			
			CPrintToChat(client, "%s%t", PREFIX, "Stopped renaming");
			
			ShowFlagOptionMenu(client, g_iPlayerEditsFlag[client]);
			return Plugin_Handled;
		}
		
		// Set the zone/fence name
		decl String:sOldFlagName[64];
		new Handle:hFlag = GetArrayCell(g_hFlags, g_iPlayerEditsFlag[client]);
		GetArrayString(hFlag, FLAG_NAME, sOldFlagName, sizeof(sOldFlagName));
		SetArrayString(hFlag, FLAG_NAME, sFlagName);
		
		CPrintToChat(client, "%s%t", PREFIX, "Name changed", sOldFlagName, sFlagName);
		
		// Update the config file
		DumpFlagDataToFile();
		
		ShowFlagOptionMenu(client, g_iPlayerEditsFlag[client]);
		
		// Don't show the name in chat
		return Plugin_Handled;
	}
	// This player edits the required players count to conquer a flag
	else if(g_bPlayerSetsRequiredPlayers[client])
	{
		// get the player count
		new String:sCount[10];
		GetCmdArgString(sCount, sizeof(sCount));
		StripQuotes(sCount);
		
		if(StrEqual(sCount, "!stop"))
		{
			CPrintToChat(client, "%s%t", PREFIX, "Stop required players");
			
			ShowFlagOptionMenu(client, g_iPlayerEditsFlag[client]);
			return Plugin_Handled;
		}
		
		new iCount = StringToInt(sCount);
		if(iCount < 1 || iCount > MAXPLAYERS)
		{
			CPrintToChat(client, "%s%t", PREFIX, "Required players out of range", MAXPLAYERS, iCount);
			return Plugin_Handled;
		}
		
		decl String:sFlagName[64];
		new Handle:hFlag = GetArrayCell(g_hFlags, g_iPlayerEditsFlag[client]);
		GetArrayString(hFlag, FLAG_NAME, sFlagName, sizeof(sFlagName));
		
		CPrintToChat(client, "%s%t", PREFIX, "Required players changed", GetArrayCell(hFlag, FLAG_REQPLAYERS), iCount);
		
		// Save to local array
		SetArrayCell(hFlag, FLAG_REQPLAYERS, iCount);
		
		// Save to config file
		DumpFlagDataToFile();
		
		ShowFlagOptionMenu(client, g_iPlayerEditsFlag[client]);
		
		return Plugin_Handled;
	}
	// This player edits the conquer time for a flag
	else if(g_bPlayerSetsConquerTime[client])
	{
		// get the conquer time
		new String:sTime[10];
		GetCmdArgString(sTime, sizeof(sTime));
		StripQuotes(sTime);
		
		if(StrEqual(sTime, "!stop"))
		{
			CPrintToChat(client, "%s%t", PREFIX, "Stop conquer time");
			
			ShowFlagOptionMenu(client, g_iPlayerEditsFlag[client]);
			return Plugin_Handled;
		}
		
		new iTime = StringToInt(sTime);
		if(iTime < 1)
		{
			CPrintToChat(client, "%s%t", PREFIX, "Conquer time out of range", iTime);
			return Plugin_Handled;
		}
		
		decl String:sFlagName[64];
		new Handle:hFlag = GetArrayCell(g_hFlags, g_iPlayerEditsFlag[client]);
		GetArrayString(hFlag, FLAG_NAME, sFlagName, sizeof(sFlagName));
		
		CPrintToChat(client, "%s%t", PREFIX, "Conquer time changed", GetArrayCell(hFlag, FLAG_TIME), iTime);
		
		// Save to local array
		SetArrayCell(hFlag, FLAG_TIME, iTime);
		
		// Save to config file
		DumpFlagDataToFile();
		
		ShowFlagOptionMenu(client, g_iPlayerEditsFlag[client]);
		
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

/**
 * Helper Functions
 */
// Saves the current flag array information to the keyvalues file
DumpFlagDataToFile()
{
	decl String:sConfigFile[PLATFORM_MAX_PATH], String:sMap[64], String:sGame[10];
	GetCurrentMap(sMap, sizeof(sMap));
	
	// Get the correct map config for this game
	if(g_bIsCSGO)
		Format(sGame, sizeof(sGame), "csgo");
	else
		Format(sGame, sizeof(sGame), "css");
	
	BuildPath(Path_SM, sConfigFile, sizeof(sConfigFile), "configs/smconquest/%s/maps/%s.cfg", sGame, sMap);
	
	new Handle:kv = CreateKeyValues("FlagsAreas");
	new iSize = GetArraySize(g_hFlags);
	new Handle:hFlag, Float:fVec[3];
	decl String:sBuffer[256];
	for(new i=0;i<iSize;i++)
	{
		hFlag = GetArrayCell(g_hFlags, i);
		IntToString(i, sBuffer, sizeof(sBuffer));
		// Create a new section for that flag
		KvJumpToKey(kv, sBuffer, true);
		
		GetArrayString(hFlag, FLAG_NAME, sBuffer, sizeof(sBuffer));
		KvSetString(kv, "description", sBuffer);
		
		KvSetNum(kv, "team", GetArrayCell(hFlag, FLAG_DEFAULTTEAM));
		KvSetNum(kv, "num_to_cap", GetArrayCell(hFlag, FLAG_REQPLAYERS));
		KvSetNum(kv, "time_to_cap", GetArrayCell(hFlag, FLAG_TIME));
		
		GetArrayArray(hFlag, FLAG_POSITION, fVec, 3);
		KvSetVector(kv, "position", fVec);
		
		GetArrayArray(hFlag, FLAG_MINS, fVec, 3);
		KvSetVector(kv, "zonemins", fVec);
		
		GetArrayArray(hFlag, FLAG_MAXS, fVec, 3);
		KvSetVector(kv, "zonemaxs", fVec);
		
		GetArrayString(hFlag, FLAG_LOGICTRIGGERT, sBuffer, sizeof(sBuffer));
		KvSetString(kv, "t_capture_relay", sBuffer);
		GetArrayString(hFlag, FLAG_LOGICTRIGGERCT, sBuffer, sizeof(sBuffer));
		KvSetString(kv, "ct_capture_relay", sBuffer);
		
		KvSetFloat(kv, "rotation", GetArrayCell(hFlag, FLAG_ROTATION));
		KvGoBack(kv);
	}
	KvRewind(kv);
	KeyValuesToFile(kv, sConfigFile);
	CloseHandle(kv);
}


stock ClearVector(Float:vec[3])
{
	vec[0] = 0.0;
	vec[1] = 0.0;
	vec[2] = 0.0;
}

stock bool:IsNullVector(const Float:vec[3])
{
	if(vec[0] == 0.0 && vec[1] == 0.0 && vec[2] == 0.0)
		return true;
	return false;
}
/*
 * Handles the player classes
 * Part of SM:Conquest
 *
 * Thread: https://forums.alliedmods.net/showthread.php?t=154354
 * visit http://www.wcfan.de/
 */
#include <sourcemod>

#define CLASS_NAME 0
#define CLASS_DEFAULT 1
#define CLASS_TEAM 2
#define CLASS_LIMIT 3
#define CLASS_WEAPONSETS 4
#define CLASS_MODEL 5
#define CLASS_ADMFLAGS 6

#define CLASS_NUMOPTIONS 7

#define MODELS_ALIAS 0
#define MODELS_MDLFILE 1

#define WEAPONSET_NAME 0
#define WEAPONSET_PRICE 1
#define WEAPONSET_WEAPONLIST 2
#define WEAPONSET_ADMFLAGS 3

#define WEAPONSET_NUMOPTIONS 4

#define GRENADE_HE 0
#define GRENADE_FLASH 1
#define GRENADE_SMOKE 2

// Array holding all classes from the config file
new Handle:g_hClasses;

enum ConfigSection
{
	State_None = 0,
	State_Root,
	State_Class,
	State_WeaponSet,
	State_Files
}

// Class config parser stuff
new ConfigSection:g_ConfigSection = State_None;
new g_iCurrentClassIndex = -1;
new g_iCurrentWeaponSetIndex = -1;

// Array holding the models
new Handle:g_hModels;

// Model config parser
new ConfigSection:g_ModelConfigSection = State_None;
new g_iCurrentModelIndex = -1;
new bool:g_bDontDownloadCurrentModel = false;

new g_iPlayerClass[MAXPLAYERS+2] = {-1, ...};
new g_iPlayerTempClass[MAXPLAYERS+2] = {-1, ...};
new g_iPlayerWeaponSet[MAXPLAYERS+2] = {-1, ...};
new g_iPlayerGrenade[MAXPLAYERS+2][3];

new Handle:g_hApplyPlayerClass[MAXPLAYERS+2] = {INVALID_HANDLE,...};
new bool:g_bPlayerJustJoined[MAXPLAYERS+2] = {true,...};

/**
 * Menu Handler
 */

// Player selected a class
public Menu_SelectClass(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}
	else if(action == MenuAction_Select)
	{
		decl String:info[35];
		GetMenuItem(menu, param2, info, sizeof(info));
		
		new iClass = StringToInt(info);
		new Handle:hClass = GetArrayCell(g_hClasses, iClass);
		
		// This class is only available to players with a certain adminflag
		new iAdminBits = GetArrayCell(hClass, CLASS_ADMFLAGS);
		if(iAdminBits > 0 && (GetUserFlagBits(param1) & iAdminBits) == 0)
		{
			// Just show the menu again. They shouldn't have been able to select this class anyways!
			ShowClassMenu(param1);
			return;
		}
		
		decl String:sClassName[128];
		GetArrayString(hClass, CLASS_NAME, sClassName, sizeof(sClassName));
		
		// Check, if this player got ninja'd and the limit is reached already
		new iCurrentPlayers = GetTotalPlayersInClass(iClass, GetClientTeam(param1));
		new iLimit = GetArrayCell(hClass, CLASS_LIMIT);
		// Allow to change the weaponset, if he's already in that class.
		if(iLimit != 0 && iCurrentPlayers >= iLimit && g_iPlayerClass[param1] != iClass)
		{
			CPrintToChat(param1, "%s%t", PREFIX, "Class limit reached", sClassName);
			ShowClassMenu(param1);
			return;
		}
		
		g_iPlayerTempClass[param1] = iClass;
		
		ShowWeaponSetMenu(param1);
	}
}


public Menu_SelectWeaponSet(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}
	else if(action == MenuAction_Cancel)
	{
		g_iPlayerTempClass[param1] = -1;
		if(param2 == MenuCancel_ExitBack)
		{
			ShowClassMenu(param1);
		}
	}
	else if(action == MenuAction_Select)
	{
		// Has to choose a class first. Something might got reset during menu display
		if(g_iPlayerTempClass[param1] == -1)
		{
			ShowClassMenu(param1);
			return;
		}
		
		decl String:info[35];
		GetMenuItem(menu, param2, info, sizeof(info));
		
		new Handle:hClass = GetArrayCell(g_hClasses, g_iPlayerTempClass[param1]);
		
		decl String:sClassName[128];
		GetArrayString(hClass, CLASS_NAME, sClassName, sizeof(sClassName));
		
		// Check, if this player got ninja'd and the limit is reached already
		new iCurrentPlayers = GetTotalPlayersInClass(g_iPlayerTempClass[param1], GetClientTeam(param1));
		new iLimit = GetArrayCell(hClass, CLASS_LIMIT);
		// Allow to change the weaponset, if he's already in that class.
		if(iLimit != 0 && iCurrentPlayers >= iLimit && g_iPlayerClass[param1] != g_iPlayerTempClass[param1])
		{
			CPrintToChat(param1, "%s%t", PREFIX, "Class limit reached", sClassName);
			ShowClassMenu(param1);
			return;
		}
		
		new iWeaponSet = StringToInt(info);
		
		decl String:sWeapon[64];
		new Handle:hWeaponSets = GetArrayCell(hClass, CLASS_WEAPONSETS);
		new Handle:hWeapons = GetArrayCell(hWeaponSets, iWeaponSet);
		GetArrayString(hWeapons, WEAPONSET_NAME, sWeapon, sizeof(sWeapon));
		
		// This weaponset is only available to players with a certain adminflag
		new iAdminBits = GetArrayCell(hWeapons, WEAPONSET_ADMFLAGS);
		if(iAdminBits > 0 && (GetUserFlagBits(param1) & iAdminBits) == 0)
		{
			// Just show the menu again. They shouldn't have been able to select this weaponset anyways!
			ShowWeaponSetMenu(param1);
			return;
		}
		
		// Check for the money
		new iPrice = GetArrayCell(hWeapons, WEAPONSET_PRICE);
		new iMoney = GetEntData(param1, g_iAccount);
		if(iMoney < iPrice)
		{
			CPrintToChat(param1, "%s%t", PREFIX, "Not enough money for weaponset");
			ShowWeaponSetMenu(param1);
			return;
		}
		
		// Get the money
		if(iPrice > 0)
			SetEntData(param1, g_iAccount, iMoney-iPrice);
		
		// set that weaponset
		g_iPlayerWeaponSet[param1] = iWeaponSet;
		
		CPrintToChat(param1, "%s%t", PREFIX, "Chose class", sClassName, sWeapon);
		
		g_iPlayerClass[param1] = g_iPlayerTempClass[param1];
		
		// Apply the first class chosing directly without the need of respawn
		if(g_bPlayerJustJoined[param1] && IsPlayerAlive(param1) && GetClientTeam(param1) >= CS_TEAM_T)
		{
			// Strip weapons
			Client_RemoveAllWeapons(param1, "weapon_knife", true);
			// Set the class with a delay
			g_hApplyPlayerClass[param1] = CreateTimer(0.1, Timer_ApplyPlayerClass, GetClientUserId(param1), TIMER_FLAG_NO_MAPCHANGE);
		}
		
		g_bPlayerJustJoined[param1] = false;
	}
}

/**
 * Menu Display
 */

ShowClassMenu(client)
{
	new iSize = GetArraySize(g_hClasses);
	if(iSize == 0)
		return;
	
	new Handle:menu = CreateMenu(Menu_SelectClass);
	SetMenuTitle(menu, "%T", "Select class", client);
	// Allow exiting, if player already has a class
	SetMenuExitButton(menu, true);
	
	new Handle:hClass, iTeam, iAdminBits;
	decl String:sClassIndex[5], String:sClassName[128];
	for(new i=0;i<iSize;i++)
	{
		IntToString(i, sClassIndex, sizeof(sClassIndex));
		hClass = GetArrayCell(g_hClasses, i);
		
		// Check if the player is in the correct team
		iTeam = GetArrayCell(hClass, CLASS_TEAM);
		if(iTeam > 0 && iTeam != GetClientTeam(client))
			continue;
		
		// This class is only available to players with a certain adminflag
		iAdminBits = GetArrayCell(hClass, CLASS_ADMFLAGS);
		if(iAdminBits > 0 && (GetUserFlagBits(client) & iAdminBits) == 0)
			continue;
		
		GetArrayString(hClass, CLASS_NAME, sClassName, sizeof(sClassName));
		
		new iCurrentPlayers = GetTotalPlayersInClass(i, GetClientTeam(client));
		new iLimit = GetArrayCell(hClass, CLASS_LIMIT);
		
		// Show an asterix * behind the class the player currently is in
		if(i == g_iPlayerClass[client])
			Format(sClassName, sizeof(sClassName), "%s *", sClassName);
		
		// Add possible players left until limit reached to that class
		if(iLimit > 0)
		{
			Format(sClassName, sizeof(sClassName), "%s [%d/%d]", sClassName, iCurrentPlayers, iLimit);
		}
		
		// Check >= due to admin overrides, which would allow to force more than the limit
		if(iLimit != 0 && iCurrentPlayers >= iLimit && g_iPlayerClass[client] != i)
			AddMenuItem(menu, sClassIndex, sClassName, ITEMDRAW_DISABLED);
		else
			AddMenuItem(menu, sClassIndex, sClassName);
	}
	
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

ShowWeaponSetMenu(client)
{
	// Has to choose a class first
	if(g_iPlayerTempClass[client] == -1)
	{
		ShowClassMenu(client);
		return;
	}
	
	new Handle:hClass = GetArrayCell(g_hClasses, g_iPlayerTempClass[client]);
	new Handle:hWeaponSets = GetArrayCell(hClass, CLASS_WEAPONSETS);
	
	new iSize = GetArraySize(hWeaponSets);
	if(iSize == 0)
		return;
	
	decl String:sClassName[128];
	GetArrayString(hClass, CLASS_NAME, sClassName, sizeof(sClassName));
	
	new Handle:menu = CreateMenu(Menu_SelectWeaponSet);
	SetMenuTitle(menu, "%T", "Select weapon set", client, sClassName);
	SetMenuExitBackButton(menu, true);
	
	new Handle:hWeapons, iPrice, iAdminBits;
	decl String:sWeaponIndex[5], String:sWeaponName[128];
	for(new i=0;i<iSize;i++)
	{
		hWeapons = GetArrayCell(hWeaponSets, i);
		
		// This weaponset is only available to players with a certain adminflag
		iAdminBits = GetArrayCell(hWeapons, WEAPONSET_ADMFLAGS);
		if(iAdminBits > 0 && (GetUserFlagBits(client) & iAdminBits) == 0)
			continue;
		
		GetArrayString(hWeapons, WEAPONSET_NAME, sWeaponName, sizeof(sWeaponName));
		IntToString(i, sWeaponIndex, sizeof(sWeaponIndex));
		
		// Show an asterix * behind the weaponset the player currently uses
		if(g_iPlayerClass[client] != -1 && g_iPlayerTempClass[client] == g_iPlayerClass[client] && i == g_iPlayerWeaponSet[client])
			Format(sWeaponName, sizeof(sWeaponName), "%s *", sWeaponName);
		
		// Add a price
		iPrice = GetArrayCell(hWeapons, WEAPONSET_PRICE);
		if(iPrice > 0)
			Format(sWeaponName, sizeof(sWeaponName), "%s ($%d)", sWeaponName, iPrice);
		
		AddMenuItem(menu, sWeaponIndex, sWeaponName);
	}
	
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

GivePlayerClassWeapons(client, iClass, iWeaponSet)
{
	new Handle:hClass = GetArrayCell(g_hClasses, iClass);
	
	// Get weapons
	new Handle:hWeaponSets = GetArrayCell(hClass, CLASS_WEAPONSETS);
	new Handle:hWeapons = GetArrayCell(hWeaponSets, iWeaponSet);
	new Handle:hWeaponList = GetArrayCell(hWeapons, WEAPONSET_WEAPONLIST);
	new iSize = GetArraySize(hWeaponList);
	decl String:sWeapon[64];
	for(new i=0;i<iSize;i+=2)
	{
		GetArrayString(hWeaponList, i, sWeapon, sizeof(sWeapon));
		
		// Handle grenades separately
		if(StrEqual(sWeapon, "weapon_hegrenade", false))
		{
			g_iPlayerGrenade[client][GRENADE_HE] = GetArrayCell(hWeaponList, i+1);
			if(g_iPlayerGrenade[client][GRENADE_HE] > 0)
				Client_GiveWeapon(client, sWeapon, false);
		}
		else if(StrEqual(sWeapon, "weapon_flashbang", false))
		{
			g_iPlayerGrenade[client][GRENADE_FLASH] = GetArrayCell(hWeaponList, i+1);
			if(g_iPlayerGrenade[client][GRENADE_FLASH] > 0)
				Client_GiveWeapon(client, sWeapon, false);
		}
		else if(StrEqual(sWeapon, "weapon_smokegrenade", false))
		{
			g_iPlayerGrenade[client][GRENADE_SMOKE] = GetArrayCell(hWeaponList, i+1);
			if(g_iPlayerGrenade[client][GRENADE_SMOKE] > 0)
				Client_GiveWeapon(client, sWeapon, false);
		}
		else if(StrEqual(sWeapon, "item_kevlar", false))
		{
			SetEntProp(client, Prop_Send, "m_ArmorValue", GetArrayCell(hWeaponList, i+1));
		}
		else if(StrEqual(sWeapon, "item_assaultsuit", false))
		{
			SetEntProp(client, Prop_Send, "m_ArmorValue", GetArrayCell(hWeaponList, i+1));
			SetEntProp(client, Prop_Send, "m_bHasHelmet", 1);
		}
		else if(StrEqual(sWeapon, "health", false))
		{
			SetEntityHealth(client, GetArrayCell(hWeaponList, i+1));
		}
		else if(StrEqual(sWeapon, "speed", false))
		{
			SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", GetArrayCell(hWeaponList, i+1));
		}
		else
		{
			// Give him the weapon
			Client_GiveWeaponAndAmmo(client, sWeapon, false, GetArrayCell(hWeaponList, i+1), -1, -1, GetArrayCell(hWeaponList, i+1));
		}
	}
	
	// Change to the primary weapon if available
	new iWeapon;
	if((iWeapon = Client_GetWeaponBySlot(client, CS_SLOT_PRIMARY)) != INVALID_ENT_REFERENCE && IsValidEdict(iWeapon))
	{
		GetEdictClassname(iWeapon, sWeapon, sizeof(sWeapon));
		FakeClientCommand(client, "use %s", sWeapon);
		
		// Set the last weapon to the secondary, if available, so quick switch is working intentionally
		if((iWeapon = Client_GetWeaponBySlot(client, CS_SLOT_SECONDARY)) != INVALID_ENT_REFERENCE && IsValidEdict(iWeapon))
		{
			Client_SetLastActiveWeapon(client, iWeapon);
		}
	}
	// or secondary weapon
	else if((iWeapon = Client_GetWeaponBySlot(client, CS_SLOT_SECONDARY)) != INVALID_ENT_REFERENCE && IsValidEdict(iWeapon))
	{
		GetEdictClassname(iWeapon, sWeapon, sizeof(sWeapon));
		FakeClientCommand(client, "use %s", sWeapon);
	}
}

GetTotalPlayersInClass(iClass, iTeam=0)
{
	new iCount = 0;
	for(new i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i) && g_iPlayerClass[i] == iClass && (iTeam == 0 || iTeam == GetClientTeam(i)))
			iCount++;
	}
	return iCount;
}

GetDefaultClass(iTeam)
{
	new iSize = GetArraySize(g_hClasses);
	new Handle:hClass, iClassTeam;
	for(new i=0;i<iSize;i++)
	{
		hClass = GetArrayCell(g_hClasses, i);
		iClassTeam = GetArrayCell(hClass, CLASS_TEAM);
		if(GetArrayCell(hClass, CLASS_DEFAULT) == 1 && (iClassTeam == iTeam || iClassTeam == 0))
			return i;
	}
	return -1;
}

/**
 * Command Callbacks
 */

public Action:Command_ShowClassMenu(client, args)
{
	ShowClassMenu(client);
	return Plugin_Handled;
}


public Action:Timer_ApplyPlayerClass(Handle:timer, any:userid)
{
	new client = GetClientOfUserId(userid);
	
	g_hApplyPlayerClass[client] = INVALID_HANDLE;
	
	if(!client || !IsClientInGame(client) || !IsPlayerAlive(client))
	{
		return Plugin_Stop;
	}
	
	// Set the default class, if unset
	if(g_iPlayerClass[client] == -1)
	{
		g_iPlayerClass[client] = GetDefaultClass(GetClientTeam(client));
		g_iPlayerWeaponSet[client] = 0;
		ShowClassMenu(client);
		CPrintToChat(client, "%s%t", PREFIX, "Class introduction");
	}
	
	// We don't want bots to have classes!
	if(IsFakeClient(client) && !GetConVarBool(g_hCVStripBots))
	{
		return Plugin_Stop;
	}
	
	// Get the classname
	decl String:sClassName[128];
	new Handle:hClass = GetArrayCell(g_hClasses, g_iPlayerClass[client]);
	GetArrayString(hClass, CLASS_NAME, sClassName, sizeof(sClassName));
	
	// This class is only available to players with a certain adminflag
	new iAdminBits = GetArrayCell(hClass, CLASS_ADMFLAGS);
	if(iAdminBits > 0 && (GetUserFlagBits(client) & iAdminBits) == 0)
	{
		// He doesn't have access anymore. Set to default class and show menu again.
		g_iPlayerClass[client] = GetDefaultClass(GetClientTeam(client));
		g_iPlayerWeaponSet[client] = 0;
		ShowClassMenu(client);
		CPrintToChat(client, "%s%t", PREFIX, "Class introduction");
	}
	
	// Get the weaponset name
	decl String:sWeapon[64];
	new Handle:hWeaponSets = GetArrayCell(hClass, CLASS_WEAPONSETS);
	new Handle:hWeapons = GetArrayCell(hWeaponSets, g_iPlayerWeaponSet[client]);
	GetArrayString(hWeapons, WEAPONSET_NAME, sWeapon, sizeof(sWeapon));
	
	// This weaponset is only available to players with a certain adminflag
	iAdminBits = GetArrayCell(hWeapons, WEAPONSET_ADMFLAGS);
	if(iAdminBits > 0 && (GetUserFlagBits(client) & iAdminBits) == 0)
	{
		// Let him select a new weaponset.
		g_iPlayerTempClass[client] = g_iPlayerClass[client];
		g_iPlayerClass[client] = -1;
		g_iPlayerWeaponSet[client] = -1;
		ShowWeaponSetMenu(client);
		return Plugin_Stop;
	}
	
	// Remove weapons again
	Client_RemoveAllWeapons(client, "weapon_knife", true);
	
	// Give him the weapons
	GivePlayerClassWeapons(client, g_iPlayerClass[client], g_iPlayerWeaponSet[client]);
	CPrintToChat(client, "%s%t", PREFIX, "Apply class", sClassName, sWeapon);
	
	// Set the model, if this class has one assigned
	new iModel = GetArrayCell(hClass, CLASS_MODEL);
	if(iModel != -1)
	{
		new Handle:hModel = GetArrayCell(g_hModels, iModel);
		decl String:sModelPath[PLATFORM_MAX_PATH];
		GetArrayString(hModel, MODELS_MDLFILE, sModelPath, sizeof(sModelPath));
		if(strlen(sModelPath) > 0)
		{
			SetEntityModel(client, sModelPath);
		}
	}
	
	
	return Plugin_Stop;
}

/**
 * Event Handler
 */

public Action:Event_OnWeaponFire(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	decl String:sWeapon[32];
	GetEventString(event, "weapon", sWeapon, sizeof(sWeapon));
	
	if(StrEqual(sWeapon, "hegrenade"))
	{
		if(g_iPlayerGrenade[client][GRENADE_HE] != 0)
			g_iPlayerGrenade[client][GRENADE_HE]--;
		
		if(g_iPlayerGrenade[client][GRENADE_HE] > 0)
		{
			GivePlayerItem(client, "weapon_hegrenade");
			CPrintToChat(client, "%s%t", PREFIX, "HE left", g_iPlayerGrenade[client][GRENADE_HE]);
		}
	}
	else if(StrEqual(sWeapon, "flashbang"))
	{
		if(g_iPlayerGrenade[client][GRENADE_FLASH] != 0)
			g_iPlayerGrenade[client][GRENADE_FLASH]--;
		
		if(g_iPlayerGrenade[client][GRENADE_FLASH] > 0)
		{
			GivePlayerItem(client, "weapon_flashbang");
			CPrintToChat(client, "%s%t", PREFIX, "Flashbangs left", g_iPlayerGrenade[client][GRENADE_FLASH]);
		}
	}
	else if(StrEqual(sWeapon, "smokegrenade"))
	{
		if(g_iPlayerGrenade[client][GRENADE_SMOKE] != 0)
			g_iPlayerGrenade[client][GRENADE_SMOKE]--;
		
		if(g_iPlayerGrenade[client][GRENADE_SMOKE] > 0)
		{
			GivePlayerItem(client, "weapon_smokegrenade");
			CPrintToChat(client, "%s%t", PREFIX, "Smokes left", g_iPlayerGrenade[client][GRENADE_SMOKE]);
		}
	}
}

/**
 * Config Parsing
 */

ParseClassConfig()
{
	// Close old class arrays
	new iSize = GetArraySize(g_hClasses);
	for(new i=0;i<iSize;i++)
	{
		CloseClassArray(i);
	}
	ClearArray(g_hClasses);
	
	new String:sFile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFile, sizeof(sFile), "configs/smconquest_classes.cfg");
	
	if(!FileExists(sFile))
		return;
	
	g_ConfigSection = State_None;
	
	new Handle:hSMC = SMC_CreateParser();
	SMC_SetReaders(hSMC, Config_OnNewSection, Config_OnKeyValue, Config_OnEndSection);
	SMC_SetParseEnd(hSMC, Config_OnParseEnd);
	
	new iLine, iColumn;
	new SMCError:smcResult = SMC_ParseFile(hSMC, sFile, iLine, iColumn);
	CloseHandle(hSMC);
	
	if(smcResult != SMCError_Okay)
	{
		decl String:sError[128];
		SMC_GetErrorString(smcResult, sError, sizeof(sError));
		LogError("Error parsing class config: %s on line %d, col %d of %s", sError, iLine, iColumn, sFile);
		
		// Clear the halfway parsed classes
		iSize = GetArraySize(g_hClasses);
		for(new i=0;i<iSize;i++)
		{
			CloseClassArray(i);
		}
		ClearArray(g_hClasses);
	}
}

public SMCResult:Config_OnNewSection(Handle:parser, const String:section[], bool:quotes)
{
	switch(g_ConfigSection)
	{
		// A new weapon 
		case State_Class:
		{
			new Handle:hClass = GetArrayCell(g_hClasses, g_iCurrentClassIndex);
			new Handle:hWeaponSets = GetArrayCell(hClass, CLASS_WEAPONSETS);
			new Handle:hWeapons = CreateArray(ByteCountToCells(128));
			
			ResizeArray(hWeapons, WEAPONSET_NUMOPTIONS);
			
			// First value is the weapon set name
			SetArrayString(hWeapons, WEAPONSET_NAME, section);
			
			// Set the price for this weaponset
			SetArrayCell(hWeapons, WEAPONSET_PRICE, 0);
			
			// Second is the weapon list
			new Handle:hWeaponList = CreateArray(ByteCountToCells(64));
			SetArrayCell(hWeapons, WEAPONSET_WEAPONLIST, hWeaponList);
			
			// Set the default admin_flags
			SetArrayCell(hWeapons, WEAPONSET_ADMFLAGS, 0);
			
			g_iCurrentWeaponSetIndex = PushArrayCell(hWeaponSets, hWeapons);
			g_ConfigSection = State_WeaponSet;
		}
		// A new class in the file
		case State_Root:
		{
			new Handle:hClass = CreateArray(ByteCountToCells(128));
			// Set the array size beforehand, since the options may be in different order in the file -> no PushArray.
			ResizeArray(hClass, CLASS_NUMOPTIONS);
			// Save the class name
			SetArrayString(hClass, CLASS_NAME, section);
			
			// Set default values
			SetArrayCell(hClass, CLASS_DEFAULT, 0);
			SetArrayCell(hClass, CLASS_TEAM, 0);
			SetArrayCell(hClass, CLASS_LIMIT, 0);
			SetArrayCell(hClass, CLASS_MODEL, -1);
			SetArrayCell(hClass, CLASS_ADMFLAGS, 0);
			
			// Create the weaponset array
			new Handle:hWeaponSets = CreateArray();
			SetArrayCell(hClass, CLASS_WEAPONSETS, hWeaponSets);
			g_iCurrentClassIndex = PushArrayCell(g_hClasses, hClass);
			g_ConfigSection = State_Class;
		}
		case State_None:
		{
			g_ConfigSection = State_Root;
		}
	}
	return SMCParse_Continue;
}

public SMCResult:Config_OnKeyValue(Handle:smc, const String:key[], const String:value[], bool:key_quotes, bool:value_quotes)
{
	if(!key[0])
		return SMCParse_Continue;
	
	new Handle:hClass = GetArrayCell(g_hClasses, g_iCurrentClassIndex);
	
	new iBuffer;
	switch(g_ConfigSection)
	{
		// Parse basic class info
		case State_Class:
		{
			if(StrEqual(key, "default", false))
			{
				iBuffer = StringToInt(value);
				if(iBuffer < 0 || iBuffer > 1)
				{
					decl String:sBuffer[64];
					GetArrayString(hClass, CLASS_NAME, sBuffer, sizeof(sBuffer));
					SetFailState("Error parsing classes. Bad value for \"default\" of \"%s\". Has to be 0 or 1.", sBuffer);
				}
				SetArrayCell(hClass, CLASS_DEFAULT, iBuffer);
				SetArrayCell(hClass, CLASS_TEAM, 0);
			}
			else if(StrEqual(key, "team", false))
			{
				iBuffer = StringToInt(value);
				if(iBuffer != 0 && (iBuffer < 2 || iBuffer > 3))
				{
					decl String:sBuffer[64];
					GetArrayString(hClass, CLASS_NAME, sBuffer, sizeof(sBuffer));
					SetFailState("Error parsing classes. Bad value for \"team\" of \"%s\". Has to be 0 = both, 2 = T or 3 = CT.", sBuffer);
				}
				
				if(GetArrayCell(hClass, CLASS_DEFAULT) == 1)
					iBuffer = 0;
				
				SetArrayCell(hClass, CLASS_TEAM, iBuffer);
			}
			else if(StrEqual(key, "limit", false))
			{
				iBuffer = StringToInt(value);
				if(iBuffer < 1)
				{
					decl String:sBuffer[64];
					GetArrayString(hClass, CLASS_NAME, sBuffer, sizeof(sBuffer));
					SetFailState("Error parsing classes. The limit of \"%s\" has to be greater than 0.", sBuffer);
				}
				SetArrayCell(hClass, CLASS_LIMIT, iBuffer);
			}
			else if(StrEqual(key, "model", false))
			{
				// A model set?
				if(strlen(value) > 0)
				{
					new iModel = -1;
					// Is there a model configured with this section name?
					new Handle:hModel;
					new iSize = GetArraySize(g_hModels);
					decl String:sBuffer[64];
					for(new i=0;i<iSize;i++)
					{
						hModel = GetArrayCell(g_hModels, i);
						GetArrayString(hModel, MODELS_ALIAS, sBuffer, sizeof(sBuffer));
						
						// This class is going to use this model
						// Save the array index
						if(StrEqual(sBuffer, value, false))
						{
							iModel = i;
							break;
						}
					}
					
					// The model isn't configured?
					if(iModel == -1)
					{
						GetArrayString(hClass, CLASS_NAME, sBuffer, sizeof(sBuffer));
						SetFailState("Error parsing classes. The model \"%s\" wasn't found for class \"%s\".", value, sBuffer);
					}
					
					// Save the array index.
					SetArrayCell(hClass, CLASS_MODEL, iModel);
				}
			}
			// This class is restricted to some admins?
			else if(StrEqual(key, "admin_flags", false))
			{
				// http://wiki.alliedmods.net/Adding_Admins_%28SourceMod%29#Levels
				if(strlen(value) > 0)
				{
					// Convert the flags to bits
					iBuffer = ReadFlagString(value);
					if(iBuffer > 0)
					{
						// Store the ADMFLAG_ bits to restrict access lateron
						SetArrayCell(hClass, CLASS_ADMFLAGS, iBuffer);
					}
				}
			}
		}
		case State_WeaponSet:
		{
			new Handle:hWeaponSets = GetArrayCell(hClass, CLASS_WEAPONSETS);
			new Handle:hWeapons = GetArrayCell(hWeaponSets, g_iCurrentWeaponSetIndex);
			new Handle:hWeaponList = GetArrayCell(hWeapons, WEAPONSET_WEAPONLIST);
			
			// We have to handle the speed value seperately, since it's a double
			new Float:fBuffer;
			if(StrEqual(key, "speed", false))
			{
				fBuffer = StringToFloat(value);
				if(fBuffer <= 0.0)
				{
					SetFailState("Error parsing classes. The speed has to be greater than 0.");
				}
				
				// Store the speed value
				PushArrayString(hWeaponList, key);
				PushArrayCell(hWeaponList, fBuffer);
			}
			// A price option is set?
			else if(StrEqual(key, "price", false))
			{
				iBuffer = StringToInt(value);
				if(iBuffer < 0)
				{
					decl String:sBuffer[64];
					GetArrayString(hWeapons, WEAPONSET_NAME, sBuffer, sizeof(sBuffer));
					SetFailState("Error parsing classes. The price of weaponset \"%s\" has to be at least 0.", sBuffer);
				}
				SetArrayCell(hWeapons, WEAPONSET_PRICE, iBuffer);
			}
			else if(StrEqual(key, "admin_flags", false))
			{
				// http://wiki.alliedmods.net/Adding_Admins_%28SourceMod%29#Levels
				if(strlen(value) > 0)
				{
					// Convert the flags to bits
					iBuffer = ReadFlagString(value);
					if(iBuffer > 0)
					{
						// Store the ADMFLAG_ bits to restrict access lateron
						SetArrayCell(hWeapons, WEAPONSET_ADMFLAGS, iBuffer);
					}
				}
			}
			else
			{
				iBuffer = StringToInt(value);
				if(iBuffer < 1)
				{
					SetFailState("Error parsing classes. The ammo of \"%s\" has to be greater than 0.", key);
				}
				
				// The weapon name
				PushArrayString(hWeaponList, key);
				// How many clips for that weapon?
				PushArrayCell(hWeaponList, iBuffer);
			}
		}
	}
	
	return SMCParse_Continue;
}

public SMCResult:Config_OnEndSection(Handle:parser)
{
	switch(g_ConfigSection)
	{
		// Finished parsing that class
		case State_Class:
		{
			g_iCurrentClassIndex = -1;
			g_ConfigSection = State_Root;
		}
		case State_WeaponSet:
		{
			g_iCurrentWeaponSetIndex = -1;
			g_ConfigSection = State_Class;
		}
	}
	
	return SMCParse_Continue;
}

public Config_OnParseEnd(Handle:parser, bool:halted, bool:failed) {
	if (failed)
		SetFailState("Error during parse of the classes config.");
	
	// Check for bad default settings.
	new iSize = GetArraySize(g_hClasses);
	new Handle:hClass, iClassTeam, iDefault[3] = {-1,...};
	for(new i=0;i<iSize;i++)
	{
		hClass = GetArrayCell(g_hClasses, i);
		iClassTeam = GetArrayCell(hClass, CLASS_TEAM);
		
		// This class wants to be the default
		if(GetArrayCell(hClass, CLASS_DEFAULT) == 1)
		{
			// The default class can't be restricted to admins
			if(GetArrayCell(hClass, CLASS_ADMFLAGS) > 0)
				SetFailState("Error parsing classes. The default class can't be restricted to admins with a certain flag!");
			
			// No team set, so global default
			if(iClassTeam == 0)
			{
				// don't allow any other default
				if(iDefault[0] != -1 || iDefault[1] != -1 || iDefault[2] != -1)
					SetFailState("Error parsing classes. There are dublicate \"default\" settings! Only set one global default or one default per team.");
				iDefault[0] = i;
			}
			else
			{
				// don't allow global default
				if(iDefault[0] != -1 || iDefault[iClassTeam-1] != -1)
					SetFailState("Error parsing classes. There are dublicate \"default\" settings! Only set one global default or one default per team.");
				iDefault[iClassTeam-1] = i;
			}
		}
	}
	
	// One team has a default one
	if(iDefault[0] == -1 && (iDefault[1] == -1 || iDefault[2] == -1))
		SetFailState("Error parsing classes. You set a default setting for one team, but no for the other.");
}

/** 
 * Model Config Parsing
 */

ParseModelConfig()
{
	// Close old model arrays
	new iSize = GetArraySize(g_hModels);
	new Handle:hModel;
	for(new i=0;i<iSize;i++)
	{
		hModel = GetArrayCell(g_hModels, i);
		CloseHandle(hModel);
	}
	ClearArray(g_hModels);
	
	new String:sFile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFile, sizeof(sFile), "configs/smconquest_models.cfg");
	
	if(!FileExists(sFile))
		return;
	
	g_ModelConfigSection = State_None;
	g_bDontDownloadCurrentModel = false;
	g_iCurrentModelIndex = -1;
	
	new Handle:hSMC = SMC_CreateParser();
	SMC_SetReaders(hSMC, ModelConfig_OnNewSection, ModelConfig_OnKeyValue, ModelConfig_OnEndSection);
	SMC_SetParseEnd(hSMC, ModelConfig_OnParseEnd);
	
	new iLine, iColumn;
	new SMCError:smcResult = SMC_ParseFile(hSMC, sFile, iLine, iColumn);
	CloseHandle(hSMC);
	
	if(smcResult != SMCError_Okay)
	{
		decl String:sError[128];
		SMC_GetErrorString(smcResult, sError, sizeof(sError));
		LogError("Error parsing model config: %s on line %d, col %d of %s", sError, iLine, iColumn, sFile);
		
		// Clear the halfway parsed classes
		iSize = GetArraySize(g_hModels);
		for(new i=0;i<iSize;i++)
		{
			hModel = GetArrayCell(g_hModels, i);
			CloseHandle(hModel);
		}
		ClearArray(g_hModels);
	}
}

public SMCResult:ModelConfig_OnNewSection(Handle:parser, const String:section[], bool:quotes)
{
	switch(g_ModelConfigSection)
	{
		// New model file list
		case State_Root:
		{
			new Handle:hModel = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH)); // Duh, that's a large array..
			
			// Save the model alias
			PushArrayString(hModel, section);
			PushArrayString(hModel, ""); // Dummy mdl path
			
			g_iCurrentModelIndex = PushArrayCell(g_hModels, hModel);
			g_ModelConfigSection = State_Files;
		}
		case State_None:
		{
			g_ModelConfigSection = State_Root;
		}
	}
	return SMCParse_Continue;
}

public SMCResult:ModelConfig_OnKeyValue(Handle:smc, const String:key[], const String:value[], bool:key_quotes, bool:value_quotes)
{
	if(!key[0])
		return SMCParse_Continue;
	
	new Handle:hModel = GetArrayCell(g_hModels, g_iCurrentModelIndex);
	
	if(g_ModelConfigSection == State_Files)
	{
		// Some other plugin is already downloading that model or it's a default one?
		if(StrEqual(key, "no_download", false) && StringToInt(value) == 1)
		{
			g_bDontDownloadCurrentModel = true;
		}
		// This is a file to download
		else if(StrEqual(key, "file", false))
		{
			// Bad file? User has to fix the file!
			if(!FileExists(value))
				return SMCParse_HaltFail;
			
			// Have clients download the file
			if(!g_bDontDownloadCurrentModel)
				AddFileToDownloadsTable(value);
			
			// Save the model path and precache the model
			if(StrEqual(value[strlen(value)-4], ".mdl", false))
			{
				PrecacheModel(value, true);
				SetArrayString(hModel, MODELS_MDLFILE, value);
			}
		}
	}
	
	return SMCParse_Continue;
}

public SMCResult:ModelConfig_OnEndSection(Handle:parser)
{
	// Finished parsing that model
	if(g_ModelConfigSection == State_Files)
	{
		// Check if there's a .mdl file somewhere
		decl String:sBuffer[PLATFORM_MAX_PATH];
		new Handle:hModel = GetArrayCell(g_hModels, g_iCurrentModelIndex);
		GetArrayString(hModel, MODELS_MDLFILE, sBuffer, sizeof(sBuffer));
		if(strlen(sBuffer) == 0)
		{
			GetArrayString(hModel, MODELS_ALIAS, sBuffer, sizeof(sBuffer));
			SetFailState("Error parsing models. Can't find a .mdl file for model \"%s\".", sBuffer);
		}
		
		g_iCurrentModelIndex = -1;
		g_bDontDownloadCurrentModel = false;
		g_ModelConfigSection = State_Root;
	}
	
	return SMCParse_Continue;
}

public ModelConfig_OnParseEnd(Handle:parser, bool:halted, bool:failed) {
	if (failed)
		SetFailState("Error during parse of the models config.");
}

CloseClassArray(iClass)
{
	new Handle:hClass = GetArrayCell(g_hClasses, iClass);
	new Handle:hWeaponSet = GetArrayCell(hClass, CLASS_WEAPONSETS);
	new iSize2 = GetArraySize(hWeaponSet);
	new Handle:hWeapon, Handle:hWeaponList;
	for(new ws=0;ws<iSize2;ws++)
	{
		hWeapon = GetArrayCell(hWeaponSet, ws);
		hWeaponList = GetArrayCell(hWeapon, WEAPONSET_WEAPONLIST);
		CloseHandle(hWeaponList);
		CloseHandle(hWeapon);
	}
	CloseHandle(hWeaponSet);
	CloseHandle(hClass);
}
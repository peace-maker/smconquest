/*
 * SM:Conquest
 * Counter-Strike Source gameplay modification
 * 
 * This plugin adds flags to any map which every team has to conquer
 * by standing near to it for an specified amount of time.
 * The team which controls all flags first wins the round.
 * 
 * Credits:
 * L.Duke: The original idea, model and sounds were taken from his abandoned MM:S plugin "Conquest". Hugh thanks!
 * Rediem: Recreated the flag materials, win overlays and font. Adjusted the default config.
 * 
 * Changelog:
 * 1.0 (06.04.2011): Initial release
 * 1.1 (20.04.2011): See changelog.txt
 * 1.2 (20.04.2011): Small hotfixes around speed and health class settings and flag adding
 * 1.3 (01.05.2011): See changelog.txt
 * 1.3.1 (28.07.2011): See changelog.txt
 *
 * Thread: https://forums.alliedmods.net/showthread.php?t=154354
 * visit http://www.wcfan.de/
 */
#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <clientprefs>
#include <sdkhooks>
#include <cstrike>
#include <colors>
#include <smlib>
#include <loghelper>

#define PLUGIN_VERSION "1.3.1"

#define PREFIX "{olive}SM:Conquest {default}>{green} "

#define PRIMARYAMMO_MODEL "models/items/boxmrounds.mdl"
#define SECONDARYAMMO_MODEL "models/items/boxsrounds.mdl"
#define AMMO_SOUND "items/ammo_pickup.wav"

new bool:g_bRoundEnded = false;
new Handle:g_hStartSound = INVALID_HANDLE;

// ConVar handles
new Handle:g_hCVRespawn;
new Handle:g_hCVRespawnTime;
new Handle:g_hCVSpawnProtection;
new Handle:g_hCVPreventWeaponDrop;
new Handle:g_hCVDropAmmo;
new Handle:g_hCVPrimaryAmmoAmount;
new Handle:g_hCVSecondaryAmmoAmount;
new Handle:g_hCVDisableBuyzones;
new Handle:g_hCVUseBuymenu;
new Handle:g_hCVInBuyzone;
new Handle:g_hCVUseClasses;
new Handle:g_hCVShowWinOverlays;
new Handle:g_hCVEnableContest;
new Handle:g_hCVHandicap;
new Handle:g_hCVCaptureScore;
new Handle:g_hCVTeamScore;
new Handle:g_hCVRemoveObjectives;
new Handle:g_hCVCaptureMoney;
new Handle:g_hCVRemoveDroppedWeapons;
new Handle:g_hCVEnforceTimelimit;
new Handle:g_hCVFadeOnConquer;
new Handle:g_hCVShowOnRadar;
new Handle:g_hCVStripLosers;
new Handle:g_hCVAmmoLifetime;
new Handle:g_hCVAdvertiseCommands;
new Handle:g_hCVStripBots;

// Tag
new Handle:g_hSVTags; 

// Respawning and spawnprotection
new Handle:g_hRespawnPlayer[MAXPLAYERS+2] = {INVALID_HANDLE,...};
new Handle:g_hRemoveSpawnProtection[MAXPLAYERS+2] = {INVALID_HANDLE,...};

// Enforce map timelimit
new Handle:g_hTimeLimitEnforcer = INVALID_HANDLE;
new g_iMapStartTime = 0;
new g_iTimeLimit = 0;

// Weapondrop ammo regive to the correct ammotype
new g_iPlayerActiveSlot[MAXPLAYERS+2] = {-1,...};
// Remove dropped weapons every 20 seconds
new Handle:g_hRemoveWeapons = INVALID_HANDLE;

// CCSPlayer::m_iAccount offset
new g_iAccount = -1;

new bool:g_bIsCSGO = false;

new Handle:g_hIgnoreRoundWinCond = INVALID_HANDLE;
new g_iOldIgnoreRoundWinCond;

// Store the sound files configured in smconquest_sounds.cfg
#define CSOUND_REDFLAG_CAPTURED 0
#define CSOUND_BLUEFLAG_CAPTURED 1
#define CSOUND_REDTEAM_WIN 2
#define CSOUND_BLUETEAM_WIN 3
#define CSOUND_ROUNDSTART 4
#define CSOUND_FLAG_AMBIENCE 5
#define CSOUND_REDTEAM_STARTS_CONQUERING 6
#define CSOUND_BLUETEAM_STARTS_CONQUERING 7

#define CSOUND_NUMSOUNDS 8
new String:g_sSoundFiles[CSOUND_NUMSOUNDS][PLATFORM_MAX_PATH];

#include "smconquest_clientpref.sp"
#include "smconquest_flags.sp"
#include "smconquest_classes.sp"
#include "smconquest_buymenu.sp"
#include "smconquest_flagadmin.sp"

public Plugin:myinfo = 
{
	name = "SM:Conquest",
	author = "Jannik 'Peace-Maker' Hartung",
	description = "Conquer areas on maps to win",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public OnPluginStart()
{
	new Handle:hVersion = CreateConVar("sm_conquest_version", PLUGIN_VERSION, "SM:Conquest version", FCVAR_PLUGIN|FCVAR_NOTIFY|FCVAR_REPLICATED|FCVAR_DONTRECORD);
	if(hVersion != INVALID_HANDLE)
		SetConVarString(hVersion, PLUGIN_VERSION);
	
	g_hCVRespawn = CreateConVar("sm_conquest_respawn", "1", "Should a player respawn after x seconds?", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hCVRespawnTime = CreateConVar("sm_conquest_respawntime", "5", "How long should the player be dead until getting respawned?", FCVAR_PLUGIN, true, 1.0);
	g_hCVSpawnProtection = CreateConVar("sm_conquest_spawnprotection", "5", "How long should the player be invincible after spawn?", FCVAR_PLUGIN, true, 0.0);
	g_hCVPreventWeaponDrop = CreateConVar("sm_conquest_noweapondrop", "1", "Should players be disallowed to drop their weapons and remove them on death?", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hCVDropAmmo = CreateConVar("sm_conquest_dropammo", "1", "Should a dead player drop some ammo depending of his weapon?", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hCVPrimaryAmmoAmount = CreateConVar("sm_conquest_droppedprimaryammo", "10", "How much ammo should a primary ammo pack give?", FCVAR_PLUGIN, true, 0.0);
	g_hCVSecondaryAmmoAmount = CreateConVar("sm_conquest_droppedsecondaryammo", "10", "How much ammo should a secondary ammo pack give?", FCVAR_PLUGIN, true, 0.0);
	g_hCVDisableBuyzones = CreateConVar("sm_conquest_disablebuyzones", "1", "Disable the buyzones on map to stop the standard buying?", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hCVUseBuymenu = CreateConVar("sm_conquest_enablebuymenu", "1", "Use the custom buymenu?", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hCVInBuyzone = CreateConVar("sm_conquest_inbuyzone", "1", "Only allow buying with the custom menu in buyzones?", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hCVUseClasses = CreateConVar("sm_conquest_enableclasses", "1", "Enable the player class system?", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hCVShowWinOverlays = CreateConVar("sm_conquest_showwinoverlays", "1", "Should we display an overlay with the winning team logo? Don't enable this on runtime - only in config. (downloading)", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hCVEnableContest = CreateConVar("sm_conquest_enablecontest", "1", "Should enemies interrupt the capture process when entering a zone?", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hCVHandicap = CreateConVar("sm_conquest_handicap", "1", "Should we decrease the amount of required players to the team count, if there are less players in the team than required?", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hCVCaptureScore = CreateConVar("sm_conquest_capturescore", "1", "How many frags should a player receive when conquering a flag?", FCVAR_PLUGIN, true, 0.0);
	g_hCVTeamScore = CreateConVar("sm_conquest_teamscore", "1", "How many points should a team earn when conquering all flags?", FCVAR_PLUGIN, true, 0.0);
	g_hCVRemoveObjectives = CreateConVar("sm_conquest_removeobjectives", "1", "Remove all bomb/hostage related stuff to prevent round end?", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hCVCaptureMoney = CreateConVar("sm_conquest_capturemoney", "500", "How much money should all players earn for capturing a flag?", FCVAR_PLUGIN, true, 0.0);
	g_hCVRemoveDroppedWeapons = CreateConVar("sm_conquest_removedroppedweapons", "20", "How often should we remove dropped weapons in x seconds interval?", FCVAR_PLUGIN, true, 0.0);
	g_hCVEnforceTimelimit = CreateConVar("sm_conquest_enforcetimelimit", "1", "End the game when the mp_timelimit is over - even midround?", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hCVFadeOnConquer = CreateConVar("sm_conquest_fadeonconquer", "1", "Fade the screen in the flag color for all players on conquer?", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hCVShowOnRadar = CreateConVar("sm_conquest_showonradar", "1", "Should enemies near an conquered flag appear on the radar of the team controlling the flag?", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hCVStripLosers = CreateConVar("sm_conquest_striplosers", "0", "Strip the losing team to knife on round end?", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hCVAmmoLifetime = CreateConVar("sm_conquest_ammolifetime", "60", "Remove dropped ammo packs after x seconds?", FCVAR_PLUGIN, true, 0.0);
	g_hCVAdvertiseCommands = CreateConVar("sm_conquest_advertisecommands", "1", "Advertise the !class and !buy commands in chat?", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hCVStripBots = CreateConVar("sm_conquest_stripbots", "1", "Strip bots to knife and set to default class on spawn?", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	
	g_hSVTags = FindConVar("sv_tags");
	
	LoadTranslations("common.phrases");
	LoadTranslations("smconquest.phrases");
	
	// Flags
	g_hFlags = CreateArray();
	g_hPlayersInZone = CreateArray();
	
	// Classes
	g_hClasses = CreateArray();
	
	// Models
	g_hModels = CreateArray();
	
	// Buymenu
	g_hBuyItemMenuArray = CreateArray();
	
	// Are we running on csgo?
	g_bIsCSGO = GuessSDKVersion() == SOURCE_SDK_CSGO;
	
	g_iAccount = FindSendPropOffs("CCSPlayer", "m_iAccount");
	if(g_iAccount == -1)
	{
		SetFailState("Can't find CCSPlayer::m_iAccount offset.");
	}
	
	if(g_bIsCSGO)
	{
		g_iSpottedOffset = FindSendPropOffs("CCSPlayer", "m_bSpotted");
		if(g_iSpottedOffset == -1)
		{
			SetFailState("Can't find CCSPlayer::m_bSpotted offset.");
		}
	}
	else
	{
		g_iPlayerSpottedOffset = FindSendPropOffs("CCSPlayerResource", "m_bPlayerSpotted");
		if(g_iPlayerSpottedOffset == -1)
		{
			SetFailState("Can't find CCSPlayerResource::m_bPlayerSpotted offset.");
		}
	}
	
	// Hook game events
	HookEvent("round_end", Event_OnRoundEnd);
	HookEvent("round_start", Event_OnRoundStart);
	HookEvent("player_spawn", Event_OnPlayerSpawn);
	HookEvent("player_death", Event_OnPlayerDeath);
	HookEvent("player_team", Event_OnPlayerTeam);
	HookEvent("weapon_fire", Event_OnWeaponFire);
	
	// Register public commands
	RegConsoleCmd("sm_class", Command_ShowClassMenu, "Displays the class selection menu");
	RegConsoleCmd("sm_buy", Command_ShowBuyMenu, "Displays the item buy menu");
	
	// Register admin commands
	RegAdminCmd("sm_spawnammo", Command_SpawnAmmoPack, ADMFLAG_SLAY, "Spawns an ammo pack where you aim. Usage: sm_spawnammo <p|s>");
	RegAdminCmd("sm_flagadmin", Command_FlagAdmin, ADMFLAG_CONFIG, "Opens the flag administration menu");
	
	// Hook chat for flag admin
	RegConsoleCmd("say", Command_Say);
	RegConsoleCmd("say_team", Command_Say);
	
	// Init Clientprefs
	CreateClientCookies();
	
	// Force the timelimit, even if the round never ends
	new Handle:hTimeLimit = FindConVar("mp_timelimit");
	HookConVarChange(hTimeLimit, ConVar_TimeLimitChanged);
	g_iTimeLimit = GetConVarInt(hTimeLimit)*60;
	
	g_hIgnoreRoundWinCond = FindConVar("mp_ignore_round_win_conditions");
	if(g_hIgnoreRoundWinCond != INVALID_HANDLE)
		g_iOldIgnoreRoundWinCond = GetConVarInt(g_hIgnoreRoundWinCond);
	
	AutoExecConfig(true, "plugin.smconquest");
	
	for(new i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i))
			OnClientPutInServer(i);
	}
}

public OnPluginEnd()
{
	MyRemoveServerTag("conquest");
	if(g_hIgnoreRoundWinCond != INVALID_HANDLE)
		SetConVarInt(g_hIgnoreRoundWinCond, g_iOldIgnoreRoundWinCond);
}

// Check if we are lateloaded (not with serverstart)
public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	RegPluginLibrary("smconquest");
	
	return APLRes_Success;
}

/** 
 * Forwards
 */

public OnMapStart()
{
	// Flag model
	AddFileToDownloadsTable("models/conquest/flagv2/flag.mdl");
	AddFileToDownloadsTable("models/conquest/flagv2/flag.dx80.vtx");
	AddFileToDownloadsTable("models/conquest/flagv2/flag.dx90.vtx");
	AddFileToDownloadsTable("models/conquest/flagv2/flag.phy");
	AddFileToDownloadsTable("models/conquest/flagv2/flag.sw.vtx");
	AddFileToDownloadsTable("models/conquest/flagv2/flag.vvd");
	AddFileToDownloadsTable("models/conquest/flagv2/flag.xbox.vtx");
	
	AddFileToDownloadsTable("materials/models/conquest/flagv2/ct_flag.vmt");
	AddFileToDownloadsTable("materials/models/conquest/flagv2/ct_flag.vtf");
	AddFileToDownloadsTable("materials/models/conquest/flagv2/neutralflag.vmt");
	AddFileToDownloadsTable("materials/models/conquest/flagv2/neutralflag.vtf");
	AddFileToDownloadsTable("materials/models/conquest/flagv2/t_flag.vmt");
	AddFileToDownloadsTable("materials/models/conquest/flagv2/t_flag.vtf");
	
	// Winning overlays
	if(GetConVarBool(g_hCVShowWinOverlays))
	{
		AddFileToDownloadsTable("materials/conquest/v1/blue_wins.vmt");
		AddFileToDownloadsTable("materials/conquest/v1/blue_wins.vtf");
		AddFileToDownloadsTable("materials/conquest/v1/red_wins.vmt");
		AddFileToDownloadsTable("materials/conquest/v1/red_wins.vtf");
	}

	// Game sounds
	// Load from smconquest_sounds.cfg
	new String:sFile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFile, sizeof(sFile), "configs/smconquest_sounds.cfg");
	
	// Clear the sounds as a base
	for(new i=0;i<CSOUND_NUMSOUNDS;i++)
		Format(g_sSoundFiles[i], PLATFORM_MAX_PATH-1, "");
	
	// The file exists? Sounds are disabled if not.
	if(FileExists(sFile))
	{
		new Handle:hKV = CreateKeyValues("ConquestSounds");
		decl String:sSection[64], String:sBuffer[PLATFORM_MAX_PATH];
		FileToKeyValues(hKV, sFile);
		if(KvGotoFirstSubKey(hKV))
		{
			do
			{
				// Is there actually a sound key?
				KvGetString(hKV, "sound", sBuffer, sizeof(sBuffer), "-1");
				if(!StrEqual(sBuffer, "-1"))
				{
					// It's in the sound folder
					Format(sBuffer, sizeof(sBuffer), "sound/%s", sBuffer);
					
					// Check if we want to download that file or if it's already packed with CS:S?
					KvGetString(hKV, "is_game_sound", sSection, sizeof(sSection), "0");
					if(!StrEqual(sSection, "1"))
					{
						// Does this sound exist?
						if(!FileExists(sBuffer))
						{
							LogError("Can't find sound \"%s\". Check your smconquest_sounds.cfg.", sBuffer);
							continue;
						}
						
						// Download that sound
						AddFileToDownloadsTable(sBuffer);
					}
					
					// Precache it
					PrecacheSound(sBuffer[6], true);
					
					// Which sound is set?
					KvGetSectionName(hKV, sSection, sizeof(sSection));
					if(StrEqual(sSection, "redteam_starts_conquering"))
					{
						strcopy(g_sSoundFiles[CSOUND_REDTEAM_STARTS_CONQUERING], PLATFORM_MAX_PATH-1, sBuffer[6]);
					}
					else if(StrEqual(sSection, "blueteam_starts_conquering"))
					{
						strcopy(g_sSoundFiles[CSOUND_BLUETEAM_STARTS_CONQUERING], PLATFORM_MAX_PATH-1, sBuffer[6]);
					}
					else if(StrEqual(sSection, "redflag_captured"))
					{
						strcopy(g_sSoundFiles[CSOUND_REDFLAG_CAPTURED], PLATFORM_MAX_PATH-1, sBuffer[6]);
					}
					else if(StrEqual(sSection, "blueflag_captured"))
					{
						strcopy(g_sSoundFiles[CSOUND_BLUEFLAG_CAPTURED], PLATFORM_MAX_PATH-1, sBuffer[6]);
					}
					else if(StrEqual(sSection, "redteam_win"))
					{
						strcopy(g_sSoundFiles[CSOUND_REDTEAM_WIN], PLATFORM_MAX_PATH-1, sBuffer[6]);
					}
					else if(StrEqual(sSection, "blueteam_win"))
					{
						strcopy(g_sSoundFiles[CSOUND_BLUETEAM_WIN], PLATFORM_MAX_PATH-1, sBuffer[6]);
					}
					else if(StrEqual(sSection, "roundstart"))
					{
						strcopy(g_sSoundFiles[CSOUND_ROUNDSTART], PLATFORM_MAX_PATH-1, sBuffer[6]);
					}
					else if(StrEqual(sSection, "flag_ambience"))
					{
						strcopy(g_sSoundFiles[CSOUND_FLAG_AMBIENCE], PLATFORM_MAX_PATH-1, sBuffer[6]);
					}
				}
			} while(KvGotoNextKey(hKV));
		}
		
		CloseHandle(hKV);
	}
	
	// Have to precache radio sounds to block them
	PrecacheSound("radio/ctwin.wav", false);
	PrecacheSound("radio/terwin.wav", false);
	
	PrecacheModel("models/conquest/flagv2/flag.mdl", true);
	if(GetConVarBool(g_hCVShowWinOverlays))
	{
		PrecacheDecal("conquest/v1/blue_wins.vmt", true);
		PrecacheDecal("conquest/v1/red_wins.vmt", true);
	}
	
	PrecacheModel(PRIMARYAMMO_MODEL, true);
	PrecacheModel(SECONDARYAMMO_MODEL, true);
	PrecacheSound(AMMO_SOUND, true);
	
	g_iLaserMaterial = PrecacheModel("materials/sprites/laser.vmt", true);
	g_iHaloMaterial = PrecacheModel("materials/sprites/halo01.vmt", true);
	g_iGlowSprite = PrecacheModel("sprites/blueglow2.vmt", true);
	
	ParseFlagConfig();
	ParseModelConfig();
	ParseClassConfig();
	ParseBuyConfig();
	
	MyAddServerTag("conquest");
	
	// Hook the player_manager, to show people on radar
	if(!g_bIsCSGO)
	{
		new iPlayerManager = FindEntityByClassname(0, "cs_player_manager");
		SDKHook(iPlayerManager, SDKHook_ThinkPost, Hook_OnPlayerManagerThinkPost);
	}
	
	// Enforce the timelimit
	g_iMapStartTime = GetTime();
	if(GetConVarBool(g_hCVEnforceTimelimit))
		g_hTimeLimitEnforcer = CreateTimer(10.0, Timer_CheckTimeLimit, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
	
	// Show the flag status
	CreateTimer(0.5, Timer_OnUpdateStatusPanel, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
	
	// Advertise the commands
	if(GetConVarBool(g_hCVAdvertiseCommands))
		CreateTimer(300.0, Timer_OnAdvertCommands, 0, TIMER_FLAG_NO_MAPCHANGE);
}

public OnMapEnd()
{
	// Flag admin
	if(g_hDebugZoneTimer != INVALID_HANDLE)
	{
		KillTimer(g_hDebugZoneTimer);
		g_hDebugZoneTimer = INVALID_HANDLE;
	}
	
	if(g_hStartSound != INVALID_HANDLE)
	{
		KillTimer(g_hStartSound);
		g_hStartSound = INVALID_HANDLE;
	}
	
	if(g_hRemoveWeapons != INVALID_HANDLE)
	{
		KillTimer(g_hRemoveWeapons);
		g_hRemoveWeapons = INVALID_HANDLE;
	}
	
	g_iMapStartTime = 0;
	if(g_hTimeLimitEnforcer != INVALID_HANDLE)
	{
		KillTimer(g_hTimeLimitEnforcer);
		g_hTimeLimitEnforcer = INVALID_HANDLE;
	}
}

public OnConfigsExecuted()
{
	ServerCommand("sv_hudhint_sound 0");
	
	if(g_hIgnoreRoundWinCond != INVALID_HANDLE)
		SetConVarInt(g_hIgnoreRoundWinCond, 1);
	if(GetConVarBool(g_hCVInBuyzone))
		ServerCommand("mp_buytime 99999");
}

public OnClientPutInServer(client)
{
	SDKHook(client, SDKHook_WeaponSwitch, Hook_OnWeaponSwitch);
	SDKHook(client, SDKHook_PostThinkPost, Hook_OnPostThinkPost);
	if(g_bIsCSGO)
		SDKHook(client, SDKHook_ThinkPost, Hook_OnThinkPost);
}

public OnClientDisconnect(client)
{
	// remove him from zone touch arrays, if he has been in a zone
	RemovePlayerFromAllZones(client);
	
	if(g_hRespawnPlayer[client] != INVALID_HANDLE)
	{
		KillTimer(g_hRespawnPlayer[client]);
		g_hRespawnPlayer[client] = INVALID_HANDLE;
	}
	
	if(g_hRemoveSpawnProtection[client] != INVALID_HANDLE)
	{
		KillTimer(g_hRemoveSpawnProtection[client]);
		g_hRemoveSpawnProtection[client] = INVALID_HANDLE;
	}
	
	if(g_hApplyPlayerClass[client] != INVALID_HANDLE)
	{
		KillTimer(g_hApplyPlayerClass[client]);
		g_hApplyPlayerClass[client] = INVALID_HANDLE;
	}
	
	if(g_hShowTempFlagPosition[client] != INVALID_HANDLE)
	{
		KillTimer(g_hShowTempFlagPosition[client]);
		g_hShowTempFlagPosition[client] = INVALID_HANDLE;
	}
	
	if(g_hShowTempZone[client] != INVALID_HANDLE)
	{
		KillTimer(g_hShowTempZone[client]);
		g_hShowTempZone[client] = INVALID_HANDLE;
	}
	
	g_iPlayerEditsFlag[client] = -1;
	ClearVector(g_fTempFlagPosition[client]);
	ClearVector(g_fTempFlagAngle[client]);
	
	g_iPlayerEditsVector[client] = NO_POINT;
	g_bPlayerAddsFlag[client] = false;
	ClearVector(g_fTempZoneVector1[client]);
	ClearVector(g_fTempZoneVector2[client]);
	
	g_iPlayerClass[client] = -1;
	g_iPlayerWeaponSet[client] = -1;
	g_iPlayerTempClass[client] = -1;
	g_bPlayerJustJoined[client] = true;
	
	g_iPlayerActiveSlot[client] = -1;
	
	g_iPlayerGrenade[client][GRENADE_HE] = 0;
	g_iPlayerGrenade[client][GRENADE_FLASH] = 0;
	g_iPlayerGrenade[client][GRENADE_SMOKE] = 0;
	
	g_bPlayerInBuyZone[client] = false;
	g_bPlayerIsBuying[client] = false;
	
	g_bPlayerRenamesFlag[client] = false;
	g_bPlayerNamesNewFlag[client] = false;
	g_bPlayerSetsRequiredPlayers[client] = false;
	g_bPlayerSetsConquerTime[client] = false;
	
	ResetCookieCache(client);
	
	if(GetConVarBool(g_hCVDropAmmo) && IsClientInGame(client))
	{
		// Bad weapon?
		if(g_iPlayerActiveSlot[client] == -1)
			return;
		
		// Remove weapons and put an ammo box instead
		// Always drop the ammo on the ground
		new Float:fOrigin[3];
		GetClientEyePosition(client, fOrigin);
		
		fOrigin[2] += 10.0;
		
		TR_TraceRayFilter(fOrigin, Float:{90.0,0.0,0.0}, MASK_PLAYERSOLID, RayType_Infinite, TraceRayNoPlayers, client);
		if (TR_DidHit())
		{
			TR_GetEndPosition(fOrigin);
		}
		
		new bool:bPrimaryWeapon = g_iPlayerActiveSlot[client] == CS_SLOT_PRIMARY;
		
		new Float:fAngle[3];
		GetClientEyeAngles(client, fAngle);
		fAngle[0] = 0.0;
		fAngle[2] = 0.0;
		
		CreateAmmoPack(fOrigin, fAngle, bPrimaryWeapon);
	}
}

/**
 * Events
 */

public Action:Event_OnPlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new userid = GetEventInt(event, "userid");
	new client = GetClientOfUserId(userid);
	
	// Just to be sure
	RemovePlayerFromAllZones(client);
	
	// Don't do anything, if no flags for that map -> "disabled"
	if(GetArraySize(g_hFlags) == 0)
		return Plugin_Continue;
	
	// Spawnprotection
	new Float:fRespawnTime = GetConVarFloat(g_hCVSpawnProtection);
	if(fRespawnTime > 0.0)
	{
		g_hRemoveSpawnProtection[client] = CreateTimer(fRespawnTime, Timer_OnDisableSpawnprotection, userid, TIMER_FLAG_NO_MAPCHANGE);
		SetEntProp(client, Prop_Data, "m_takedamage", 0);
		SetEntityRenderMode(client, RENDER_TRANSCOLOR);
		SetEntityRenderColor(client, 0, 255, 150, 170);
	}
	
	g_iPlayerGrenade[client][GRENADE_HE] = 0;
	g_iPlayerGrenade[client][GRENADE_FLASH] = 0;
	g_iPlayerGrenade[client][GRENADE_SMOKE] = 0;
	
	if(g_hApplyPlayerClass[client] != INVALID_HANDLE)
	{
		KillTimer(g_hApplyPlayerClass[client]);
		g_hApplyPlayerClass[client] = INVALID_HANDLE;
	}
	
	// Remove any leftover progressbar, if he just spectated someone :o
	SetEntPropFloat(client, Prop_Send, "m_flProgressBarStartTime", 0.0);
	SetEntProp(client, Prop_Send, "m_iProgressBarDuration", 0);
	
	// Player class
	if(GetConVarBool(g_hCVUseClasses))
	{
		// Strip weapons
		if(GetClientTeam(client) >= CS_TEAM_T)
		{
			// Don't strip the bot, if it's disabled :)
			if(!IsFakeClient(client) || (IsFakeClient(client) && GetConVarBool(g_hCVStripBots)))
				Client_RemoveAllWeapons(client, "weapon_knife", true);
			// Set the class with a delay
			g_hApplyPlayerClass[client] = CreateTimer(0.5, Timer_ApplyPlayerClass, userid, TIMER_FLAG_NO_MAPCHANGE);
		}
	}
	
	g_bPlayerInBuyZone[client] = false;
	g_bPlayerIsBuying[client] = false;
	
	return Plugin_Continue;
}

public Action:Event_OnPlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	new userid = GetEventInt(event, "userid");
	new client = GetClientOfUserId(userid);
	
	RemovePlayerFromAllZones(client);
	
	// Don't do anything, if no flags for that map -> "disabled"
	if(GetArraySize(g_hFlags) == 0)
		return Plugin_Continue;
	
	// Respawn the player with a delay
	if(g_hRespawnPlayer[client] != INVALID_HANDLE)
	{
		KillTimer(g_hRespawnPlayer[client]);
		g_hRespawnPlayer[client] = INVALID_HANDLE;
	}
	
	// Stop giving him the weapons
	if(g_hApplyPlayerClass[client] != INVALID_HANDLE)
	{
		KillTimer(g_hApplyPlayerClass[client]);
		g_hApplyPlayerClass[client] = INVALID_HANDLE;
	}
	
	// TODO: Add option to reset to default weaponset of that class on death/teamchange
	
	if(GetConVarBool(g_hCVRespawn) && GetClientTeam(client) >= CS_TEAM_T)
	{
		new iRespawnTime = GetConVarInt(g_hCVRespawnTime);
		
		new Handle:hDataPack = CreateDataPack();
		WritePackCell(hDataPack, userid);
		WritePackCell(hDataPack, iRespawnTime);
		ResetPack(hDataPack);
		g_hRespawnPlayer[client] = CreateTimer(1.0, Timer_OnPlayerRespawnTick, hDataPack, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE|TIMER_DATA_HNDL_CLOSE);
		Client_PrintKeyHintText(client, "%t", "Respawn in x seconds", iRespawnTime);
	}
	
	// Drop ammo box
	if(GetConVarBool(g_hCVDropAmmo))
	{
		// Bad weapon?
		if(g_iPlayerActiveSlot[client] == -1)
			return Plugin_Continue;
		
		// Remove weapons and put an ammo box instead
		// Always drop the ammo on the ground
		new Float:fOrigin[3];
		GetClientEyePosition(client, fOrigin);
		
		fOrigin[2] += 10.0;
		
		TR_TraceRayFilter(fOrigin, Float:{90.0,0.0,0.0}, MASK_PLAYERSOLID, RayType_Infinite, TraceRayNoPlayers, client);
		if (TR_DidHit())
		{
			TR_GetEndPosition(fOrigin);
		}
		
		new bool:bPrimaryWeapon = g_iPlayerActiveSlot[client] == CS_SLOT_PRIMARY;
		
		new Float:fAngle[3];
		GetClientEyeAngles(client, fAngle);
		fAngle[0] = 0.0;
		fAngle[2] = 0.0;
		
		CreateAmmoPack(fOrigin, fAngle, bPrimaryWeapon);
	}
	
	return Plugin_Continue;
}

public Action:Event_OnPlayerTeam(Handle:event, const String:name[], bool:dontBroadcast)
{
	new userid = GetEventInt(event, "userid");
	new client = GetClientOfUserId(userid);
	new team = GetEventInt(event, "team");
	new oldteam = GetEventInt(event, "oldteam");
	RemovePlayerFromAllZones(client);
	
	// Stop giving him the weapons
	if(g_hApplyPlayerClass[client] != INVALID_HANDLE)
	{
		KillTimer(g_hApplyPlayerClass[client]);
		g_hApplyPlayerClass[client] = INVALID_HANDLE;
	}
	
	// Don't do anything, if no flags for that map -> "disabled"
	if(GetArraySize(g_hFlags) == 0)
		return Plugin_Continue;
	
	// Don't care, if he's joining the same team again :P
	if(oldteam == team)
		return Plugin_Continue;
	
	if(team > CS_TEAM_SPECTATOR)
	{
		// Respawn the player, if he's not alive already or is being respawned
		if(GetConVarBool(g_hCVRespawn) && !IsPlayerAlive(client) && g_hRespawnPlayer[client] == INVALID_HANDLE)
		{
			new iRespawnTime = GetConVarInt(g_hCVRespawnTime);
			
			new Handle:hDataPack = CreateDataPack();
			WritePackCell(hDataPack, userid);
			WritePackCell(hDataPack, iRespawnTime);
			ResetPack(hDataPack);
			g_hRespawnPlayer[client] = CreateTimer(1.0, Timer_OnPlayerRespawnTick, hDataPack, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE|TIMER_DATA_HNDL_CLOSE);
			Client_PrintKeyHintText(client, "%t", "Respawn in x seconds", iRespawnTime);
		}
		
		// Reset the class, if it's team specific or full in the new team
		if(g_iPlayerClass[client] != -1)
		{
			new Handle:hClass = GetArrayCell(g_hClasses, g_iPlayerClass[client]);
			
			// The current class needs to be for both teams
			new iTeam = GetArrayCell(hClass, CLASS_TEAM);
			if(iTeam == 0)
			{
				// Check if the class is already full in the new team.
				new iCurrentPlayers = GetTotalPlayersInClass(g_iPlayerClass[client], team);
				new iLimit = GetArrayCell(hClass, CLASS_LIMIT);
				if(iLimit != 0 && iCurrentPlayers >= iLimit)
				{
					// The class is full in the new team. Reset to default.
					g_iPlayerClass[client] = -1;
					g_iPlayerTempClass[client] = -1;
					g_iPlayerWeaponSet[client] = -1;
					// Apply the class directly again
					g_bPlayerJustJoined[client] = true;
				}
			}
			// This one is team specific. Reset to default.
			else
			{
				g_iPlayerClass[client] = -1;
				g_iPlayerTempClass[client] = -1;
				g_iPlayerWeaponSet[client] = -1;
				// Apply the class directly again
				g_bPlayerJustJoined[client] = true;
			}
		}
		// No class assigned before. Reset just to be sure;)
		else
		{
			g_iPlayerTempClass[client] = -1;
			g_iPlayerWeaponSet[client] = -1;
			// Apply the class directly again
			g_bPlayerJustJoined[client] = true;
		}
		
		if(GetConVarBool(g_hCVUseClasses))
		{
			// Set the class with a delay
			g_hApplyPlayerClass[client] = CreateTimer(0.5, Timer_ApplyPlayerClass, userid, TIMER_FLAG_NO_MAPCHANGE);
		}
	}
	
	return Plugin_Continue;
}

public Action:Event_OnRoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	g_bRoundEnded = false;
	
	// Remove the objectives
	if(GetConVarBool(g_hCVRemoveObjectives))
	{
		new iMaxEntities = GetMaxEntities(), String:eName[64];
		for (new i=MaxClients;i<iMaxEntities;i++)
		{
			if (IsValidEdict(i)
			&& IsValidEntity(i)
			&& GetEdictClassname(i, eName, sizeof(eName)))
			{
				// remove bombzones and hostages so no normal gameplay could end the round
				if(StrContains(eName, "hostage_entity") != -1 
					|| StrContains(eName, "func_bomb_target") != -1 
					|| StrContains(eName, "func_hostage_rescue") != -1)
				{
					AcceptEntityInput(i, "Kill");
				}
			}
		}
	}
	
	// Remove all old flags first
	RemoveLeftFlags();
	
	// Spawn all flags
	new iSize = GetArraySize(g_hFlags);
	
	// Don't do anything, if no flags for that map -> "disabled"
	if(iSize == 0)
		return Plugin_Continue;
	
	for(new i=0;i<iSize;i++)
	{
		SpawnFlag(i);
	}
	
	// Clear the overlay
	if(GetConVarBool(g_hCVShowWinOverlays))
	{
		Client_SetScreenOverlayForAll("");
	}
	
	if(g_hStartSound != INVALID_HANDLE)
	{
		KillTimer(g_hStartSound);
		g_hStartSound = INVALID_HANDLE;
	}
	
	// Only play the sound, if the admin has set a valid file
	if(strlen(g_sSoundFiles[CSOUND_FLAG_AMBIENCE]) == 0)
		g_hStartSound = CreateTimer(3.0, Timer_OnStartSound, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
	
	if(strlen(g_sSoundFiles[CSOUND_ROUNDSTART]) > 0)
		EmitSoundToAll(g_sSoundFiles[CSOUND_ROUNDSTART]);
	
	if(g_hRemoveWeapons != INVALID_HANDLE)
	{
		KillTimer(g_hRemoveWeapons);
		g_hRemoveWeapons = INVALID_HANDLE;
	}
	
	new Float:fRemoveInterval = GetConVarFloat(g_hCVRemoveDroppedWeapons);
	if(fRemoveInterval > 0.0)
	{
		g_hRemoveWeapons = CreateTimer(fRemoveInterval, Timer_OnRemoveWeapons, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
	}
	
	return Plugin_Continue;
}

public Action:Event_OnRoundEnd(Handle:event, const String:name[], bool:dontBroadcast)
{
	g_bRoundEnded = true;
	
	if(g_hStartSound != INVALID_HANDLE)
	{
		KillTimer(g_hStartSound);
		g_hStartSound = INVALID_HANDLE;
	}
	
	if(g_hRemoveWeapons != INVALID_HANDLE)
	{
		KillTimer(g_hRemoveWeapons);
		g_hRemoveWeapons = INVALID_HANDLE;
	}
	
	// Don't do anything, if no flags for that map -> "disabled"
	if(GetArraySize(g_hFlags) == 0)
		return Plugin_Continue;
	
	// Stop the default round end radio sound
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			StopSound(i, SNDCHAN_STATIC, "radio/ctwin.wav");
			StopSound(i, SNDCHAN_STATIC, "radio/terwin.wav");
		}
	}
	
	return Plugin_Continue;
}

/**
 * SDKHook Callbacks
 */

public OnEntityCreated(entity, const String:classname[])
{
	// Remove the bomb
	if(StrEqual(classname, "weapon_c4", false) && GetConVarBool(g_hCVRemoveObjectives) && GetArraySize(g_hFlags) > 0)
		AcceptEntityInput(entity, "Kill");
}

public Action:CS_OnCSWeaponDrop(client, weapon)
{
	// Don't do anything, if no flags for that map -> "disabled" or no weapon dropped
	if(!GetConVarBool(g_hCVPreventWeaponDrop) || GetArraySize(g_hFlags) == 0 || weapon == -1)
		return Plugin_Continue;
	
	// Primary or secondary weapon? Don't drop.
	if(IsClientInGame(client) && (Client_GetWeaponBySlot(client, CS_SLOT_PRIMARY) == weapon || Client_GetWeaponBySlot(client, CS_SLOT_SECONDARY) == weapon))
	{
		// Player buys a new weapon through the buymenu. delete the old.
		if(g_bPlayerIsBuying[client])
		{
			RemovePlayerItem(client, weapon);
			AcceptEntityInput(weapon, "Kill");
			return Plugin_Continue;
		}
		
		return Plugin_Handled;
	}

	// Drop grenades.
	// Need to do that, since we actually "drop" the grenade, when throwing it.
	// If we "block" it here, it still get's thrown, but the player don't change to his previous weapon, but stays empty-handed :O
	// We can remove them later on, with our OnRemoveWeapons timer
	return Plugin_Continue;
}

// Keep track of which weapon the player is holding for dropping the correct ammo on death.
public Action:Hook_OnWeaponSwitch(client, weapon)
{
	// Don't do anything, if no flags for that map -> "disabled"
	if(GetArraySize(g_hFlags) == 0)
		return Plugin_Continue;
	
	// If that player isn't ingame anymore, stop
	if(!IsClientInGame(client))
		return Plugin_Continue;
	
	if(Client_GetWeaponBySlot(client, CS_SLOT_PRIMARY) == weapon)
		g_iPlayerActiveSlot[client] = CS_SLOT_PRIMARY;
	else if(Client_GetWeaponBySlot(client, CS_SLOT_SECONDARY) == weapon)
		g_iPlayerActiveSlot[client] = CS_SLOT_SECONDARY;
	else
		g_iPlayerActiveSlot[client] = -1;
	
	return Plugin_Continue;
}

public bool:TraceRayNoPlayers(entity, mask, any:data)
{
	if(entity == data || entity >= 1 || entity <= MaxClients)
	{
		return false;
	}
	return true;
}

public Hook_OnStartTouchAmmo(entity, other)
{
	if(other < 1 || other > MaxClients || !IsPlayerAlive(other))
	{
		return;
	}
	
	// Get ammo type
	decl String:sTargetName[64];
	GetEntPropString(entity, Prop_Data, "m_iName", sTargetName, sizeof(sTargetName));
	ReplaceString(sTargetName, sizeof(sTargetName), "scq_ammo_", "");
	new iWeaponType = StringToInt(sTargetName);
	
	// Primary ammo
	if(iWeaponType == 0)
	{
		new iWeapon = Client_GetWeaponBySlot(other, CS_SLOT_PRIMARY);
		if(iWeapon != INVALID_ENT_REFERENCE)
		{
			decl String:sWeapon[64];
			new iPrimaryAmmo, iSecondaryAmmo = -1;
			GetEdictClassname(iWeapon, sWeapon, sizeof(sWeapon));
			Client_GetWeaponPlayerAmmo(other, sWeapon, iPrimaryAmmo, iSecondaryAmmo);
			Client_SetWeaponPlayerAmmoEx(other, iWeapon, iPrimaryAmmo+GetConVarInt(g_hCVPrimaryAmmoAmount));
			AcceptEntityInput(entity, "Kill");
			EmitSoundToAll(AMMO_SOUND, other, SNDCHAN_AUTO, SNDLEVEL_SCREAMING);
		}
	}
	else if(iWeaponType == 1)
	{
		new iWeapon = Client_GetWeaponBySlot(other, CS_SLOT_SECONDARY);
		if(iWeapon != INVALID_ENT_REFERENCE)
		{
			decl String:sWeapon[64];
			new iPrimaryAmmo, iSecondaryAmmo = -1;
			GetEdictClassname(iWeapon, sWeapon, sizeof(sWeapon));
			Client_GetWeaponPlayerAmmo(other, sWeapon, iPrimaryAmmo, iSecondaryAmmo);
			Client_SetWeaponPlayerAmmoEx(other, iWeapon, iPrimaryAmmo+GetConVarInt(g_hCVSecondaryAmmoAmount));
			AcceptEntityInput(entity, "Kill");
			EmitSoundToAll(AMMO_SOUND, other);
		}
	}
}

public Hook_OnPostThinkPost(entity)
{
	// Don't do anything, if no flags for that map -> "disabled"
	if(GetArraySize(g_hFlags) == 0)
		return;
	
	// Simulate not being in buyzone, but keep the information for our own buymenu
	new bool:bInBuyZone = GetEntProp(entity, Prop_Send, "m_bInBuyZone") == 1;
	if(bInBuyZone)
	{
		if(GetConVarBool(g_hCVDisableBuyzones))
			SetEntProp(entity, Prop_Send, "m_bInBuyZone", 0);
	}
	
	if(!g_bPlayerInBuyZone[entity] && bInBuyZone)
	{
		g_bPlayerInBuyZone[entity] = true;
		
	}
	else if(g_bPlayerInBuyZone[entity] && !bInBuyZone)
	{
		g_bPlayerInBuyZone[entity] = false;
	}
	
	// show the progressbar for spectating clients either
	if(!IsPlayerAlive(entity) || IsClientObserver(entity))
	{
		// Only show the bar, when spectating a player directly
		new Obs_Mode:iObsMode = Client_GetObserverMode(entity);
		if(iObsMode == OBS_MODE_IN_EYE || iObsMode == OBS_MODE_CHASE)
		{
			new iObsTarget = Client_GetObserverTarget(entity);
			if(iObsTarget != -1)
			{
				// Is this player currently conquering a flag?
				new iSize = GetArraySize(g_hPlayersInZone), iNumPlayers, Handle:hPlayers, Handle:hFlag;
				new iConquerStartTime, iTime, iClient;
				for(new i=0;i<iSize;i++)
				{
					// Is this flag currently being conquered by someone?
					hFlag = GetArrayCell(g_hFlags, i);
					iConquerStartTime = GetArrayCell(hFlag, FLAG_CONQUERSTARTTIME);
					if(iConquerStartTime != -1)
					{
						hPlayers = GetArrayCell(g_hPlayersInZone, i);
						iNumPlayers = GetArraySize(hPlayers);
						for(new x=0;x<iNumPlayers;x++)
						{
							iClient = GetArrayCell(hPlayers, x);
							// We're spectaing a conqueror, show the bar either
							if(iClient == iObsTarget)
							{
								iTime = GetArrayCell(hFlag, FLAG_TIME);
								SetEntPropFloat(entity, Prop_Send, "m_flProgressBarStartTime", GetGameTime());
								SetEntProp(entity, Prop_Send, "m_iProgressBarDuration", iTime - GetTime() + iConquerStartTime);
								return;
							}
						}
					}
				}
			}
		}
		
		SetEntPropFloat(entity, Prop_Send, "m_flProgressBarStartTime", 0.0);
		SetEntProp(entity, Prop_Send, "m_iProgressBarDuration", 0);
	}
}

/**
 * Timer Callbacks
 */
 
public Action:Timer_OnPlayerRespawnTick(Handle:timer, any:hDataPack)
{
	new userid = ReadPackCell(hDataPack);
	new client = GetClientOfUserId(userid);
	if(g_bRoundEnded || !client || IsPlayerAlive(client) || GetClientTeam(client) < CS_TEAM_T)
	{
		g_hRespawnPlayer[client] = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	new iPos = GetPackPosition(hDataPack);
	
	new iSecondsLeft = ReadPackCell(hDataPack);
	
	iSecondsLeft--;
	SetPackPosition(hDataPack, iPos);
	WritePackCell(hDataPack, iSecondsLeft);
	ResetPack(hDataPack);
	
	if(iSecondsLeft > 0)
	{
		Client_PrintKeyHintText(client, "%t", "Respawn in x seconds", iSecondsLeft);
	}
	else
	{
		g_hRespawnPlayer[client] = INVALID_HANDLE;
		Client_PrintKeyHintText(client, "");
		CS_RespawnPlayer(client);
		return Plugin_Stop;
	}
	
	return Plugin_Continue;
}

public Action:Timer_OnDisableSpawnprotection(Handle:timer, any:userid)
{
	new client = GetClientOfUserId(userid);
	if(!client)
		return Plugin_Stop;
	
	g_hRemoveSpawnProtection[client] = INVALID_HANDLE;
	
	SetEntProp(client, Prop_Data, "m_takedamage", 2);
	SetEntityRenderMode(client, RENDER_NORMAL);
	SetEntityRenderColor(client, 255, 255, 255, 255);
	
	return Plugin_Stop;
}

public Action:Timer_OnStartSound(Handle:timer, any:data)
{
	g_hStartSound = INVALID_HANDLE;
	
	new iSize = GetArraySize(g_hFlags);
	new Handle:hFlag, iFlag, Float:fPos[3];
	for(new i=0;i<iSize;i++)
	{
		hFlag = GetArrayCell(g_hFlags, i);
		iFlag = GetArrayCell(hFlag, FLAG_FLAGENTITY);
		GetArrayArray(hFlag, FLAG_POSITION, fPos, 3);
		fPos[2] += 30.0;
		// TODO: Restart the sound everytime a player joins, so it's heared by everyone and not only those who were present on round start! AmbientSHook?
		EmitAmbientSound(g_sSoundFiles[CSOUND_FLAG_AMBIENCE], fPos, iFlag);
	}
	
	return Plugin_Stop;
}

public Action:Timer_OnRemoveWeapons(Handle:timer, any:data)
{
	if(GetConVarFloat(g_hCVRemoveDroppedWeapons) == 0.0)
	{
		g_hRemoveWeapons = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	new iMaxEntities = GetMaxEntities();
	decl String:sClassName[64];
	for(new i=MaxClients+1;i<iMaxEntities;i++)
	{
		if(IsValidEntity(i)
		&& IsValidEdict(i)
		&& GetEdictClassname(i, sClassName, sizeof(sClassName))
		&& StrContains(sClassName, "weapon_") != -1
		&& GetEntPropEnt(i, Prop_Send, "m_hOwner") == -1)
			AcceptEntityInput(i, "Kill");
	}
	return Plugin_Continue;
}

// Force the timelimit set with mp_timelimit, even midround
public Action:Timer_CheckTimeLimit(Handle:timer, any:data)
{
	if(g_iTimeLimit != 0 && (GetTime() - g_iMapStartTime) >= g_iTimeLimit)
	{
		new iGameEnd  = FindEntityByClassname(-1, "game_end");
		if (iGameEnd == -1 && (iGameEnd = CreateEntityByName("game_end")) == -1) 
		{
			LogError("Unable to create entity \"game_end\"!");
		} 
		else 
		{
			g_hTimeLimitEnforcer = INVALID_HANDLE;
			AcceptEntityInput(iGameEnd, "EndGame");
			return Plugin_Stop;
		}
	}
	
	return Plugin_Continue;
}

// Teach the players the available commands
public Action:Timer_OnAdvertCommands(Handle:timer, any:data)
{
	if(!GetConVarBool(g_hCVAdvertiseCommands))
		return Plugin_Stop;
	
	if(data == 0 && GetConVarBool(g_hCVUseClasses))
	{
		CPrintToChatAll("%s%t", PREFIX, "Advert !class");
		// Only advert for the !buy command, if it's enabled ofc :)
		if(GetConVarBool(g_hCVUseBuymenu))
			data = 1;
	}
	else if(data == 1 && GetConVarBool(g_hCVUseBuymenu))
	{
		if(GetConVarBool(g_hCVInBuyzone))
			CPrintToChatAll("%s%t %t", PREFIX, "Advert !buy", "Advert !buy in buyzone");
		else
			CPrintToChatAll("%s%t", PREFIX, "Advert !buy");
		data = 0;
	}
	// We don't use any of the commands, so stop the timer.
	else
	{
		return Plugin_Stop;
	}
	
	// Reshow the other advert in 5 minutes
	CreateTimer(300.0, Timer_OnAdvertCommands, data, TIMER_FLAG_NO_MAPCHANGE);
	
	return Plugin_Stop;
}

/**
 * 
 * ConVar Change Callbacks
 */ 
 
public ConVar_TimeLimitChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if(!StrEqual(oldValue, newValue))
	{
		g_iTimeLimit = StringToInt(newValue)*60;
	}
}

/**
 * Helper functions
 */

bool:CreateAmmoPack(Float:fOrigin[3], Float:fAngle[3], bool:bPrimaryAmmo)
{
	new iAmmo = CreateEntityByName("prop_physics");
	if(iAmmo != -1)
	{
		// Don't rotate pitch and roll
		fAngle[0] = 0.0;
		fAngle[2] = 0.0;
		TeleportEntity(iAmmo, fOrigin, fAngle, NULL_VECTOR);
		
		decl String:sTargetName[64];
		Format(sTargetName, sizeof(sTargetName), "scq_ammo_%d", (bPrimaryAmmo?0:1));
		DispatchKeyValue(iAmmo, "targetname", sTargetName);
		
		// Spawn big model
		if(bPrimaryAmmo)
		{
			SetEntityModel(iAmmo, PRIMARYAMMO_MODEL);
		}
		else
		{
			SetEntityModel(iAmmo, SECONDARYAMMO_MODEL);
		}
		
		DispatchSpawn(iAmmo);
		ActivateEntity(iAmmo);
		
		SDKHook(iAmmo, SDKHook_StartTouch, Hook_OnStartTouchAmmo);
		
		// Remove it after x seconds
		// Thanks to FoxMulder for his Snippet
		// http://forums.alliedmods.net/showthread.php?t=129135
		new Float:fAmmoLifeTime = GetConVarFloat(g_hCVAmmoLifetime);
		if(fAmmoLifeTime > 0.0)
		{
			Format(sTargetName, sizeof(sTargetName), "OnUser1 !self:kill::%f:1", fAmmoLifeTime);
			SetVariantString(sTargetName);
			AcceptEntityInput(iAmmo, "AddOutput");
			AcceptEntityInput(iAmmo, "FireUser1");
		}
		return true;
	}
	
	return false;
}

/**
 * Helper functions
 */

public Action:Command_SpawnAmmoPack(client, args)
{
	if(args == 0)
	{
		ReplyToCommand(client, "%sUsage: sm_spawnammo <p|s>", PREFIX);
		return Plugin_Handled;
	}
	
	decl String:sAmmoType[5];
	GetCmdArgString(sAmmoType, sizeof(sAmmoType));
	StripQuotes(sAmmoType);
	
	new bool:bPrimaryAmmo;
	if(StrEqual(sAmmoType, "p", false))
		bPrimaryAmmo = true;
	else if(StrEqual(sAmmoType, "s", false))
		bPrimaryAmmo = false;
	else
	{
		ReplyToCommand(client, "%sUsage: sm_spawnammo <p|s>", PREFIX);
		return Plugin_Handled;
	}
	
	new Float:fOrigin[3], Float:fAngle[3], Float:fEnd[3];
	GetClientEyePosition(client, fOrigin);
	GetClientEyeAngles(client, fAngle);
	
	// convert degrees to radians
	fAngle[0] = DegToRad(fAngle[0]);
	fAngle[1] = DegToRad(fAngle[1]);
	
	// calculate entity destination after creation (raw number is an offset distance)
	fEnd[0] = fOrigin[0] + 164 * Cosine(fAngle[0]) * Cosine(fAngle[1]);
	fEnd[1] = fOrigin[1] + 164 * Cosine(fAngle[0]) * Sine(fAngle[1]);
	fEnd[2] = fOrigin[2] - 50 * Sine(fAngle[0]);
	
	
	TR_TraceRayFilter(fOrigin, fEnd, MASK_PLAYERSOLID, RayType_EndPoint, TraceRayNoPlayers, client);
	if(TR_DidHit())
		TR_GetEndPosition(fEnd);
	
	CreateAmmoPack(fEnd, fAngle, bPrimaryAmmo);
	return Plugin_Handled;
}

// Stock by psychonic
// http://forums.alliedmods.net/showpost.php?p=1294224&postcount=2
stock MyAddServerTag(const String:tag[])
{
	decl String:currtags[128];
	if (g_hSVTags == INVALID_HANDLE)
	{
		return;
	}
	
	GetConVarString(g_hSVTags, currtags, sizeof(currtags));
	if (StrContains(currtags, tag) > -1)
	{
		// already have tag
		return;
	}
	
	decl String:newtags[128];
	Format(newtags, sizeof(newtags), "%s%s%s", currtags, (currtags[0]!=0)?",":"", tag);
	new flags = GetConVarFlags(g_hSVTags);
	SetConVarFlags(g_hSVTags, flags & ~FCVAR_NOTIFY);
	SetConVarString(g_hSVTags, newtags);
	SetConVarFlags(g_hSVTags, flags);
}

stock MyRemoveServerTag(const String:tag[])
{
	decl String:newtags[128];
	if (g_hSVTags == INVALID_HANDLE)
	{
		return;
	}
	
	GetConVarString(g_hSVTags, newtags, sizeof(newtags));
	if (StrContains(newtags, tag) == -1)
	{
		// tag isn't on here, just bug out
		return;
	}
	
	ReplaceString(newtags, sizeof(newtags), tag, "");
	ReplaceString(newtags, sizeof(newtags), ",,", "");
	new flags = GetConVarFlags(g_hSVTags);
	SetConVarFlags(g_hSVTags, flags & ~FCVAR_NOTIFY);
	SetConVarString(g_hSVTags, newtags);
	SetConVarFlags(g_hSVTags, flags);
}
/*
 * Handles the model config parsing
 * Part of SM:Conquest
 *
 * Thread: https://forums.alliedmods.net/showthread.php?t=154354
 * visit http://www.wcfan.de/
 */
#include <sourcemod>

#define MODELS_ALIAS 0
#define MODELS_MDLFILE 1

// Array holding the models
new Handle:g_hModels;

enum OverlayMaterials {
	String:m_CT[PLATFORM_MAX_PATH],
	String:m_T[PLATFORM_MAX_PATH]
}

enum FlagTypes {
	String:WhiteFlag[6],
	String:RedFlag[6],
	String:BlueFlag[6]
}

enum ConfigSection
{
	State_None = 0,
	State_Root,
	State_Files,
	State_Flag,
	State_Overlays,
	State_Class,
	State_WeaponSet
}

// Model config parser
new ConfigSection:g_ModelConfigSection = State_None;
new g_iCurrentModelIndex = -1;
new bool:g_bDontDownloadCurrentModel = false;

new g_OverlayMaterials[OverlayMaterials];
new g_FlagSkinOptions[FlagTypes];
new String:g_sFlagModelPath[PLATFORM_MAX_PATH];
new String:g_sFlagAnimation[64];

/** 
 * Model Config Parsing
 */

bool:ParseModelConfig()
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
	
	g_sFlagModelPath[0] = 0;
	g_sFlagAnimation[0] = 0;
	g_OverlayMaterials[m_CT][0] = 0;
	g_OverlayMaterials[m_T][0] = 0;
	
	new String:sFile[PLATFORM_MAX_PATH], String:sGame[10];
	
	// Get the correct config for this game
	if(g_bIsCSGO)
		Format(sGame, sizeof(sGame), "csgo");
	else
		Format(sGame, sizeof(sGame), "css");
	BuildPath(Path_SM, sFile, sizeof(sFile), "configs/smconquest/%s/smconquest_models.cfg", sGame);
	
	if(!FileExists(sFile))
		return false;
	
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
		return false;
	}
	
	return true;
}

public SMCResult:ModelConfig_OnNewSection(Handle:parser, const String:section[], bool:quotes)
{
	switch(g_ModelConfigSection)
	{
		// New model file list
		case State_Root:
		{
			if(StrEqual(section, "flag_config", false))
			{
				g_ModelConfigSection = State_Flag;
			}
			else if(StrEqual(section, "overlay_materials", false))
			{
				g_ModelConfigSection = State_Overlays;
			}
			else
			{
				new Handle:hModel = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH)); // Duh, that's a large array..
				
				// Save the model alias
				PushArrayString(hModel, section);
				PushArrayString(hModel, ""); // Dummy mdl path
				
				g_iCurrentModelIndex = PushArrayCell(g_hModels, hModel);
				g_ModelConfigSection = State_Files;
			}
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
	
	switch(g_ModelConfigSection)
	{
		case State_Files:
		{
			new Handle:hModel = GetArrayCell(g_hModels, g_iCurrentModelIndex);
			
			// Some other plugin is already downloading that model or it's a default one?
			if(StrEqual(key, "no_download", false) && StringToInt(value) == 1)
			{
				g_bDontDownloadCurrentModel = true;
			}
			// This is a file to download
			else if(StrEqual(key, "file", false))
			{
				// Bad file? User has to fix the file!
				if(!FileExists(value, true))
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
		case State_Flag:
		{
			if(StrEqual(key, "file", false))
			{
				// Bad file? User has to fix the file!
				if(!FileExists(value, true))
					return SMCParse_HaltFail;
				
				// Have clients download the file
				AddFileToDownloadsTable(value);
				
				// Save the model path and precache the model
				if(StrEqual(value[strlen(value)-4], ".mdl", false))
				{
					PrecacheModel(value, true);
					strcopy(g_sFlagModelPath, sizeof(g_sFlagModelPath), value);
				}
			}
			else if(StrEqual(key, "skin_red", false))
			{
				strcopy(g_FlagSkinOptions[RedFlag], sizeof(g_FlagSkinOptions[RedFlag]), value);
			}
			else if(StrEqual(key, "skin_blue", false))
			{
				strcopy(g_FlagSkinOptions[BlueFlag], sizeof(g_FlagSkinOptions[RedFlag]), value);
			}
			else if(StrEqual(key, "skin_white", false))
			{
				strcopy(g_FlagSkinOptions[WhiteFlag], sizeof(g_FlagSkinOptions[RedFlag]), value);
			}
			else if(StrEqual(key, "animation", false))
			{
				strcopy(g_sFlagAnimation, sizeof(g_sFlagAnimation), value);
			}
			else
			{
				LogError("Unknown key \"%s\" in flag_config section in smconquest_models.cfg");
				return SMCParse_HaltFail;
			}
		}
		case State_Overlays:
		{
			if(StrEqual(key, "ct_file", false) || StrEqual(key, "t_file", false))
			{
				// Bad file? User has to fix the file!
				if(!FileExists(value, true))
					return SMCParse_HaltFail;
				
				// Have clients download the file
				AddFileToDownloadsTable(value);
				
				// Save the model path and precache the model
				if(StrEqual(value[strlen(value)-4], ".vtf", false))
				{
					// Skip the "materials/" part of the path to be able to use it in r_screenoverlay
					new iOffset;
					if(StrContains(value, "materials/") == 0)
						iOffset = 10;
					if(StrEqual(key, "ct_file", false))
					{
						strcopy(g_OverlayMaterials[m_CT], sizeof(g_OverlayMaterials[m_CT]), value[iOffset]);
						PrintToServer("ct_file: %s", g_OverlayMaterials[m_CT]);
					}
					else
					{
						strcopy(g_OverlayMaterials[m_T], sizeof(g_OverlayMaterials[m_T]), value[iOffset]);
						PrintToServer("t_file: %s", g_OverlayMaterials[m_T]);
					}
				}
				else if(StrEqual(value[strlen(value)-4], ".vmt", false))
				{
					PrecacheDecal(value, true);
				}
			}
			else
			{
				LogError("Unknown key \"%s\" in overlay_materials section in smconquest_models.cfg");
				return SMCParse_HaltFail;
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
	}
	
	g_ModelConfigSection = State_Root;
	
	return SMCParse_Continue;
}

public ModelConfig_OnParseEnd(Handle:parser, bool:halted, bool:failed) {
	if (failed)
		SetFailState("Error during parse of the models config.");
}
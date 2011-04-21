/*
 * Handles the weapon buying
 * Part of SM:Conquest
 *
 * visit http://www.wcfan.de/
 */
#include <sourcemod>

new Handle:g_hBuyCategoryMenu = INVALID_HANDLE;
new Handle:g_hBuyItemMenuArray;

new bool:g_bPlayerInBuyZone[MAXPLAYERS+2] = {false,...};
new bool:g_bPlayerIsBuying[MAXPLAYERS+2] = {false,...};

/**
 * Menu Handlers
 */

public Menu_SelectBuyCategory(Handle:menu, MenuAction:action, param1, param2)
{
	// Translate the header
	if(action == MenuAction_Display)
	{
		new Handle:panel = Handle:param2;
		decl String:sMenuTitle[64];
		Format(sMenuTitle, sizeof(sMenuTitle), "%T", "Select category", param1);
		SetPanelTitle(panel, sMenuTitle);
	}
	if(action == MenuAction_Select)
	{
		// Buymenu disabled?
		if(!GetConVarBool(g_hCVUseBuymenu))
			return;
		
		if(!IsPlayerAlive(param1))
		{
			CPrintToChat(param1, "%s%t", PREFIX, "Has to be alive");
			return;
		}
		
		if(GetConVarBool(g_hCVInBuyzone) && !g_bPlayerInBuyZone[param1])
		{
			PrintCenterText(param1, "#Cstrike_NotInBuyZone");
			return;
		}
		
		decl String:sInfo[256];
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
		
		new iBuy = StringToInt(sInfo);
		new Handle:hBuy = GetArrayCell(g_hBuyItemMenuArray, iBuy);
		DisplayMenu(hBuy, param1, MENU_TIME_FOREVER);
	}
}

public Menu_BuyItem(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack)
		{
			DisplayMenu(g_hBuyCategoryMenu, param1, MENU_TIME_FOREVER);
		}
	}
	else if(action == MenuAction_Select)
	{
		// Buymenu disabled?
		if(!GetConVarBool(g_hCVUseBuymenu))
			return;
		
		if(!IsPlayerAlive(param1))
		{
			CPrintToChat(param1, "%s%t", PREFIX, "Has to be alive");
			return;
		}
		
		if(GetConVarBool(g_hCVInBuyzone) && !g_bPlayerInBuyZone[param1])
		{
			PrintCenterText(param1, "#Cstrike_NotInBuyZone");
			return;
		}
		
		decl String:sInfo[256], String:sDisplay[256], String:sExplode[2][256];
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo), _, sDisplay, sizeof(sDisplay));
		
		ExplodeString(sInfo, "|", sExplode, 2, 255);
		
		new iPrice = StringToInt(sExplode[1]);
		
		// enough money?
		new iMoney = GetEntData(param1, g_iAccount);
		if(iMoney < iPrice)
		{
			CPrintToChat(param1, "%s%t", PREFIX, "Not enough money", sDisplay);
			DisplayMenu(menu, param1, MENU_TIME_FOREVER);
			return;
		}
		
		new bool:bIsNade = false;
		// Give the weapon
		if(StrEqual(sExplode[0], "item_nvgs", false))
		{
			// That item_nvgs doesn't really exist;)
			SetEntProp(param1, Prop_Send, "m_bHasNightVision", 1);
		}
		else if(StrEqual(sExplode[0], "item_kevlar", false))
		{
			SetEntProp(param1, Prop_Send, "m_ArmorValue", 100);
		}
		else if(StrEqual(sExplode[0], "item_assaultsuit", false))
		{
			SetEntProp(param1, Prop_Send, "m_ArmorValue", 100);
			SetEntProp(param1, Prop_Send, "m_bHasHelmet", 1);
		}
		else
		{
			// Handle grenades separately
			new bool:bAddNade = true;
			if(StrEqual(sExplode[0], "weapon_hegrenade", false))
			{
				g_iPlayerGrenade[param1][GRENADE_HE]++;
				if(g_iPlayerGrenade[param1][GRENADE_HE] > 1)
				{
					bAddNade = false;
					CPrintToChat(param1, "%s%t", PREFIX, "HE bought", iPrice, g_iPlayerGrenade[param1][GRENADE_HE]);
				}
				bIsNade = true;
			}
			else if(StrEqual(sExplode[0], "weapon_flashbang", false))
			{
				g_iPlayerGrenade[param1][GRENADE_FLASH]++;
				if(g_iPlayerGrenade[param1][GRENADE_FLASH] > 2)
				{
					bAddNade = false;
					CPrintToChat(param1, "%s%t", PREFIX, "Flashbang bought", iPrice, g_iPlayerGrenade[param1][GRENADE_FLASH]);
				}
				bIsNade = true;
			}
			else if(StrEqual(sExplode[0], "weapon_smokegrenade", false))
			{
				g_iPlayerGrenade[param1][GRENADE_SMOKE]++;
				if(g_iPlayerGrenade[param1][GRENADE_SMOKE] > 1)
				{
					bAddNade = false;
					CPrintToChat(param1, "%s%t", PREFIX, "Smoke bought", iPrice, g_iPlayerGrenade[param1][GRENADE_SMOKE]);
				}
				bIsNade = true;
			}
			
			// Setting this, will tell the OnWeaponDrop hook to remove the dropped weapon instead of blocking.
			// We don't know the slot of the added item, so we can't remove the weapon here.
			g_bPlayerIsBuying[param1] = true;
			new iWeapon = -1;
			if(bAddNade)
				iWeapon = GivePlayerItem(param1, sExplode[0]);
			if(iWeapon != -1)
			{
				// Grenades shouldn't be equipped.
				if(!bIsNade)
					EquipPlayerWeapon(param1, iWeapon);
			}
			// Set to active weapon
			FakeClientCommand(param1, "use %s", sExplode[0]);
			g_bPlayerIsBuying[param1] = false;
		}
		// Get the money
		SetEntData(param1, g_iAccount, iMoney-iPrice);
		if(!bIsNade)
			CPrintToChat(param1, "%s%t", PREFIX, "Item bought", sDisplay);
		// Redisplay the menu
		DisplayMenu(menu, param1, MENU_TIME_FOREVER);
	}
}

/**
 * Command Handlers
 */

public Action:Command_ShowBuyMenu(client, args)
{
	// Don't try to show the menu, if the config file is missing/bugged
	if(g_hBuyCategoryMenu == INVALID_HANDLE)
		return Plugin_Handled;
	
	// Buymenu disabled?
	if(!GetConVarBool(g_hCVUseBuymenu))
		return Plugin_Handled;
	
	if(client && !IsPlayerAlive(client))
	{
		CPrintToChat(client, "%s%t", PREFIX, "Has to be alive");
		return Plugin_Handled;
	}
	
	if(GetConVarBool(g_hCVInBuyzone) && !g_bPlayerInBuyZone[client])
	{
		PrintCenterText(client, "#Cstrike_NotInBuyZone");
		return Plugin_Handled;
	}
	
	DisplayMenu(g_hBuyCategoryMenu, client, MENU_TIME_FOREVER);
	
	return Plugin_Handled;
}

/**
 * Helper functions
 */
ParseBuyConfig()
{
	// Remove old menu
	if(g_hBuyCategoryMenu != INVALID_HANDLE)
	{
		CloseHandle(g_hBuyCategoryMenu);
		g_hBuyCategoryMenu = INVALID_HANDLE;
	}
	
	new iSize = GetArraySize(g_hBuyItemMenuArray);
	new Handle:hBuy;
	for(new i=0;i<iSize;i++)
	{
		hBuy = GetArrayCell(g_hBuyItemMenuArray, i);
		CloseHandle(hBuy);
	}
	ClearArray(g_hBuyItemMenuArray);
	
	new String:sFile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFile, sizeof(sFile), "configs/smconquest_buymenu.cfg");
	
	if(!FileExists(sFile))
	{
		if(GetConVarBool(g_hCVUseBuymenu))
			LogError("Can't find buymenu config in %s", sFile);
		return;
	}
	
	new Handle:kv = CreateKeyValues("BuyMenu");
	FileToKeyValues(kv, sFile);
	
	if (!KvGotoFirstSubKey(kv))
	{
		CloseHandle(kv);
		if(GetConVarBool(g_hCVUseBuymenu))
			LogError("Error parsing buymenu config in %s", sFile);
		return;
	}
	
	g_hBuyCategoryMenu = CreateMenu(Menu_SelectBuyCategory);
	// This is translated in the callback
	SetMenuTitle(g_hBuyCategoryMenu, "Select category");
	SetMenuExitButton(g_hBuyCategoryMenu, true);
	
	decl String:sBuffer[256], String:sInfoBuffer[256];
	new iBuy, iPrice;
	do
	{
		// Create the sub menu listing the items
		hBuy = CreateMenu(Menu_BuyItem);
		SetMenuExitBackButton(hBuy, true);
		KvGetSectionName(kv, sBuffer, sizeof(sBuffer));
		SetMenuTitle(hBuy, sBuffer);
		
		// Add the category
		iBuy = PushArrayCell(g_hBuyItemMenuArray, hBuy);
		IntToString(iBuy, sInfoBuffer, sizeof(sInfoBuffer));
		AddMenuItem(g_hBuyCategoryMenu, sInfoBuffer, sBuffer);
		
		// Parse the item list
		if(KvGotoFirstSubKey(kv))
		{
			do
			{
				// Get the Itemname
				KvGetSectionName(kv, sBuffer, sizeof(sBuffer));
				
				// Get the item classname
				KvGetString(kv, "item", sInfoBuffer, sizeof(sInfoBuffer));
				
				iPrice = KvGetNum(kv, "price");
				Format(sBuffer, sizeof(sBuffer), "%s ($%d)", sBuffer, iPrice);
				Format(sInfoBuffer, sizeof(sInfoBuffer), "%s|%d", sInfoBuffer, iPrice);
				
				AddMenuItem(hBuy, sInfoBuffer, sBuffer);
			} while (KvGotoNextKey(kv));
			KvGoBack(kv);
		}
	} while(KvGotoNextKey(kv));
	
	CloseHandle(kv);
}
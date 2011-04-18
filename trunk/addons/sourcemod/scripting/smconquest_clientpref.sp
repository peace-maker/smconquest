/*
 * Handles the client cookies
 * Part of SM:Conquest
 *
 * visit http://www.wcfan.de/
 */
#include <sourcemod>
#include <clientprefs>

new Handle:g_hUseHUD = INVALID_HANDLE;
new bool:g_bUseHUD[MAXPLAYERS+2] = {true, ...};

new Handle:g_hUseHintStatus = INVALID_HANDLE;
new bool:g_bUseHintStatus[MAXPLAYERS+2] = {true, ...};

/**
 * Public Forwards
 */

public OnClientCookiesCached(client)
{
	decl String:sBuffer[256];
	// This one wants the top hud?
	GetClientCookie(client, g_hUseHUD, sBuffer, sizeof(sBuffer));
	if(strlen(sBuffer) == 0 || StrEqual(sBuffer, "1"))
		g_bUseHUD[client] = true;
	else
		g_bUseHUD[client] = false;
	
	// This one wants the hint hud?
	GetClientCookie(client, g_hUseHintStatus, sBuffer, sizeof(sBuffer));
	if(strlen(sBuffer) == 0 || StrEqual(sBuffer, "1"))
		g_bUseHintStatus[client] = true;
	else
		g_bUseHintStatus[client] = false;
}

/**
 * Menu Creation and Handling
 */

public Cookie_SettingsMenuHandler(client, CookieMenuAction:action, any:info, String:buffer[], maxlen)
{
	if(action == CookieMenuAction_SelectOption)
	{
		ShowSettingsMenu(client);
	}
}

ShowSettingsMenu(client)
{
	new Handle:hMenu = CreateMenu(Menu_SettingsMenuHandler);
	SetMenuTitle(hMenu, "SM:Conquest Settings");
	SetMenuExitBackButton(hMenu, true);
	
	decl String:sBuffer[64];
	Format(sBuffer, sizeof(sBuffer), "Show top HUD flag status? (Requires clientfix): ");
	if(g_bUseHUD[client])
		Format(sBuffer, sizeof(sBuffer), "%sOn", sBuffer);
	else
		Format(sBuffer, sizeof(sBuffer), "%sOff", sBuffer);
	AddMenuItem(hMenu, "usehud", sBuffer);
	
	Format(sBuffer, sizeof(sBuffer), "Show hint HUD flag status?: ");
	if(g_bUseHintStatus[client])
		Format(sBuffer, sizeof(sBuffer), "%sOn", sBuffer);
	else
		Format(sBuffer, sizeof(sBuffer), "%sOff", sBuffer);
	AddMenuItem(hMenu, "usehint", sBuffer);
	
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public Menu_SettingsMenuHandler(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}
	else if(action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack)
		{
			ShowCookieMenu(param1);
		}
	}
	else if(action == MenuAction_Select)
	{
		decl String:info[35];
		GetMenuItem(menu, param2, info, sizeof(info));
		
		// Change the HUD display
		if(StrEqual(info, "usehud"))
		{
			if(g_bUseHUD[param1])
			{
				SetClientCookie(param1, g_hUseHUD, "0");
				g_bUseHUD[param1] = false;
			}
			else
			{
				SetClientCookie(param1, g_hUseHUD, "1");
				g_bUseHUD[param1] = true;
			}
		}
		else if(StrEqual(info, "usehint"))
		{
			if(g_bUseHintStatus[param1])
			{
				SetClientCookie(param1, g_hUseHintStatus, "0");
				g_bUseHintStatus[param1] = false;
				// Remove the hint text immediately, so the user sees the result faster
				PrintHintText(param1, "");
			}
			else
			{
				SetClientCookie(param1, g_hUseHintStatus, "1");
				g_bUseHintStatus[param1] = true;
			}
		}
		
		ShowSettingsMenu(param1);
	}
}

/**
 * Helpers
 */

CreateClientCookies()
{
	g_hUseHUD = RegClientCookie("smconquest_usehud", "Show top HUD flag status? (Requires clientfix)", CookieAccess_Protected);
	g_hUseHintStatus = RegClientCookie("smconquest_usehintstatus", "Show hint HUD flag status?", CookieAccess_Protected);
	
	SetCookieMenuItem(Cookie_SettingsMenuHandler, 0, "SM:Conquest");
}

// Reset the cookie vars to default
ResetCookieCache(client)
{
	g_bUseHUD[client] = true;
	g_bUseHintStatus[client] = true;
}
#pragma semicolon 1

#include <sourcemod>
#include <store>

#include <clientprefs>

#undef REQUIRE_EXTENSIONS
#include <tf2_stocks>

#define PLUGIN_NAME "[Store] Loadouts Module"
#define PLUGIN_DESCRIPTION "Loadouts module for the Sourcemod Store."
#define PLUGIN_VERSION_CONVAR "store_loadouts_version"

#define MOTD "store-user/USERID/loadout"
#define CSGO_MOTD "store-users/csgofile"

//Config Globals
int g_loadoutsAmount = 3;

char TF2_ClassName[TFClassType][] = {"", "scout", "sniper", "soldier", "demoman", "medic", "heavy", "pyro", "spy", "engineer" };

Handle g_clientLoadoutChangedForward;

char g_game[STORE_MAX_LOADOUTGAME_LENGTH];

int g_clientLoadout[MAXPLAYERS + 1];
Handle g_lastClientLoadout;

bool g_databaseInitialized;

public Plugin myinfo =
{
	name = PLUGIN_NAME,
	author = STORE_AUTHORS,
	description = PLUGIN_DESCRIPTION,
	version = STORE_VERSION,
	url = STORE_URL
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("Store_OpenLoadoutMenu", Native_OpenLoadoutMenu);
	CreateNative("Store_GetClientsCurrentLoadout", Native_GetClientsCurrentLoadout);
	CreateNative("Store_OpenLoadoutsMOTD", Native_OpenLoadoutsMOTD);
	
	g_clientLoadoutChangedForward = CreateGlobalForward("Store_OnClientLoadoutChanged", ET_Event, Param_Cell);
	
	RegPluginLibrary("store-loadout");	
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("store.phrases");
	
	CreateConVar(PLUGIN_VERSION_CONVAR, STORE_VERSION, PLUGIN_NAME, FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_DONTRECORD);
	
	g_lastClientLoadout = RegClientCookie("lastClientLoadout", "Client loadout", CookieAccess_Protected);
	
	GetGameFolderName(g_game, sizeof(g_game));
	
	HookEvent("player_spawn", Event_PlayerSpawn);
	
	LoadConfig();
}

public void Store_OnCoreLoaded()
{
	Store_AddMainMenuItem("Loadout", "Loadout Description", _, OnMainMenuLoadoutClick, 10);
}

public void OnMapStart()
{
	if (g_databaseInitialized)
	{
		Store_GetLoadouts(INVALID_HANDLE, INVALID_FUNCTION, false);
	}
}

public void Store_OnDatabaseInitialized()
{
	g_databaseInitialized = true;
	Store_GetLoadouts(INVALID_HANDLE, INVALID_FUNCTION, false);
	
	Store_RegisterPluginModule(PLUGIN_NAME, PLUGIN_DESCRIPTION, PLUGIN_VERSION_CONVAR, STORE_VERSION);
}

public void OnClientCookiesCached(int client)
{
	char buffer[12];
	GetClientCookie(client, g_lastClientLoadout, buffer, sizeof(buffer));
	g_clientLoadout[client] = StringToInt(buffer);
}

void LoadConfig() 
{
	Handle kv = CreateKeyValues("root");
	
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/store/loadout.cfg");
	
	if (!FileToKeyValues(kv, path)) 
	{
		CloseHandle(kv);
		SetFailState("Can't read config file %s", path);
	}

	char menuCommands[255];
	KvGetString(kv, "loadout_commands", menuCommands, sizeof(menuCommands));
	Store_RegisterChatCommands(menuCommands, ChatCommand_OpenLoadout);
	
	g_loadoutsAmount = KvGetNum(kv, "loadouts_amount", 3);
	
	CloseHandle(kv);
	
	Store_AddMainMenuItem("Loadout", "Loadout Description", _, OnMainMenuLoadoutClick, 10);
}

public void ChatCommand_OpenLoadout(int client)
{
	OpenLoadoutMenu(client);
}

public void OnMainMenuLoadoutClick(int client, const char[] value)
{
	OpenLoadoutMenu(client);
}

public void Event_PlayerSpawn(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (g_clientLoadout[client] == 0 || !IsLoadoutAvailableFor(client, g_clientLoadout[client]))
	{
		FindOptimalLoadoutFor(client);
	}
}

void OpenLoadoutMenu(int client)
{
	/*
	new Handle:filter = CreateTrie();
	SetTrieString(filter, "game", g_game);
	SetTrieValue(filter, "team", GetClientTeam(client));
	
	if (StrEqual(g_game, "tf"))
	{
		new String:className[10];
		TF2_GetClassName(TF2_GetPlayerClass(client), className, sizeof(className));
		SetTrieString(filter, "class", className);
	}
	
	Store_GetLoadouts(filter, GetLoadoutsCallback, true, client);
	*/
	
	Store_GetClientLoadouts(GetSteamAccountID(client), GetClientLoadoutsCallback, client);
}

public bool GetClientLoadoutsCallback(int[] ids, int count, any client)
{
	Handle menu = CreateMenu(LoadoutMenuSelectHandle);
	SetMenuTitle(menu, "Loadout\n \n");
	
	AddMenuItem(menu, "Create", "Create new Loadout");
	
	for (int i = 0; i < count; i++)
	{
		if (i > g_loadoutsAmount)
		{
			continue;
		}
		
		char displayName[STORE_MAX_DISPLAY_NAME_LENGTH];
		Store_GetLoadoutDisplayName(ids[i], displayName, sizeof(displayName));
		
		char itemText[sizeof(displayName) + 3];
		
		if (g_clientLoadout[client] == ids[i])
		{
			strcopy(itemText, sizeof(itemText), "[L] ");
		}
		
		Format(itemText, sizeof(itemText), "%s%s", itemText, displayName);
		
		char itemValue[8];
		IntToString(ids[i], itemValue, sizeof(itemValue));
		
		AddMenuItem(menu, itemValue, itemText);
	}
	
	SetMenuExitBackButton(menu, true);
	DisplayMenu(menu, client, 0);
}

public int LoadoutMenuSelectHandle(Handle menu, MenuAction action, int client, int slot)
{
	switch (action)
	{
		case MenuAction_Select:
			{
				char sMenuItem[64];
				GetMenuItem(menu, slot, sMenuItem, sizeof(sMenuItem));
				
				if (StrEqual(sMenuItem, "Create"))
				{
					
				}
				else
				{
					g_clientLoadout[client] = StringToInt(sMenuItem);			
					SetClientCookie(client, g_lastClientLoadout, sMenuItem);
					
					Call_StartForward(g_clientLoadoutChangedForward);
					Call_PushCell(client);
					Call_Finish();
					
					OpenLoadoutMenu(client);
				}
			}
		case MenuAction_Cancel:
			{
				if (slot == MenuCancel_ExitBack)
				{
					Store_OpenMainMenu(client);
				}
			}
		case MenuAction_End: CloseHandle(menu);
	}
}

bool IsLoadoutAvailableFor(int client, int loadout)
{
	char game[STORE_MAX_LOADOUTGAME_LENGTH];
	Store_GetLoadoutGame(loadout, game, sizeof(game));
	
	if (!StrEqual(game, "") && !StrEqual(game, g_game))
	{
		return false;
	}
	
	if (StrEqual(g_game, "tf"))
	{
		char loadoutClass[STORE_MAX_LOADOUTCLASS_LENGTH];
		Store_GetLoadoutClass(loadout, loadoutClass, sizeof(loadoutClass));
		
		char className[10];
		TF2_GetClassName(TF2_GetPlayerClass(client), className, sizeof(className));
		
		if (!StrEqual(loadoutClass, "") && !StrEqual(loadoutClass, className))
		{
			return false;
		}
	}
	
	int loadoutTeam = Store_GetLoadoutTeam(loadout);
	if (loadoutTeam != -1 && GetClientTeam(client) != loadoutTeam)
	{
		return false;
	}
		
	return true;
}

void FindOptimalLoadoutFor(int client)
{
	if (!g_databaseInitialized)
	{
		return;
	}
	
	Handle filter = CreateTrie();
	SetTrieString(filter, "game", g_game);
	SetTrieValue(filter, "team", GetClientTeam(client));
	
	if (StrEqual(g_game, "tf"))
	{
		char className[10];
		TF2_GetClassName(TF2_GetPlayerClass(client), className, sizeof(className));
		SetTrieString(filter, "class", className);
	}
	
	Store_GetLoadouts(filter, FindOptimalLoadoutCallback, true, GetClientUserId(client));
}

public void FindOptimalLoadoutCallback(int[] ids, int count, any data)
{
	int client = GetClientOfUserId(data);
	
	if (!client)
	{
		return;
	}
	
	if (count > 0)
	{
		g_clientLoadout[client] = ids[0];
		
		char buffer[12];
		IntToString(g_clientLoadout[client], buffer, sizeof(buffer));
		
		SetClientCookie(client, g_lastClientLoadout, buffer);
		
		Call_StartForward(g_clientLoadoutChangedForward);
		Call_PushCell(client);
		Call_Finish();
	}
	else
	{
		Store_LogWarning("No loadout found.");
	}	
}

public int Native_OpenLoadoutMenu(Handle plugin, numParams)
{       
	OpenLoadoutMenu(GetNativeCell(1));
}

public int Native_GetClientsCurrentLoadout(Handle plugin, numParams)
{       
	return g_clientLoadout[GetNativeCell(1)];
}

void TF2_GetClassName(TFClassType classType, char[] buffer, int maxlength)
{
	strcopy(buffer, maxlength, TF2_ClassName[classType]);
}

public int Native_OpenLoadoutsMOTD(Handle plugin, numParams)
{
	OpenLoadoutsMOTD(GetNativeCell(1));
}

void OpenLoadoutsMOTD(int client)
{
	char sURL[128];
	Store_GetStoreBaseURL(sURL, sizeof(sURL));
	
	switch (GetEngineVersion())
	{
		case Engine_CSGO:
		{
			Format(sURL, sizeof(sURL), "%s%s", sURL, CSGO_MOTD);
			ShowMOTDPanel(client, "Store Loadouts Interface", sURL, MOTDPANEL_TYPE_URL);
		}
		
		default:
		{
			char sID[32];
			IntToString(Store_GetClientUserID(client), sID, sizeof(sID));
			
			Format(sURL, sizeof(sURL), "%s%s", sURL, MOTD);
			ReplaceString(sURL, sizeof(sURL), "USERID", sID, true);
			
			Handle Radio = CreateKeyValues("data");
			KvSetString(Radio, "title", "Store Loadouts Interface");
			KvSetString(Radio, "type", "2");
			KvSetString(Radio, "msg", sURL);
			ShowVGUIPanel(client, "info", Radio, false);
			CloseHandle(Radio);
		}
	}
}
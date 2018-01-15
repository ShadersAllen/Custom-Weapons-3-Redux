#pragma semicolon 1
#pragma newdecls required

#define MAX_STEAMIDS_PER_WEAPON 5    // How many people's steamIDs can be listed on a weapon to give Self-Made quality to
#define MAX_STEAMAUTH_LENGTH    21
#define MAX_COMMUNITYID_LENGTH  18

#include <sourcemod>
#include <sourcemod-misc>
#include <tf2_stocks>
#include <sdkhooks>

#include <tf2items>
#include <tf2attributes>

#include <cw3-core-redux>
#include <cw3-attributes-redux>

// TF2 Weapon qualities
enum
{
	TFQual_None = -1,       // Probably should never actually set an item's quality to this
	TFQual_Normal = 0,
	TFQual_NoInspect = 0,   // Players cannot see your attributes
	TFQual_Rarity1,
	TFQual_Genuine = 1,
	TFQual_Rarity2,
	TFQual_Level = 2,       //  Same color as "Level # Weapon" text in description
	TFQual_Vintage,
	TFQual_Rarity3,         //  Is actually 4 - sort of brownish
	TFQual_Rarity4,
	TFQual_Unusual = 5,
	TFQual_Unique,
	TFQual_Community,
	TFQual_Developer,
	TFQual_Selfmade,
	TFQual_Customized,
	TFQual_Strange,
	TFQual_Completed,
	TFQual_Haunted,         //  13
	TFQual_Collectors,
	TFQual_Decorated
}

enum (<<= 1)
{
	EF_BONEMERGE2 = (1 << 0),    // Merges bones of names shared with a parent entity to the position and direction of the parent's.
	EF_BRIGHTLIGHT,             // Emits a dynamic light of RGB(250,250,250) and a random radius of 400 to 431 from the origin.
	EF_DIMLIGHT,                // Emits a dynamic light of RGB(100,100,100) and a random radius of 200 to 231 from the origin.
	EF_NOINTERP,                // Don't interpolate on the next frame.
	EF_NOSHADOW,                // Don't cast a shadow. To do: Does this also apply to shadow maps?
	EF_NODRAW,                  // Entity is completely ignored by the client. Can cause prediction errors if a player proceeds to collide with it on the server.
	EF_NORECEIVESHADOW,         // Don't receive dynamic shadows.
	EF_BONEMERGE_FASTCULL2,      // For use with EF_BONEMERGE2. If set, the entity will use its parent's origin to calculate whether it is visible; if not set, it will set up parent's bones every frame even if the parent is not in the PVS.
	EF_ITEM_BLINK,              // Blink an item so that the user notices it. Added for Xbox 1, and really not very subtle.
	EF_PARENT_ANIMATES2          // Assume that the parent entity is always animating. Causes it to realign every frame.
}

bool bLate;

Handle aItems[TF2_MAX_CLASSES][MAXSLOTS];
Handle fOnWeaponGive;
Handle fOnWeaponEntCreated;
Handle fOnWeaponSwitch;

TFClassType BrowsingClass[MAXPLAYERS + 1];
int BrowsingSlot[MAXPLAYERS + 1];
int LookingAtItem[MAXPLAYERS + 1];
Handle hEquipTimer[MAXPLAYERS + 1];
Handle hBotEquipTimer[MAXPLAYERS + 1];
bool InRespawnRoom[MAXPLAYERS + 1];
int SavedWeapons[MAXPLAYERS + 1][TF2_MAX_CLASSES][MAXSLOTS];
Handle hSavedWeapons[MAXPLAYERS + 1][TF2_MAX_CLASSES][MAXSLOTS];
bool OKToEquipInArena[MAXPLAYERS + 1];

int g_iEntRefOfCustomWearable[MAXPLAYERS + 1][MAXSLOTS];
int g_iWeaponOfExtraWearable[MAX_ENTITY_LIMIT];
bool g_bHasExtraWearable[MAX_ENTITY_LIMIT];

int g_iTheWeaponSlotIWasLastHitBy[MAXPLAYERS + 1] = {-1,...};

bool IsCustom[MAX_ENTITY_LIMIT];

char WeaponName[MAXPLAYERS + 1][MAXSLOTS][64];
char WeaponDescription[MAXPLAYERS + 1][MAXSLOTS][512];

Handle CustomConfig[MAX_ENTITY_LIMIT];

Handle cvarEnabled;
Handle cvarOnlyInSpawn;
Handle cvarArenaSeconds;
Handle cvarBots;
Handle cvarMenu;
Handle cvarOnlyTeam;

bool roundRunning = true;
float arenaEquipUntil;
int weaponcount;

// TODO: Delete this once the wearables plugin is released!
// [
int tiedEntity[MAX_ENTITY_LIMIT]; // Entity to tie the wearable to.
int wearableOwner[MAX_ENTITY_LIMIT]; // Who owns this wearable.
bool onlyVisIfActive[MAX_ENTITY_LIMIT]; // NOT "visible weapon". If true, this wearable is only shown if the weapon is active.
bool hasWearablesTied[MAX_ENTITY_LIMIT]; // If true, this entity has (or did have) at least one wearable tied to it.

Handle g_hSdkEquipWearable;
// ]

public Plugin myinfo =
{
	name = "Custom Weapons 3 - Redux",
	author = "MasterOfTheXP (original cw2 developer), Theray070696 (rewrote cw2 into cw3), Redux by Keith Warren (Drixevel)",
	description = "Allows players to create and use custom-made weapons.",
	version = "1.0.0",
	url = "http://sourcemod.com/"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("cw3-core-redux");

	CreateNative("CW3_GetClientWeapon", Native_GetClientWeapon);
	CreateNative("CW3_GetWeaponConfig", Native_GetWeaponConfig);
	CreateNative("CW3_IsCustom", Native_IsCustom);
	CreateNative("CW3_GetClientWeaponName", Native_GetClientWeaponName);

	CreateNative("CW3_EquipItem", Native_EquipItem);
	CreateNative("CW3_EquipItemByIndex", Native_EquipItemIndex);
	CreateNative("CW3_EquipItemByName", Native_EquipItemName);

	CreateNative("CW3_GetNumItems", Native_GetNumItems);
	CreateNative("CW3_GetItemConfigByIndex", Native_GetItemConfig);
	CreateNative("CW3_GetItemNameByIndex", Native_GetItemName);
	CreateNative("CW3_FindItemByName", Native_FindItemByName);

	fOnWeaponGive = CreateGlobalForward("CW3_OnWeaponSpawned", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
	fOnWeaponEntCreated = CreateGlobalForward("CW3_OnWeaponEntCreated", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Any, Param_Any);
	fOnWeaponSwitch = CreateGlobalForward("CW3_OnWeaponSwitch", ET_Ignore, Param_Cell, Param_Cell);

	bLate = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	CreateConVar("sm_cw3_redux_version", "1.0.0", "Change anything you want, but please don't change this!");
	cvarEnabled = CreateConVar("sm_cw3_enable", "1", "Enable Custom Weapons. When set to 0, custom weapons will be removed from all players.");
	cvarOnlyInSpawn = CreateConVar("sm_cw3_onlyinspawn", "1", "Custom weapons can only be equipped from within a spawn room.");
	cvarArenaSeconds = CreateConVar("sm_cw3_arena_time", "20", "Time, in seconds, after spawning in Arena, that players can still equip custom weapons.");
	cvarBots = CreateConVar("sm_cw3_bots", "0.15", "Percent chance, for each slot, that bots will equip a custom weapon each time they spawn.");
	cvarMenu = CreateConVar("sm_cw3_menu", "1", "Clients are allowed to say /custom to equip weapons manually. Set to 0 to disable manual weapon selection without disabling the entire plugin.");
	cvarOnlyTeam = CreateConVar("sm_cw3_onlyteam", "0", "If non-zero, custom weapons can only be equipped by one team; 2 = RED, 3 = BLU.");

	HookEvent("post_inventory_application", Event_Resupply);
	HookEvent("player_hurt", Event_Hurt);
	HookEvent("player_death", Event_Death, EventHookMode_Pre);
	HookEvent("teamplay_round_start", Event_RoundStart);
	HookEvent("teamplay_round_win", Event_RoundEnd);
	HookEvent("teamplay_round_stalemate", Event_RoundEnd);

	RegAdminCmd("sm_custom", Command_Custom, ADMFLAG_ROOT);
	RegAdminCmd("sm_cus", Command_Custom, ADMFLAG_ROOT);
	RegConsoleCmd("sm_c", Command_Custom);
	RegAdminCmd("sm_reloadweapons", Command_ReloadWeapons, ADMFLAG_ROOT);

	Handle hGameConf = LoadGameConfigFile("tf2items.randomizer");

	if (hGameConf != null)
	{
		StartPrepSDKCall(SDKCall_Player);
		PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CTFPlayer::EquipWearable");
		PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
		g_hSdkEquipWearable = EndPrepSDKCall();

		CloseHandle(hGameConf);
	}

	CreateTimer(1.0, Timer_OneSecond, _, TIMER_REPEAT);

	if (IsValidEntity(0))
	{
		Event_RoundStart(null, "teamplay_round_start", false);
	}
}

public void OnConfigsExecuted()
{
	weaponcount = 0;

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/customweapons");

	if (!DirExists(sPath))
	{
		CreateDirectory(sPath, 511);
	}

	for (TFClassType class = TFClass_Scout; class <= TFClass_Engineer; class++)
	{
		for (int slot = 0; slot <= 4; slot++)
		{
			if (null == aItems[class][slot])
			{
				aItems[class][slot] = CreateArray();
			}
			else
			{
				ClearArray(aItems[class][slot]);
			}
		}
	}

	Handle hDir = OpenDirectory(sPath);

	char FileName[PLATFORM_MAX_PATH];
	FileType type;

	while ((ReadDirEntry(hDir, FileName, sizeof(FileName), type)))
	{
		if (type != FileType_File)
		{
			continue;
		}

		Format(FileName, sizeof(FileName), "%s/%s", sPath, FileName);
		Handle hFile = CreateKeyValues("custom_weapon");

		if (!FileToKeyValues(hFile, FileName))
		{
			PrintToServer("[Custom Weapons 3] WARNING! Something seems to have gone wrong with opening %s. It won't be added to the weapons list.", FileName);
			CloseHandle(hFile);
			CloseHandle(hDir);
			continue;
		}

		if (!KvJumpToKey(hFile, "classes"))
		{
			PrintToServer("[Custom Weapons 3] WARNING! Weapon config %s does not have any classes marked as being able to use the weapon.", FileName);
			CloseHandle(hFile);
			CloseHandle(hDir);
			continue;
		}

		int numClasses;
		for (TFClassType class = TFClass_Scout; class <= TFClass_Engineer; class++)
		{
			int value;
			switch (class)
			{
				case TFClass_Scout: value = KvGetNum(hFile, "scout", -1);
				case TFClass_Soldier: value = KvGetNum(hFile, "soldier", -1);
				case TFClass_Pyro: value = KvGetNum(hFile, "pyro", -1);
				case TFClass_DemoMan: value = KvGetNum(hFile, "demoman", -1);
				case TFClass_Heavy: value = KvGetNum(hFile, "heavy", -1);
				case TFClass_Engineer: value = KvGetNum(hFile, "engineer", -1);
				case TFClass_Medic: value = KvGetNum(hFile, "medic", -1);
				case TFClass_Sniper: value = KvGetNum(hFile, "sniper", -1);
				case TFClass_Spy: value = KvGetNum(hFile, "spy", -1);
			}

			if (value == -1)
			{
				continue;
			}

			PushArrayCell(aItems[class][value], hFile);
			numClasses++;
		}

		if (!numClasses)
		{
			PrintToServer("[Custom Weapons 3] WARNING! Weapon config %s does not have any classes marked as being able to use the weapon.", FileName);
			CloseHandle(hDir);
			continue;
		}

		weaponcount++;
	}

	CloseHandle(hDir);
	PrintToServer("[Custom Weapons 3] Custom Weapons 3 loaded successfully with %i weapons.", weaponcount);

	if (bLate)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i))
			{
				OnClientPostAdminCheck(i);
			}
		}

		bLate = false;
	}
}

public void OnPluginEnd()
{
	RemoveAllCustomWeapons();
}

public void OnClientPostAdminCheck(int client)
{
	BrowsingClass[client] = TFClass_Unknown;
	BrowsingSlot[client] = 0;
	LookingAtItem[client] = 0;
	hEquipTimer[client] = null;
	hBotEquipTimer[client] = null;
	InRespawnRoom[client] = false;
	OKToEquipInArena[client] = false;

	for (int class = 0; class <= view_as<int>(TFClass_Engineer); class++)
	{
		for (int slot = 0; slot <= 4; slot++)
		{
			SavedWeapons[client][class][slot] = -1;
			hSavedWeapons[client][class][slot] = null;
		}
	}

	SDKHook(client, SDKHook_WeaponSwitchPost, OnWeaponSwitch);
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public Action Command_ReloadWeapons(int client, int args)
{
	RemoveAllCustomWeapons();
	OnConfigsExecuted();
	ReplyToCommand(client, "[Custom Weapons 3] Custom Weapons has been reloaded.");
	return Plugin_Handled;
}

public Action Command_Custom(int client, int args)
{
	if (client == 0)
	{
		ReplyToCommand(client, "[Custom Weapons 3] Custom Weapons is loaded with %i weapons.", weaponcount);
		return Plugin_Handled;
	}

	CustomMainMenu(client);
	return Plugin_Handled;
}

void CustomMainMenu(int client)
{
	if (!GetConVarBool(cvarMenu))
	{
		return;
	}

	Handle menu = CreateMenu(CustomMainHandler);

	//int counts[MAXSLOTS];
	TFClassType class;

	if (IsPlayerAlive(client))
	{
		class = TF2_GetPlayerClass(client);
	}
	else
	{
		class = view_as<TFClassType>(GetEntProp(client, Prop_Send, "m_iDesiredPlayerClass"));
	}

	SetMenuTitle(menu, "Custom Weapons 3 Beta");

	for (int i = 0; i < MAXSLOTS; i++)
	{
		if (aItems[class][i] == null)
		{
			continue;
		}

		int size = GetArraySize(aItems[class][i]);
		//counts[i] = size;

		//if (counts[i] > 0)  If there are weapons for this slot, add a menu select for them.
		if (size > 0)
		{
			switch (i)
			{
				case 0: AddMenuItem(menu, "0", "- Primary -");   // First string is the weapon slot it applies to, second string is what's displayed in the menu.
				case 1: AddMenuItem(menu, "1", "- Secondary -"); // This is necessary because it's possible to have custom primaries, but no custom secondaries.
				case 2: AddMenuItem(menu, "2", "- Melee -");
				case 3:
				{
					switch (class)
					{
						case TFClass_Engineer:  AddMenuItem(menu, "3", "- Build PDA -");
						case TFClass_Spy:       AddMenuItem(menu, "3", "- Disguise Kit -");
					}
				}
				case 4:
				{
					switch (class)
					{
						case TFClass_Engineer:  AddMenuItem(menu, "4", "- Destroy PDA -");
						case TFClass_Spy:       AddMenuItem(menu, "4", "- Cloak -");
					}
				}
			}
		}
	}

	//AddMenuItem(menu, "5", "- Recommended Loadouts -");

	/*for (int i = 0; i < MAXSLOTS; i++)
	{
		counts[i] = GetArraySize(aItems[class][i]);

		if (counts[i])
		{
			switch (i)
			{
				case 0: SetMenuTitle(menu, "Custom Weapons 3 Indev\n- Primary -");
				case 1: SetMenuTitle(menu, "Custom Weapons 3 Indev\n- Secondary -");
				case 2: SetMenuTitle(menu, "Custom Weapons 3 Indev\n- Melee -");
				case 3: SetMenuTitle(menu, "Custom Weapons 3 Indev\n- PDA -");
				case 4: SetMenuTitle(menu, "Custom Weapons 3 Indev\n- PDA 2 -");
			}

			break;
		}
	}

	for (int slot = 0; slot <= 4; slot++)
	{
	if (!counts[slot])
	{
	continue;
	}

	int saved = SavedWeapons[client][class][slot];
	for (int i = 0; i < counts[slot]; i++)
	{
	Handle hWeapon = GetArrayCell(aItems[class][slot], i);
	char Name[64];
	char Index[TF2_MAX_CLASSES];
	char flags[64];
	bool canUseWeapon;

	KvRewind(hWeapon);
	KvGetString(hWeapon, "flags", flags, sizeof(flags));

	if (strlen(flags) == 0)
	{
	KvRewind(hWeapon);
	KvGetString(hWeapon, "flag", flags, sizeof(flags));
	}

	KvRewind(hWeapon);
	if (KvJumpToKey(hWeapon, "flag") || KvJumpToKey(hWeapon, "flags"))
	{
	AdminId adminID = GetUserAdmin(client);

	if (adminID != INVALID_ADMIN_ID)
	{
	AdminFlag adminFlags[AdminFlags_TOTAL];
	int flagBits = ReadFlagString(flags);
	FlagBitsToArray(flagBits, adminFlags, AdminFlags_TOTAL);

	for (int j = 0; j < AdminFlags_TOTAL; j++)
	{
	if (GetAdminFlag(adminID, adminFlags[j]) && !canUseWeapon)
	{
	canUseWeapon = true;
	}
	}
	}
	else
	{
	canUseWeapon = false;
	}
	}
	else
	{
	canUseWeapon = true;
	}

	if (!canUseWeapon)
	{
	continue;
	}

	KvRewind(hWeapon);
	KvGetSectionName(hWeapon, Name, sizeof(Name));

	if (saved == i)
	{
	Format(Name, sizeof(Name), "%s ✓", Name);
	}

	Format(Index, sizeof(Index), "%i %i", slot, i);

	if (i == counts[slot] - 1 && slot < 4)
	{
	int nextslot;

	for (int j = slot+1; j <= 4; j++)
	{
	if (counts[j])
	{
	nextslot = j;
	break;
	}
	}

	switch (nextslot)
	{
	case 1: Format(Name, sizeof(Name), "%s\n- Secondary -", Name);
	case 2: Format(Name, sizeof(Name), "%s\n- Melee -", Name);
	case 3: Format(Name, sizeof(Name), "%s\n- PDA -", Name);
	case 4: Format(Name, sizeof(Name), "%s\n- PDA 2 -", Name);
	}
	}

	AddMenuItem(menu, Index, Name);
	}
	}*/

	if (GetMenuItemCount(menu) == 0)
	{
		PrintToChat(client, "\x01\x07FFA07AThis server doesn't have any custom weapons for your class yet. Sorry!");
	}

	BrowsingClass[client] = class;
	SetMenuPagination(menu, MENU_NO_PAGINATION);

	SetMenuExitButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public int CustomMainHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			if (param2 == 5)
			{
				PrintToChat(param1, "This feature is currently a WiP, sorry!");
				CustomMainMenu(param1);
				return;
			}

			if (BrowsingClass[param1] != TF2_GetPlayerClass(param1))
			{
				CustomMainMenu(param1);
				return;
			}

			/* char sel[20];
			GetMenuItem(menu, param2, sel, sizeof(sel));

			char sIdxs[2][TF2_MAX_CLASSES];
			ExplodeString(sel, " ", sIdxs, sizeof(sIdxs), sizeof(sIdxs));
			WeaponInfoMenu(param1, BrowsingClass[param1], StringToInt(sIdxs[0]), StringToInt(sIdxs[1]));*/

			char szSlot[2];
			GetMenuItem(menu, param2, szSlot, sizeof(szSlot));
			int iSlot = StringToInt(szSlot);

			WeaponSelectMenu(param1, iSlot);
		}
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

void WeaponSelectMenu(int iClient, int iSlot)
{
	if (iSlot == -1 || iClient == -1)
	{
		return;
	}

	int counts[MAXSLOTS];
	counts[iSlot] = GetArraySize(aItems[BrowsingClass[iClient]][iSlot]);

	Handle hWeaponSelectMenu = CreateMenu(WeaponSelectHandler);

	switch (iSlot)
	{
		case 0: SetMenuTitle(hWeaponSelectMenu, "- Primary Custom Weapons -");   // First string is the weapon slot it applies to, second string is what's displayed in the menu.
		case 1: SetMenuTitle(hWeaponSelectMenu, "- Secondary Custom Weapons -"); // This is necessary because it's possible to have custom primaries, but no custom secondaries.
		case 2: SetMenuTitle(hWeaponSelectMenu, "- Melee Custom Weapons -");
		case 3:
		{
			switch (BrowsingClass[iClient])
			{
				case TFClass_Engineer:  SetMenuTitle(hWeaponSelectMenu, "- Build PDA Custom Weapons -");
				case TFClass_Spy:       SetMenuTitle(hWeaponSelectMenu, "- Disguise Kit Custom Weapons -");
			}
		}
		case 4:
		{
			switch (BrowsingClass[iClient])
			{
				case TFClass_Engineer:  SetMenuTitle(hWeaponSelectMenu, "- Destroy PDA Custom Weapons -");
				case TFClass_Spy:       SetMenuTitle(hWeaponSelectMenu, "- Cloak Custom Weapons -");
			}
		}
	}

	int saved = SavedWeapons[iClient][BrowsingClass[iClient]][iSlot];
	for (int i = 0; i < counts[iSlot]; i++) // Loop through the number of weapons for this slot
	{
		Handle hWeapon = GetArrayCell(aItems[BrowsingClass[iClient]][iSlot], i);
		KvRewind(hWeapon);

		char Name[64];
		KvGetSectionName(hWeapon, Name, sizeof(Name)); // Get the name of the weapon

		if (saved == i)
		{
			Format(Name, sizeof(Name), "%s ✓", Name);
		}

		char Index[40];
		Format(Index, sizeof(Index), "%i %i", iSlot, i);

		/*if (i == counts[iSlot] - 1 && iSlot < 4)
		{
		int nextslot;
		for (int j = iSlot+1; j <= 4; j++)
		{
		if (counts[j])
		{
		nextslot = j;
		break;
	}
}

switch (nextslot)
{
case 1: Format(Name, sizeof(Name), "%s\n- Secondary -", Name);
case 2: Format(Name, sizeof(Name), "%s\n- Melee -", Name);
case 3: Format(Name, sizeof(Name), "%s\n- PDA -", Name);
case 4: Format(Name, sizeof(Name), "%s\n- PDA 2 -", Name);
}
}*/

		AddMenuItem(hWeaponSelectMenu, Index, Name);
	}

	SetMenuExitBackButton(hWeaponSelectMenu, true);

	DisplayMenu(hWeaponSelectMenu, iClient, MENU_TIME_FOREVER);
}

public int WeaponSelectHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			if (BrowsingClass[param1] != TF2_GetPlayerClass(param1))
			{
				CustomMainMenu(param1);
				return;
			}

			char sel[40];
			GetMenuItem(menu, param2, sel, sizeof(sel));

			if (StringToInt(sel) == -1) // Chose to return to Main menu.
			{
				CustomMainMenu(param1);
				return;
			}

			char sIdxs[2][40];
			ExplodeString(sel, " ", sIdxs, sizeof(sIdxs), sizeof(sIdxs[]));

			WeaponInfoMenu(param1, BrowsingClass[param1], StringToInt(sIdxs[0]), StringToInt(sIdxs[1]));
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				CustomMainMenu(param1);
			}
		}
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

void WeaponInfoMenu(int client, TFClassType class, int slot, int weapon, float delay = -1.0)
{
	if (!GetConVarBool(cvarMenu))
	{
		return;
	}

	if (delay != -1.0)
	{
		Handle data;
		CreateDataTimer(delay, Timer_WeaponInfoMenu, data, TIMER_FLAG_NO_MAPCHANGE);
		WritePackCell(data, GetClientUserId(client));
		WritePackCell(data, view_as<int>(class));
		WritePackCell(data, slot);
		WritePackCell(data, weapon);
		ResetPack(data);
		return;
	}

	if (class != TF2_GetPlayerClass(client))
	{
		CustomMainMenu(client);
		return;
	}

	Handle menu = CreateMenu(WeaponInfoHandler);
	Handle hWeapon = GetArrayCell(aItems[class][slot], weapon);

	KvRewind(hWeapon);

	char Name[64];
	KvGetSectionName(hWeapon, Name, sizeof(Name));

	KvSetEscapeSequences(hWeapon, true);

	char description[512];
	KvGetString(hWeapon, "description", description, sizeof(description));

	KvSetEscapeSequences(hWeapon, false);

	ReplaceString(description, sizeof(description), "\\n", "\n");
	SetMenuTitle(menu, "%s\n \n%s\n ", Name, description);

	//AddMenuItem(menu, "", "Use", ITEMDRAW_DEFAULT);

	if (IsPlayerAlive(client))
	{
		if (hWeapon != hSavedWeapons[client][class][slot])
		{
			bool equipped;
			for (int i = 0; i <= 2; i++)
			{
				int wep = GetPlayerWeaponSlot(client, i);

				if (wep == -1)
				{
					continue;
				}

				if (!IsCustom[wep])
				{
					continue;
				}

				if (CustomConfig[wep] != hWeapon)
				{
					continue;
				}

				equipped = true;
				break;
			}
			if (equipped)
			{
				AddMenuItem(menu, "", "Save", ITEMDRAW_DEFAULT);
			}
			else
			{
				AddMenuItem(menu, "", "Save & Equip", ITEMDRAW_DEFAULT);
			}
		}
		else
		{
			AddMenuItem(menu, "", "Unequip", ITEMDRAW_DEFAULT);
		}
	}
	else
	{
		if (hWeapon != hSavedWeapons[client][class][slot])
		{
			AddMenuItem(menu, "", "Save", ITEMDRAW_DEFAULT);
		}
		else
		{
			AddMenuItem(menu, "", "Unequip", ITEMDRAW_DEFAULT);
		}
	}

	AddMenuItem(menu, "", "", ITEMDRAW_SPACER);
	AddMenuItem(menu, "", "Prev Weapon", weapon ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	AddMenuItem(menu, "", "Next Weapon", weapon != GetArraySize(aItems[class][slot])-1 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

	SetMenuExitBackButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);

	BrowsingClass[client] = class;
	BrowsingSlot[client] = slot;
	LookingAtItem[client] = weapon;
	strcopy(WeaponName[client][slot], sizeof(Name), Name);
	strcopy(WeaponDescription[client][slot], sizeof(description), description);
}

public int WeaponInfoHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			switch (param2)
			{
				case 0:
				{
					TFClassType class = BrowsingClass[param1];
					int slot = BrowsingSlot[param1];
					int index = LookingAtItem[param1];
					int onlyteam = GetConVarInt(cvarOnlyTeam);
					Handle hWeaponConfig = GetArrayCell(aItems[class][slot], index);

					if (hWeaponConfig != null)
					{
						KvRewind(hWeaponConfig);

						char adminFlagsStr[12];
						KvGetString(hWeaponConfig, "flags", adminFlagsStr, sizeof(adminFlagsStr));

						if (strlen(adminFlagsStr) == 0)
						{
							KvRewind(hWeaponConfig);
							KvGetString(hWeaponConfig, "flag", adminFlagsStr, sizeof(adminFlagsStr));
						}

						KvRewind(hWeaponConfig);
						bool canUseWeapon;

						if (KvJumpToKey(hWeaponConfig, "flag") || KvJumpToKey(hWeaponConfig, "flags"))
						{
							AdminId adminID = GetUserAdmin(param1);

							if (adminID != INVALID_ADMIN_ID)
							{
								AdminFlag adminFlags[AdminFlags_TOTAL];
								int flagBits = ReadFlagString(adminFlagsStr);
								FlagBitsToArray(flagBits, adminFlags, AdminFlags_TOTAL);

								for (int j = 0; j < AdminFlags_TOTAL; j++)
								{
									if (GetAdminFlag(adminID, adminFlags[j]) && !canUseWeapon)
									{
										canUseWeapon = true;
									}
								}
							}
							else
							{
								canUseWeapon = false;
							}
						}
						else
						{
							canUseWeapon = true;
						}

						if (!canUseWeapon)
						{
							PrintToChat(param1, "[CW3] Sorry! This weapon is restricted so only certain people can use it!");
							return;
						}
					}

					if (index != SavedWeapons[param1][class][slot])
					{
						SavedWeapons[param1][class][slot] = index;
						hSavedWeapons[param1][class][slot] = GetArrayCell(aItems[class][slot], index);

						bool equipped;
						int weapon = GetPlayerWeaponSlot(param1, slot);

						// This might be confusing, but here we go...
						if (IsValidEntity(weapon))
						{
							if (IsCustom[weapon] && CustomConfig[weapon] == hSavedWeapons[param1][class][slot])
							{
								equipped = true;
							}
						}

						// They don't have it equipped, they're alive, and...
						// "OnlyTeam" is off, or their team is the only team that can equip, and...
						// they're in a respawn room, OR they can equip weapons whenever, OR...
						// it's the beginning of an Arena round.
						if (!equipped && IsPlayerAlive(param1) && (!onlyteam || onlyteam == GetClientTeam(param1)) && (InRespawnRoom[param1] || !GetConVarBool(cvarOnlyInSpawn) || (IsArenaActive() && OKToEquipInArena[param1] && arenaEquipUntil >= GetTickedTime())))
						{
							GiveCustomWeaponByIndex(param1, class, slot, index);
						}
					}
					else
					{
						SavedWeapons[param1][class][slot] = -1;
						hSavedWeapons[param1][class][slot] = null;
						WeaponName[param1][slot][0] = '\0';
						WeaponDescription[param1][slot][0] = '\0';
					}

					WeaponInfoMenu(param1, class, slot, index, 0.2);
				}
				case 2: WeaponInfoMenu(param1, BrowsingClass[param1], BrowsingSlot[param1], LookingAtItem[param1] - 1);
				case 3: WeaponInfoMenu(param1, BrowsingClass[param1], BrowsingSlot[param1], LookingAtItem[param1] + 1);
			}
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				CustomMainMenu(param1);
			}
		}
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

public Action Timer_WeaponInfoMenu(Handle timer, Handle data)
{
	int client = GetClientOfUserId(ReadPackCell(data));

	if (client == 0)
	{
		return;
	}

	TFClassType class = view_as<TFClassType>(ReadPackCell(data));
	int slot = ReadPackCell(data);
	int weapon = ReadPackCell(data);

	WeaponInfoMenu(client, class, slot, weapon);
}

int GiveCustomWeaponByIndex(int client, TFClassType class, int slot, int weapon, bool makeActive = true, bool checkClass = true)
{
	if (checkClass && class != TF2_GetPlayerClass(client))
	{
		return -1;
	}

	Handle hConfig = GetArrayCell(aItems[class][slot], weapon);

	if (hConfig == null)
	{
		ThrowError("Weapon %i in slot %i for class %i is invalid", weapon, slot, class);
		return -1;
	}

	return GiveCustomWeapon(client, hConfig, makeActive);
}

int GiveCustomWeapon(int client, Handle hConfig, bool makeActive = true)
{
	if (!IsValidClient(client))
	{
		return -1;
	}

	TFClassType class = TF2_GetPlayerClass(client);

	KvRewind(hConfig);

	char adminFlagsStr[12];
	KvGetString(hConfig, "flags", adminFlagsStr, sizeof(adminFlagsStr));

	if (strlen(adminFlagsStr) == 0)
	{
		KvRewind(hConfig);
		KvGetString(hConfig, "flag", adminFlagsStr, sizeof(adminFlagsStr));
	}

	KvRewind(hConfig);

	bool canUseWeapon;
	if (KvJumpToKey(hConfig, "flag") || KvJumpToKey(hConfig, "flags"))
	{
		AdminId adminID = GetUserAdmin(client);
		if (adminID != INVALID_ADMIN_ID)
		{
			AdminFlag adminFlags[AdminFlags_TOTAL];
			int flagBits = ReadFlagString(adminFlagsStr);
			FlagBitsToArray(flagBits, adminFlags, AdminFlags_TOTAL);

			for (int j = 0; j < AdminFlags_TOTAL; j++)
			{
				if(GetAdminFlag(adminID, adminFlags[j]) && !canUseWeapon)
				{
					canUseWeapon = true;
				}
			}
		}
		else
		{
			canUseWeapon = false;
		}
	}
	else
	{
		canUseWeapon = true;
	}

	if (!canUseWeapon)
	{
		return -1;
	}

	KvRewind(hConfig);

	char name[96];
	KvGetSectionName(hConfig, name, sizeof(name));

	char baseClass[64];
	KvGetString(hConfig, "baseclass", baseClass, sizeof(baseClass));
	int baseIndex = KvGetNum(hConfig, "baseindex", -1);
	int itemQuality = KvGetNum(hConfig, "quality", TFQual_Customized);
	int itemLevel = KvGetNum(hConfig, "level", -1);

	char szSteamIDList[(MAX_STEAMAUTH_LENGTH * MAX_STEAMIDS_PER_WEAPON) + (MAX_STEAMIDS_PER_WEAPON * 2)];
	KvGetString(hConfig, "steamids", szSteamIDList, sizeof(szSteamIDList));

	bool forcegen = view_as<bool>(KvGetNum(hConfig, "forcegen", view_as<bool>(false)));

	int mag = KvGetNum(hConfig, "mag", -1);

	if (mag == -1)
	{
		mag = KvGetNum(hConfig, "clip", -1); // add support for using clip instead of magazine
	}

	int ammo = KvGetNum(hConfig, "ammo", -1);
	int metal = KvGetNum(hConfig, "metal", -1);

	char szExplode[MAXSLOTS][MAX_STEAMAUTH_LENGTH]; // SteamIDs are separated by commas,,,,
	ExplodeString(szSteamIDList, ",", szExplode, sizeof(szExplode), sizeof(szExplode[]));

	for (int i = 0; i < MAX_STEAMIDS_PER_WEAPON; i++) // Give selfmade quality to creators of weapons, regardless of whatever quality was set.
	{
		if (!IsClientAuthorized(client))
		{
			break;
		}

		AuthIdType iAuthId = GetSteamIdAuthType(szExplode[i]);

		char sSteamID[MAX_STEAMAUTH_LENGTH];
		GetClientAuthId(client, iAuthId, sSteamID, sizeof(sSteamID));

		if (StrEqual(sSteamID, szExplode[i]))
		{
			itemQuality = TFQual_Selfmade;
			break;
		}
	}

	int slot = -1;
	if (KvJumpToKey(hConfig, "classes"))
	{
		char sClass[32];
		TF2_GetClientClassName(client, sClass, sizeof(sClass));

		slot = KvGetNum(hConfig, sClass, -1);

		if (slot == -1)
		{
			for (TFClassType i = TFClass_Scout; i <= TFClass_Engineer; i++)
			{
				TF2_GetClassName(i, sClass, sizeof(sClass));
				slot = KvGetNum(hConfig, sClass, -1);

				if (slot != -1)
				{
					break;
				}
			}
		}

		if (slot == -1)
		{
			ThrowError("Slot could not be determined for weapon \"%s\"", name);
		}
	}

	KvRewind(hConfig);

	if (ammo == -1)
	{
		if (KvJumpToKey(hConfig, "ammo-classes"))
		{
			char sClass[32];
			TF2_GetClientClassName(client, sClass, sizeof(sClass));
			ammo = KvGetNum(hConfig, sClass, -1);
		}

		KvRewind(hConfig);
	}

	bool bWearable = false;

	if (StrEqual(baseClass, "wearable_demoshield", false))
	{
		bWearable = view_as<bool>(2);
	}
	else if (StrEqual(baseClass, "wearable", false))
	{
		bWearable = true;
	}

	if (!bWearable)
	{
		if (StrEqual(baseClass, "saxxy", false))
		{
			switch (class)
			{
				case TFClass_Scout: Format(baseClass, sizeof(baseClass), "bat");
				case TFClass_Soldier: Format(baseClass, sizeof(baseClass), "shovel");
				case TFClass_DemoMan: Format(baseClass, sizeof(baseClass), "bottle");
				case TFClass_Engineer: Format(baseClass, sizeof(baseClass), "wrench");
				case TFClass_Medic: Format(baseClass, sizeof(baseClass), "bonesaw");
				case TFClass_Sniper: Format(baseClass, sizeof(baseClass), "club");
				case TFClass_Spy: Format(baseClass, sizeof(baseClass), "knife");
				default: Format(baseClass, sizeof(baseClass), "fireaxe");
			}
		}
		else if (StrEqual(baseClass, "shotgun", false))
		{
			switch (class)
			{
				case TFClass_Scout: Format(baseClass, sizeof(baseClass), "scattergun");
				case TFClass_Soldier, TFClass_DemoMan: Format(baseClass, sizeof(baseClass), "shotgun_soldier");
				case TFClass_Pyro: Format(baseClass, sizeof(baseClass), "shotgun_pyro");
				case TFClass_Heavy: Format(baseClass, sizeof(baseClass), "shotgun_hwg");
				default: Format(baseClass, sizeof(baseClass), "shotgun_primary");
			}
		}
		else if (StrEqual(baseClass, "pistol", false) && TFClass_Scout == class)
		{
			Format(baseClass, sizeof(baseClass), "pistol_scout");
		}

		Format(baseClass, sizeof(baseClass), "tf_weapon_%s", baseClass);
	}
	else
	{
		Format(baseClass, sizeof(baseClass), "tf_%s", baseClass);
	}

	int flags = OVERRIDE_ALL;

	if (forcegen)
	{
		flags |= FORCE_GENERATION;
	}

	Handle hWeapon = TF2Items_CreateItem(flags);
	TF2Items_SetClassname(hWeapon, baseClass);
	TF2Items_SetItemIndex(hWeapon, baseIndex);

	if (KvJumpToKey(hConfig, "level"))
	{
		TF2Items_SetLevel(hWeapon, itemLevel);
	}
	else
	{
		TF2Items_SetLevel(hWeapon, 1);
	}

	KvRewind(hConfig);

	TF2Items_SetQuality(hWeapon, itemQuality);

	int numAttributes;
	if (KvJumpToKey(hConfig, "attributes") && KvGotoFirstSubKey(hConfig))
	{
		do {
			char szPlugin[64];
			KvGetString(hConfig, "plugin", szPlugin, sizeof(szPlugin));

			if (!StrEqual(szPlugin, "tf2items", false))
			{
				continue;
			}

			char Att[64];
			KvGetSectionName(hConfig, Att, sizeof(Att));

			char Value[64];
			KvGetString(hConfig, "value", Value, sizeof(Value));

			TF2Items_SetAttribute(hWeapon, numAttributes++, StringToInt(Att), StringToFloat(Value));
		}
		while (KvGotoNextKey(hConfig));
	}

	KvRewind(hConfig);

	TF2Items_SetNumAttributes(hWeapon, numAttributes);

	TF2_RemoveWeaponSlot(client, slot);
	if (!slot || slot == 1) // primary and secondary
	{
		int i = -1;

		while ((i = FindEntityByClassname(i, "tf_wearable*")) != -1)
		{
			if (client != GetEntPropEnt(i, Prop_Send, "m_hOwnerEntity") || GetEntProp(i, Prop_Send, "m_bDisguiseWearable"))
			{
				continue;
			}

			if (!slot)
			{
				switch (GetEntProp(i, Prop_Send, "m_iItemDefinitionIndex"))
				{
					case 405, 608: TF2_RemoveWearable(client, i);
				}
			}
			else
			{
				switch (GetEntProp(i, Prop_Send, "m_iItemDefinitionIndex"))
				{
					case 57, 231, 642, 133, 444, 131, 406, 1099, 1144: TF2_RemoveWearable(client, i);
				}
			}
		}
	}

	int ent = TF2Items_GiveNamedItem(client, hWeapon);
	CloseHandle(hWeapon);

	g_iEntRefOfCustomWearable[client][slot] = -1;

	if (bWearable)
	{
		switch (bWearable)
		{
			case 2:
			{
				if (KvJumpToKey(hConfig, "worldmodel"))
				{
					char ModelName[PLATFORM_MAX_PATH];
					KvGetString(hConfig, "modelname", ModelName, sizeof(ModelName));

					if (ModelName[0] != '\0' && FileExists(ModelName, true))
					{
						SetModelIndex(ent, ModelName);
						CreateWearable(client, ModelName, true);
					}
				}

				KvRewind(hConfig);
			}
			case 1:
			{
				if (KvJumpToKey(hConfig, "worldmodel"))
				{
					char ModelName[PLATFORM_MAX_PATH];
					KvGetString(hConfig, "modelname", ModelName, sizeof(ModelName));

					if (ModelName[0] != '\0' && FileExists(ModelName, true))
					{
						SetModelIndex(ent, ModelName);
						g_iEntRefOfCustomWearable[client][slot] = EntIndexToEntRef(ent);
					}
				}

				KvRewind(hConfig);
			}
		}

		TF2_EquipWearable(client, ent);

		ClientCommand(client, "slot3"); // Switch to melee
		OnWeaponSwitch(client, GetPlayerWeaponSlot(client, TFWeaponSlot_Melee));
	}
	else
	{
		EquipPlayerWeapon(client, ent);
	}

	if (itemQuality == TFQual_Selfmade && !KvJumpToKey(hConfig, "nosparkle"))
	{
		TF2Attrib_SetByName(ent, "attach particle effect", 4.0);
		TF2Attrib_SetByName(ent, "selfmade description", 1.0);
	}

	if (ammo != -1)
	{
		SetAmmo(client, ent, ammo);
	}

	if (mag != -1)
	{
		SetClip(ent, mag);
	}

	if (metal != -1)
	{
		SetEntProp(client, Prop_Data, "m_iAmmo", metal, 4, 3);
	}

	KvRewind(hConfig);

	if (KvJumpToKey(hConfig, "backpack"))
	{
		char szModelName[PLATFORM_MAX_PATH];
		KvGetString(hConfig, "modelname", szModelName, sizeof(szModelName));

		if (szModelName[0] != '\0' && FileExists(szModelName, true))
		{
			int iExtraWearable = EquipWearable(client, szModelName, false, 0, false);

			if (iExtraWearable != -1)
			{
				g_iWeaponOfExtraWearable[iExtraWearable] = ent;

				int effects = GetEntProp(iExtraWearable, Prop_Send, "m_fEffects");
				SetEntProp(iExtraWearable, Prop_Send, "m_fEffects", effects & ~EF_NODRAW); // Ensures that it'll be visible
			}

			g_bHasExtraWearable[ent] = true;

			int attachment = KvGetNum(hConfig, "attachment", -1);
			if (attachment > -1)
			{
				SetEntProp(iExtraWearable, Prop_Send, "m_fEffects", 0);
				SetEntProp(iExtraWearable, Prop_Send, "m_iParentAttachment", attachment);

				float offs[3];
				KvGetVector(hConfig, "pos", offs);

				float angOffs[3];
				KvGetVector(hConfig, "ang", angOffs);

				float scale = KvGetFloat(hConfig, "scale", 1.0);

				SetEntPropVector(iExtraWearable, Prop_Send, "m_vecOrigin", offs);
				SetEntPropVector(iExtraWearable, Prop_Send, "m_angRotation", angOffs);

				if (scale != 1.0)
				{
					SetEntPropFloat(iExtraWearable, Prop_Send, "m_flModelScale", scale);
				}
			}

			int m_hExtraWearable = GetEntPropEnt(ent, Prop_Send, "m_hExtraWearable");
			if (IsValidEntity(m_hExtraWearable))
			{
				int replace = KvGetNum(hConfig, "replace", 1);
				if (replace == 1)
				{
					SetEntityRenderMode(m_hExtraWearable, RENDER_TRANSCOLOR);
					SetEntityRenderColor(m_hExtraWearable, 0, 0, 0, 0);
				}
				else if (replace == 2)
				{
					SetEntPropFloat(m_hExtraWearable, Prop_Send, "m_flModelScale", 0.0);
				}
				else if (replace == 3)
				{
					SetEntPropEnt(ent, Prop_Send, "m_hExtraWearable", iExtraWearable);
					TF2_RemoveWearable(client, m_hExtraWearable);
				}
			}
		}
	}

	IsCustom[ent] = true;
	CustomConfig[ent] = hConfig;

	Call_StartForward(fOnWeaponEntCreated);
	Call_PushCell(ent);
	Call_PushCell(slot);
	Call_PushCell(client);
	Call_PushCell(view_as<int>(bWearable));
	Call_PushCell(view_as<int>(makeActive));
	Call_Finish();

	if (StrEqual(baseClass, "tf_weapon_sapper", false) || StrEqual(baseClass, "tf_weapon_builder", false))
	{
		SetEntProp(ent, Prop_Send, "m_iObjectType", 3);
		SetEntProp(ent, Prop_Data, "m_iSubType", 3);
	}

	if (!bWearable)
	{
		if (makeActive && !StrEqual(baseClass, "tf_weapon_invis", false))
		{
			ClientCommand(client, "slot%i", slot+1);
			OnWeaponSwitch(client, ent);
		}
		else
		{
			OnWeaponSwitch(client, GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon"));
		}
	}

	Action act = Plugin_Continue;
	Call_StartForward(fOnWeaponGive);
	Call_PushCell(ent);
	Call_PushCell(slot);
	Call_PushCell(client);
	Call_Finish(act);

	return ent;
}

public void OnWeaponSwitch(int client, int weapon)
{
	if (!IsValidEntity(weapon))
	{
		return;
	}

	Call_StartForward(fOnWeaponSwitch);
	Call_PushCell(client);
	Call_PushCell(weapon);
	Call_Finish();

	// TODO: Delete this once the wearables plugin is released!
	int i = -1;
	while ((i = FindEntityByClassname(i, "tf_wearable*")) != -1)
	{
		if (!onlyVisIfActive[i] || client != wearableOwner[i])
		{
			continue;
		}

		int effects = GetEntProp(i, Prop_Send, "m_fEffects");

		if (weapon == tiedEntity[i])
		{
			SetEntProp(i, Prop_Send, "m_fEffects", effects & ~32);
		}
		else
		{
			SetEntProp(i, Prop_Send, "m_fEffects", effects |= 32);
		}
	}
}

public void OnEntityDestroyed(int ent)
{
	if (ent <= 0 || ent > 2048)
	{
		return;
	}

	IsCustom[ent] = false;
	CustomConfig[ent] = null;

	g_iWeaponOfExtraWearable[ent] = -1;
	g_bHasExtraWearable[ent] = false;

	// TODO: Delete this once the wearables plugin is released!
	if (ent <= 0 || ent > 2048)
	{
		return;
	}

	if (hasWearablesTied[ent])
	{
		int i = -1;
		while ((i = FindEntityByClassname(i, "tf_wearable*")) != -1)
		{
			if (ent != tiedEntity[i])
			{
				continue;
			}

			if (IsValidClient(wearableOwner[ent]))
			{
				TF2_RemoveWearable(wearableOwner[ent], i);
			}
			else
			{
				AcceptEntityInput(i, "Kill"); // This can cause graphical glitches
			}
		}

		hasWearablesTied[ent] = false;
	}

	tiedEntity[ent] = 0;
	wearableOwner[ent] = 0;
	onlyVisIfActive[ent] = false;
}

public Action Event_Resupply(Handle event, const char[] name, bool dontBroadcast)
{
	int uid = GetEventInt(event, "userid");
	int client = GetClientOfUserId(uid);

	if (!GetConVarBool(cvarEnabled) || client == 0)
	{
		return;
	}

	hEquipTimer[client] = CreateTimer(0.0, Timer_CheckEquip, uid, TIMER_FLAG_NO_MAPCHANGE);
	hBotEquipTimer[client] = CreateTimer(GetRandomFloat(0.0, 1.5), Timer_CheckBotEquip, uid, TIMER_FLAG_NO_MAPCHANGE);

	for (int i = 0; i < MAXSLOTS; i++)
	{
		g_iEntRefOfCustomWearable[client][i] = -1;
	}
}

public Action OnTakeDamage(int iVictim, int &iAtker, int &iInflictor, float &flDamage, int &iDmgType, int &iWeapon, float vDmgForce[3], float vDmgPos[3], int iDmgCustom)
{
	if (0 < iAtker && iAtker <= MaxClients)
	{
		g_iTheWeaponSlotIWasLastHitBy[iVictim] = GetWeaponEntitySlot(iAtker, iWeapon);
	}

	return Plugin_Continue;
}

void DisplayDeathMenu(int iKiller, int iVictim, TFClassType iAtkClass, int iAtkSlot)
{
	if (iAtkSlot == -1 || iAtkSlot > 4 || iAtkClass == TFClass_Unknown || iKiller == iVictim || !IsValidClient(iKiller)) // In event_death, iVictim will surely be valid at this point
	{
		return;
	}

	int weapon = GetPlayerWeaponSlot(iKiller, iAtkSlot);

	if(weapon == -1 || !IsCustom[weapon] || WeaponName[iKiller][iAtkSlot][0] == '\0' || WeaponDescription[iKiller][iAtkSlot][0] == '\0')
	{
		return;
	}

	Handle hMenu = CreateMenu(MenuHandler_Null);
	SetMenuTitle(hMenu, "%s\n \n%s", WeaponName[iKiller][iAtkSlot], WeaponDescription[iKiller][iAtkSlot]);

	AddMenuItem(hMenu, "exit", "Close");

	SetMenuPagination(hMenu, MENU_NO_PAGINATION);
	SetMenuExitButton(hMenu, false);
	DisplayMenu(hMenu, iVictim, 8); // 8 second lasting menu
}

public Action Event_Death(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));

	if (!IsValidClient(client))
	{
		return Plugin_Continue;
	}

	int iKiller = GetClientOfUserId(GetEventInt(event, "attacker"));

	if (iKiller && IsValidClient(iKiller) && g_iTheWeaponSlotIWasLastHitBy[client] != -1) // TODO: Test this vs environmental deaths and whatnot.
	{
		char szWeaponLogClassname[64];
		GetValueFromConfig(iKiller, g_iTheWeaponSlotIWasLastHitBy[client], "logname", szWeaponLogClassname, sizeof(szWeaponLogClassname));

		if (szWeaponLogClassname[0] != '\0')
		{
			SetEventString(event, "weapon_logclassname", szWeaponLogClassname);
		}
	}

	if (GetEventInt(event, "death_flags") & TF_DEATHFLAG_DEADRINGER)
	{
		return Plugin_Continue;
	}

	if (IsValidClient(iKiller))
	{
		DisplayDeathMenu(iKiller, client, TF2_GetPlayerClass(iKiller), g_iTheWeaponSlotIWasLastHitBy[client]);
	}

	g_iTheWeaponSlotIWasLastHitBy[client] = -1;

	return Plugin_Continue;
}

public int MenuHandler_Null(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		CloseHandle(menu);
	}
}

public Action Event_Hurt(Handle event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));

	if (victim > 0)
	{
		OKToEquipInArena[victim] = false;
	}

	if (attacker > 0)
	{
		OKToEquipInArena[attacker] = false;
	}
}

bool GetValueFromConfig(int iClient, int iSlot, const char[] szKey, char[] szValue, int iszValueSize)
{
	int iClass = view_as<int>(TF2_GetPlayerClass(iClient));

	if (!IsValidClient(iClient) || iSlot > 4 || SavedWeapons[iClient][iClass][iSlot] == -1 || aItems[iClass][iSlot] == null)
	{
		return false;
	}

	Handle hConfig = GetArrayCell(aItems[iClass][iSlot], SavedWeapons[iClient][iClass][iSlot]);

	if (hConfig == null)
	{
		return false;
	}

	KvRewind(hConfig);

	if (StrEqual(szKey, "name"))
	{
		return KvGetSectionName(hConfig, szValue, iszValueSize);
	}
	else
	{
		KvGetString(hConfig, szKey, szValue, iszValueSize);
	}

	return false;
}

public Action Timer_CheckEquip(Handle timer, any data)
{
	int client = GetClientOfUserId(data);

	if (!GetConVarBool(cvarEnabled) || client == 0 || timer != hEquipTimer[client] || !IsPlayerAlive(client))
	{
		return;
	}

	TFClassType class = TF2_GetPlayerClass(client);
	for (int slot = 0; slot <= 4; slot++)
	{
		if (SavedWeapons[client][class][slot] > -1)
		{
			GiveCustomWeaponByIndex(client, class, slot, SavedWeapons[client][class][slot], false);
		}
	}
}

public Action Timer_CheckBotEquip(Handle timer, any data)
{
	int client = GetClientOfUserId(data);

	if (!GetConVarBool(cvarEnabled) || client == 0 || timer != hBotEquipTimer[client])
	{
		return;
	}

	if (IsFakeClient(client) && IsPlayerAlive(client))
	{
		TFClassType class = TF2_GetPlayerClass(client);
		int maxSlots = (class == TFClass_Engineer || class == TFClass_Spy) ? 4 : 2;
		float weaponChance = GetConVarFloat(cvarBots);

		for (int slot = 0; slot <= maxSlots; slot++)
		{
			if (GetRandomFloat(0.0, 1.0) > weaponChance)
			{
				continue;
			}

			int numItems = GetArraySize(aItems[class][slot]);

			if (!numItems)
			{
				continue;
			}

			Handle aOptions = CreateArray();
			for (int i = 0; i < numItems; i++)
			{
				Handle hConfig = GetArrayCell(aItems[class][slot], i);
				KvRewind(hConfig);

				if (KvGetNum(hConfig, "nobots"))
				{
					continue;
				}

				PushArrayCell(aOptions, i);
			}

			int numOptions = GetArraySize(aOptions);

			if (!numOptions)
			{
				continue;
			}

			int choice = GetArrayCell(aOptions, GetRandomInt(0, numOptions-1));
			CloseHandle(aOptions);

			GiveCustomWeaponByIndex(client, class, slot, choice, false);
		}
	}
}

public void Event_RoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	roundRunning = true;

	for (int client = 1; client <= MaxClients; client++)
	{
		InRespawnRoom[client] = false;
	}

	int i = -1;
	while ((i = FindEntityByClassname(i, "func_respawnroom")) != -1)
	{
		SDKHook(i, SDKHook_TouchPost, OnTouchRespawnRoom);
		SDKHook(i, SDKHook_StartTouchPost, OnTouchRespawnRoom);
		SDKHook(i, SDKHook_EndTouch, OnEndTouchRespawnRoom);
	}

	if (event != null && IsArenaActive())
	{
		arenaEquipUntil = GetTickedTime() + GetConVarFloat(cvarArenaSeconds);

		for (int j = 1; j <= MaxClients; j++)
		{
			OKToEquipInArena[j] = true;
		}
	}
}

public void Event_RoundEnd(Handle event, const char[] name, bool dontBroadcast)
{
	roundRunning = false;
}

public void OnTouchRespawnRoom(int entity, int other)
{
	if (other < 1 || other > MaxClients || !IsClientInGame(other) || !IsPlayerAlive(other) || !roundRunning)
	{
		return;
	}

	InRespawnRoom[other] = true;
}

public void OnEndTouchRespawnRoom(int entity, int other)
{
	if (other < 1 || other > MaxClients || !IsClientInGame(other) || !IsPlayerAlive(other) || !roundRunning)
	{
		return;
	}

	InRespawnRoom[other] = false;
}

public Action Timer_OneSecond(Handle timer)
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || IsFakeClient(client) || !IsPlayerAlive(client))
		{
			continue;
		}

		if (GetEntProp(client, Prop_Send, "m_nNumHealers") > 0)
		{
			char customHealers[256];
			int numCustomHealers;

			for (int i = 1; i <= MaxClients; i++)
			{
				if (client == i || !IsClientInGame(i) || !IsPlayerAlive(i) || client != TF2_GetHealingTarget(i))
				{
					continue;
				}

				int medigun = GetPlayerWeaponSlot(i, 1);

				if (!IsCustom[medigun])
				{
					continue;
				}

				KvRewind(CustomConfig[medigun]);

				char name[64];
				KvGetSectionName(CustomConfig[medigun], name, sizeof(name));

				Format(customHealers, sizeof(customHealers), "%s%s%N is using: %s", customHealers, numCustomHealers++ ? "\n" : "", i, name);
			}

			if (numCustomHealers)
			{
				PrintHintText(client, customHealers);
			}
		}
	}
}

// NATIVES

public int Native_GetClientWeapon(Handle plugin, int args)
{
	int client = GetNativeCell(1);
	int slot = GetNativeCell(2);

	if (!IsValidClient(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client index %i is invalid", client);
	}

	int wep = GetPlayerWeaponSlot(client, slot);

	return IsCustom[wep] ? (view_as<int>(CustomConfig[wep])) : 0;
}

public int Native_GetWeaponConfig(Handle plugin, int args)
{
	int weapon = GetNativeCell(1);

	if (weapon == -1)
	{
		return 0;
	}

	return IsCustom[weapon] ? (view_as<int>(CustomConfig[weapon])) : 0;
}

public int Native_IsCustom(Handle plugin, int args)
{
	int wep = GetNativeCell(1);

	if (wep <= -1)
	{
		return false;
	}

	return IsCustom[wep];
}

public int Native_GetClientWeaponName(Handle plugin, int args)
{
	int client = GetNativeCell(1);
	int slot = GetNativeCell(2);
	int namelen = GetNativeCell(4);

	if (!IsValidClient(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client index %i is invalid", client);
	}

	int wep = GetPlayerWeaponSlot(client, slot);

	if (!IsCustom[wep])
	{
		SetNativeString(3, "", GetNativeCell(4));
		return false;
	}

	KvRewind(CustomConfig[wep]);

	char[] name = new char[namelen];
	KvGetSectionName(CustomConfig[wep], name, namelen);

	SetNativeString(3, name, namelen);
	return true;
}

public int Native_EquipItem(Handle plugin, int args)
{
	int client = GetNativeCell(1);
	Handle weapon = view_as<Handle>(GetNativeCell(2));
	bool makeActive = GetNativeCell(3);

	if (!IsValidClient(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client index %i is invalid", client);
	}

	return GiveCustomWeapon(client, weapon, makeActive);
}

public int Native_EquipItemIndex(Handle plugin, int args)
{
	int client = GetNativeCell(1);
	TFClassType class = view_as<TFClassType>(GetNativeCell(2));
	int slot = GetNativeCell(3);
	int index = GetNativeCell(4);
	bool makeActive = GetNativeCell(5);
	bool checkClass = GetNativeCell(6);

	if (!IsValidClient(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client index %i is invalid", client);
	}

	if (class < TFClass_Scout || class > TFClass_Engineer)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Player class index %i is invalid", class);
	}

	return GiveCustomWeaponByIndex(client, class, slot, index, makeActive, checkClass);
}

public int Native_EquipItemName(Handle plugin, int args)
{
	int client = GetNativeCell(1);

	char name[96];
	GetNativeString(2, name, sizeof(name));

	bool makeActive = GetNativeCell(3);

	if (!IsValidClient(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client index %i is invalid", client);
	}

	TFClassType myClass = TF2_GetPlayerClass(client);
	TFClassType class2; // Loop through all classes -- first by the player's class, then other classes in order

	do
	{
		TFClassType class = (class2 == view_as<TFClassType>(0) ? myClass : class2);

		if (class2 == myClass)
		{
			continue;
		}

		for (int i = 0; i <= MAXSLOTS; i++) // Slots
		{
			int num = GetArraySize(aItems[class][i]);

			for (int j = 0; j < num; j++)
			{
				Handle hConfig = GetArrayCell(aItems[class][i], j);
				KvRewind(hConfig);

				char jName[96];
				KvGetSectionName(hConfig, jName, sizeof(jName));

				if (StrEqual(name, jName, false))
				{
					return GiveCustomWeapon(client, hConfig, makeActive);
				}
			}
		}
	}
	while (++class2 < view_as<TFClassType>(10));

	return -1;
}

public int Native_GetNumItems(Handle plugin, int args)
{
	TFClassType class = view_as<TFClassType>(GetNativeCell(1));
	int slot = GetNativeCell(2);

	if (class < TFClass_Scout || class > TFClass_Engineer)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Player class index %i is invalid", class);
	}

	return GetArraySize(aItems[class][slot]);
}

public int Native_GetItemConfig(Handle plugin, int args)
{
	TFClassType class = view_as<TFClassType>(GetNativeCell(1));
	int slot = GetNativeCell(2);
	int index = GetNativeCell(3);

	if (class < TFClass_Scout || class > TFClass_Engineer)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Player class index %i is invalid", class);
	}

	return GetArrayCell(aItems[class][slot], index);
}

public int Native_GetItemName(Handle plugin, int args)
{
	TFClassType class = view_as<TFClassType>(GetNativeCell(1));
	int slot = GetNativeCell(2);
	int index = GetNativeCell(3);
	int namelen = GetNativeCell(5);

	if (class < TFClass_Scout || class > TFClass_Engineer)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Player class index %i is invalid", class);
	}

	Handle hWeapon = GetArrayCell(aItems[class][slot], index);
	KvRewind(hWeapon);

	char[] name = new char[namelen];
	KvGetSectionName(hWeapon, name, namelen);

	int bytes;
	SetNativeString(4, name, namelen, _, bytes);

	return bytes;
}

public int Native_FindItemByName(Handle plugin, int args)
{
	char name[96];
	GetNativeString(1, name, sizeof(name));

	for (TFClassType class = TFClass_Scout; class <= TFClass_Engineer; class++)
	{
		for (int i = 0; i < MAXSLOTS; i++) // Slots
		{
			int num = GetArraySize(aItems[class][i]);

			for (int j = 0; j < num; j++)
			{
				Handle hConfig = GetArrayCell(aItems[class][i], j);
				KvRewind(hConfig);

				char jName[96];
				KvGetSectionName(hConfig, jName, sizeof(jName));

				if (StrEqual(name, jName, false))
				{
					return view_as<int>(hConfig);
				}
			}
		}
	}

	return 0;
}

void RemoveAllCustomWeapons()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i))
		{
			int health = GetClientHealth(i);
			TF2_RegeneratePlayer(i);
			SetEntityHealth(i, health);
		}
	}
}

int EquipWearable(int client, char[] Mdl, bool vm, int weapon = 0, bool visactive = true)
{
	int wearable = CreateWearable(client, Mdl, vm);

	if (!IsValidEntity(wearable))
	{
		return wearable;
	}

	wearableOwner[wearable] = client;

	if (weapon > MaxClients)
	{
		tiedEntity[wearable] = weapon;
		hasWearablesTied[weapon] = true;
		onlyVisIfActive[wearable] = visactive;

		int effects = GetEntProp(wearable, Prop_Send, "m_fEffects");

		if (weapon == GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon"))
		{
			SetEntProp(wearable, Prop_Send, "m_fEffects", effects & ~32);
		}
		else
		{
			SetEntProp(wearable, Prop_Send, "m_fEffects", effects |= 32);
		}
	}

	return wearable;
}

int CreateWearable(int client, char[] model, bool vm) // Randomizer code :3
{
	int entity = CreateEntityByName(vm ? "tf_wearable_vm" : "tf_wearable");

	if (!IsValidEntity(entity))
	{
		return entity;
	}

	SetEntProp(entity, Prop_Send, "m_nModelIndex", PrecacheModel(model));
	SetEntProp(entity, Prop_Send, "m_fEffects", 129);
	SetEntProp(entity, Prop_Send, "m_iTeamNum", GetClientTeam(client));
	SetEntProp(entity, Prop_Send, "m_usSolidFlags", 4);
	SetEntProp(entity, Prop_Send, "m_CollisionGroup", 11);

	DispatchSpawn(entity);

	SetVariantString("!activator");
	ActivateEntity(entity);

	TF2_EquipWearable(client, entity);
	return entity;
}

void TF2_EquipWearable(int client, int entity)
{
	if (g_hSdkEquipWearable == null)
	{
		LogMessage("Error: Can't call EquipWearable, SDK functions not loaded!");
		return;
	}

	SDKCall(g_hSdkEquipWearable, client, entity);
}

AuthIdType GetSteamIdAuthType(const char[] szId)
{
	if (StrContains(szId, "STEAM_0:") != -1)
	{
		return AuthId_Steam2;
	}

	if (StrContains(szId, "[U:1:") != -1)
	{
		return AuthId_Steam3;
	}

	if (StrContains(szId, "7656119") != -1)
	{
		return AuthId_SteamID64;
	}

	return view_as<AuthIdType>(-1);
}

void SetModelIndex(int entity, char[] model)
{
	if (IsValidEntity(entity))
	{
		SetEntProp(entity, Prop_Send, "m_nModelIndex", PrecacheModel(model));
	}
}

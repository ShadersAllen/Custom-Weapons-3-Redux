#pragma semicolon 1

#include <tf2_stocks>
#include <sdkhooks>
#include <cw3-core-redux>

public Plugin myinfo =
{
	name = "Custom Weapons 3 - Redux: Models Application",
	author = "MasterOfTheXP (original cw2 developer), Theray070696 (rewrote cw2 into cw3), Redux by Keith Warren (Drixevel)",
	description = "Applies custom models to weapons.",
	version = "1.0.0",
	url = "http://sourcemod.com/"
};

bool HasCustomViewmodel[2049];
int ViewmodelOfWeapon[2049];
bool HasCustomWorldmodel[2049];
int WorldmodelOfWeapon[2049];

// TODO: Delete this once the wearables plugin is released!
// [
int tiedEntity[2049]; // Entity to tie the wearable to.
int wearableOwner[2049]; // Who owns this wearable.
bool onlyVisIfActive[2049]; // NOT "visible weapon". If true, this wearable is only shown if the weapon is active.
bool hasWearablesTied[2049]; // If true, this entity has (or did have) at least one wearable tied to it.

bool g_bSdkStarted = false;
Handle g_hSdkEquipWearable;
// ]

public void OnPluginStart()
{
	HookEvent("player_death", Event_Death, EventHookMode_Pre);
	
	TF2_SdkStartup();
}

public void CW3_OnWeaponEntCreated(int weapon, int slot, int client, bool wearable, bool makeActive)
{
	if (wearable)
	{
		return;
	}
	
	TFClassType class = TF2_GetPlayerClass(client);
	Handle hConfig = CW3_GetWeaponConfig(weapon);
	
	if (hConfig == null)
	{
		hConfig = CW3_GetClientWeapon(client, slot);
		
		if (hConfig == null)
		{
			return;
		}
	}
	
	KvRewind(hConfig);
	
	if (KvJumpToKey(hConfig, "viewmodel"))
	{
		char ModelName[PLATFORM_MAX_PATH];
		KvGetString(hConfig, "modelname", ModelName, sizeof(ModelName));
		
		if (StrContains(ModelName, "models/", false))
		{
			Format(ModelName, sizeof(ModelName), "models/%s", ModelName);
		}
		
		if (-1 == StrContains(ModelName, ".mdl", false))
		{
			Format(ModelName, sizeof(ModelName), "%s.mdl", ModelName);
		}
		
		if (strlen(ModelName) && FileExists(ModelName, true))
		{
			int vm = EquipWearable(client, ModelName, true, weapon, true);
			
			if (vm > -1)
			{
				ViewmodelOfWeapon[vm] = weapon;
			}
			
			char arms[PLATFORM_MAX_PATH];
			switch (class)
			{
			case TFClass_Scout: Format(arms, sizeof(arms), "models/weapons/c_models/c_scout_arms.mdl");
			case TFClass_Soldier: Format(arms, sizeof(arms), "models/weapons/c_models/c_soldier_arms.mdl");
			case TFClass_Pyro: Format(arms, sizeof(arms), "models/weapons/c_models/c_pyro_arms.mdl");
			case TFClass_DemoMan: Format(arms, sizeof(arms), "models/weapons/c_models/c_demo_arms.mdl");
			case TFClass_Heavy: Format(arms, sizeof(arms), "models/weapons/c_models/c_heavy_arms.mdl");
			case TFClass_Engineer: Format(arms, sizeof(arms), "models/weapons/c_models/c_engineer_arms.mdl");
			case TFClass_Medic: Format(arms, sizeof(arms), "models/weapons/c_models/c_medic_arms.mdl");
			case TFClass_Sniper: Format(arms, sizeof(arms), "models/weapons/c_models/c_sniper_arms.mdl");
			case TFClass_Spy: Format(arms, sizeof(arms), "models/weapons/c_models/c_spy_arms.mdl");
			}
			
			if (strlen(arms) > 0 && FileExists(arms, true))
			{
				PrecacheModel(arms, true);
				int armsVm = EquipWearable(client, arms, true, weapon, true);
				
				if (armsVm > -1)
				{
					ViewmodelOfWeapon[armsVm] = weapon;
				}
			}
			
			HasCustomViewmodel[weapon] = true;
			int attachment = KvGetNum(hConfig, "attachment", -1);
			
			if (attachment > -1)
			{
				SetEntProp(vm, Prop_Send, "m_fEffects", 0);
				SetEntProp(vm, Prop_Send, "m_iParentAttachment", attachment);
				
				float offs[3];
				KvGetVector(hConfig, "pos", offs);
				
				float angOffs[3];
				KvGetVector(hConfig, "ang", angOffs);
				
				float flScale = KvGetFloat(hConfig, "scale", 1.0);
				
				SetEntPropVector(vm, Prop_Send, "m_vecOrigin", offs);
				SetEntPropVector(vm, Prop_Send, "m_angRotation", angOffs);
				
				if (flScale != 1.0)
				{
					SetEntPropFloat(vm, Prop_Send, "m_flModelScale", flScale);
				}
			}
		}
	}
	
	KvRewind(hConfig);
	
	if (KvJumpToKey(hConfig, "worldmodel"))
	{
		new String:ModelName[PLATFORM_MAX_PATH];
		KvGetString(hConfig, "modelname", ModelName, sizeof(ModelName));
		
		if (StrContains(ModelName, "models/", false))
		{
			Format(ModelName, sizeof(ModelName), "models/%s", ModelName);
		}
		
		if (-1 == StrContains(ModelName, ".mdl", false))
		{
			Format(ModelName, sizeof(ModelName), "%s.mdl", ModelName);
		}
		
		if (strlen(ModelName) && FileExists(ModelName, true))
		{
			int model = PrecacheModel(ModelName, true);
			
			SetEntProp(weapon, Prop_Send, "m_iWorldModelIndex", model);
			SetEntProp(weapon, Prop_Send, "m_nModelIndexOverrides", model, _, 0);
		}
	}
}

public void CW3_OnWeaponSwitch(int client, int Wep)
{
	if (!IsValidEntity(Wep))
	{
		return;
	}
	
	if (HasCustomViewmodel[Wep])
	{
		SetEntProp(GetEntPropEnt(client, Prop_Send, "m_hViewModel"), Prop_Send, "m_fEffects", 32);
	}
	
	// TODO: Delete this once the wearables plugin is released!
	
	int entity = INVALID_ENT_REFERENCE;
	while ((entity = FindEntityByClassname(entity, "tf_wearable*")) != INVALID_ENT_REFERENCE)
	{
		if (!onlyVisIfActive[entity])
		{
			continue;
		}
		
		if (client != wearableOwner[entity])
		{
			continue;
		}
		
		int effects = GetEntProp(entity, Prop_Send, "m_fEffects");
		
		if (Wep == tiedEntity[entity])
		{
			SetEntProp(entity, Prop_Send, "m_fEffects", effects & ~32);
		}
		else
		{
			SetEntProp(entity, Prop_Send, "m_fEffects", effects |= 32);
		}
	}
}

public void OnEntityDestroyed(int entity)
{
	if (entity <= 0 || entity > 2048)
	{
		return;
	}
	
	HasCustomViewmodel[entity] = false;
	ViewmodelOfWeapon[entity] = 0;
	HasCustomWorldmodel[entity] = false;
	WorldmodelOfWeapon[entity] = 0;
	
	// TODO: Delete this once the wearables plugin is released!
	if (entity <= 0 || entity > 2048)
	{
		return;
	}
	
	if (hasWearablesTied[entity])
	{	
		int entity2 = INVALID_ENT_REFERENCE;
		while ((entity2 = FindEntityByClassname(entity2, "tf_wearable*")) != INVALID_ENT_REFERENCE)
		{
			if (entity != tiedEntity[entity2])
			{
				continue;
			}
			
			if (IsValidClient(wearableOwner[entity]))
			{
				TF2_RemoveWearable(wearableOwner[entity], entity2);
			}
			else
			{
				AcceptEntityInput(entity2, "Kill"); // This can cause graphical glitches
			}
		}
		
		hasWearablesTied[entity] = false;
	}
	
	tiedEntity[entity] = 0;
	wearableOwner[entity] = 0;
	onlyVisIfActive[entity] = false;
}

public Action Event_Death(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if (client == 0)
	{
		return Plugin_Continue;
	}

	if (GetEventInt(event, "death_flags") & TF_DEATHFLAG_DEADRINGER)
	{
		return Plugin_Continue;
	}

	int entity = INVALID_ENT_REFERENCE;
	while ((entity = FindEntityByClassname(entity, "tf_wearable*")) != INVALID_ENT_REFERENCE)
	{
		if (!tiedEntity[entity])
		{
			continue;
		}
		
		if (client != GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity"))
		{
			continue;
		}
		
		if (GetEntProp(entity, Prop_Send, "m_bDisguiseWearable"))
		{
			continue;
		}
		
		TF2_RemoveWearable(client, entity);
	}

	return Plugin_Continue;
}

// Wearable crap, ripped out of my bad private wearables plugin
// TODO: Create a nice public plugin to make this into a native which all plugins can use.

stock int EquipWearable(int client, char[] Mdl, bool vm, int weapon = 0, bool visactive = true)
{
	// ^ bad name probably
	int wearable = CreateWearable(client, Mdl, vm);
	
	if (wearable == -1)
	{
		return -1;
	}
	
	wearableOwner[wearable] = client;
	
	if (weapon > MaxClients)
	{
		tiedEntity[wearable] = weapon;
		hasWearablesTied[weapon] = true;
		onlyVisIfActive[wearable] = visactive;
		
		new effects = GetEntProp(wearable, Prop_Send, "m_fEffects");
		
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

stock int CreateWearable(int client, char[] model, bool vm) // Randomizer code :3
{
	new entity = CreateEntityByName(vm ? "tf_wearable_vm" : "tf_wearable");
	
	if (!IsValidEntity(entity))
	{
		return -1;
	}
	
	SetEntProp(entity, Prop_Send, "m_nModelIndex", PrecacheModel(model));
	SetEntProp(entity, Prop_Send, "m_fEffects", 129);
	SetEntProp(entity, Prop_Send, "m_iTeamNum", GetClientTeam(client));
	SetEntProp(entity, Prop_Send, "m_usSolidFlags", 4);
	SetEntProp(entity, Prop_Send, "m_CollisionGroup", 11);
	
	DispatchSpawn(entity);
	
	SetVariantString("!activator");
	ActivateEntity(entity);
	
	TF2_EquipWearable(client, entity); // urg
	return entity;
}

// *sigh*
stock void TF2_EquipWearable(int client, int entity)
{
	if (g_bSdkStarted == false || g_hSdkEquipWearable == null)
	{
		TF2_SdkStartup();
		LogMessage("Error: Can't call EquipWearable, SDK functions not loaded! If it continues to fail, reload plugin or restart server. Make sure your gamedata is intact!");
		return;
	}
	
	SDKCall(g_hSdkEquipWearable, client, entity);
}

stock bool TF2_SdkStartup()
{
	Handle hGameConf = LoadGameConfigFile("tf2items.randomizer");
	
	if (hGameConf == null)
	{
		LogMessage("Couldn't load SDK functions (GiveWeapon). Make sure tf2items.randomizer.txt is in your gamedata folder! Restart server if you want wearable weapons.");
		return false;
	}
	
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CTFPlayer::EquipWearable");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	g_hSdkEquipWearable = EndPrepSDKCall();

	CloseHandle(hGameConf);
	g_bSdkStarted = true;
	return true;
}

stock bool IsValidClient(int client)
{
	return (0 < client && client <= MaxClients && IsClientInGame(client));
}
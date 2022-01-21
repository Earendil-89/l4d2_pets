/**
 * ================================================================================ *
 *                               [L4D2] Zombie pets                                 *
 * -------------------------------------------------------------------------------- *
 *  Author      :   Eärendil                                                        *
 *  Descrp      :   Survivors can have a zombie pet following them                  *
 *  Version     :   1.0                                                             *
 *  Link        :   https://forums.alliedmods.net/showthread.php?t=336006           *
 * ================================================================================ *
 *                                                                                  *
 *  CopyRight (C) 2022 Eduardo "Eärendil" Chueca                                    *
 * -------------------------------------------------------------------------------- *
 *  This program is free software; you can redistribute it and/or modify it under   *
 *  the terms of the GNU General Public License, version 3.0, as published by the   *
 *  Free Software Foundation.                                                       *
 *                                                                                  *
 *  This program is distributed in the hope that it will be useful, but WITHOUT     *
 *  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS   *
 *  FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more          *
 *  details.                                                                        *
 *                                                                                  *
 *  You should have received a copy of the GNU General Public License along with    *
 *  this program.  If not, see <http://www.gnu.org/licenses/>.                      *
 * ================================================================================ *
 */

#pragma semicolon 1 
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <dhooks>
#include <left4dhooks>

#define FCVAR_FLAGS FCVAR_NOTIFY
#define PLUGIN_VERSION "1.0"
#define GAMEDATA "l4d2_pets"
#define PET_LIMIT 16

ConVar g_hAllow;
ConVar g_hGameModes;			
ConVar g_hCurrGamemode;			
ConVar g_hFlags;
ConVar g_hGlobPetLim;
ConVar g_hPlyPetLim;
ConVar g_hPetFree;
ConVar g_hPetColor;

bool g_bAllowedGamemode;
bool g_bPluginOn;
int g_iFlags;
int g_iGlobPetLim;
int g_iPlyPetLim;
int g_iOwner[MAXPLAYERS+1];		// Who owns this pet?
Handle g_hDetThreat, g_hDetThreatL4D1, g_hDetTarget;

// Plugin Info
public Plugin myinfo =
{
	name = "[L4D2] Pets",
	author = "Eärendil",
	description = "Survivors can have a zombie pet following them.",
	version = PLUGIN_VERSION,
	url = "",
};

// Load plugin if is a L4D or L4D2 server
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	if( GetEngineVersion() == Engine_Left4Dead2 )
		return APLRes_Success;
	
	strcopy(error, err_max, "Plugin only supports Left 4 Dead 1 & 2");
	return APLRes_SilentFailure;
}

// Plugin Start
public void OnPluginStart()
{
	CreateConVar("l4d2_pets_version",			PLUGIN_VERSION,			"Zombie pets version",			FCVAR_NOTIFY|FCVAR_DONTRECORD);
	
	g_hAllow =		CreateConVar("l4d2_pets_enable",				"1",					"1 = Plugin On. 0 = Plugin Off.", FCVAR_FLAGS, true, 0.0, true, 1.0);
	g_hGameModes =	CreateConVar("l4d2_pets_gamemodes",				"",						"Enable plugin in these gamemodes, separated by commas, no spaces.", FCVAR_FLAGS);
	g_hFlags =		CreateConVar("l4d2_pets_flags",					"",						"Flags required for a player to create a pet, empty to allow everyone.", FCVAR_FLAGS);
	g_hGlobPetLim =	CreateConVar("l4d2_pets_global_limit",			"4",					"Maximum amount of pets allowed in game.", FCVAR_FLAGS, true, 0.0, true, float(PET_LIMIT));
	g_hPlyPetLim =	CreateConVar("l4d2_pets_player_limit",			"1",					"Maximum amount of pets each player can have.", FCVAR_FLAGS, true, 0.0, true, float(PET_LIMIT));
	g_hPetFree =	CreateConVar("l4d2_pets_ownerdeath_action",		"0",					"What will happen to the pet if its owner dies?\n0 = Kill pet.\n1 = Transfer to random survivor.\n2 = Make it wild.", FCVAR_FLAGS, true, 0.0, true, 2.0);
	g_hPetColor =	CreateConVar("l4d2_pets_opacity",				"235",					"Opacity of the pet.", FCVAR_FLAGS, true, 0.0, true, 255.0);

	g_hCurrGamemode = FindConVar("mp_gamemode");
	
	g_hAllow.AddChangeHook(CvarChange_Enable);
	g_hGameModes.AddChangeHook(CvarChange_Enable);
	g_hCurrGamemode.AddChangeHook(CvarChange_Enable);
	g_hFlags.AddChangeHook(CVarChange_Cvars);
	g_hGlobPetLim.AddChangeHook(CVarChange_Cvars);
	g_hPlyPetLim.AddChangeHook(CVarChange_Cvars);
	
	AutoExecConfig(true, "l4d2_pets");
	
	RegConsoleCmd("sm_pet", CmdSayPet, "Create a charger pet that will follow survivor.");
	
	// Setting DHooks
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "gamedata/%s.txt", GAMEDATA);
	if( FileExists(sPath) == false ) SetFailState("\n==========\nMissing required file: \"%s\".\nRead installation instructions again.\n==========", sPath);

	Handle hGameData = LoadGameConfigFile(GAMEDATA);
	if( hGameData == null ) SetFailState("Failed to load \"%s.txt\" gamedata.", GAMEDATA);

	g_hDetThreat = DHookCreateFromConf(hGameData, "SurvivorBehavior::SelectMoreDangerousThreat");
	if( !g_hDetThreat ) SetFailState("Failed to find \"SurvivorBehavior::SelectMoreDangerousThreat\" signature.");
	
	g_hDetTarget = DHookCreateFromConf(hGameData, "SurvivorAttack::SelectTarget");
	if( !g_hDetTarget ) SetFailState("Failed to find \"SurvivorAttack::SelectTarget\" signature.");
	
	g_hDetThreatL4D1 = DHookCreateFromConf(hGameData, "L4D1SurvivorBehavior::SelectMoreDangerousThreat");
	if( !g_hDetThreat ) SetFailState("Failed to find \"L4D1SurvivorBehavior::SelectMoreDangerousThreat\" signature.");
	
	delete hGameData;
}

public void OnMapStart()
{
	for( int i = 1; i < MaxClients; i++ )
		g_iOwner[i] = 0;
}

public void OnConfigsExecuted()
{
	GetGameMode();
	SwitchPlugin();
	ConVars();
}

public void OnClientDisconnect(int client)
{
	for( int i = 1; i < MaxClients; i++ )
	{
		if( g_iOwner[i] != 0 )
		{
			g_iOwner[i] = 0;
			ForcePlayerSuicide(i);
		}
	}
}

public void OnPluginEnd()
{
	for( int i = 1; i < MaxClients; i++ )
	{
		if( g_iOwner[i] != 0 )
			ForcePlayerSuicide(i);
	}
}
//==========================================================================================
//										ConVars
//==========================================================================================
 
public void CvarChange_Enable(Handle conVar, const char[] oldValue, const char[] newValue)
{
	GetGameMode();
	SwitchPlugin();
}

public void CVarChange_Cvars(Handle conVar, const char[] oldValue, const char[] newValue)
{
	ConVars();
}

void GetGameMode()
{
	char sCurrGameMode[32], sGameModes[128];
	g_hCurrGamemode.GetString(sCurrGameMode, sizeof(sCurrGameMode));
	g_hGameModes.GetString(sGameModes, sizeof(sGameModes));

	if( sGameModes[0] )
	{
		char sBuffer[32][32];
		if( ExplodeString(sGameModes, ",", sBuffer, sizeof(sBuffer), sizeof(sBuffer[])) == 0 )
		{
			g_bAllowedGamemode = true;
			return;
		}
		
		for( int i = 0; i < sizeof(sBuffer); i++ )
		{
			if( StrEqual(sBuffer[i], sCurrGameMode, false) )
			{
				g_bAllowedGamemode = true;
				return;
			}
		}
		// No match = Not allowed Gamemode
		g_bAllowedGamemode = false;
		return;
	}
	
	g_bAllowedGamemode = true;
}

void SwitchPlugin()
{
	if( g_bPluginOn == false && g_hAllow.BoolValue == true && g_bAllowedGamemode == true )
	{
		g_bPluginOn = true;
		HookEvent("round_start", Event_Round_Start, EventHookMode_PostNoCopy);
		HookEvent("player_death", Event_Player_Death);
		HookEvent("player_bot_replace", Event_Player_Replaced);
		HookEvent("bot_player_replace", Event_Bot_Replaced);
		
		if( !DHookEnableDetour(g_hDetThreat, true, SelectThreat_Post) )
			SetFailState("Failed to detour \"SurvivorBehavior::SelectMoreDangerousThreat\".");
		
		if( !DHookEnableDetour(g_hDetThreatL4D1, true, SelectThreat_Post) )
			SetFailState("Failed to detour \"L4D1SurvivorBehavior::SelectMoreDangerousThreat\".");

		if( !DHookEnableDetour(g_hDetTarget, true, SelectTarget_Post) )
			SetFailState("Failed to detour \"SurvivorAttack::SelectTarget\".");	
	}
	
	if( g_bPluginOn == true && (g_hAllow.BoolValue == false || g_bAllowedGamemode == false) )
	{
		g_bPluginOn = false;
		UnhookEvent("round_start", Event_Round_Start);
		UnhookEvent("player_death", Event_Player_Death);
		UnhookEvent("player_bot_replace", Event_Player_Replaced);
		UnhookEvent("bot_player_replace", Event_Bot_Replaced);

		DHookDisableDetour(g_hDetThreat,		true, SelectThreat_Post);
		DHookDisableDetour(g_hDetThreatL4D1,	true, SelectThreat_Post);
		DHookDisableDetour(g_hDetTarget,		true, SelectTarget_Post);
		
		for( int i = 1; i < MaxClients; i++ )
		{
			if( g_iOwner[i] != 0 )
			{
				g_iOwner[i] = 0;
				ForcePlayerSuicide(i);
			}
		}
	}
}

void ConVars()
{
	char sBuffer[32], sBuffer2[4][8];
	g_hFlags.GetString(sBuffer, sizeof(sBuffer));
	g_iFlags = ReadFlagString(sBuffer);
	g_iGlobPetLim = g_hGlobPetLim.IntValue;
	g_iPlyPetLim = g_hPlyPetLim.IntValue;
	
	g_hPetColor.GetString(sBuffer, sizeof(sBuffer));
	if( ExplodeString(sBuffer, ",", sBuffer2, sizeof(sBuffer2), sizeof(sBuffer2[])) != 4 )
		return;
}

//==========================================================================================
//									Detours
//==========================================================================================

/**
 *	Detour callback for SurvivorBehavior::SelectMoreDangerousThreat(INextBot const*,CBaseCombatCharacter const*,CBaseCombatCharacter*,CBaseCombatCharacter*)
 *	1st value is unknown, 2nd is the survivor bot performing the function, 3rd is the current most dangerous threat for survivor,
 *	4th is the next threat for the survivor, returns 4th param as most dangerous threat
 *	This callback checks if the survivor tries to choose a pet charger as next more dangerous threat, don't allow it, and return current threat
 */
public MRESReturn SelectThreat_Post(DHookReturn hReturn, DHookParam hParams)
{
	int currentThreat = DHookGetParam(hParams, 3);
	int nextThreat = DHookGetParam(hParams, 4);
	if( nextThreat <= 0 || nextThreat > MaxClients ) // Not a player
		return MRES_Ignored;
		
	if( g_iOwner[nextThreat] != 0 ) // Bot is trying to choose a charger pet as more dangerous threat, prevent it
	{
		if( currentThreat > 0 && currentThreat <= MaxClients && g_iOwner[currentThreat] != 0 ) // Also current threat is a pet
		{
			DHookSetReturn(hReturn, FirstFirstCommonAvailable()); // Set next threat as any common infected, then survivor will look for more dangerous threats(but never a pet!)
			return MRES_Supercede;
		}
		DHookSetReturn(hReturn, currentThreat); // Don't allow survivor to pick the charger pet, keep this infected as more dangerous
		return MRES_Supercede;
	}
	return MRES_Ignored;
}

/**
 *	Detour callback for SurvivorAttack::SelectTarget(SurvivorBot *)
 *	This is the last function called in the survivor decisions to attack an infected, if there are no more zombies in bot sight, he will attempt to attack
 *	survivor pet even if this plugin doesn't allow it to pick as the most dangerous, because survivor has no more zombies to pick
 *	this completely prevents survivor to attack or aim charger like if it doesn't exist, but survivor will have charger as the target it should attack
 *	so survivor will move like if its fighting charger but will not attack or aim at him
 *	The previous callback allows survivor to choose another infected easily and don't get stuck doing nothing if has the charger as attack target
 */
public MRESReturn SelectTarget_Post(DHookReturn hReturn, DHookParam hParams)
{
	int target = DHookGetReturn(hReturn);
	if( target <= 0 || target > MaxClients ) // Just ignore commons or invalid targets
		return MRES_Ignored;
		
	if( g_iOwner[target] )	// Bot will try to attack a charger pet, just block it
	{
		DHookSetReturn(hReturn, 0);
		return MRES_Supercede;
	}
	return MRES_Ignored;
}

//==========================================================================================
//											Events & Hooks
//==========================================================================================

public Action Event_Round_Start(Event event, const char[] name, bool dontBroadcast)
{
	for( int i = 1; i < MaxClients; i++ )
		g_iOwner[i] = 0;
		
	return Plugin_Continue;
}

public Action Event_Player_Death(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if( !client || client > MaxClients ) return Plugin_Continue;
	
	if( GetClientTeam(client) == 3 )
	{
		if( g_iOwner[client] != 0 )
		g_iOwner[client] = 0;	
		return Plugin_Continue;
	}

	for( int i = 1; i <= MaxClients; i++ )
	{
		if( g_iOwner[i] == client )
		{
			switch( g_hPetFree.IntValue )
			{
				case 0:{
					ForcePlayerSuicide(i);
					g_iOwner[i] = 0;
				}
				case 1: TransferPet(i);
				case 2: WildPet(i);
			}
		}
	}
		
	return Plugin_Continue;
}

public Action Event_Player_Replaced(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("player"));
	if( GetClientTeam(client) == 3 ) // Teamchange? Kill pet
	{
		for( int i = 1; i <= MaxClients; i++ )
		{
			if( g_iOwner[i] == client )
			{
				ForcePlayerSuicide(i);
				g_iOwner[i] = 0;
			}
		}	
		return Plugin_Continue;
	}
	int bot = GetClientOfUserId(event.GetInt("bot"));
	for( int i = 1; i <= MaxClients; i++ )
	{
		if( g_iOwner[i] == client )
			g_iOwner[i] = bot;
	}
	return Plugin_Continue;
}

public Action Event_Bot_Replaced(Event event, const char[] name, bool dontBroadcast)
{
	int bot = GetClientOfUserId(event.GetInt("bot"));
	int client = GetClientOfUserId(event.GetInt("player"));
	
	for( int i = 1; i < MaxClients; i++ )
	{
		if( g_iOwner[i] == bot )
			g_iOwner[i] = client;
	}
	return Plugin_Continue;
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2])
{
	if( g_iOwner[client] == 0) return Plugin_Continue;
	
	if( buttons & IN_ATTACK ) buttons &= ~IN_ATTACK;
	if( buttons & IN_ATTACK2 ) buttons &= ~IN_ATTACK2;
	
	return Plugin_Changed;
}

public Action L4D2_OnChooseVictim(int specialInfected, int &curTarget)
{
	if( g_iOwner[specialInfected] != 0 )
	{
		curTarget = g_iOwner[specialInfected];
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

public Action OnShootPet(int victim, int& attacker, int& inflictor, float& damage, int& damagetype, int& ammotype, int hitbox, int hitgroup)
{
	return Plugin_Handled;
}

public Action OnHurtPet(int victim, int& attacker, int& inflictor, float& damage, int& damagetype, int& weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
	if( attacker < 0 && attacker <= MaxClients && GetClientTeam(attacker) == 2 )
		return Plugin_Handled;
		
	return Plugin_Continue;
}

//==========================================================================================
//										Say command
//==========================================================================================


public Action CmdSayPet(int client, int args)
{
	if( !client || !IsClientInGame(client) )
	{
		ReplyToCommand(client, "[SM] This command can be only used ingame.");
		return Plugin_Handled;
	}
	
	if( GetClientTeam(client) != 2 || !IsPlayerAlive(client) )
	{
		ReplyToCommand(client, "[SM] You must be survivor and alive to use this command.");		
		return Plugin_Handled;	
	}
		
	int iClientFlags = GetUserFlagBits(client);
	if( g_iFlags != 0 && !(iClientFlags & g_iFlags) && !(iClientFlags & ADMFLAG_ROOT) )
	{
		ReplyToCommand(client, "[SM] You don't have enough permissions to spawn a pet.");
		return Plugin_Handled;
	}
	if( args == 1 )
	{
		char sBuffer[16];
		GetCmdArg(1, sBuffer, sizeof(sBuffer));
		if( StrEqual( sBuffer, "remove") )
		{
			for( int i = 1; i < MaxClients; i++ )
			{
				if( g_iOwner[i] == client )
				{
					ForcePlayerSuicide(i);
					g_iOwner[i] = 0;
				}
			}
			ReplyToCommand(client, "[SM] Removed all your pets.");
		}
		else ReplyToCommand(client, "[SM] Invalid argument.");

		return Plugin_Handled;
	}
	if( GetSurvivorPets(client) >= g_iPlyPetLim ) 
	{
		ReplyToCommand(client, "[SM] You have reached the limit of pets you can have.");
		return Plugin_Handled;
	}
	if( GetTotalPets() >= g_iGlobPetLim )
	{
		ReplyToCommand(client, "[SM] Total pet limit reached.");
		return Plugin_Handled;
	}
	if( !SpawnPet(client) )
		ReplyToCommand(client, "[SM] Error creating a pet, please try again.");
	else
		ReplyToCommand(client, "[SM] You have a new pet!");

	return Plugin_Handled;
}

//==========================================================================================
//										Functions
//==========================================================================================

bool SpawnPet(int client)
{
	bool bReturn;
	float vPos[3];
	
	if( !L4D_GetRandomPZSpawnPosition(client, 6, 5, vPos) )	// Try to get a random position to spawn the pet
		GetClientAbsOrigin(client, vPos);
		
	L4D2_SpawnSpecial(6, vPos, NULL_VECTOR);
	for( int i = MaxClients; i > 0; i-- ) // Reverse loop from last connected player to first one
	{
		if( !IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) != 3  || !IsFakeClient(i) )
			continue;
			
		if( GetEntProp(i, Prop_Send, "m_zombieClass") == 6 )
		{
			g_iOwner[i] = client;
			SetEntityRenderMode(i, RENDER_TRANSTEXTURE);	// Set rendermode
			SetEntityRenderColor(i, 255, 255, 255, g_hPetColor.IntValue);	// Set translucency (color doesn't work)
			SetEntProp(i, Prop_Send, "m_iGlowType", 3);	// Make pet glow green
			SetEntProp(i, Prop_Send, "m_nGlowRange", 5000);
			SetEntProp(i, Prop_Send, "m_glowColorOverride", 39168);	// Glow color green
			SetEntProp(i, Prop_Send, "m_CollisionGroup", 1); // Prevent collisions with players
			SDKHook(i, SDKHook_TraceAttack, OnShootPet);	// Allows bullets to pass through the pet
			SDKHook(i, SDKHook_OnTakeDamage, OnHurtPet);	// Prevents pet from taking any type of damage from survivors
			bReturn = true;
			break;
		}
	}
	return bReturn;
}

int GetSurvivorPets(int client)
{
	int result = 0;
	for( int i = 0; i <= MaxClients; i++ )
	{
		if( g_iOwner[i] == client )
			result++;
	}
	return result;
}

int GetTotalPets()
{
	int result = 0;
	for( int i = 0; i <= MaxClients; i++ )
	{
		if( g_iOwner[i] != 0 )
		result++;
	}
	return result;
}

// Transfers pet to any random player(non-bot)
void TransferPet(int pet)
{
	// Get total survivor players amount
	int totalHumans = 0;
	int[] iArrayHumans = new int[MaxClients];
	for(int i = 1; i <= MaxClients; i++ )
	{
		if( IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i) && !IsFakeClient(i) )
		{
			iArrayHumans[totalHumans] = i;
			totalHumans++;
		}
	}
	
	if( totalHumans == 0 ) // No players? Kill pet
	{
		g_iOwner[pet] = 0;
		ForcePlayerSuicide(pet);
		return;
	}
	
	g_iOwner[pet] = iArrayHumans[GetRandomInt(0, totalHumans)];
}

// Release the pet and convert it into normal SI
void WildPet(int pet)
{
	g_iOwner[pet] = 0;
	SetEntityRenderColor(pet, 255, 255, 255, g_hPetColor.IntValue);
	SetEntProp(pet, Prop_Send, "m_iGlowType", 0);
	SetEntProp(pet, Prop_Send, "m_nGlowRange", 5000);
	SetEntProp(pet, Prop_Send, "m_glowColorOverride", 39168);
	SetEntProp(pet, Prop_Send, "m_CollisionGroup", 5);
	SDKUnhook(pet, SDKHook_TraceAttack, OnShootPet);
	SDKUnhook(pet, SDKHook_OnTakeDamage, OnHurtPet);
}

int FirstFirstCommonAvailable()
{
	int i = -1;
	while( (i = FindEntityByClassname(i, "infected")) != -1 )
		return i;

	return 0;
}
/*============================================================================================
									Changelog
----------------------------------------------------------------------------------------------
* 1.0	(21-Jan-2021)
	- First release
============================================================================================*/

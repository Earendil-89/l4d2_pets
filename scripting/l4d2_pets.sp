/**
 * ================================================================================ *
 *                               [L4D2] Zombie pets                                 *
 * -------------------------------------------------------------------------------- *
 *  Author      :   Eärendil                                                        *
 *  Descrp      :   Survivors can have a zombie pet following them                  *
 *  Version     :   1.1.2                                                           *
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

//#tryinclude <actions>

#define CARRY_OFFSET 45.0

#define FCVAR_FLAGS FCVAR_NOTIFY
#define PLUGIN_VERSION "1.1.2"
#define GAMEDATA "l4d2_pets"
#define PET_LIMIT 16
#define	CHECK_TICKS 75

ConVar g_hAllow;
ConVar g_hGameModes;			
ConVar g_hCurrGamemode;			
ConVar g_hFlags;
ConVar g_hGlobPetLim;
ConVar g_hPlyPetLim;
ConVar g_hPetFree;
ConVar g_hPetColor;
ConVar g_hJockSize;
ConVar g_hJockPitch;
ConVar g_hPetAttack;
ConVar g_hPetDist;
ConVar g_hPetDmg;
ConVar g_hPetUpdateRate;
ConVar g_hPetTargetMethod;
ConVar g_hPetCarrySlowSurvivors;

GlobalForward g_fwOnCanHavePets;
GlobalForward g_fwOnCanPetReviveIncap;
GlobalForward g_fwOnTryEndCarry;

bool g_bAllowedGamemode;
bool g_bPluginOn;
bool g_bStarted;
int g_iPetAttack;
int g_iFlags;
int g_iGlobPetLim;
int g_iPlyPetLim;
bool g_bCarriedThisRound[MAXPLAYERS+1];
int g_iCarrier[MAXPLAYERS+1] = { -1, ... };
int g_iLastRevive[MAXPLAYERS+1];
int g_iOwner[MAXPLAYERS + 1];		// Who owns this pet?
int g_iLastCommand[MAXPLAYERS + 1] = { -1, ... };		// Last player this pet was sent to attack, 0 = move to a position
//float g_fLastFlow[MAXPLAYERS+1];
float g_fLastBracket[MAXPLAYERS+1];
int g_iTarget[MAXPLAYERS + 1];	// Pet can target another special infected to protect its owner
int g_iNextCheck[MAXPLAYERS + 1];
int g_iPetTargetMethod;
int g_iPetCarrySlowSurvivors;
float g_fPetDist;
float g_fPetUpdateRate;
// victim to attacker.
float g_fImaginaryDamage[MAXPLAYERS+1][MAXPLAYERS+1];
// g_fNextOpenDoor[pet][door]
float g_fNextOpenDoor[MAXPLAYERS+1][2049];
Handle g_hDetThreat, g_hDetThreatL4D1, g_hDetTarget, g_hDetLeap;
Handle g_hPetVictimTimer[MAXPLAYERS + 1];

int g_iDistanceDoor = 0;
float g_fTargetOrigin[3];

// When pet revives with ownership
int g_iOverrideRevive = 0;

// Plugin Info
public Plugin myinfo =
{
    name = "[L4D2] Pets",
    author = "Eärendil",
    description = "Survivors can have a zombie pet following and defending them.",
    version = PLUGIN_VERSION,
    url = "",
};

// Load plugin if is a L4D or L4D2 server
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    if( GetEngineVersion() == Engine_Left4Dead2 )
    {
        CreateNative("L4D2_Pets_ForceCarry", Native_ForceCarry);
        CreateNative("L4D2_Pets_GetCarrier", Native_GetCarrier);
        return APLRes_Success;
    }
    strcopy(error, err_max, "Plugin only supports Left 4 Dead 1 & 2");
    return APLRes_SilentFailure;
}

public int Native_ForceCarry(Handle caller, int numParams)
{
    int client = GetNativeCell(1);
    int pet = GetNativeCell(2);

    if(pet == -1 && g_iCarrier[client] != -1)
    {
        EndCarryBetweenPlayers(g_iCarrier[client], client);
    }
    else
    {
        StartCarryBetweenPlayers(pet, client);
    }

    if(pet != -1 && g_hPetVictimTimer[pet] != INVALID_HANDLE)
    {
        TriggerTimer(g_hPetVictimTimer[pet]);
    }

    return 0;
}


public int Native_GetCarrier(Handle caller, int numParams)
{
    int client = GetNativeCell(1);

    return g_iCarrier[client];
}

public void OnPluginStart()
{
    CreateConVar("l4d2_pets_version",			PLUGIN_VERSION,			"Zombie pets version",			FCVAR_NOTIFY|FCVAR_DONTRECORD);
    
    g_hAllow =		        CreateConVar("l4d2_pets_enable",               "1",					"1 = Plugin On. 0 = Plugin Off.", FCVAR_FLAGS, true, 0.0, true, 1.0);
    g_hGameModes =	        CreateConVar("l4d2_pets_gamemodes",            "",						"Enable plugin in these gamemodes, separated by commas, no spaces.", FCVAR_FLAGS);
    g_hFlags =		        CreateConVar("l4d2_pets_flags",                "",						"Flags required for a player to create a pet, empty to allow everyone.", FCVAR_FLAGS);
    g_hGlobPetLim =	        CreateConVar("l4d2_pets_global_limit",         "4",					"Maximum amount of pets allowed in game.", FCVAR_FLAGS, true, 0.0, true, float(PET_LIMIT));
    g_hPlyPetLim =	        CreateConVar("l4d2_pets_player_limit",         "1",					"Maximum amount of pets allowed per player.", FCVAR_FLAGS, true, 0.0, true, float(PET_LIMIT));
    g_hPetFree =	        CreateConVar("l4d2_pets_ownerdeath_action",    "0",					"What will happen to the pet if its owner dies?\n0 = Kill pet.\n1 = Transfer to random survivor.\n2 = Make it wild.", FCVAR_FLAGS, true, 0.0, true, 2.0);
    g_hPetColor =	        CreateConVar("l4d2_pets_opacity",              "235",					"Opacity of the pet.\n0 = Invisible. 255 = Full opaque.", FCVAR_FLAGS, true, 0.0, true, 255.0);
    g_hJockSize =	        CreateConVar("l4d2_pets_size",                 "0.55",					"(JOCKEYS ONLY) Scale pets by this amount", FCVAR_FLAGS, true, 0.1, true, 5.0);
    g_hJockPitch =	        CreateConVar("l4d2_pets_pitch",                "150",					"Zombie sound pitch, default pitch: 100.", FCVAR_FLAGS, true, 0.0, true, 255.0);
    g_hPetAttack =	        CreateConVar("l4d2_pets_attack",               "2",					"Allow pets to attack other SI.\n0 = Don't allow.\n1 = Only if the SI attacks its owner.\n2 = The closest SI to its owner.", FCVAR_FLAGS, true, 0.0, true, 2.0);
    g_hPetDmg =		        CreateConVar("l4d2_pets_dmg_scale",            "5.0",					"Multiply pet damage caused to other SI by this value.", FCVAR_FLAGS, true, 0.0, true, 100.0);
    g_hPetDist =	        CreateConVar("l4d2_pets_target_dist",          "400",					"Radius around the survivor to allow pets to attack enemy SI.", FCVAR_FLAGS, true, 0.0, true, 65535.0);
    g_hPetUpdateRate =	    CreateConVar("l4d2_pets_target_update_rate",   "3.0",					"Time in seconds Pet updates their target.", FCVAR_FLAGS, true, 0.3, true, 10.0);
    g_hPetTargetMethod =	CreateConVar("l4d2_pets_target_method",        "1",					"0 = Pet targets closest to owner. 1 = Pet focuses on pinned, then on incapped, then on closest to owner.", FCVAR_FLAGS, true, 0.0, true, 1.0);
    g_hPetCarrySlowSurvivors =	CreateConVar("l4d2_pets_carry_slow_survivors",        "0",					"0 = Pets don't carry slow survivors. 1 = Pets carry slow survivors to safe room after owner arrives. 2 = Like 1 but pets also carry incapped survivors.", FCVAR_FLAGS, true, 0.0, true, 2.0);

    g_hCurrGamemode = FindConVar("mp_gamemode");

    g_fwOnCanHavePets = CreateGlobalForward("L4D2_Pets_OnCanHavePets", ET_Event, Param_Cell, Param_Cell, Param_CellByRef);
    g_fwOnCanPetReviveIncap = CreateGlobalForward("L4D2_Pets_OnCanPetReviveIncap", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_FloatByRef);
    g_fwOnTryEndCarry = CreateGlobalForward("L4D2_Pets_OnTryEndCarry", ET_Event, Param_Cell, Param_Cell, Param_Cell);
    
    g_hAllow.AddChangeHook(CvarChange_Enable);
    g_hGameModes.AddChangeHook(CvarChange_Enable);
    g_hCurrGamemode.AddChangeHook(CvarChange_Enable);
    g_hFlags.AddChangeHook(CVarChange_Cvars);
    g_hGlobPetLim.AddChangeHook(CVarChange_Cvars);
    g_hPlyPetLim.AddChangeHook(CVarChange_Cvars);
    g_hPetAttack.AddChangeHook(CVarChange_PetAtk);
    g_hPetDist.AddChangeHook(CVarChange_Cvars);
    g_hPetUpdateRate.AddChangeHook(CVarChange_Cvars);
    g_hPetTargetMethod.AddChangeHook(CVarChange_Cvars);
    g_hPetCarrySlowSurvivors.AddChangeHook(CVarChange_Cvars);
    
    AutoExecConfig(true, "l4d2_pets");
    
    RegConsoleCmd("sm_pet", CmdSayPet, "Open pets menu.");
    
    // Setting DHooks, not enabling
    char sPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sPath, sizeof(sPath), "gamedata/%s.txt", GAMEDATA);
    if( FileExists(sPath) == false ) SetFailState("\n==========\nMissing required file: \"%s\".\nRead installation instructions again.\n==========", sPath);

    Handle hGameData = LoadGameConfigFile(GAMEDATA);
    if( hGameData == null ) SetFailState("Failed to load \"%s.txt\" gamedata.", GAMEDATA);

    /**
        *  New method to detour functions, function addresses have changed
        *  This was made by Silvers
        */
    Address offset = GameConfGetAddress(hGameData, "SurvivorBehavior::SelectMoreDangerousThreat");
    g_hDetThreat = DHookCreateDetour(offset, CallConv_THISCALL, ReturnType_CBaseEntity, ThisPointer_Ignore);
    DHookAddParam(g_hDetThreat, HookParamType_CBaseEntity);
    DHookAddParam(g_hDetThreat, HookParamType_CBaseEntity);
    DHookAddParam(g_hDetThreat, HookParamType_CBaseEntity);
    DHookAddParam(g_hDetThreat, HookParamType_CBaseEntity);

    offset = GameConfGetAddress(hGameData, "L4D1SurvivorBehavior::SelectMoreDangerousThreat");
    g_hDetThreatL4D1 = DHookCreateDetour(offset, CallConv_THISCALL, ReturnType_CBaseEntity, ThisPointer_Ignore);
    DHookAddParam(g_hDetThreatL4D1, HookParamType_CBaseEntity);
    DHookAddParam(g_hDetThreatL4D1, HookParamType_CBaseEntity);
    DHookAddParam(g_hDetThreatL4D1, HookParamType_CBaseEntity);
    DHookAddParam(g_hDetThreatL4D1, HookParamType_CBaseEntity);

    // g_hDetThreat = DHookCreateFromConf(hGameData, "SurvivorBehavior::SelectMoreDangerousThreat");
    // if( !g_hDetThreat ) SetFailState("Failed to find \"SurvivorBehavior::SelectMoreDangerousThreat\" signature.");
    
    // g_hDetThreatL4D1 = DHookCreateFromConf(hGameData, "L4D1SurvivorBehavior::SelectMoreDangerousThreat");
    // if( !g_hDetThreatL4D1 ) SetFailState("Failed to find \"L4D1SurvivorBehavior::SelectMoreDangerousThreat\" signature.");
    
    g_hDetTarget = DHookCreateFromConf(hGameData, "SurvivorAttack::SelectTarget");
    if( !g_hDetTarget ) SetFailState("Failed to find \"SurvivorAttack::SelectTarget\" signature.");
    
    g_hDetLeap = DHookCreateFromConf(hGameData, "CLeap::OnTouch");
    if( !g_hDetLeap ) SetFailState("Failed to find \"CLeap::OnTouch\" signature.");
    
    delete hGameData;
}

public void OnMapStart()
{
    for( int i = 1; i <= MaxClients; i++ )
    {
        g_iOwner[i] = 0;
        g_bCarriedThisRound[i] = false;
        g_iCarrier[i] = -1;

        for(int door=0;door < sizeof(g_fNextOpenDoor[]);door++)
        {
            g_fNextOpenDoor[i][door] = 0.0;
        }
    }

    g_fTargetOrigin = NULL_VECTOR;

    CreateTimer(0.5, Timer_PetsOpenDoors, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
}

public Action Timer_PetsOpenDoors(Handle hTimer)
{
    for(int i=1;i <= MaxClients;i++)
    {
        if(!IsClientInGame(i))
            continue;

        else if(!IsPlayerAlive(i))
            continue;

        else if(g_iOwner[i] == 0)
            continue;

        int count = GetEntityCount();

        float fOrigin[3];
        GetEntPropVector(i, Prop_Data, "m_vecAbsOrigin", fOrigin);

        for (int door = MaxClients+1;door < count;door++)
        {
            if(!IsValidEdict(door))
                continue;

            else if(g_fNextOpenDoor[i][door] > GetGameTime())
                continue;

            char sClassname[64];
            GetEdictClassname(door, sClassname, sizeof(sClassname));

            if((strncmp(sClassname, "prop_door_rotating", 18) == 0 && !(GetEntProp(door, Prop_Data, "m_spawnflags") & 32768)) || (strncmp(sClassname, "func_door", 9) == 0 && GetEntProp(door, Prop_Data, "m_spawnflags") & 256))
            {

                float fDoorOrigin[3];
                GetEntPropVector(door, Prop_Data, "m_vecOrigin", fDoorOrigin);

                if(GetVectorDistance(fOrigin, fDoorOrigin) < 225.0)
                {
                    // Pets will occasionally be stuck on open safe room doors, so we must ensure the pet can deal with both open and close doors.
                    g_fNextOpenDoor[i][door] = GetGameTime() + 5.0;

                    char sTargetname[64];
                    GetEntPropString(i, Prop_Data, "m_iName", sTargetname, sizeof(sTargetname));

                    SetEntPropString(i, Prop_Data, "m_iName", "AverageDoorEnjoyer");
                    SetVariantString("AverageDoorEnjoyer");
                    AcceptEntityInput(door, "OpenAwayFrom");
                    SetEntPropString(i, Prop_Data, "m_iName", sTargetname);



                    CreateTimer(2.5, Timer_CloseDoor, EntIndexToEntRef(door), TIMER_FLAG_NO_MAPCHANGE);
                }
            }
        }
    }

    return Plugin_Continue;
}

public Action Timer_CloseDoor(Handle hTimer, int ref)
{
    int door = EntRefToEntIndex(ref);

    if(door == INVALID_ENT_REFERENCE)
        return Plugin_Stop;
    
    AcceptEntityInput(door, "Close");
    
    return Plugin_Stop;
}

public void OnConfigsExecuted()
{
    GetGameMode();
    SwitchPlugin();
    ConVars();
    SetPetAtk();
}

public void OnClientPutInServer(int client)
{
    if( !g_bPluginOn )
        return;

    if( !g_bStarted )
    {
        g_bStarted = true;
        HookPlayers();
    }
    else SDKHook(client, SDKHook_OnTakeDamage, ScaleFF);
}

public void OnClientConnected(int client)
{
    g_iCarrier[client] = -1;
}

public void OnClientDisconnect(int client)
{
    if( !g_bPluginOn )
        return;

    delete g_hPetVictimTimer[client];
    g_iOwner[client] = 0;
    g_iTarget[client] = 0;
    g_iCarrier[client] = -1;
}

public void OnPluginEnd()
{
    for( int i = 1; i <= MaxClients; i++ )
    {
        if( g_iOwner[i] != 0 )
        {
            // Should be enough to also call "player_death" and detach revive timers from the incapped survivors.
            ForcePlayerSuicide(i);
        }
    }
}

public void OnGameFrame()
{
    for(int i=1;i <= MaxClients;i++)
    {
        if(!IsClientInGame(i))
            continue;

        else if(g_iCarrier[i] == -1)
            continue;

        else if(!IsClientInGame(g_iCarrier[i]))
        {
            g_iCarrier[i] = -1;
            continue;
        }

        float fOrigin[3], fAngles[3];
        GetClientEyePosition(g_iCarrier[i], fOrigin);
        GetClientEyeAngles(g_iCarrier[i], fAngles);	

        // Only account for the angle of rotation of +left and +right in console.

        fAngles[0] = 0.0;

        float fwd[3];


        GetAngleVectors(fAngles, fwd, NULL_VECTOR, NULL_VECTOR);

        NegateVector(fwd);

        ScaleVector(fwd, 20.0);

        AddVectors(fOrigin, fwd, fOrigin);

        fOrigin[2] += CARRY_OFFSET - 64.0;
        TeleportEntity(i, fOrigin, NULL_VECTOR, {0.0, 0.0, 0.1});
    }
}

public Action L4D2_OnHitByVomitJar(int victim, int &attacker)
{
    if(L4D_GetClientTeam(attacker) != L4DTeam_Survivor)
        return Plugin_Continue;

    else if(g_iOwner[victim] == 0)
        return Plugin_Continue;

    return Plugin_Handled;
}
public Action L4D_OnLedgeGrabbed(int client)
{
    if(g_iCarrier[client] != -1)
        return Plugin_Handled;

    return Plugin_Continue;
}
/* ========================================================================================= *
*                                          ConVars                                          *
* ========================================================================================= */

void CvarChange_Enable(Handle conVar, const char[] oldValue, const char[] newValue)
{
    GetGameMode();
    SwitchPlugin();
}

void CVarChange_Cvars(Handle conVar, const char[] oldValue, const char[] newValue)
{
    ConVars();
}

void CVarChange_PetAtk(Handle conVar, const char[] oldValue, const char[] newValue)
{
    SetPetAtk();
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
        HookEvent("round_start",		Event_Round_Start, EventHookMode_PostNoCopy);
        HookEvent("round_end",			Event_Round_End, EventHookMode_PostNoCopy);
        HookEvent("player_spawn",		Event_Player_Spawn);
        HookEvent("player_death",		Event_Player_Death);
        HookEvent("player_bot_replace", Event_Player_Replaced);
        HookEvent("bot_player_replace", Event_Bot_Replaced);
        HookEvent("player_hurt",		Event_Player_Hurt);
        HookEvent("charger_carry_start", Event_Charger_Carry_Start);
        
        if( !DHookEnableDetour(g_hDetThreat, true, SelectThreat_Post) )
            SetFailState("Failed to detour \"SurvivorBehavior::SelectMoreDangerousThreat\".");
        
        if( !DHookEnableDetour(g_hDetThreatL4D1, true, SelectThreat_Post) )
            SetFailState("Failed to detour \"L4D1SurvivorBehavior::SelectMoreDangerousThreat\".");

        if( !DHookEnableDetour(g_hDetTarget, true, SelectTarget_Post) )
            SetFailState("Failed to detour \"SurvivorAttack::SelectTarget\".");	
            
        if( !DHookEnableDetour(g_hDetLeap, false, LeapJockey) )
            SetFailState("Failed to detour \"CLeap::OnTouch\".");
        
        AddNormalSoundHook(SoundHook);
        HookPlayers();
    }
    
    if( g_bPluginOn == true && (g_hAllow.BoolValue == false || g_bAllowedGamemode == false) )
    {
        g_bPluginOn = false;
        UnhookEvent("round_start",			Event_Round_Start, EventHookMode_PostNoCopy);
        UnhookEvent("round_end",			Event_Round_End, EventHookMode_PostNoCopy);
        UnhookEvent("player_death",			Event_Player_Death);
        UnhookEvent("player_bot_replace",	Event_Player_Replaced);
        UnhookEvent("bot_player_replace",	Event_Bot_Replaced);
        UnhookEvent("player_hurt",			Event_Player_Hurt);

        DHookDisableDetour(g_hDetThreat,		true, SelectThreat_Post);
        DHookDisableDetour(g_hDetThreatL4D1,	true, SelectThreat_Post);
        DHookDisableDetour(g_hDetTarget,		true, SelectTarget_Post);
        DHookDisableDetour(g_hDetLeap,			false, LeapJockey);
        
        for( int i = 1; i <= MaxClients; i++ )
        {
            if( g_iOwner[i] != 0 )
                KillPet(i);
            
            g_iOwner[i] = 0;
            g_iTarget[i] = 0;
        }
        RemoveNormalSoundHook(SoundHook);
        UnhookPlayers();
    }
}

void ConVars()
{
    char sBuffer[32], sBuffer2[4][8];
    g_hFlags.GetString(sBuffer, sizeof(sBuffer));
    g_iFlags = ReadFlagString(sBuffer);
    g_iGlobPetLim = g_hGlobPetLim.IntValue;
    g_iPlyPetLim = g_hPlyPetLim.IntValue;
    g_fPetDist = Pow(g_hPetDist.FloatValue, 2.0);
    g_fPetUpdateRate = g_hPetUpdateRate.FloatValue;
    g_iPetTargetMethod = g_hPetTargetMethod.IntValue;
    g_iPetCarrySlowSurvivors = g_hPetCarrySlowSurvivors.IntValue;
    
    g_hPetColor.GetString(sBuffer, sizeof(sBuffer));
    if( ExplodeString(sBuffer, ",", sBuffer2, sizeof(sBuffer2), sizeof(sBuffer2[])) != 4 )
        return;
}

void SetPetAtk()
{
    g_iPetAttack = g_hPetAttack.IntValue;
    if( g_iPetAttack == 2 )
    {
        for( int i = 1; i <= MaxClients; i++ )
        {
            delete g_hPetVictimTimer[i];
            if( g_iOwner[i] != 0 )
                g_hPetVictimTimer[i] = CreateTimer(g_fPetUpdateRate, ChangeVictim_Timer, i);
        }
    }
}

/* ========================================================================================= *
*                                           Detours                                         *
* ========================================================================================= */

/**
    *	Detour callback for SurvivorBehavior::SelectMoreDangerousThreat(INextBot const*,CBaseCombatCharacter const*,CBaseCombatCharacter*,CBaseCombatCharacter*)
*	1st value is unknown, 2nd is the survivor bot performing the function, 3rd is the current most dangerous threat for survivor,
*	4th is the next threat for the survivor, returns 4th param as most dangerous threat
*	This callback checks if the survivor tries to choose a pet charger as next more dangerous threat, don't allow it, and return current threat
*/
MRESReturn SelectThreat_Post(DHookReturn hReturn, DHookParam hParams)
{
    int currentThreat = DHookGetParam(hParams, 3);
    int nextThreat = DHookGetParam(hParams, 4);
    if( nextThreat <= 0 || nextThreat > MaxClients ) // Not a player
        return MRES_Ignored;
        
    if( g_iOwner[nextThreat] != 0 ) // Bot is trying to choose a pet as more dangerous threat, prevent it
    {
        if( currentThreat > 0 && currentThreat <= MaxClients && g_iOwner[currentThreat] != 0 ) // Also current threat is a pet
        {
            DHookSetReturn(hReturn, FindFirstCommonAvailable()); // Set next threat as any common infected, then survivor will look for more dangerous threats(but never a pet!)
            return MRES_Supercede;
        }
        DHookSetReturn(hReturn, currentThreat); // Don't allow survivor to pick the pet, keep this infected as more dangerous
        return MRES_Supercede;
    }
    return MRES_Ignored;
}

/**
    *	Detour callback for SurvivorAttack::SelectTarget(SurvivorBot *)
*	This is the last function called in the survivor decisions to attack an infected, if there are no more zombies in bot sight, he will attempt to attack
*	survivor pet even if the last detour didn't allowed it to pick as the most dangerous, because survivor has no more zombies to pick
*	this completely prevents survivor to attack or aim the pet like if it doesn't exist, but survivor will have the pet as the target it should attack
*	so survivor will move like if its fighting the pet but will not attack or aim at him
*	The previous callback allows survivor to choose another infected easily and don't get stuck doing nothing if has the charger as attack target
*/
MRESReturn SelectTarget_Post(DHookReturn hReturn, DHookParam hParams)
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

/**
    *	Detour callback for CLeap::OnTouch(CBaseEntity *)
*	Its called when Jockey ability "touches" another entity, but ability is being constantly fired
*	Jockey works different than other SI. Killing or blocking permanently jockey ability freezes it, it seems that the ability controls the zombie wtf
*	Jockey can bypass OnPlayerRunCmd blocks and attack players, maybe because ability forces jockey to leap even with buttons blocked
*	This prevents jockey to grab survivors but won't prevent him from attempting to grab a survivor
*	So the jockey will jump constantly around its owner
*/
MRESReturn LeapJockey(int pThis, DHookParam hParams)
{	
    int target = DHookGetParam(hParams, 1);
    // Jockey ability is being fired continously, this ignores when ability is touching nothing or other entities
    if( target <= 0 || target > MaxClients )
        return MRES_Ignored;
        
    int jockey = GetEntPropEnt(pThis, Prop_Send, "m_owner");
    if( g_iOwner[jockey] != 0 )
    {
        // Dont allow Leap ability to touch any survivor
        if( GetClientTeam(target) == 2 )
            return MRES_Supercede;
    }
    return MRES_Ignored;
}

/* ========================================================================================= *
*                                       Events & Hooks                                      *
* ========================================================================================= */

void Event_Round_Start(Event event, const char[] name, bool dontBroadcast)
{
    for( int i = 1; i <= MaxClients; i++ )
    {
        g_bCarriedThisRound[i] = false;

        g_iOwner[i] = 0;
        if( IsClientInGame(i) )
            SDKHook(i, SDKHook_OnTakeDamage, ScaleFF);
    }
}

void Event_Round_End(Event event, const char[] name, bool dontBroadcast)
{
    for( int i = 1; i <= MaxClients; i++ )
    {
        if( IsClientInGame(i) )
            SDKUnhook(i, SDKHook_OnTakeDamage, ScaleFF);	
    }
}


Action Event_Player_Spawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if( client == 0 ) return Plugin_Continue;

    for( int i = 0; i < sizeof(g_fImaginaryDamage); i++ )
    {
        g_fImaginaryDamage[client][i] = 0.0;
        g_fImaginaryDamage[i][client] = 0.0;
    }

    return Plugin_Continue;
}
Action Event_Player_Death(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if( client == 0 ) return Plugin_Continue;
    
    int carried = GetPlayerCarry(client);

    g_iCarrier[client] = -1;

    if(carried != -1)
        g_iCarrier[carried] = -1;

    if(g_iOwner[client] != 0 && g_iLastRevive[client] != 0)
    {
        int trueVictim = g_iLastRevive[client];

        SetEntPropEnt(trueVictim, Prop_Send, "m_reviveOwner", -1);
        SetEntPropFloat(trueVictim, Prop_Send, "m_flProgressBarStartTime", 0.0);
        SetEntPropFloat(trueVictim, Prop_Send, "m_flProgressBarDuration", 0.0);

        g_iLastRevive[client] = 0;
    }

    g_iOwner[client] = 0;
    delete g_hPetVictimTimer[client];

    for( int i = 1; i <= MaxClients; i++ )
    {
        if( g_iOwner[i] == client )
        {
            switch( g_hPetFree.IntValue )
            {
                case 0: KillPet(i);
                case 1: TransferPet(i);
                case 2: WildPet(i);
            }
        }
    }
        
    return Plugin_Continue;
}

Action Event_Player_Replaced(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("player"));
    int bot = GetClientOfUserId(event.GetInt("bot"));
    
    for( int i = 1; i <= MaxClients; i++ )
    {
        if( g_iOwner[i] == client )
            g_iOwner[i] = bot;

        if( g_iLastRevive[i] == client)
        {
            g_iLastRevive[i] = 0;

            SetEntPropEnt(i, Prop_Send, "m_reviveTarget", -1);

            SetEntPropEnt(client, Prop_Send, "m_reviveOwner", -1);
            SetEntPropFloat(client, Prop_Send, "m_flProgressBarStartTime", 0.0);
            SetEntPropFloat(client, Prop_Send, "m_flProgressBarDuration", 0.0);

            SetEntPropEnt(bot, Prop_Send, "m_reviveOwner", -1);
            SetEntPropFloat(bot, Prop_Send, "m_flProgressBarStartTime", 0.0);
            SetEntPropFloat(bot, Prop_Send, "m_flProgressBarDuration", 0.0);
        }
    }

    if( GetClientTeam(client) == 3 ) // Teamchange? Kill pet
    {
        for( int i = 1; i <= MaxClients; i++ )
        {
            if( g_iOwner[i] == client )
                KillPet(i);
        }
    }   
    return Plugin_Continue;
}

void Event_Bot_Replaced(Event event, const char[] name, bool dontBroadcast)
{
    int bot = GetClientOfUserId(event.GetInt("bot"));
    int client = GetClientOfUserId(event.GetInt("player"));
    
    for( int i = 1; i <= MaxClients; i++ )
    {
        if( g_iOwner[i] == bot )
            g_iOwner[i] = client;

        if( g_iLastRevive[i] == bot)
        {     
            g_iLastRevive[i] = 0;

            SetEntPropEnt(i, Prop_Send, "m_reviveTarget", -1);

            SetEntPropEnt(client, Prop_Send, "m_reviveOwner", -1);
            SetEntPropFloat(client, Prop_Send, "m_flProgressBarStartTime", 0.0);
            SetEntPropFloat(client, Prop_Send, "m_flProgressBarDuration", 0.0);

            SetEntPropEnt(bot, Prop_Send, "m_reviveOwner", -1);
            SetEntPropFloat(bot, Prop_Send, "m_flProgressBarStartTime", 0.0);
            SetEntPropFloat(bot, Prop_Send, "m_flProgressBarDuration", 0.0);
        }
    }
}

Action Event_Player_Hurt(Event event, const char[] name, bool dontBroadcast)
{
    if( g_iPetAttack != 1 )
        return Plugin_Continue;

    int client = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    
    if( !client || GetClientTeam(client) != 2 )
        return Plugin_Continue;
    
    if( attacker <= 0 || attacker > MaxClients || GetClientTeam(attacker) != 3 )
        return Plugin_Continue;
    
    for( int i = 0; i <= MaxClients; i++ )
    {
        if( g_iOwner[i] == client && g_iTarget[i] == 0 )
            g_iTarget[i] = attacker;
    }
    return Plugin_Continue;
}


Action Event_Charger_Carry_Start(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("userid"));
    
    if(victim == 0)
        return Plugin_Continue;
    
    else if(g_iCarrier[victim] == -1)
        return Plugin_Continue;

    EndCarryBetweenPlayers(g_iCarrier[victim], victim, true);

    return Plugin_Continue;
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2])
{
    if( g_iOwner[client] == 0) return Plugin_Continue;
    if( g_iTarget[client] != 0 ) return Plugin_Continue;
    
    if( buttons & IN_ATTACK ) buttons &= ~IN_ATTACK;	// Main ability, always block
    
    int iTimer = FindSendPropInfo("CTerrorPlayer", "m_noAvoidanceTimer");
    SetEntData(client, iTimer + 4, GetGameTime() + 65535.0);
    SetEntData(client, iTimer + 8, GetGameTime() + 65535.0);
    
    // Check survivor target position, if its very close block melee, if not is blocked and is trying to break a door or something
    if( buttons & IN_ATTACK2 ) // Allow pet to use is melee if is targetting another client (zombie)
    {
        if( g_iTarget[client] != 0 )
            return Plugin_Continue;
        if( ++g_iNextCheck[client] >= CHECK_TICKS ) // Instead of checking positions between pet and owner every time, do it every X attempts, reduces CPU usage
        {
            g_iNextCheck[client] = 0;
            float vPetPos[3], vOwnerPos[3];
            GetClientAbsOrigin(client, vPetPos);
            GetClientAbsOrigin(g_iOwner[client], vOwnerPos);
            if( GetVectorDistance(vPetPos, vOwnerPos, true) > 16834.0 || L4D_GetPinnedInfected(g_iOwner[client]) != 0 ) // More than 128 game units between pet and owner
                return Plugin_Changed;
        }
        buttons &= ~IN_ATTACK2;
    }
    
    return Plugin_Changed;
}

Action SoundHook(int clients[64], int &numClients, char sample[PLATFORM_MAX_PATH], int &entity, int &channel, float &volume, int &level, int &pitch, int &flags)
{
    if( entity < 0 || entity > MaxClients )
        return Plugin_Continue;
        
    if( g_iOwner[entity] != 0 )
        pitch = g_hJockPitch.IntValue;
    
    return Plugin_Changed;
}

public Action L4D2_OnChooseVictim(int specialInfected, int &curTarget)
{   
    if(g_iLastCommand[specialInfected] == -2)
        return Plugin_Stop;

    return OnChooseVictim(specialInfected, curTarget);
}

Action OnChooseVictim(int specialInfected, int &curTarget)
{
    if( g_iTarget[specialInfected] != 0 ) // Pet has an attack target different than its owner
    {
        if( IsClientInGame(g_iTarget[specialInfected]) && IsPlayerAlive(g_iTarget[specialInfected]) )	// Check if target is still alive
        {
            curTarget = g_iTarget[specialInfected];	
        }
        else
        {
            curTarget = g_iOwner[specialInfected];	
            g_iTarget[specialInfected] = 0;	// Remove target
        }

        return Plugin_Changed;
    }
    if( g_iOwner[specialInfected] != 0 )
    {
        curTarget = g_iOwner[specialInfected];
        return Plugin_Changed;
    }

    return Plugin_Continue;
}
Action OnShootPet(int victim, int& attacker, int& inflictor, float& damage, int& damagetype, int& ammotype, int hitbox, int hitgroup)
{
    if(LibraryExists("RPG_Perks"))
        return Plugin_Continue;

    return Plugin_Handled;
}

Action OnHurtPet(int victim, int& attacker, int& inflictor, float& damage, int& damagetype, int& weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
    if(LibraryExists("RPG_Perks"))
        return Plugin_Continue;

    if(IsPlayer(attacker) && GetClientTeam(attacker) == 2 )
        return Plugin_Handled;
        
    return Plugin_Continue;
}

public Action RPG_Perks_OnShouldIgnoreEntireTeamTouch(int client)
{
    if(g_bCarriedThisRound[client] && L4D2_GetCurrentFinaleStage() != FINALE_GAUNTLET_ESCAPE)
        return Plugin_Handled;

    return Plugin_Continue;
}

public void RPG_Perks_OnCalculateDamage(int priority, int victim, int attacker, int inflictor, float &damage, int damagetype, int hitbox, int hitgroup, bool &bDontInterruptActions, bool &bDontStagger, bool &bDontInstakill, bool &bImmune)
{   
    OnCalculateDamage(priority, victim, attacker, inflictor, damage, damagetype, bDontInterruptActions, bDontStagger, bDontInstakill, bImmune);
}

Action OnCalculateDamage(int priority, int victim, int attacker, int inflictor, float &damage, int damagetype, bool &bDontInterruptActions, bool &bDontStagger, bool &bDontInstakill, bool &bImmune)
{
    if(!IsPlayer(victim))
        return Plugin_Continue;

    if(!IsPlayer(attacker) && !(damagetype & DMG_BURN))
        return Plugin_Continue;

    // If both attacker and defender are not pets, ignore damage calculation
    else if(g_iOwner[victim] == 0 && (IsPlayer(attacker) && g_iOwner[attacker] == 0))
        return Plugin_Continue;

    if(priority == -10)
    {
        int pinner = L4D_GetPinnedInfected(victim);

        if(pinner != 0 && L4D2_GetPlayerZombieClass(pinner) == L4D2ZombieClass_Jockey)
        {
            
            damage = 0.0;
            bDontInterruptActions = true;
            bDontInstakill = true;
            bDontStagger = true;
            bImmune = true;
            SDKHooks_TakeDamage(pinner, inflictor, attacker, damage, damagetype|DMG_DROWNRECOVER, _, _, _, false);

            return Plugin_Stop;
        }
    }
    if(priority != 9)
        return Plugin_Continue;

    else if(IsPlayer(attacker) && L4D_GetClientTeam(victim) == L4D_GetClientTeam(attacker) && g_iOwner[victim] == 0)
    {
        damage *= g_hPetDmg.FloatValue;
        return Plugin_Changed;
    }

    int pinner = L4D_GetPinnedInfected(victim);

    if(pinner != 0)
    {
        if(L4D2_GetPlayerZombieClass(pinner) == L4D2ZombieClass_Smoker)
        {
            g_fImaginaryDamage[pinner][attacker] += damage;

            if(g_fImaginaryDamage[pinner][attacker] >= GetEntityHealth(pinner))
            {
                L4D_Smoker_ReleaseVictim(victim, pinner);

                g_fImaginaryDamage[pinner][attacker] = 0.0;
            }
        }
    }

    if(damagetype & DMG_FALL || damagetype & DMG_DROWN)
        return Plugin_Continue;

    damage = 0.0;
    bDontInterruptActions = true;
    bDontInstakill = true;
    bDontStagger = true;
    bImmune = true;

    if(IsPlayer(attacker) && g_iPetCarrySlowSurvivors != 0 && GetPlayerCarry(attacker) == -1 && L4D_GetClientTeam(victim) == L4DTeam_Survivor && IsNotCarryable(g_iOwner[attacker]) && !IsNotCarryable(victim))
    {
        StartCarryBetweenPlayers(attacker, victim);
        //SetPetBlindState(attacker, true);
    }

    return Plugin_Stop;
}

public Action Timer_CheckPetReviveIncap(Handle hTimer, int userid)
{
    int attacker = GetClientOfUserId(userid);

    if(attacker == 0)
        return Plugin_Stop;

    else if(g_iOwner[attacker] == 0)
    {
        int trueVictim = g_iLastRevive[attacker];

        SetEntityMoveType(attacker, MOVETYPE_WALK);
        SetEntPropEnt(trueVictim, Prop_Send, "m_reviveOwner", -1);
        SetEntPropFloat(trueVictim, Prop_Send, "m_flProgressBarStartTime", 0.0);
        SetEntPropFloat(trueVictim, Prop_Send, "m_flProgressBarDuration", 0.0);
        g_iLastRevive[attacker] = 0;
        return Plugin_Stop;
    }

    int victim = 0;

    for(int i = 1; i <= MaxClients; i++ )
    {
        if( IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i) && L4D_IsPlayerIncapacitated(i) && GetEntPropEnt(i, Prop_Send, "m_reviveOwner") == attacker)
        {
            victim = i;
        }
    }

    if(victim == 0)
    {
        int trueVictim = g_iLastRevive[attacker];
        SetEntityMoveType(attacker, MOVETYPE_WALK);
        SetEntPropEnt(trueVictim, Prop_Send, "m_reviveOwner", -1);
        SetEntPropFloat(trueVictim, Prop_Send, "m_flProgressBarStartTime", 0.0);
        SetEntPropFloat(trueVictim, Prop_Send, "m_flProgressBarDuration", 0.0);
        g_iLastRevive[attacker] = 0;
        return Plugin_Stop;
    }

    if(GetEntPropFloat(victim, Prop_Send, "m_flProgressBarStartTime") + GetEntPropFloat(victim, Prop_Send, "m_flProgressBarDuration") < GetGameTime())
    {
        SetEntityMoveType(attacker, MOVETYPE_WALK);

        ReviveWithOwnership(victim, g_iOwner[attacker]);

        g_iLastRevive[attacker] = 0;
        return Plugin_Stop;
    }

    SetEntityMoveType(attacker, MOVETYPE_NONE);
    return Plugin_Continue;
}

public void RPG_Perks_OnGetSpecialInfectedClass(int priority, int client, L4D2ZombieClassType &zclass)
{
    if(priority != 9)
        return;
    
    else if(g_iOwner[client] == 0)
        return;
    
    //  L4D2ZombieClass_Charger or L4D2ZombieClass_Jockey
    zclass = view_as<L4D2ZombieClassType>(GetEntProp(client, Prop_Send, "m_zombieClass"));
}

public void RPG_Perks_OnZombiePlayerSpawned(int client)
{
    if(g_iOwner[client] == 0)
        return;

    ResetInfectedAbility(client, 9999.9);
}
/*
BehaviorAction g_attackAction;

public void OnActionCreated( BehaviorAction action, int actor, const char[] name )
{
    if(!IsPlayer(actor))
        return;

    if(StrEqual(name, "ChargerAttack"))
    {
        g_attackAction = view_as<BehaviorAction>(CloneHandle(action));
        return;
    }
    else if(g_iOwner[actor] == 0)
        return;

    // ChargerEvade
    if(StrContains(name, "Retreat", false) == -1 && StrContains(name, "Evade", false) == -1)
        return;

    action.OnStart = OnStart_ChangeToAttack;
}

public Action OnStart_ChangeToAttack(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
    if(g_attackAction)
    {
        return action.ChangeTo(g_attackAction, "Charger Pet");
    }

    return Plugin_Continue;
}
*/
bool IsPlayer(int entity)
{
    if(entity >= 1 && entity <= MaxClients)
        return true;
        
    return false;
}

// Disable damage to survivors caused by pets, increase damage received by SI from pets
Action ScaleFF(int victim, int& attacker, int& inflictor, float& damage, int& damagetype, int& ammotype, int hitbox, int hitgroup)
{
    if(LibraryExists("RPG_Perks"))
        return Plugin_Continue;

    Action rtn;

    bool dummy_value;

    rtn = OnCalculateDamage(-10, victim, attacker, inflictor, damage, damagetype, dummy_value, dummy_value, dummy_value, dummy_value);

    if(rtn == Plugin_Stop)
        return rtn;

    rtn = OnCalculateDamage(9, victim, attacker, inflictor, damage, damagetype, dummy_value, dummy_value, dummy_value, dummy_value);

    return rtn;
}

/* ========================================================================================= *
*                                            Timers                                         *
* ========================================================================================= */
Action ChangeVictim_Timer(Handle timer, int pet)
{
    
    UpdatePetCollisionGroup(pet);

    float vPet[3];
    GetClientAbsOrigin(pet, vPet);

    int carried = GetPlayerCarry(pet);

    if(carried != -1)
    { 
        if(!IsNotCarryable(g_iOwner[pet]) || IsNotCarryable(carried) || L4D_GetPinnedInfected(carried) != 0 || g_iPetCarrySlowSurvivors == 0)
        {    
            Call_StartForward(g_fwOnTryEndCarry);

            Call_PushCell(carried);
            Call_PushCell(pet);
            Call_PushCell(g_iOwner[pet]);

            Action rtn;
            Call_Finish(rtn);

            if(rtn < Plugin_Handled)
            {
                EndCarryBetweenPlayers(pet, carried);
            }
        }
    }

    for(int i = 1; i <= MaxClients; i++ )
    {
        if(!IsClientInGame(i))
            continue;
            
        else if(L4D_GetClientTeam(i) != L4DTeam_Survivor)
            continue;
            
        else if(!IsPlayerAlive(i))
            continue;

        int target = GetEntPropEnt(i, Prop_Send, "m_reviveTarget");

    
        if(target != -1)
        {
            // Critical bug fix...
            if(GetEntPropEnt(target, Prop_Send, "m_reviveOwner") != i)
            {
                SetEntPropEnt(i, Prop_Send, "m_reviveTarget", -1);
            }
        }

        if(GetEntPropEnt(i, Prop_Send, "m_reviveOwner") != pet)
            continue;

        float vIncapped[3];
        GetClientAbsOrigin(i, vIncapped);   
        
        if(!L4D_IsPlayerIncapacitated(i) || GetVectorDistance(vIncapped, vPet, false) >= 128.0)
        {
            SetEntPropEnt(i, Prop_Send, "m_reviveOwner", -1);
            SetEntPropFloat(i, Prop_Send, "m_flProgressBarStartTime", 0.0);
            SetEntPropFloat(i, Prop_Send, "m_flProgressBarDuration", 0.0);
        }
    }

    int owner = g_iOwner[pet];

    // Rare bug...
    bool bCanPet = true;
    Action rtnPet;

    Call_StartForward(g_fwOnCanHavePets);
    
    Call_PushCell(owner);
    Call_PushCell(L4D2_GetPlayerZombieClass(pet));
    Call_PushCellRef(bCanPet);

    Call_Finish(rtnPet);

    if(rtnPet > Plugin_Continue && !bCanPet)
    {
        KillPet(pet);
        return Plugin_Stop;
    }

    // Another rare bug...
    if(L4D_GetPinnedSurvivor(pet) != 0)
    {
        L4D_StaggerPlayer(pet, pet, NULL_VECTOR);

        // Special trick to end stagger.
        char TempFormat[128];
        FormatEx(TempFormat, sizeof(TempFormat), "GetPlayerFromUserID(%i).SetModel(GetPlayerFromUserID(%i).GetModelName())", GetClientUserId(pet), GetClientUserId(pet));
        L4D2_ExecVScriptCode(TempFormat);
    }
    else
    {
        ResetInfectedAbility(pet, 9999.9);
    }

    g_hPetVictimTimer[pet] = null;
    float vTarget[3];
    float vOwner[3];

    float fDist = g_fPetDist;
    int nextTarget = 0;

    GetClientAbsOrigin(owner, vOwner);

    int door = L4D_GetCheckpointLast();

    if(door != -1)
    {
        if((g_fTargetOrigin[0] == 0.0 && g_fTargetOrigin[1] == 0.0 && g_fTargetOrigin[2] == 0.0) || !L4D_IsPositionInLastCheckpoint(g_fTargetOrigin))
        {
            g_iDistanceDoor = 256;
            FindRandomSpotInSafeRoom(false, g_fTargetOrigin);
        }
    }

    // PrintToChatAll("%i %i %i %i", IsNotCarryable(owner), !IsFakeClient(owner), g_iPetCarrySlowSurvivors != 0, GetCarryTargetOrigin(pet));

    if(IsNotCarryable(owner) && L4D_GetPinnedInfected(owner) == 0 && !IsFakeClient(owner) && g_iPetCarrySlowSurvivors != 0 && GetCarryTargetOrigin(pet))
    {
        fDist = Pow(131071.0, 2.0);

        if(GetPlayerCarry(pet) == -1)
        {
            for( int i = 1; i <= MaxClients; i++ )
            {
                if(IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2 && g_iCarrier[i] == -1 && !IsNotCarryable(i) && (g_iPetCarrySlowSurvivors == 2 || !L4D_IsPlayerIncapacitated(i)))
                {
                    GetClientAbsOrigin(i, vTarget);
                    GetClientAbsOrigin(owner, vPet);

                    float tempDist = GetVectorDistance(vPet, vTarget, true);

                    if( tempDist < fDist )
                    {
                        nextTarget = i;
                        fDist = tempDist;
                    }			
                }
            }
        }
        else
        {
            nextTarget = owner;

            if(g_iLastCommand[pet] != -2)
            {
                g_iLastCommand[pet] = -2;
            }

            int target = GetPlayerCarry(pet);

            if(L4D_IsPlayerIncapacitated(target))
            {
                float fDuration = -1.0;

                Call_StartForward(g_fwOnCanPetReviveIncap);

                Call_PushCell(target);
                Call_PushCell(pet);
                Call_PushCell(g_iOwner[pet]);

                Call_PushFloatRef(fDuration);

                Call_Finish();

                if(fDuration >= 0.0 && GetEntPropEnt(target, Prop_Send, "m_reviveOwner") == -1 && g_iLastRevive[pet] == 0)
                {
                    nextTarget = target;

                    float vIncapped[3];
                    GetClientAbsOrigin(target, vIncapped);

                    if(GetVectorDistance(vIncapped, vPet, false) < 128.0)
                    {
                        if(fDuration == 0.0)
                        {
                            ReviveWithOwnership(target, g_iOwner[pet]);
                        }
                        else
                        {
                            SetEntityMoveType(pet, MOVETYPE_NONE);

                            SetEntPropFloat(target, Prop_Send, "m_flProgressBarStartTime", GetGameTime());
                            SetEntPropFloat(target, Prop_Send, "m_flProgressBarDuration", fDuration);
                            SetEntPropEnt(target, Prop_Send, "m_reviveOwner", pet);

                            g_iLastRevive[pet] = target;

                            CreateTimer(0.1, Timer_CheckPetReviveIncap, GetClientUserId(pet), TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
                        }
                    }
                }
            }
        }
    }
    if(nextTarget == 0)
    {
        if(g_iLastCommand[pet] == -2)
        {
            // Bug where you can't BOT_CMD_ATTACK during BOT_CMD_MOVE
            g_iLastCommand[pet] = 99999;
        }
        switch(g_iPetTargetMethod)
        {
            case 0:
            {
                for( int i = 1; i <= MaxClients; i++ )
                {
                    if( i != pet && IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 3 && g_iOwner[i] == 0)
                    {
                        int ability = L4D_GetPlayerCustomAbility(i);

                        if(GetEntProp(i, Prop_Send, "m_zombieClass") == view_as<int>(L4D2ZombieClass_Tank) && ability != -1)
                        {
                            if(GetEntPropFloat(ability, Prop_Send, "m_timestamp") > GetGameTime())
                            {
                                continue;
                            }
                        }

                        GetClientAbsOrigin(i, vTarget);
                        float tempDist = GetVectorDistance(vOwner, vTarget, true);

                        if( tempDist < fDist )
                        {
                            fDist = tempDist;

                            if(L4D_GetPinnedSurvivor(i) == 0)
                            {
                                nextTarget = i;
                            }
                            else
                            {
                                if(GetEntProp(i, Prop_Send, "m_zombieClass") != view_as<int>(L4D2ZombieClass_Smoker) || L4D_HasReachedSmoker(L4D_GetPinnedSurvivor(i)))
                                {
                                    nextTarget = i;
                                }
                                else
                                {
                                    nextTarget = L4D_GetPinnedSurvivor(i);   
                                }
                            }
                        }			
                    }
                }
            }
            case 1:
            {
                for( int i = 1; i <= MaxClients; i++ )
                {
                    if( i != pet && IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 3 && L4D_GetPinnedSurvivor(i) != 0 && g_iOwner[i] == 0)
                    {
                        GetClientAbsOrigin(i, vTarget);
                        float tempDist = GetVectorDistance(vOwner, vTarget, true);
                        if( tempDist < fDist )
                        {
                            fDist = tempDist;

                            if(GetEntProp(i, Prop_Send, "m_zombieClass") != view_as<int>(L4D2ZombieClass_Smoker) || L4D_HasReachedSmoker(L4D_GetPinnedSurvivor(i)))
                            {
                                nextTarget = i;
                            }
                            else
                            {
                                nextTarget = L4D_GetPinnedSurvivor(i);
                            }
                        }			
                    }
                }

                if(nextTarget == 0)
                {
                    fDist = g_fPetDist;

                    int closestIncapped = 0;

                    for( int i = 1; i <= MaxClients; i++ )
                    {
                        if( i != pet && IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2 && L4D_IsPlayerIncapacitated(i))
                        {
                            GetClientAbsOrigin(i, vTarget);
                            float tempDist = GetVectorDistance(vOwner, vTarget, true);
                            if( tempDist < fDist )
                            {
                                fDist = tempDist;
                                closestIncapped = i;
                            }	
                        }
                    }

                    // This is the closest incapped survivor. Find closest SI to it.
                    if(closestIncapped != 0)
                    {
                        float fDuration = -1.0;

                        Call_StartForward(g_fwOnCanPetReviveIncap);

                        Call_PushCell(closestIncapped);
                        Call_PushCell(pet);
                        Call_PushCell(g_iOwner[pet]);

                        Call_PushFloatRef(fDuration);

                        Call_Finish();

                        if(fDuration >= 0.0 && GetEntPropEnt(closestIncapped, Prop_Send, "m_reviveOwner") == -1 && g_iLastRevive[pet] == 0)
                        {
                            nextTarget = closestIncapped;

                            float vIncapped[3];
                            GetClientAbsOrigin(closestIncapped, vIncapped);

                            if(GetVectorDistance(vIncapped, vPet, false) < 128.0)
                            {
                                if(fDuration == 0.0)
                                {
                                    ReviveWithOwnership(closestIncapped, g_iOwner[pet]);
                                }
                                else
                                {
                                    SetEntityMoveType(pet, MOVETYPE_NONE);

                                    SetEntPropFloat(closestIncapped, Prop_Send, "m_flProgressBarStartTime", GetGameTime());
                                    SetEntPropFloat(closestIncapped, Prop_Send, "m_flProgressBarDuration", fDuration);
                                    SetEntPropEnt(closestIncapped, Prop_Send, "m_reviveOwner", pet);

                                    g_iLastRevive[pet] = closestIncapped;

                                    CreateTimer(0.1, Timer_CheckPetReviveIncap, GetClientUserId(pet), TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
                                }
                            }
                        }
                        else
                        {
                            fDist = g_fPetDist;

                            float vIncapped[3];
                            GetClientAbsOrigin(closestIncapped, vIncapped);
                            for( int i = 1; i <= MaxClients; i++ )
                            {
                                if( i != pet && IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 3 && g_iOwner[i] == 0)
                                {
                                    GetClientAbsOrigin(i, vTarget);

                                    float tempDist = GetVectorDistance(vIncapped, vTarget, true);
                                    if( tempDist < fDist )
                                    {
                                        fDist = tempDist;
                                        nextTarget = i;
                                    }			
                                }
                            }
                        }
                    }
                }

                if(nextTarget == 0)
                {
                    fDist = g_fPetDist;
                    for( int i = 1; i <= MaxClients; i++ )
                    {
                        if( i != pet && IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 3 && g_iOwner[i] == 0)
                        {
                            int ability = L4D_GetPlayerCustomAbility(i);

                            if(GetEntProp(i, Prop_Send, "m_zombieClass") == view_as<int>(L4D2ZombieClass_Tank) && ability != -1)
                            {
                                if(GetEntPropFloat(ability, Prop_Send, "m_timestamp") > GetGameTime())
                                {
                                    continue;
                                }
                            }

                            GetClientAbsOrigin(i, vTarget);
                            float tempDist = GetVectorDistance(vOwner, vTarget, true);
                            if( tempDist < fDist )
                            {
                                fDist = tempDist;
                                nextTarget = i;
                            }			
                        }
                    }
                }
            }
        }
    }

    g_iTarget[pet] = nextTarget;

    float fPetOrigin[3];
    GetEntPropVector(pet, Prop_Data, "m_vecAbsOrigin", fPetOrigin);

    bool bShouldUpdate = false;

    float fLastBracket = g_fLastBracket[pet];

    float fFlowIncrease = 325.0;

    g_fLastBracket[pet] += (fFlowIncrease / L4D2Direct_GetMapMaxFlowDistance()) * 100.0 * g_fPetUpdateRate;

    if(door != -1)
    {
        if(GetEntProp(door, Prop_Send, "m_spawnflags") & DOOR_FLAG_IGNORE_USE)
        {
            g_fLastBracket[pet] = 85.0;
        }
    }

    if(GetNextBracketPercent(fLastBracket) < GetNextBracketPercent(g_fLastBracket[pet]))
        bShouldUpdate = true;

    //float fPetFlowPercent = (L4D2Direct_GetTerrorNavAreaFlow(L4D_GetNearestNavArea(fPetOrigin)) / L4D2Direct_GetMapMaxFlowDistance()) * 100.0;

    if(g_iLastCommand[pet] != -2)
    {
        if(g_iLastCommand[pet] != g_iTarget[pet])
        {
            if(IsPlayer(g_iTarget[pet]))
            {
                g_iLastCommand[pet] = g_iTarget[pet];

                L4D2_CommandABot(pet, 0, BOT_CMD_RESET);
                L4D2_CommandABot(pet, g_iTarget[pet], BOT_CMD_ATTACK);
            }
            else if(g_iLastCommand[pet] != -1)
            {
                g_iLastCommand[pet] = -1;

                L4D2_CommandABot(pet, 0, BOT_CMD_RESET);
            }
        }
    }
    else if(bShouldUpdate)
    {
        float fTargetOrigin[3];
        if(GetCarryTargetOrigin(pet, fTargetOrigin))
        {
            //PrintToChatAll("a %.1f %.1f %.1f %.5f %.5f", fTargetOrigin[0], fTargetOrigin[1], fTargetOrigin[2], fPetFlowPercent, g_fLastBracket[pet]);
            L4D2_CommandABot(pet, 0, BOT_CMD_MOVE, fTargetOrigin);
        }
    }   
    
    //g_fLastFlow[pet] = fPetFlowPercent;

    g_hPetVictimTimer[pet] = CreateTimer(g_fPetUpdateRate, ChangeVictim_Timer, pet);
    
    return Plugin_Continue;
}

stock bool GetCarryTargetOrigin(int pet, float fTargetOrigin[3] = NULL_VECTOR)
{
    int owner = g_iOwner[pet];

    int carried = GetPlayerCarry(pet);

    if(owner == carried && GetClientButtons(carried) & IN_SPEED)
    {
        SetupInitialBracket(pet);
        return false;
    }

    float fOrigin[3];
    GetEntPropVector(pet, Prop_Data, "m_vecAbsOrigin", fOrigin);

    int finale = FindEntityByClassname(-1, "trigger_finale");
    //int elevator = FindEntityByClassname(-1, "func_elevator");

    //PrintToChatAll("%i %f %f %f", L4D2_NavAreaBuildPath(L4D_GetNearestNavArea(fOrigin), L4D_GetNearestNavArea(g_fTargetOrigin), 65535.0, 2, false), g_fTargetOrigin[0], g_fTargetOrigin[1], g_fTargetOrigin[2]);

    if(GetPlayerCarry(pet) == -1)
        return true;

    if(finale != -1)
    {
        GetEntPropVector(finale, Prop_Data, "m_vecAbsOrigin", fTargetOrigin);

        return true;
    }

    if(g_fLastBracket[pet] >= 100.0 || GetPlayerCarry(pet) != owner)
    {
        fTargetOrigin = g_fTargetOrigin;

        return true;
    }

    return FindNextBracketArea(pet, fTargetOrigin);
}
/* ========================================================================================= *
*                                        Say Command                                        *
* ========================================================================================= */

Action CmdSayPet(int client, int args)
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

    bool bCanCharger = true, bCanJockey = true;
    Action rtnCharger, rtnJockey;

    Call_StartForward(g_fwOnCanHavePets);
    
    Call_PushCell(client);
    Call_PushCell(L4D2ZombieClass_Charger);
    Call_PushCellRef(bCanCharger);

    Call_Finish(rtnCharger);

    Call_StartForward(g_fwOnCanHavePets);
    
    Call_PushCell(client);
    Call_PushCell(L4D2ZombieClass_Jockey);
    Call_PushCellRef(bCanJockey);

    Call_Finish(rtnJockey);
        
    int iClientFlags = GetUserFlagBits(client);

    if( rtnCharger <= Plugin_Continue && rtnJockey <= Plugin_Continue && g_iFlags != 0 && !(iClientFlags & g_iFlags) && !(iClientFlags & ADMFLAG_ROOT) )
    {
        ReplyToCommand(client, "[SM] You don't have enough permissions to spawn a pet.");
        return Plugin_Handled;
    }
    // Spawn random pet
    if( args == 0 )
    {
        if( GetSurvivorPets(client) >= g_iPlyPetLim )
        {
            ReplyToCommand(client, "[SM] You have reached the limit of pets you can have.");
            return Plugin_Handled;
        }
        else if( GetTotalPets() >= g_iGlobPetLim )
        {
            ReplyToCommand(client, "[SM] Total pet limit reached.");
            return Plugin_Handled;
        }

        bool bResult = false;
        bool bNoAccess = false;


        if(bCanCharger && bCanJockey)
        {
            bResult = SpawnPet(client, GetRandomInt(5, 6));
        }
        else if(bCanCharger)
        {
            bResult = SpawnPet(client, view_as<int>(L4D2ZombieClass_Charger));
        }
        else if(bCanJockey)
        {
            bResult = SpawnPet(client, view_as<int>(L4D2ZombieClass_Jockey));
        }
        else
        {
            bNoAccess = true;
        }


        if(bNoAccess)
            ReplyToCommand(client, "[SM] Error: You don't have rights to spawn a pet.");

        else if(!bResult)
            ReplyToCommand(client, "[SM] Error creating a pet, please try again.");
        else
            ReplyToCommand(client, "[SM] You have a new pet!");
            
        return Plugin_Handled;
    }
    if( args == 1 )
    {
        char sBuffer[16];
        GetCmdArg(1, sBuffer, sizeof(sBuffer));
        if( StrEqual( sBuffer, "remove") )
        {
            for( int i = 1; i <= MaxClients; i++ )
            {
                if( g_iOwner[i] == client )
                    KillPet(i);
            }
            ReplyToCommand(client, "[SM] Removed all your pets.");
        }
        else if( StrEqual(sBuffer, "jockey") || StrEqual(sBuffer, "charger") )
        {
            if( GetSurvivorPets(client) >= g_iPlyPetLim )
            {
                ReplyToCommand(client, "[SM] You have reached the limit of pets you can have.");
                return Plugin_Handled;
            }
            else if( GetTotalPets() >= g_iGlobPetLim )
            {
                ReplyToCommand(client, "[SM] Total pet limit reached.");
                return Plugin_Handled;
            }
            else if( StrEqual(sBuffer, "jockey") )
            {
                if(!bCanJockey)
                    ReplyToCommand(client, "[SM] Error: You don't have rights to spawn a Jockey pet.");

                else if( !SpawnPet(client, 5) )
                    ReplyToCommand(client, "[SM] Error creating a pet, please try again.");
                else
                    ReplyToCommand(client, "[SM] You have a new Jockey pet!");				
            }
            else
            {
                if(!bCanCharger)
                    ReplyToCommand(client, "[SM] Error: You don't have rights to spawn a Charger pet.");

                else if( !SpawnPet(client, 6) )
                    ReplyToCommand(client, "[SM] Error creating a pet, please try again.");
                else
                    ReplyToCommand(client, "[SM] You have a new Charger pet!");				
            }
        }
        else ReplyToCommand(client, "[SM] Invalid argument.");

        return Plugin_Handled;
    }
    return Plugin_Handled;
}

/* ========================================================================================= *
*                                         Functions                                         *
* ========================================================================================= */

bool SpawnPet(int client, int zClass)
{
    bool bReturn;
    float vPos[3];
    
    if( !L4D_GetRandomPZSpawnPosition(client, 5, 5, vPos) )	// Try to get a random position to spawn the pet
        GetClientAbsOrigin(client, vPos);
        
    int pet = L4D2_SpawnSpecial(zClass, vPos, NULL_VECTOR);

    g_iOwner[pet] = client;
    g_iLastCommand[pet] = -1;
    g_fLastBracket[pet] = 0.0;
    //g_fLastFlow[pet] = 0.0;
    SetEntityRenderMode(pet, RENDER_TRANSTEXTURE);	// Set rendermode
    SetEntityRenderColor(pet, 255, 255, 255, g_hPetColor.IntValue);	// Set translucency (color doesn't work)
    SetEntProp(pet, Prop_Send, "m_iGlowType", 3);	// Make pet glow
    SetEntProp(pet, Prop_Send, "m_nGlowRange", 5000);
    SetEntProp(pet, Prop_Send, "m_glowColorOverride", 39168);	// Glow color green
    if( zClass == 5 ) SetEntPropFloat(pet, Prop_Send, "m_flModelScale", g_hJockSize.FloatValue); // Only for jockeys

    UpdatePetCollisionGroup(pet);
    SDKHook(pet, SDKHook_TraceAttack, OnShootPet);	// Allows bullets to pass through the pet
    SDKHook(pet, SDKHook_OnTakeDamage, OnHurtPet);	// Prevents pet from taking any type of damage from survivors
    SetEntPropEnt(pet, Prop_Send, "m_hOwnerEntity", client);
    ResetInfectedAbility(pet, 9999.9);
    bReturn = true;
    delete g_hPetVictimTimer[pet];
    g_hPetVictimTimer[pet] = CreateTimer(g_hPetUpdateRate.FloatValue, ChangeVictim_Timer, pet);

    for(int door=0;door < sizeof(g_fNextOpenDoor[]);door++)
    {
        g_fNextOpenDoor[pet][door] = 0.0;
    }

    return bReturn;
}

void UpdatePetCollisionGroup(int pet)
{
    if(L4D_IsInLastCheckpoint(pet))
    {
        // Debris, prevents collision and also prevents counting as a Special Infected for the Safe Room count.
        // Debris makes the pet immune to trigger_hurt.
        SetEntProp(pet, Prop_Send, "m_CollisionGroup", 1);
    }
    else
    {
        // Debris trigger, prevents collision but counts as a Special Infected in the same room.
        // Unlike debris, pet is no longer immune to trigger_hurt
        SetEntProp(pet, Prop_Send, "m_CollisionGroup", 2);
    }
}
int GetSurvivorPets(int client)
{
    int result = 0;
    for( int i = 1; i <= MaxClients; i++ )
    {
        if( g_iOwner[i] == client )
            result++;
    }
    return result;
}

int GetTotalPets()
{
    int result = 0;
    for( int i = 1; i <= MaxClients; i++ )
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
        KillPet(pet);
        return;
    }
    
    g_iOwner[pet] = iArrayHumans[GetRandomInt(0, totalHumans)];
}

// Release the pet and convert it into normal SI
void WildPet(int pet)
{
    g_iOwner[pet] = 0;
    SetEntityRenderColor(pet, 255, 255, 255, 255);
    SetEntProp(pet, Prop_Send, "m_iGlowType", 0);
    SetEntProp(pet, Prop_Send, "m_nGlowRange", 5000);
    SetEntProp(pet, Prop_Send, "m_glowColorOverride", 39168);
    SetEntProp(pet, Prop_Send, "m_CollisionGroup", 5);
    SDKUnhook(pet, SDKHook_TraceAttack, OnShootPet);
    SDKUnhook(pet, SDKHook_OnTakeDamage, OnHurtPet);
    ResetInfectedAbility(pet, 1.0);
}

int FindFirstCommonAvailable()
{
    int i = -1;
    while( (i = FindEntityByClassname(i, "infected")) != -1 )
        return i;

    return 0;
}

void KillPet(int pet)
{
    if( IsClientInGame(pet) && IsPlayerAlive(pet) && IsFakeClient(pet) ) // Just in case is not an alive bot here
        ForcePlayerSuicide(pet);
        
    g_iOwner[pet] = 0;
    g_iTarget[pet] = 0;
    g_iNextCheck[pet] = 0;
}

void HookPlayers()
{
    for( int i = 1; i <= MaxClients; i++ )
    {
        if( IsClientInGame(i) )
            SDKHook(i, SDKHook_OnTakeDamage, ScaleFF);
    }	
}

void UnhookPlayers()
{
    for( int i = 1; i <= MaxClients; i++ )
    {
        if( IsClientInGame(i) )
            SDKUnhook(i, SDKHook_OnTakeDamage, ScaleFF);
    }
}

// If infected have they ability used they will go directly to their target/owner instead of
// searching a proper spot to use their unusable ability
void ResetInfectedAbility(int client, float time)
{
    if( client > 0 )
    {
        if( IsClientInGame(client) && IsPlayerAlive(client) && GetClientTeam(client) == 3 )
        {
            int ability = GetEntPropEnt(client, Prop_Send, "m_customAbility");
            if( ability > 0 )
            {
                SetEntPropFloat(ability, Prop_Send, "m_duration", time);
                SetEntPropFloat(ability, Prop_Send, "m_timestamp", GetGameTime() + time);
            }
        }
    }
}

bool IsNotCarryable(int client)
{
    if(g_iCarrier[client] != -1 && g_iOwner[g_iCarrier[client]] == client && !L4D_IsInLastCheckpoint(client))
    {
        return true;
    }

    else if(L4D_IsInLastCheckpoint(client))
        return true;

    else if(IsFakeClient(client))
        return true;
    
    return false;
}

int GetPlayerCarry(int client)
{
    for(int i=1;i <= MaxClients;i++)
    {
        if(g_iCarrier[i] == client)
        {
            return i;
        }
    }

    return -1;
}

stock void StartCarryBetweenPlayers(int carrier, int carried)
{
    g_iCarrier[carried] = carrier;
    g_bCarriedThisRound[carried] = true;

    SetupInitialBracket(carrier);

    if(g_hPetVictimTimer[carrier] != INVALID_HANDLE)
    {
        TriggerTimer(g_hPetVictimTimer[carrier]);
    }
}

stock void SetupInitialBracket(int carrier)
{
    float fPetOrigin[3];
    GetEntPropVector(carrier, Prop_Data, "m_vecAbsOrigin", fPetOrigin);

    float fMaxFlow = L4D2Direct_GetMapMaxFlowDistance();

    float fPetFlowPercent = (L4D2Direct_GetTerrorNavAreaFlow(L4D_GetNearestNavArea(fPetOrigin)) / fMaxFlow) * 100.0;

    if(fPetFlowPercent <= 0.0)
        fPetFlowPercent = 0.0;

    // reduce by 0.01 to force calculation immediately by making next timer switch the bracket.
    g_fLastBracket[carrier] = GetNextBracketPercent(fPetFlowPercent) - 0.01;

    if(g_fLastBracket[carrier] > 100.0)
        g_fLastBracket[carrier] = 100.0;

    int door = L4D_GetCheckpointLast();

    if(door != -1)
    {
        if(GetEntProp(door, Prop_Send, "m_spawnflags") & DOOR_FLAG_IGNORE_USE)
        {
            g_fLastBracket[carrier] = 85.0;
        }
    }
}
stock void EndCarryBetweenPlayers(int carrier, int carried, bool bDontTeleport = false)
{
    g_iCarrier[carried] = -1;
    g_iLastCommand[carrier] = 0;
    g_fLastBracket[carrier] = 0.0;
    //g_fLastFlow[carrier] = 0.0;

    float fOrigin[3];
    GetEntPropVector(carried, Prop_Data, "m_vecAbsOrigin", fOrigin);

    if(IsPlayerStuck(carried, fOrigin) && !bDontTeleport)
    {
        // -1 * CARRY_OFFSET to teleport the carried back to the carrier, and not vise versa.
        if(IsPlayerStuck(carried, fOrigin, -1 * CARRY_OFFSET))
        {
            float fCarrierOrigin[3];
            GetEntPropVector(carrier, Prop_Data, "m_vecAbsOrigin", fCarrierOrigin);

            TeleportEntity(carried, fCarrierOrigin, NULL_VECTOR, NULL_VECTOR);
        }
        else
        {
            // decrease offset to teleport the carried back to the carrier, and not vise versa.
            fOrigin[2] -= CARRY_OFFSET;

            TeleportEntity(carried, fOrigin, NULL_VECTOR, NULL_VECTOR);

            int zclass = GetEntProp(carrier, Prop_Send, "m_zombieClass");

            int owner = g_iOwner[carrier];

            KillPet(carrier);

            if(owner != 0)
            {
                SpawnPet(owner, zclass);
            }
        }
    }
}


stock bool IsPlayerStuck(int client, const float Origin[3] = NULL_VECTOR, float HeightOffset = 0.0)
{
    float vecMin[3], vecMax[3], vecOrigin[3];
    
    GetClientMins(client, vecMin);
    GetClientMaxs(client, vecMax);
    
    if(UC_IsNullVector(Origin))
        GetClientAbsOrigin(client, vecOrigin);
        
    else
    {
        vecOrigin = Origin;
        vecOrigin[2] += HeightOffset;
    }
    
    TR_TraceHullFilter(vecOrigin, vecOrigin, vecMin, vecMax, MASK_PLAYERSOLID, TraceRayDontHitPlayers);
    return TR_DidHit();
}

public bool TraceRayDontHitPlayers(int entityhit, int mask) 
{
    return (entityhit>MaxClients || entityhit == 0);
}

stock bool UC_IsNullVector(const float Vector[3])
{
    return (Vector[0] == NULL_VECTOR[0] && Vector[0] == NULL_VECTOR[1] && Vector[2] == NULL_VECTOR[2]);
}

stock int GetEntityHealth(int entity)
{
    return GetEntProp(entity, Prop_Data, "m_iHealth");
}

stock void ReviveWithOwnership(int victim, int reviver)
{
    if(L4D_GetClientTeam(reviver) == L4DTeam_Infected)
    {
        int owner = GetEntPropEnt(reviver, Prop_Send, "m_hOwnerEntity");

        if(owner == -1)
            return;

        reviver = owner;
    }
    
    g_iOverrideRevive = reviver;

    SetEntPropEnt(victim, Prop_Send, "m_reviveOwner", -1);
    SetEntPropFloat(victim, Prop_Send, "m_flProgressBarStartTime", 0.0);
    SetEntPropFloat(victim, Prop_Send, "m_flProgressBarDuration", 0.0);

    HookEvent("revive_success", Event_ReviveSuccessPre, EventHookMode_Pre);
    L4D_ReviveSurvivor(victim);
    UnhookEvent("revive_success", Event_ReviveSuccessPre, EventHookMode_Pre);

    g_iOverrideRevive = 0;

    SetEntPropEnt(victim, Prop_Send, "m_reviveOwner", -1);
}

public Action Event_ReviveSuccessPre(Event event, const char[] name, bool dontBroadcast)
{
    if(g_iOverrideRevive != 0)
    {
        SetEventInt(event, "userid", GetClientUserId(g_iOverrideRevive));

        g_iOverrideRevive = 0;

        return Plugin_Changed;
    }

    return Plugin_Continue;
}

stock int CountPinnedSurvivors()
{
    int count = 0;

    for(int i = 1; i <= MaxClients; i++ )
    {
        if(!IsClientInGame(i))
            continue;
            
        else if(L4D_GetClientTeam(i) != L4DTeam_Survivor)
            continue;
            
        else if(!IsPlayerAlive(i))
            continue;

        else if(L4D_GetPinnedInfected(i) == 0)
            continue;

        count++;
    }

    return count;
}

stock bool FindRandomSpotInSafeRoom(bool bStartSafeRoom, float fOrigin[3])
{
    ArrayList aAreas = CreateArray(1);
    L4D_GetAllNavAreas(aAreas);

    ArrayList aLotteryAreas = CreateArray(1);

    int totalEntries = 0;

    for(int i=0;i < aAreas.Length;i++)
    {
        Address area = aAreas.Get(i);

        if(!(L4D_GetNavArea_AttributeFlags(area) & NAV_BASE_MOSTLY_FLAT))
        {
            aLotteryAreas.Push(0);
            continue;
        }
        // Some stupid maps like Blood Harvest finale and The Passing finale have CHECKPOINT inside a FINALE marked area.
        else if(L4D_GetNavArea_SpawnAttributes(area) & NAV_SPAWN_FINALE)
        {
            aLotteryAreas.Push(0);
            continue;
        }

        // https://developer.valvesoftware.com/wiki/List_of_L4D_Series_Nav_Mesh_Attributes
        else if(!(L4D_GetNavArea_SpawnAttributes(area) & NAV_SPAWN_CHECKPOINT))
        {
            aLotteryAreas.Push(0);
            continue;
        }
        
        float fCenter[3];

        L4D_GetNavAreaCenter(area, fCenter);

        if((bStartSafeRoom && L4D_IsPositionInFirstCheckpoint(fCenter)) || (!bStartSafeRoom && L4D_IsPositionInLastCheckpoint(fCenter)))
        {
            // Direct correlation between size of nav area and how likely it is to win the raffle to ensure a random spot is given for the average of the safe room.
            float fSize[3];
            L4D_GetNavAreaSize(area, fSize);

            // Ignore height.
            fSize[2] = 0.0;

            // The bigger the area is, the more likely it is to win the lottery.
            int entries = RoundFloat(GetVectorLength(fSize));
            totalEntries += entries;

            aLotteryAreas.Push(entries);

            continue;
        }

        aLotteryAreas.Push(0);
    }

    int luckyNumber = GetRandomInt(0, totalEntries);
    Address luckyArea = Address_Null;
    
    int relativeTotalEntries = 0;
    
    for(int i=0;i < aLotteryAreas.Length;i++)
    {
        // We can do this because they are structured the same.
        Address area = aAreas.Get(i);
        int entries = aLotteryAreas.Get(i);

        if(luckyNumber <= relativeTotalEntries + entries)
        {
            luckyArea = area;
            
            break;
        }	
        
        relativeTotalEntries += entries;
    }

    float fWinnerSpot[3];
    L4D_FindRandomSpot(view_as<int>(luckyArea), fWinnerSpot);

    int door = -1;

    while((door = FindEntityByClassname(door, "prop_door_rotating_checkpoint")) != -1)
    {
        float fDoorOrigin[3];
        GetEntPropVector(door, Prop_Data, "m_vecAbsOrigin", fDoorOrigin);

        if(GetVectorDistance(fDoorOrigin, fWinnerSpot) < g_iDistanceDoor)
        {
            // Slowly care less about the distance until it's impossible to ignore.
            g_iDistanceDoor--;

            return FindRandomSpotInSafeRoom(bStartSafeRoom, fOrigin);
        }
    }

    door = -1;
    
    // No Mercy first chapter.
    while((door = FindEntityByClassname(door, "prop_door_rotating")) != -1)
    {
        float fDoorOrigin[3];
        GetEntPropVector(door, Prop_Data, "m_vecAbsOrigin", fDoorOrigin);

        if(GetVectorDistance(fDoorOrigin, fWinnerSpot) < g_iDistanceDoor)
        {
            // Slowly care less about the distance until it's impossible to ignore.
            g_iDistanceDoor--;
            return FindRandomSpotInSafeRoom(bStartSafeRoom, fOrigin);
        }
    }

    CloseHandle(aAreas);
    fOrigin = fWinnerSpot;

    return true;
}

stock bool FindNextBracketArea(int pet, float fOrigin[3])
{
    float fMaxFlow = L4D2Direct_GetMapMaxFlowDistance();

    float fPetOrigin[3];
    GetEntPropVector(pet, Prop_Data, "m_vecAbsOrigin", fPetOrigin);

    float fPetFlowPercent = (L4D2Direct_GetTerrorNavAreaFlow(L4D_GetNearestNavArea(fPetOrigin)) / fMaxFlow) * 100.0;

    // Rounds to ceil to next multiplier of 5.
    float fBracketPercent = GetNextBracketPercent(g_fLastBracket[pet]);

    ArrayList aAreas = CreateArray(1);
    L4D_GetAllNavAreas(aAreas);

    Address winnerArea = Address_Null;
    float fWinnerPercent = 0.0;

    for(int i=0;i < aAreas.Length;i++)
    {
        Address area = aAreas.Get(i);

        float fFlowPercent = (L4D2Direct_GetTerrorNavAreaFlow(area) / fMaxFlow) * 100.0;

        if(fFlowPercent < fPetFlowPercent)
            continue;

        else if(fFlowPercent > fBracketPercent)
            continue;

        else if(L4D_GetNavArea_AttributeFlags(area) & NAV_BASE_CROUCH)
            continue;
        
        if(fWinnerPercent < fFlowPercent)
        {
            winnerArea = area;
            fWinnerPercent = fFlowPercent;
        }
    }

    if(winnerArea == Address_Null)
    {
        return false;
    }
    
    float fWinnerSpot[3];
    L4D_GetNavAreaCenter(winnerArea, fWinnerSpot);

    CloseHandle(aAreas);
    fOrigin = fWinnerSpot;

    return true;
}

stock float GetNextBracketPercent(float fLastBracket)
{
    int iBracketJumps = 5;

    float fBracketPercent = float(RoundToCeil((fLastBracket + 0.01) / float(iBracketJumps)) * iBracketJumps);

    if(fBracketPercent > 100.0)
        return 101.0;

    return fBracketPercent;
}

/*============================================================================================
                                    Changelog
----------------------------------------------------------------------------------------------
* 1.1.2 (08-Dec-2022)
    - Changed detouring method.
    - Fix minor code erros.

* 1.1.1 (22-Jun-2022)
    - Fixed l4d2_pets_attack ConVar limits.
    
* 1.1  (22-Jun-2022)
    - Players now can have also a Jockey as a pet.
    - Pets will attempt to attack other special infected.
    - Improved pet behaviour.
    - Pet noise pitch can be changed. 
    - New ConVars (l4d2_pets_pitch, l4d2_pets_attack, l4d2_pets_dmg_scale,
    l4d2_pets_target_dist)

* 1.0.1 (21-Jan-2022)
    - Pets can attempt to destroy obstacles.
    
* 1.0   (21-Jan-2022)
    - First release
============================================================================================*/
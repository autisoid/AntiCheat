/*
    xWhitey's AntiCheat (Sven Co-op plugin) source file
    Authors of the code: xWhitey, Sven Co-op community (/incognico/ "Nico", "twilightzone" server's scripts, Mikk155).
    Special thanks to: frizzy (the main idea?), ilyadud21 "vorbis" (testing) and, of course, a1 (testing, finding false positives)! These guys helped me to test the anticheat in the first place.
    Feel free to PM me @ Discord: @tyabus if I forgot to mention somebody.
    Do not delete this comment block. Respect others' work!
*/

enum ESpeedhackState {
    kSpeedhackNot = 0,
    kSpeedhackFast,
    kSpeedhackSlow //We don't really detect "slowhack", we only detect freeze and 0.01 speedhack (!!!)
}

class CPlayerData {
    CPlayerData() {
        m_flLastPreThinkCallTime = m_flLastPenaltyApplyTime = m_flTheTimePlayerWasAtThatOrigin = m_flAnimTime = m_flPreviousAnimTimeDelta = m_flLastSpeedhackPenaltyApplyTime = 0.f;
        m_vecLastOrigin = m_vecLastOriginUtilStartedLagging = g_vecZero;
        m_bHasMovedSinceLastOriginPenaltyApply = m_bShouldApplyStrictPenalty = m_bIsHeavilyLagging = m_bIsClientsidelyFrozen = false;
        m_nTimesAnimDeltaWasZero = m_nTimesAnimDeltaWasTheSame = m_nTimesSpeedhacked = m_iPreThinkCallCounter = m_iPreThinkAvgCallCount = m_nTimesCallCountWasSuspicious = m_nViolations = 0;
        m_eSpeedhackState = kSpeedhackNot;
        m_flLastFwdBtnUpdateTime = m_flLastBackBtnUpdateTime = m_flLastLeftBtnUpdateTime = m_flLastRightBtnUpdateTime = 0.f;
        m_flCallCounterTimer = 0.f;
    }

    float m_flLastPreThinkCallTime; //Once player thinks, we save the time when they "thought".
    float m_flLastPenaltyApplyTime; //Last "anti-air-stuck" penalty apply time. Although it also works with FakeLag :D
    Vector m_vecLastOrigin; //The last origin where player was once "thought".
    float m_flTheTimePlayerWasAtThatOrigin; //The clock time when we saved last player's origin
    bool m_bHasMovedSinceLastOriginPenaltyApply; //Whether the player has moved once we saved their last origin
    float m_flAnimTime; //Last animation blend association time
    float m_flPreviousAnimTimeDelta; //Current animation time - our saved animation time (delta)
    int m_nTimesAnimDeltaWasZero; //When delta is zero, this usually means the player is slowhacking or frozen.
    int m_nTimesAnimDeltaWasTheSame; //When delta is the same amongst a lot of "Think" calls, this usally means the player is speedhacking.
    ESpeedhackState m_eSpeedhackState; //Speedhack state (is it really needed? Lol.)
    float m_flLastSpeedhackPenaltyApplyTime; //Last speedhack penalty apply time
    int m_nTimesSpeedhacked; //How many times did the player speedhack?
    
    int m_iPreThinkCallCounter; //How many times does the player "Think" per 0.1 second? (increases)
    float m_flCallCounterTimer; //The time we use to count calls per 0.1 second
    int m_iPreThinkAvgCallCount; //How many times does the player "Think" per 0.1 second? (final value)
    int m_nTimesCallCountWasSuspicious; //How many times was the call count value suspicious?
    
    int m_nViolations; //Player's violations
    
    //TODO: impl "strict penalty" and "loyal penalty"
    bool m_bShouldApplyStrictPenalty; //We would not apply strict penalty rules if the player is lagging. Although we don't let 'em lag so much
    Vector m_vecLastOriginUtilStartedLagging; //We save the position where the player was before they started lagging.
    bool m_bIsHeavilyLagging; //The player is choking packets. We don't let 'em choke more than 17 packets tho
    
    bool m_bIsClientsidelyFrozen; //Determines whether the player is frozen on their side
    
    //Player's button update time
    float m_flLastFwdBtnUpdateTime;
    float m_flLastBackBtnUpdateTime;
    float m_flLastLeftBtnUpdateTime;
    float m_flLastRightBtnUpdateTime;
}

array<CPlayerData@> g_apPlayerData;

CScheduledFunction@ g_lpfnTheChecker = null;

void PluginInit() {
    g_Module.ScriptInfo.SetAuthor("xWhitey");
    g_Module.ScriptInfo.SetContactInfo("tyabus @ Discord");
    
    g_apPlayerData.resize(0);
    g_apPlayerData.resize(33);
    
    //Initializing player datas
    for (uint idx = 0; idx < g_apPlayerData.length(); idx++) {
        @g_apPlayerData[idx] = CPlayerData();
    }
    
    if (g_lpfnTheChecker is null)
        @g_lpfnTheChecker = g_Scheduler.SetInterval("Checker", 0.05f);
    
    g_Hooks.RegisterHook(Hooks::Player::PlayerPreThink, @HOOKED_PlayerPreThink);
}

void MapInit() {
    g_apPlayerData.resize(0);
    g_apPlayerData.resize(33);
        
    //Initializing player datas
    for (uint idx = 0; idx < g_apPlayerData.length(); idx++) {
        @g_apPlayerData[idx] = CPlayerData();
    }
}

//Emulating player movement even if they're frozen.
void ApplyPenalty(CBasePlayer@ _Player, uint& in _HowMuch) {
    float flForwardSpeed = 0.0f;
    float flUpMove = (_Player.pev.button & IN_JUMP) != 0 ? 320.f : 0.0f;
    if ((_Player.pev.button & IN_FORWARD) != 0)
        flForwardSpeed += 320.f;
    if ((_Player.pev.button & IN_BACK) != 0)
        flForwardSpeed -= 320.f;
                
    float flSideSpeed = 0.0f;
    if ((_Player.pev.button & IN_MOVERIGHT) != 0)
        flSideSpeed += 320.f;
    if ((_Player.pev.button & IN_MOVELEFT) != 0)
        flSideSpeed -= 320.f;

    for (uint i = 0; i < _HowMuch; i++) {
        g_EngineFuncs.RunPlayerMove(_Player.edict(), _Player.pev.v_angle, flForwardSpeed, flSideSpeed, flUpMove, _Player.pev.button, _Player.pev.impulse, 5);
    }
}

//Here we do various tricky operations to check whether the player is frozen or no
void Checker() {
    for (uint idx = 0; idx < g_apPlayerData.length(); idx++) {
        CPlayerData@ pData = g_apPlayerData[idx];
        if (pData is null) continue;
        CBasePlayer@ pPlayer = g_PlayerFuncs.FindPlayerByIndex(idx);
        if (pPlayer is null or !pPlayer.IsConnected()) continue;
        float flCurrentEngineTime = g_EngineFuncs.Time();
        if ((pPlayer.pev.flags & FL_FROZEN) != 0 && pData.m_flLastSpeedhackPenaltyApplyTime != 0.f) {
            if (flCurrentEngineTime - pData.m_flLastSpeedhackPenaltyApplyTime >= 5.f) {
                pPlayer.pev.flags &= ~FL_FROZEN;
                pData.m_flLastSpeedhackPenaltyApplyTime = 0.f;
            }
        }
        if (flCurrentEngineTime - pData.m_flLastPreThinkCallTime > 0.2f) {
            if (flCurrentEngineTime - pData.m_flLastPenaltyApplyTime < 0.5f) continue;
            if (pData.m_bIsHeavilyLagging) continue;
            pData.m_bIsClientsidelyFrozen = true;
           
            ApplyPenalty(pPlayer, 35);
            //g_PlayerFuncs.ClientPrint(pPlayer, HUD_PRINTTALK, "[VIO] You failed AirStuck (It took too long for you to update your position)\n");
            
            pData.m_flLastPenaltyApplyTime = flCurrentEngineTime;
        } else {
            pData.m_bIsClientsidelyFrozen = false;
        }
        if (pData.m_vecLastOrigin != g_vecZero) {
            if (pData.m_vecLastOrigin != pPlayer.pev.origin) {
                pData.m_vecLastOrigin = pPlayer.pev.origin;
                pData.m_bHasMovedSinceLastOriginPenaltyApply = true;
                pData.m_bIsClientsidelyFrozen = false;
            } else {
                if (pData.m_bHasMovedSinceLastOriginPenaltyApply) {
                    pData.m_flTheTimePlayerWasAtThatOrigin = flCurrentEngineTime;
                    pData.m_bHasMovedSinceLastOriginPenaltyApply = false;
                }
                if (pPlayer.pev.velocity.Length() != 0.f && flCurrentEngineTime - pData.m_flTheTimePlayerWasAtThatOrigin > 0.05f) {
                    pData.m_bIsClientsidelyFrozen = true;
                    ApplyPenalty(pPlayer, 15);
                    //g_PlayerFuncs.ClientPrint(pPlayer, HUD_PRINTTALK, "[VIO] You failed AirStuck (You didn't move to expected position in expected time)\n");
                }
            }
        } else {
            pData.m_vecLastOrigin = pPlayer.pev.origin;
            pData.m_bIsClientsidelyFrozen = false;
        }
        if (pData.m_eSpeedhackState == kSpeedhackSlow) {
            pData.m_bIsClientsidelyFrozen = true;
            ApplyPenalty(pPlayer, 10);
            //g_PlayerFuncs.ClientPrint(pPlayer, HUD_PRINTTALK, "[VIO] You failed AirStuck (Animation blend association time was zero multiple times)\n");
        }
    }
}

HookReturnCode HOOKED_PlayerPreThink(CBasePlayer@ _Player, uint& out _Flags) {
    int iPlayerIdx = _Player.entindex();
    
    CPlayerData@ pData = g_apPlayerData[iPlayerIdx];
    if (pData is null) return HOOK_CONTINUE;
    float flCurrentEngineTime = g_EngineFuncs.Time();
    
    if (pData.m_flCallCounterTimer == 0.f) {
        pData.m_flCallCounterTimer = flCurrentEngineTime;
        pData.m_iPreThinkCallCounter++;
    } else {
        pData.m_iPreThinkCallCounter++;
        if (flCurrentEngineTime - pData.m_flCallCounterTimer >= 0.01f) {
            pData.m_iPreThinkAvgCallCount = pData.m_iPreThinkCallCounter;
            if (pData.m_iPreThinkCallCounter >= 20 /* suspicious value */ && !pData.m_bIsClientsidelyFrozen) {
                pData.m_nTimesCallCountWasSuspicious++;
            }
            pData.m_iPreThinkCallCounter = 0;
            pData.m_flCallCounterTimer = flCurrentEngineTime;
        }
    }
    
    if (pData.m_nTimesCallCountWasSuspicious > (pData.m_bIsHeavilyLagging ? 5 : 2) && (_Player.pev.flags & FL_FROZEN) == 0 && pData.m_iPreThinkAvgCallCount >= 20) {
        pData.m_nViolations++;
        //g_PlayerFuncs.ClientPrint(_Player, HUD_PRINTTALK, "[VIO] You failed Speedhack (VL: " + string(pData.m_nViolations) + ", PPS: " + string(pData.m_iPreThinkAvgCallCount) + ")\n");
        pData.m_nTimesCallCountWasSuspicious = 0;
    }
    
    pData.m_flLastPreThinkCallTime = flCurrentEngineTime;
    
    if (pData.m_flAnimTime == 0.f) {
        pData.m_flAnimTime = _Player.pev.animtime;
    } else {
        if (_Player.IsAlive() && (_Player.pev.flags & FL_FROZEN) == 0 /*&& (_Player.pev.sequence < 12 || _Player.pev.sequence > 18)*/ /* death anims could cause false positive */) {
            float flFwdBtnDelta = flCurrentEngineTime - pData.m_flLastFwdBtnUpdateTime;
            float flBackBtnDelta = flCurrentEngineTime - pData.m_flLastBackBtnUpdateTime;
            float flLeftBtnDelta = flCurrentEngineTime - pData.m_flLastLeftBtnUpdateTime;
            float flRightBtnDelta = flCurrentEngineTime - pData.m_flLastRightBtnUpdateTime;
            float flTotalBtnsDelta = flFwdBtnDelta + flBackBtnDelta + flLeftBtnDelta + flRightBtnDelta;
        
            float flCurrentAnimTimeDelta = _Player.pev.animtime - pData.m_flAnimTime;
            if (pData.m_flPreviousAnimTimeDelta != 0.f) {
                pData.m_nTimesAnimDeltaWasZero = 0;
                if (pData.m_flPreviousAnimTimeDelta == flCurrentAnimTimeDelta) {
                    pData.m_nTimesAnimDeltaWasTheSame++;
                } else {
                    pData.m_flPreviousAnimTimeDelta = flCurrentAnimTimeDelta;
                    pData.m_nTimesAnimDeltaWasTheSame = 0;
                    pData.m_eSpeedhackState = kSpeedhackNot;
                }
                int iPenaltyCount = 2;
                if (flTotalBtnsDelta <= 0.1f /* player is spamming movement keys, this false positive was detected by a1, thanks =) */) iPenaltyCount += 1;
                if (pData.m_nTimesAnimDeltaWasTheSame > iPenaltyCount && pData.m_nViolations > 5) {
                    pData.m_nViolations = 0;    
                    pData.m_nTimesSpeedhacked++;
                    pData.m_eSpeedhackState = kSpeedhackFast;
                    pData.m_flLastSpeedhackPenaltyApplyTime = flCurrentEngineTime;
                    //g_PlayerFuncs.ClientPrintAll(HUD_PRINTTALK, "Applied penalty!\n");
                    _Player.pev.flags |= FL_FROZEN;
                }
            } else {
                pData.m_nTimesAnimDeltaWasZero++;
                pData.m_flPreviousAnimTimeDelta = flCurrentAnimTimeDelta;
                if (pData.m_nTimesAnimDeltaWasZero > 5) { //Well, it detects only REALLY low values as like 0.01
                    pData.m_eSpeedhackState = kSpeedhackSlow;
                    if (pData.m_vecLastOriginUtilStartedLagging != g_vecZero) {
                        if (pData.m_vecLastOriginUtilStartedLagging != _Player.pev.origin) {
                            pData.m_bIsHeavilyLagging = false;
                            if (pData.m_nTimesAnimDeltaWasZero > 17) {
                                g_EntityFuncs.SetOrigin(_Player, pData.m_vecLastOriginUtilStartedLagging);
                            }
                            pData.m_vecLastOriginUtilStartedLagging = g_vecZero;
                        } else {
                            pData.m_bIsHeavilyLagging = true;
                        }
                    } else {
                        pData.m_vecLastOriginUtilStartedLagging = _Player.pev.origin;
                    }
                }
            }
        } else {
            pData.m_nTimesAnimDeltaWasZero = 0;
            pData.m_nTimesAnimDeltaWasTheSame = 0;
            pData.m_eSpeedhackState = kSpeedhackNot;
        }
        pData.m_flAnimTime = _Player.pev.animtime;
    }
    
    if ((_Player.pev.button & IN_FORWARD) != 0)
        pData.m_flLastFwdBtnUpdateTime = flCurrentEngineTime;
    if ((_Player.pev.button & IN_BACK) != 0)
        pData.m_flLastBackBtnUpdateTime = flCurrentEngineTime;
    if ((_Player.pev.button & IN_MOVELEFT) != 0)
        pData.m_flLastLeftBtnUpdateTime = flCurrentEngineTime;
    if ((_Player.pev.button & IN_MOVERIGHT) != 0)
        pData.m_flLastRightBtnUpdateTime = flCurrentEngineTime;

    return HOOK_CONTINUE;
}

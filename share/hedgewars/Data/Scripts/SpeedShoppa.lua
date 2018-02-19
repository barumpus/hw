--[=[
Speed Shoppa Mission Framework for Hedgewars

This is a simple library intended to make setting up simple training missions a trivial
task. The library has been created to reduce redundancy in Lua scripts.

The framework generates complete and fully Speed Shoppa missions by just
one function call.

The missions generated by this script are all the same:
- The player will get a team with a single hedgehog.
- The team gets infinite ropes.
- A fixed set of crates will spawn at predefined positions.
- The mission ends successfully when all crates have been collected
- The mission ends unsuccessfully when the time runs out or the hedgehog dies
- When the mission ends, the time it took to finish the mission is shown

To use this library, you first have to load it and to call SpeedShoppaMission once with
the appropriate parameters. Really, that’s all!
See the comment of SpeedShoppaMission for a specification of all parameters.

]=]

HedgewarsScriptLoad("/Scripts/Locale.lua")

--[[
SpeedShoppaMission(params)

This function sets up the *entire* mission and needs one argument: params.
The argument “params” is a table containing fields which describe the training mission.
	mandatory fields:
	- map:			the name of the map to be used
	- theme:		the name of the theme (does not need to be a standalone theme)
	- time:			the time limit in milliseconds
	- crates:		The coordinates of where the crates will be spawned.
				It is a table containing tables containing coordinates of format
				{ x=value, y=value }. Example:
					crates = {
						{ x = 324, y = 43 },
						{ x = 123, y = 56 },
						{ x = 6, y = 0 },
					}
				There must be at least 1 crate.

	optional fields:
	- missionTitle:		the name of the mission (optional but highly recommended) (default: "Speed Shoppa")
	- hogHat:		hat of the hedgehog (default: "NoHat")
	- hogName:		name of the hedgehog (default: "Roper")
	- teamName:		name of the hedgehog’s team (default: "Shoppers")
	- teamGrave:		name of the hedgehog’s grave (default: "Statue")
	- teamFlag:		name of the team’s flag (default: "cm_shoppa")
	- clanColor:		color of the (only) clan (default: 0xFF0204, which is a red tone)
	- goalText:		A short string explaining the goal of the mission
				(default: "Use your rope to collect all crates as fast as possible.")
	- faceLeft:		If true, the hog faces to the left initially, if false, it faces to the right.
				(default: false (=right))
	- crateType		Specify the type of crate (this has no gameplay effect), pick one of
				"ammo", "utility", "health". Default: "ammo"
	- extra_onGameStart:	A function which is called at the end of this script's onGameStart. It takes no parameters.
				You could use this to spawn additional gears like girders or mines.
	- extra_onGameInit:	A function which is called at the end of this script's onGameInit.
]]


local playerHog
local gameStarted = false
local cratesCollected = 0
local gameEnded = false
local timeOut = false
local hogHurt = false
local endTime

local crates

function SpeedShoppaMission(params)
	if params.hogHat == nil then params.hogHat = "NoHat" end
	if params.hogName == nil then params.hogName = loc("Roper") end
	if params.teamName == nil then params.teamName = loc("Shoppers") end
	if params.goalText == nil then params.goalText = loc("Use your rope to collect all crates as fast as possible.") end
	if params.missionTitle == nil then params.missionTitle = loc("Speed Shoppa") end
	if params.clanColor == nil then params.clanColor = 0xFF0204 end
	if params.teamGrave == nil then params.teamGrave = "Statue" end
	if params.teamFlag == nil then params.teamFlag = "cm_shoppa" end
	if params.extra_onGameInit == nil then params.extra_onGameInit = function() end end
	if params.extra_onGameStart == nil then params.extra_onGameStart = function() end end
	if params.faceLeft == nil then params.faceLeft = false end

	crates = params.crates
	startTime = params.time

	_G.onGameInit = function()
		GameFlags = gfDisableWind + gfOneClanMode + gfBorder + gfSolidLand
		TurnTime = startTime
		CaseFreq = 0 
		MinesNum = 0 
		Explosives = 0 
		Delay = 10 
		Theme = params.theme
		Map = params.map
		-- Disable Sudden Death
		WaterRise = 0
		HealthDecrease = 0
	
		AddTeam(params.teamName, params.clanColor, params.teamGrave, "Castle", "Default", params.teamFlag)
		playerHog = AddHog(params.hogName, 0, 1, params.hogHat)
		HogTurnLeft(playerHog, params.faceLeft)
		
		SetGearPosition(playerHog, params.hog_x, params.hog_y)

		params.extra_onGameInit()
	end

	_G.onAmmoStoreInit = function()
		SetAmmo(amRope, 9, 0, 0, 1)
	end

	_G.onGameStart = function()
		SendHealthStatsOff()
		ShowMission(params.missionTitle, loc("Challenge"), params.goalText, -amRope, 5000) 
		for i=1,#crates do
			spawnCrate(crates[i].x, crates[i].y)
		end
		params.extra_onGameStart()
	end

	_G.onNewTurn = function()
		SetWeapon(amRope)
		gameStarted = true
	end
	_G.onGearDelete = function(gear)
		if GetGearType(gear) == gtCase and not hogHurt and not timeOut then
			cratesCollected = cratesCollected + 1
			PlaySound(sndShotgunReload)
			if cratesCollected == #crates then
				endTime = TurnTimeLeft
				finalize()
			else
				AddCaption(string.format(loc("%d crate(s) remaining"), #crates - cratesCollected))
			end
		elseif gear == playerHog then
			finalize()
		end
	end

	_G.onGearDamage = function(gear)
		if gear == playerHog then
			hogHurt = true
		end
	end


	_G.onGameTick20 = function()
		if TurnTimeLeft < 40 and TurnTimeLeft > 0 and gameStarted and not timeOut and not gameEnded then
			timeOut = true
			AddCaption(loc("Time's up!"))
			SetHealth(playerHog, 0)
			hogHurt = true
		end
	end

	_G.finalize = function()
		if not gameEnded then
			if cratesCollected == #crates then
				PlaySound(sndVictory, playerHog)
				SetEffect(playerHog, heInvulnerable, 1)
				SetState(playerHog, bor(GetState(playerHog), gstWinner))
				SetState(playerHog, band(GetState(playerHog), bnot(gstHHDriven)))
				AddCaption(loc("Challenge completed!"))
				SendStat(siGameResult, loc("Challenge completed!"))
				SendStat(siPointType, loc("milliseconds"))
				local time = startTime - endTime
				SendStat(siPlayerKills, tostring(time), params.teamName)
				SendStat(siCustomAchievement, string.format(loc("You have finished the challenge in %.3f s."), (time/1000)))
				TurnTimeLeft = 0
			else
				SendStat(siGameResult, loc("Challenge failed!"))
				SendStat(siPointType, loc("crate(s)"))
				SendStat(siPlayerKills, tostring(cratesCollected), params.teamName)
				SendStat(siCustomAchievement, string.format(loc("You have collected %d out of %d crate(s)."), cratesCollected, #crates))
			end
			gameEnded = true
			EndGame()
		end
	end

	_G.spawnCrate = function(x, y)
		if params.crateType == "utility" then
			SpawnFakeUtilityCrate(x, y, false, false)
		elseif params.crateType == "ammo" then
			SpawnFakeAmmoCrate(x, y, false, false)
		elseif params.crateType == "health" then
			SpawnFakeHealthCrate(x, y, false, false)
		else
			SpawnFakeAmmoCrate(x, y, false, false)
		end
	end

end

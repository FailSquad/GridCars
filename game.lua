local game = {
	GAMESTATE = "",
	SERVERGAMESTATE = "",
	usersMoved = {},
	newUserPositions = {},
	crashedUsers = {},		-- remembers how many rounds the user has to wait
	time = 0,
	maxTime = 0,
	timerEvent = nil,
	time2 = 0,
	maxTime2 = 0,
	timerEvent2 = nil,
	roundTime = 10,
	winnerID = nil
}

-- Possible gamestates:
-- "startup": camera should move to start line
-- "move": players are allowed to make their move.
-- "wait": waiting for server or other players, or for animtion

function game:init()
end

function game:show()
	STATE = "Game"
	ui:setActiveScreen( nil )

	map:removeAllCars()

	game.winnerID = nil

	if server then
		for id, u in pairs( server:getUsers() ) do
			local col = {
				u.customData.red,
				u.customData.green,
				u.customData.blue,
				255
			}

			local x, y = 0,0
			if map.startPositions[id] then
				x, y = map.startPositions[id].x, map.startPositions[id].y
			end
			map:newCar( u.id, x, y, col )

			server:send( CMD.NEW_CAR, u.id .. "|" .. x .. "|" .. y )

			crashedUsers = {}

		end

		-- Start the round after 3 seconds!
		self.timerEvent = function()
			game:startMovementRound()
		end
		self.maxTime = 3
	end

	-- Do a cool camera startup swing:
	map:camSwingAbort()
	map:camSwingToPos( map.startProjPoint.x, map.startProjPoint.y, 1.5 )
	self.timerEvent2 = function()
		if client then
			game:camToCar( client:getID() )
		end
	end
	self.maxTime2 = 2
end

function game:camToCar( id )
	if client then
		local x, y = map:getCarPos( id )
		x = x*GRIDSIZE
		y = y*GRIDSIZE
		map:camSwingToPos( x, y, 1 )
	end
end

function game:update( dt )
	map:update( dt )
	-- print(self.timerEvent)
	-- Timer1:
	if self.maxTime > 0 then
		self.time = self.time + dt
		if self.time >= self.maxTime then
			self.maxTime = 0
			self.time = 0
			self.timerEvent()
		end
	end
	if self.maxTime2 > 0 then
		self.time2 = self.time2 + dt
		if self.time2 >= self.maxTime2 then
			self.maxTime2 = 0
			self.time2 = 0
			self.timerEvent2()
		end
	end
end

function game:draw()
	if client then
		map:draw()
		if self.GAMESTATE == "move" then
			map:drawTargetPoints( client:getID() )
		end
		if love.keyboard.isDown( " " ) then
			map:drawCarInfo()
		end
		game:drawUserList()
	end
end

function game:drawUserList()
	-- Print list of users:
	love.graphics.setColor( 255,255,255, 255 )
	local users, num = network:getUsers()
	local x, y = 20, 60
	local i = 1
	if client and users then
		love.graphics.setColor( 0, 0, 0, 128 )
		love.graphics.rectangle( "fill", x - 5, y - 5, 400, num*20 + 5 )
		for k, u in pairs( users ) do
			love.graphics.setColor( 255,255,255, 255 )
			love.graphics.printf( i .. ":", x, y, 20, "right" )
			love.graphics.printf( u.playerName, x + 25, y, 250, "left" )

			local dx = love.graphics.getFont():getWidth( u.playerName ) + 40
			local lapString = "Lap: " .. map:getCarRound( u.id )
			love.graphics.print( lapString, x + dx, y )

			-- Show crashed users in list:
			if u.customData.crashed == true then
				love.graphics.setColor( 255, 128, 128, 255 )
				dx = dx + love.graphics.getFont():getWidth( lapString ) + 20
				local rounds = u.customData.waitingRounds or 1
				love.graphics.print( "[Crashed! (" .. rounds .. ")]", x + dx, y )
			elseif not u.customData.moved == true then
				love.graphics.setColor( 255, 255, 128, 255 )
				dx = dx + love.graphics.getFont():getWidth( lapString ) + 20
				love.graphics.print( "[Waiting for move]", x + dx, y )
			end
			y = y + 20
			i = i + 1
		end
	end
end

function game:keypressed( key )
end

function game:mousepressed( x, y, button )
	if button == "l" then
	if client then
		if self.GAMESTATE == "move" then
			-- Turn screen coordinates into grid coordinates:
			local gX, gY = map:screenToGrid( x, y )
			gX = math.floor( gX + 0.5 )
			gY = math.floor( gY + 0.5 )
			if map:clickAtTargetPosition( client:getID(), gX, gY ) then
				self:sendNewCarPosition( gX, gY )
			end
		end
	end
end
end

function game:setState( state )
	self.GAMESTATE = state
	print("Set game state", state)
	if self.GAMESTATE == "move" then
		if client then
			map:resetCarNextMovement( client:getID() )
		end
	end
end

function game:newCar( msg )
	if not server then
		local id, x, y = msg:match( "(.*)|(.*)|(.*)")
		id = tonumber(id)
		x = tonumber(x)
		y = tonumber(y)
		print("new car?", id, x, y)
		local users = client:getUsers()
		local u = users[id]
		print("user:", u, users[id])
		if u then
			local col = {
				u.customData.red,
				u.customData.green,
				u.customData.blue,
				255
			}
			map:newCar( id, x, y, col )
		end
	end
end

function game:sendNewCarPosition( x, y )
	-- CLIENT ONLY!
	if client then
		client:send( CMD.MOVE_CAR, x .. "|" .. y )

		map:setCarNextMovement( client:getID(), x, y )
	end
end

function game:startMovementRound()
	--SERVER ONLY!
	print("starting new round.")
	if server then
		self.SERVERGAMESTATE = "move"
		game.usersMoved = {}
		for k, u in pairs( server:getUsers() ) do

			-- On all crashed users, count one down because we're starting a new round...
			if game.crashedUsers[u.id] then
				game.crashedUsers[u.id] = game.crashedUsers[u.id] - 1
				if game.crashedUsers[u.id] <= 0 then
					-- If I've waited long enough, let me rejoin the game:
					server:setUserValue( u, "crashed", false )
					game.crashedUsers[u.id] = nil
				end
			end

			-- If a user crashed, let everyone know:
			if game.crashedUsers[u.id] then
				server:setUserValue( u, "waitingRounds", game.crashedUsers[u.id] )
				server:setUserValue( u, "crashed", true )
				-- Consider this user to be finished...
				game.usersMoved[u.id] = true
			else
				-- Only let users move if they haven't crashed:
				server:send( CMD.GAMESTATE, "move", u )
				server:setUserValue( u, "moved", false )
			end
			print( u.id, "crashed?", game.crashedUsers[u.id], game.usersMoved[u.id] )
		end

		-- If all users crashed, continue:
		game:checkForRoundEnd()
	end
end

function game:moveAll()
	if server then
		for k, u in pairs( server:getUsers() ) do
			--local x, y = map:getCarPos( u.id )
			local x,y = self.newUserPositions[u.id].x, self.newUserPositions[u.id].y
			server:send( CMD.MOVE_CAR, u.id .. "|" .. x .. "|" .. y )
		end
	end
	self.timerEvent = function()

		game:checkForWinner()

		if not game.winnerID then
			game:startMovementRound()
		else
			game:sendWinner( game.winnerID )
			self.timerEvent = game.sendBackToLobby
			self.maxTime = 5
		end
	end
	self.maxTime = 1.2
end

function game:validateCarMovement( id, x, y )
	--SERVER ONLY!
	if server then
		-- if this user has not moved yet:
		if self.usersMoved[id] == nil then
--			map:setCarPos( id, x, y )
			print( "server moving car to:", x, y)
			--map:setCarPosDirectly(id, x, y) --car-id as number, pos as Gridpos
			local oldX, oldY = map:getCarPos( id )
	

			-- Step along the path and check if there's a collision. If so, stop there.
			local p = {x = oldX, y = oldY }
			local diff = {x = x-oldX, y = y-oldY}
			local dist = utility.length( diff )
			diff = utility.normalize(diff)

			-- Step forward in steps of 0.5 length - this makes sure no small gaps are jumped!
			local crashed, crashSiteFound = false, false
			for l = 0.5, dist, 0.5 do
				p = {x = oldX + l*diff.x, y = oldY + l*diff.y }
				if not map:isPointOnRoad( p.x*GRIDSIZE, p.y*GRIDSIZE, 0 ) then
					crashed = true
				
					-- remembers how many rounds the user has to wait
					game.crashedUsers[id] = SKIP_ROUNDS_ON_CRASH + 1
					-- Step backwards:
					for lBack = l, 0, -0.5 do
						p = {x = oldX + lBack*diff.x, y = oldY + lBack*diff.y }
						p.x = math.floor(p.x)
						p.y = math.floor(p.y)
						print("testing", p.x, p.y)
						if map:isPointOnRoad( p.x*GRIDSIZE, p.y*GRIDSIZE, 0 ) then
							crashSiteFound = true
							x, y = p.x, p.y
							break
						end
					end
					break
				end
			end

			if crashed and not crashSiteFound then
				x, y = oldX, oldY
			end

			self.usersMoved[id] = true
			self.newUserPositions[id] = {x=x, y=y}

			local user = server:getUsers()[id]
			if user then
				-- tell this user to wait!
				server:send( CMD.GAMESTATE, "wait", user )
				-- Let all users know this user has already moved:
				server:setUserValue( user, "moved", true )
			end

			game:checkForRoundEnd()
		end
	end
end

function game:checkForRoundEnd()
	-- Check if all users have sent their move:
	print("DONE with the round?")
	local doneMoving = true
	for k, u in pairs( server:getUsers() ) do
		if not self.usersMoved[u.id] then
			print("not done moving", u.id)
			doneMoving = false
			break
		end
	end
	-- If all users have sent the move, go on to next round:
	if doneMoving then
		print("\tdone.")
		self:moveAll()
	end
end

function game:checkForWinner()
	if server and not game.winnerID then
		for k, u in pairs( server:getUsers() ) do
			if map:getCarRound( u.id ) >= LAPS then
				game.winnerID = u.id
				print("WINNER FOUND!", u.id)
				break
			end
		end
	end
end

function game:moveCar( msg )
	-- CLIENT ONLY!
	if client then
		local id, x, y = msg:match( "(.*)|(.*)|(.*)" )
		id = tonumber(id)
		x = tonumber(x)
		y = tonumber(y)
		map:setCarPos( id, x, y )
	end
end

function game:playerWins( msg )
	game.winnerID = tonumber(msg)	
	game:camToCar( game.winnerID )
	self.timerEvent2 = game.zoomOut
	self.maxTime2 = 3
end

function game:sendWinner()
	if server then
		server:send( CMD.PLAYER_WINS, game.winnerID )
	end
end
function game:sendBackToLobby()
	if server then
		server:send( CMD.BACK_TO_LOBBY, "" )
	end
end

function game:zoomOut()
	local cX = map.Boundary.minX + (map.Boundary.maxX - map.Boundary.minX)*0.5
	local cY = map.Boundary.minY + (map.Boundary.maxY - map.Boundary.minY)*0.5
	map:camSwingToPos( cX, cY )
end
return game

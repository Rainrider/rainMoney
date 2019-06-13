local addonName = ...

local days, totals, session, player, others, sessionStart, broker
local timeOffset = 0

local function spairs(tbl, desc)
	local keys = {}

	for key in next, tbl do
		keys[#keys + 1] = key
	end

	table.sort(keys, desc and function(a, b) return a > b end)

	local i = 0
	local function iter()
		i = i + 1
		local key = keys[i]
		if key then
			return key, tbl[key], i
		end
	end

	return iter, tbl
end

local function SetTimeOffset()
	local current = _G.date('*t')
	local utc = _G.date('!*t')
	utc.isdst = current.isdst

	timeOffset = _G.difftime(_G.time(current) - _G.time(utc))
end

local addon = _G.CreateFrame('Frame')
addon:SetScript('OnEvent', function(self, event, ...)
	self[event](self, ...)
end)

local function GetToday()
	-- number of days since epoch
	return math.ceil((_G.time() + timeOffset) / (24 * 60 * 60))
end

function addon:ADDON_LOADED(name)
	if name ~= addonName then return end

	-- saved vars
	_G.rainMoneyDB = _G.rainMoneyDB or {}
	local db = _G.rainMoneyDB

	local realm = _G.GetRealmName()
	db[realm] = db[realm] or { days = {}, totals = {} }
	days = db[realm].days
	totals = db[realm].totals

	local playerName = _G.UnitName('player')
	local _, class = _G.UnitClass('player')
	local color = _G.RAID_CLASS_COLORS[class].colorStr
	-- always get fresh data for the player
	totals[playerName] = { color = color, money = 0 }
	player = totals[playerName]

	others = 0
	for char, info in next, totals do
		if char ~= playerName then
			others = others + info.money
		end
	end

	session = 0
	SetTimeOffset()

	-- slash commands
	_G['SLASH_' .. addonName .. '1'] = '/rmoney'
	_G['SLASH_' .. addonName .. '2'] = '/rainmoney'
	_G.SlashCmdList[addonName] = self.Command

	self:UnregisterEvent('ADDON_LOADED')

	self:RegisterEvent('PLAYER_ENTERING_WORLD')
	self:RegisterEvent('PLAYER_MONEY')
	self:RegisterEvent('PLAYER_LOGOUT')
end

function addon:PLAYER_ENTERING_WORLD()
	sessionStart = _G.time()
	self:PLAYER_MONEY()
	self:UnregisterEvent('PLAYER_ENTERING_WORLD')
end

function addon:PLAYER_MONEY()
	local money = _G.GetMoney()
	local amount = money - player.money
	player.money = money
	broker.value = _G.GetMoneyString(money, true)

	if amount ~= money then
		local today = GetToday()
		days[today] = (days[today] or 0) + amount
		session = session + amount
	end
end

function addon:PLAYER_LOGOUT()
	local keys = {}
	for day in next, days do
		keys[#keys + 1] = day
	end

	-- remove entries older than 30 play days
	if #keys > 30 then
		table.sort(keys, function(a, b) return a > b end)

		for i = 31, #keys do
			local day = keys[i]
			days[day] = nil
		end
	end
end

function addon.Command(message)
	local command, name = string.split(' ', message)
	name = name or ''

	if command == 'delete' then
		for char, info in next, totals do
			if char == name then
				if info == player then
					return print(string.format('|cff0099cc%s|r: You cannot delete the current character.', addonName))
				end
				totals[char] = nil
				return print(string.format('|cff0099cc%s|r: Deleted character %q.', addonName, char))
			end
		end
		print(string.format('|cff0099cc%s|r: Character %q not found.', addonName, name))
	else
		print(string.format('|cff0099cc%s|r: Unknown command %q.', addonName, command))
	end
end

function addon:GetStatistics()
	local week, month = 0, 0

	for day, money, lag in spairs(days, true) do
		if lag < 8 then
			week = week + money
			month = month + money
		elseif lag < 31 then
			month = month + money
		end
	end

	local sessionTime = math.max(_G.time() - sessionStart, 3600)

	return {
		session = session,
		hour    = (session / sessionTime) * 3600,
		today   = days[GetToday()] or 0,
		week    = week,
		month   = month,
		totals  = player.money + others
	}
end

addon:RegisterEvent('ADDON_LOADED')

local LDB = _G.LibStub('LibDataBroker-1.1')
broker = LDB:NewDataObject(addonName, {
	type = 'data source',
	label = _G.MONEY,
	icon = [=[Interface\Minimap\Tracking\Auctioneer]=],
	OnTooltipShow = function(tooltip)
		local stats = addon:GetStatistics()
		for stat, amount in next, stats do
			if amount >= 0 then
				stats[stat] = _G.GetMoneyString(amount, true)
			else
				stats[stat] = '-' .. _G.GetMoneyString(-amount, true)
			end
		end

		tooltip:SetText(_G.MONEY)
		tooltip:AddLine(' ')

		for char, info in spairs(totals) do
			tooltip:AddDoubleLine(
				('|c%s%s|r'):format(info.color, char),
				_G.GetMoneyString(info.money, true),
				1, 1, 1, 1, 1, 1
			)
		end

		tooltip:AddLine(' ')
		tooltip:AddDoubleLine('Session', stats.session, 1, 1, 1, 1, 1, 1)
		tooltip:AddDoubleLine('Per hour', stats.hour, 1, 1, 1, 1, 1, 1)
		tooltip:AddLine(' ')
		tooltip:AddDoubleLine('Today', stats.today, 1, 1, 1, 1, 1, 1)
		tooltip:AddDoubleLine('Last 7 days', stats.week, 1, 1, 1, 1, 1, 1)
		tooltip:AddDoubleLine('Last 30 days', stats.month, 1, 1, 1, 1, 1, 1)
		tooltip:AddLine(' ')
		tooltip:AddDoubleLine('Total', stats.totals, 1, 1, 1, 1, 1, 1)
	end,
})
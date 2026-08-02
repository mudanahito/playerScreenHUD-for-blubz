local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local PlayerDataManager = {}

--configs. hello next programmer, change this if you wish :)
local DATASTORE_NAME = "PlayerData_v1"     -- bump version if you change the template shape
local SAVE_INTERVAL = 60                    -- auto-save every N seconds
local MAX_RETRIES = 5
local RETRY_BASE_DELAY = 1                  -- seconds, exponential backoff

local dataStore = DataStoreService:GetDataStore(DATASTORE_NAME)

--basic data

local function newDataTemplate()
	return {
		Level = 1,
		Exp = 0,
		ExpToNextLevel = 100,

		Money = 0,
		Fragments = 0,

		MaxHealth = 100,
		MaxStamina = 100,
		LastStamina = 100,

		Inventory = {},

		LastSaved = 0,
		DataVersion = 1,
	}
end

--stuffs for datastore

local sessionData = {} 
local sessionLocks = {} 
local loadedPlayers = {}

--bindable events

PlayerDataManager.DataLoaded = Instance.new("BindableEvent")
PlayerDataManager.LevelUp = Instance.new("BindableEvent")
PlayerDataManager.CurrencyChanged = Instance.new("BindableEvent") 
PlayerDataManager.InventoryChanged = Instance.new("BindableEvent")

--utility (could've put it in a seperate module but I'll see later)

local function attemptWithRetry(fn, ...)
	local args = {...}
	local success, result

	for attempt = 1, MAX_RETRIES do
		success, result = pcall(fn, table.unpack(args))
		if success then
			return true, result
		end

		warn(("[PlayerDataManager] Attempt %d/%d failed: %s"):format(attempt, MAX_RETRIES, tostring(result)))

		if attempt < MAX_RETRIES then
			task.wait(RETRY_BASE_DELAY * (2 ^ (attempt - 1)))
		end
	end

	return false, result
end

--load and save

local function deepFillDefaults(data, template)
	for key, value in pairs(template) do
		if data[key] == nil then
			data[key] = value
		elseif type(value) == "table" and type(data[key]) == "table" then
			deepFillDefaults(data[key], value)
		end
	end
	return data
end

local function loadData(player)
	local key = "Player_" .. player.UserId

	local success, result = attemptWithRetry(function()
		return dataStore:GetAsync(key)
	end)

	local template = newDataTemplate()

	if success and result ~= nil then
		return deepFillDefaults(result, template)
	elseif success and result == nil then
		return template
	else
		warn("[PlayerDataManager] Failed to load data for " .. player.Name .. " after retries. Using template as fallback (not saved until a successful load/save).")
		return template, true
	end
end

local function saveData(player, data)
	if not data then return false end

	local key = "Player_" .. player.UserId
	data.LastSaved = os.time()

	local success = attemptWithRetry(function()
		dataStore:SetAsync(key, data)
	end)

	if not success then
		warn("[PlayerDataManager] Failed to save data for " .. player.Name .. " after all retries.")
	end

	return success
end

--uhh? unecessary comment here? meh

local function onPlayerAdded(player)
	sessionLocks[player] = true

	local data, loadFailed = loadData(player)
	sessionData[player] = data
	sessionLocks[player] = false

	if not loadFailed then
		loadedPlayers[player] = true
	end

	PlayerDataManager.DataLoaded:Fire(player, data)
end

local function onPlayerRemoving(player)
	local data = sessionData[player]
	if data and loadedPlayers[player] then
		while sessionLocks[player] do
			task.wait(0.1)
		end
		sessionLocks[player] = true
		saveData(player, data)
		sessionLocks[player] = false
	end

	sessionData[player] = nil
	sessionLocks[player] = nil
	loadedPlayers[player] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

for _, player in ipairs(Players:GetPlayers()) do
	if not sessionData[player] then
		task.spawn(onPlayerAdded, player)
	end
end

task.spawn(function()
	while true do
		task.wait(SAVE_INTERVAL)
		for player, data in pairs(sessionData) do
			if loadedPlayers[player] and not sessionLocks[player] then
				sessionLocks[player] = true
				saveData(player, data)
				sessionLocks[player] = false
			end
		end
	end
end)

game:BindToClose(function()
	if RunService:IsStudio() then
		return 
	end
	for player, data in pairs(sessionData) do
		if loadedPlayers[player] then
			saveData(player, data)
		end
	end
end)

--utility for other scripts
function PlayerDataManager.GetData(player)
	return sessionData[player]
end

function PlayerDataManager.IsLoaded(player)
	return loadedPlayers[player] == true
end

function PlayerDataManager.WaitForData(player, timeout)
	timeout = timeout or 10
	local start = os.clock()
	while not loadedPlayers[player] do
		if os.clock() - start > timeout then
			warn("[PlayerDataManager] WaitForData timed out for " .. player.Name)
			return nil
		end
		task.wait(0.1)
	end
	return sessionData[player]
end

--progression
function PlayerDataManager.AddExp(player, amount)
	local data = sessionData[player]
	if not data or amount == nil or amount <= 0 then return end

	data.Exp += amount

	while data.Exp >= data.ExpToNextLevel do
		data.Exp -= data.ExpToNextLevel
		data.Level += 1
		data.ExpToNextLevel = math.floor(data.ExpToNextLevel * 1.15)

		PlayerDataManager.LevelUp:Fire(player, data.Level)
	end
end

function PlayerDataManager.SetLevel(player, level)
	local data = sessionData[player]
	if not data then return end
	data.Level = level
	PlayerDataManager.LevelUp:Fire(player, level)
end

--currency
local function modifyCurrency(player, currencyName, amount)
	local data = sessionData[player]
	if not data or amount == nil then return false end

	local newAmount = data[currencyName] + amount
	if newAmount < 0 then
		return false
	end

	data[currencyName] = newAmount
	PlayerDataManager.CurrencyChanged:Fire(player, currencyName, newAmount)
	return true
end

function PlayerDataManager.AddMoney(player, amount)
	return modifyCurrency(player, "Money", amount)
end

function PlayerDataManager.RemoveMoney(player, amount)
	return modifyCurrency(player, "Money", -math.abs(amount))
end

function PlayerDataManager.AddFragments(player, amount)
	return modifyCurrency(player, "Fragments", amount)
end

function PlayerDataManager.RemoveFragments(player, amount)
	return modifyCurrency(player, "Fragments", -math.abs(amount))
end

function PlayerDataManager.SyncVitalsToHumanoid(player, humanoid)
	local data = sessionData[player]
	if not data or not humanoid then return end

	humanoid.MaxHealth = data.MaxHealth
	humanoid.Health = data.MaxHealth

	humanoid:SetAttribute("MaxStamina", data.MaxStamina)
	humanoid:SetAttribute("Stamina", data.LastStamina)
end

function PlayerDataManager.CaptureStaminaFromHumanoid(player, humanoid)
	local data = sessionData[player]
	if not data or not humanoid then return end

	data.LastStamina = humanoid:GetAttribute("Stamina") or data.LastStamina
end

function PlayerDataManager.SetMaxHealth(player, newMax, humanoid)
	local data = sessionData[player]
	if not data then return end
	data.MaxHealth = newMax
	if humanoid then
		humanoid.MaxHealth = newMax
		humanoid.Health = math.min(humanoid.Health, newMax)
	end
end

function PlayerDataManager.SetMaxStamina(player, newMax, humanoid)
	local data = sessionData[player]
	if not data then return end
	data.MaxStamina = newMax
	if humanoid then
		humanoid:SetAttribute("MaxStamina", newMax)
		local current = humanoid:GetAttribute("Stamina") or newMax
		humanoid:SetAttribute("Stamina", math.min(current, newMax))
	end
end

function PlayerDataManager.AddItem(player, itemData)
	local data = sessionData[player]
	if not data or not itemData or not itemData.id then return false end

	itemData.amount = itemData.amount or 1

	for _, entry in ipairs(data.Inventory) do
		if entry.id == itemData.id then
			entry.amount += itemData.amount
			PlayerDataManager.InventoryChanged:Fire(player, data.Inventory)
			return true
		end
	end

	local newEntry = {}
	for k, v in pairs(itemData) do
		newEntry[k] = v
	end
	table.insert(data.Inventory, newEntry)

	PlayerDataManager.InventoryChanged:Fire(player, data.Inventory)
	return true
end

function PlayerDataManager.RemoveItem(player, itemId, amount)
	local data = sessionData[player]
	if not data then return false end
	amount = amount or 1

	for i, entry in ipairs(data.Inventory) do
		if entry.id == itemId then
			if entry.amount < amount then
				return false
			end

			entry.amount -= amount
			if entry.amount <= 0 then
				table.remove(data.Inventory, i)
			end

			PlayerDataManager.InventoryChanged:Fire(player, data.Inventory)
			return true
		end
	end

	return false
end

function PlayerDataManager.GetItem(player, itemId)
	local data = sessionData[player]
	if not data then return nil end

	for _, entry in ipairs(data.Inventory) do
		if entry.id == itemId then
			return entry
		end
	end
	return nil
end

function PlayerDataManager.HasItem(player, itemId, amount)
	amount = amount or 1
	local entry = PlayerDataManager.GetItem(player, itemId)
	return entry ~= nil and entry.amount >= amount
end

function PlayerDataManager.ForceSave(player)
	local data = sessionData[player]
	if not data or not loadedPlayers[player] then return false end

	while sessionLocks[player] do
		task.wait(0.1)
	end
	sessionLocks[player] = true
	local ok = saveData(player, data)
	sessionLocks[player] = false
	return ok
end

return PlayerDataManager

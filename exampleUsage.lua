local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService:WaitForChild("PlayerDataManager"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local dataUpdated = remotes:WaitForChild("DataUpdated")
local requestData = remotes:WaitForChild("RequestData")

local function pushFullData(player)
	local data = PlayerDataManager.GetData(player)
	if data then
		dataUpdated:FireClient(player, "Full", data)
	end
end

PlayerDataManager.DataLoaded.Event:Connect(function(player, data)
	dataUpdated:FireClient(player, "Full", data)
end)

PlayerDataManager.LevelUp.Event:Connect(function(player, newLevel)
	dataUpdated:FireClient(player, "LevelUp", newLevel)
end)

PlayerDataManager.CurrencyChanged.Event:Connect(function(player, currencyName, newAmount)
	dataUpdated:FireClient(player, "Currency", { name = currencyName, amount = newAmount })
end)

PlayerDataManager.InventoryChanged.Event:Connect(function(player, inventory)
	dataUpdated:FireClient(player, "Inventory", inventory)
end)


requestData.OnServerEvent:Connect(function(player)
	pushFullData(player)
end)

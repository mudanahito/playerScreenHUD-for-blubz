local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local screen = script.Parent -- PlayerScreen ScreenGui
local hud = screen:WaitForChild("Hud"):WaitForChild("Content")

local healthFrame = hud:WaitForChild("Health")
local healthValueLabel = healthFrame.Content.Value["Value"] -- nested TextLabel per your tree
local healthBar = healthFrame.Content.Current.Current

local staminaFrame = hud:WaitForChild("Stamina")
local staminaValueLabel = staminaFrame.Content.Value["Value"]
local staminaBar = staminaFrame.Content.Current.Current

local levelFrame = hud:WaitForChild("Level")
local levelValueLabel = levelFrame.Content.Value["Value"]

local currencysList = hud:WaitForChild("Currencys") -- there are two top-level "Currencys" TextLabels
local moneyLabel, fragmentsLabel
do
	local currencyLabels = {}
	for _, child in ipairs(hud:GetChildren()) do
		if child.Name == "Currencys" and child:IsA("TextLabel") then
			table.insert(currencyLabels, child)
		end
	end
	moneyLabel = currencyLabels[1] and currencyLabels[1]:FindFirstChild("Currencys")
	fragmentsLabel = currencyLabels[2] and currencyLabels[2]:FindFirstChild("Currencys")
end


local function setBarFill(barFrame, ratio)
	ratio = math.clamp(ratio, 0, 1)
	barFrame.Size = UDim2.new(ratio, 0, barFrame.Size.Y.Scale, barFrame.Size.Y.Offset)
end

local function bindHumanoid(humanoid)
	local function updateHealth()
		local ratio = humanoid.MaxHealth > 0 and (humanoid.Health / humanoid.MaxHealth) or 0
		setBarFill(healthBar, ratio)
		healthValueLabel.Text = math.floor(humanoid.Health) .. "/" .. math.floor(humanoid.MaxHealth)
	end
	updateHealth()
	humanoid:GetPropertyChangedSignal("Health"):Connect(updateHealth)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(updateHealth)

	local function updateStamina()
		local stamina = humanoid:GetAttribute("Stamina") or 0
		local maxStamina = humanoid:GetAttribute("MaxStamina") or 100
		local ratio = maxStamina > 0 and (stamina / maxStamina) or 0
		setBarFill(staminaBar, ratio)
		staminaValueLabel.Text = math.floor(stamina) .. "/" .. math.floor(maxStamina)
	end
	updateStamina()
	humanoid:GetAttributeChangedSignal("Stamina"):Connect(updateStamina)
	humanoid:GetAttributeChangedSignal("MaxStamina"):Connect(updateStamina)
end

local function onCharacterAdded(character)
	local humanoid = character:WaitForChild("Humanoid")
	bindHumanoid(humanoid)
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)


local remotes = ReplicatedStorage:WaitForChild("Remotes")
local dataUpdated = remotes:WaitForChild("DataUpdated")
local requestData = remotes:WaitForChild("RequestData")

local function updateLevel(level)
	levelValueLabel.Text = tostring(level)
end

local function updateCurrency(currencyName, amount)
	if currencyName == "Money" and moneyLabel then
		moneyLabel.Text = tostring(amount)
	elseif currencyName == "Fragments" and fragmentsLabel then
		fragmentsLabel.Text = tostring(amount)
	end
end

dataUpdated.OnClientEvent:Connect(function(kind, payload)
	if kind == "Full" then
		updateLevel(payload.Level)
		updateCurrency("Money", payload.Money)
		updateCurrency("Fragments", payload.Fragments)

	elseif kind == "LevelUp" then
		updateLevel(payload)

	elseif kind == "Currency" then
		updateCurrency(payload.name, payload.amount)
	end
end)

requestData:FireServer()

local MarketplaceService = game:GetService("MarketplaceService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SharedModules = ServerStorage.SharedModules
local Modules = ServerScriptService.Modules

local ClientFunctions = require(SharedModules.ClientFunctions)
local ServerFunctions = require(Modules.ServerFunctions)
local PropertiesModule = require(SharedModules.Properties)
local FurnitureModule = require(SharedModules.FurnitureShop)
local InteractionModule = require(Modules.Interaction)

local Remotes = ReplicatedStorage.Remotes
local ServerGUIs = ServerStorage.ServerGUIs
local FurnitureModels = ReplicatedStorage.Furniture
local PurchaseableLots = workspace.Purchaseable_Lots
local Properties = ServerStorage.Properties

local PROXIMITY_DISTANCE = 20

local function stringToCFrame(str)
	return CFrame.new(table.unpack(str:gsub(" ",""):split(",")))
end

local function isInsidePart(position, part)
	local v3 = part.CFrame:PointToObjectSpace(position)
	return (math.abs(v3.X) <= part.Size.X / 2)
		and (math.abs(v3.Z) <= part.Size.Z / 2)
end

local function validPropertyColor(color)
	for _, colorValue in pairs(PropertiesModule.PropertyColors) do
		if colorValue == color then
			return true
		end
	end

	return false
end

local function hasAvailableFurniture(player, property, furnitureSelected)
	local amountPlaced = 0
	
	for _, furniture in pairs(property.Furniture:GetChildren()) do
		if furniture.Name == furnitureSelected then
			amountPlaced = amountPlaced + 1
		end
	end

	if _G.sessionData[player].Furniture[furnitureSelected] ~= nil and _G.sessionData[player].Furniture[furnitureSelected] > amountPlaced then
		return true
	else
		return false
	end
end

local function furnitureUsed(player, property, furnitureSelected)
	local amountPlaced = 0
	
	for _, furniture in pairs(property.Furniture:GetChildren()) do
		if furniture.Name == furnitureSelected then
			amountPlaced = amountPlaced + 1
		end
	end
	
	return amountPlaced
end

local function getFurnitureType(player, furnitureSelected)
	for furnitureType, furniture in pairs(FurnitureModule.Items) do
		if furniture[furnitureSelected] ~= nil then
			return furnitureType
		end
	end
end

local function trackFurnitureHealth(player, furniture)
	furniture.Health.Changed:connect(function()
		if furniture.Health.Value <= 0 then
			local cashSpawnCFrame = furniture.PrimaryPart.CFrame
			local dropsCash = furniture.DropsCash.Value

			if _G.sessionData[player].Furniture[furniture.Name] > 1 then
				_G.sessionData[player].Furniture[furniture.Name] = _G.sessionData[player].Furniture[furniture.Name] - 1
			else
				_G.sessionData[player].Furniture[furniture.Name] = nil
			end

			furniture:Destroy()

			if dropsCash then
				ServerFunctions.SpawnCash(50, cashSpawnCFrame)
			end

			ServerFunctions.ObjectSmashEffects(cashSpawnCFrame)
		end
	end)
end

local function giveEditGui(player, lot)
	local editGui = ServerGUIs["EditHome"]:Clone()
	local ownsFurniture = false
	editGui.Lot.Value = lot
	
	for furnitureType, furniture in pairs(FurnitureModule.Items) do
		for furnitureName, furnitureValues in pairs(furniture) do
			if _G.sessionData[player].Furniture[furnitureName] ~= nil then
				local itemFrame = ServerGUIs.ItemContainer:Clone()
				itemFrame.Name = furnitureName 
				itemFrame.AmountOwned.Value = _G.sessionData[player].Furniture[furnitureName]
				itemFrame.Frame.Amount.Text = "x"..tostring(_G.sessionData[player].Furniture[furnitureName] - furnitureUsed(player, lot, furnitureName))
				itemFrame.Frame.Icon.Image = furnitureValues.Icon
				itemFrame.Frame.ItemName.Text = furnitureName
				itemFrame.Parent = editGui.Frame.SubFrame[furnitureType]
				ownsFurniture = true
			end
		end
	end

	if ownsFurniture then
		editGui.Frame.SubFrame.NoItemLabel.Visible = false
	end
	
	editGui.Parent = player.PlayerGui
end

local function givePropertyGui(player, lot)
	if player.Character 
		and not player.Character.States.InShop.Value 
		and not player.Character.States.Knocked.Value 
	then
		player.Character.States.InShop.Value = true

		local propertyGui = ServerGUIs["PropertyGui"]:Clone()
		propertyGui.PropertyType.Value = lot.Name
		propertyGui.Lot.Value = lot

		for propertyName, propertyValues in pairs(PropertiesModule.Items[lot.Name]) do	
			local itemFrame = ServerGUIs.ItemContainer:Clone()
			itemFrame.LayoutOrder = propertyValues.Price
			itemFrame.Icon.Image = propertyValues.Icon
			itemFrame.Name = propertyName 
			itemFrame.ItemName.Text = propertyName 
			itemFrame.LevelFrame.Level.Text = "Level "..tostring(propertyValues.LevelRequired).."+"

			if propertyValues.GamePassRequired then
				itemFrame.Price.Text = "GamePass Only"
			else
				itemFrame.Price.Text = "$"..ClientFunctions.ConvertShort(propertyValues.Price)	
			end

			if _G.sessionData[player].Property[lot.Name][propertyName] ~= nil then
				itemFrame.Owned.Value = true
				itemFrame.LockedIcon.Visible = false
			end

			itemFrame.Parent = propertyGui.Frame.Properties.Content
		end

		propertyGui.Parent = player.PlayerGui
		Remotes.UnequipInventory:FireClient(player)
	end
end

local function initializeProperty(player, propertyName, propertyType, playerLot)
	local furnitureToRemove = {}
	
	playerLot.Furniture:ClearAllChildren()
	playerLot.PropertyPlaced:ClearAllChildren()

	local newProperty = Properties[propertyType][propertyName]:Clone()
	newProperty:SetPrimaryPartCFrame(playerLot.Center.CFrame)
	newProperty.Parent = playerLot.PropertyPlaced

	for _, propertyInteractions in pairs(newProperty.Interactions:GetChildren()) do
		InteractionModule.SetupInteraction(propertyInteractions)
	end

	if newProperty:FindFirstChild("Primary") then
		for _, part in pairs(newProperty.Primary:GetChildren()) do
			part.BrickColor = BrickColor.new(_G.sessionData[player].Property[playerLot.Name][newProperty.Name].Colors.Primary)
		end
	end
	
	if newProperty:FindFirstChild("Secondary") then
		for _, part in pairs(newProperty.Secondary:GetChildren()) do
			part.BrickColor = BrickColor.new(_G.sessionData[player].Property[playerLot.Name][newProperty.Name].Colors.Secondary)
		end
	end
	
	for furnitureName, positionTable in pairs(_G.sessionData[player].Property[playerLot.Name][newProperty.Name].Furniture) do
		for index, objectCFrame in pairs(positionTable) do
			if hasAvailableFurniture(player, playerLot, furnitureName) then
				local furniture = FurnitureModels[furnitureName]:Clone()
				local HealthProperty = Instance.new("IntValue", furniture)
				local OwnerProperty = Instance.new("ObjectValue", furniture)
				local furnitureType = Instance.new("StringValue", furniture)
				
				HealthProperty.Name = "Health"
				OwnerProperty.Name = "FurnitureOwner"
				OwnerProperty.Value = player
				furnitureType.Name = "FurnitureType"
				furnitureType.Value = getFurnitureType(player, furnitureName)
				
				if FurnitureModule.Items[furnitureType.Value][furnitureName].Health ~= nil then
					HealthProperty.Value = FurnitureModule.Items[furnitureType.Value][furnitureName].Health
				else
					HealthProperty.Value = 150
				end

				local selectionBox = Instance.new("SelectionBox")
				selectionBox.Adornee = furniture.Hitbox
				selectionBox.Parent = furniture.Hitbox
				
				furniture.Parent = playerLot.Furniture
				
				local worldCFrame = playerLot.Center.CFrame:ToWorldSpace(stringtocf(objectCFrame))
				local IndexVal = Instance.new("IntValue", furniture)
				
				IndexVal.Name = "IndexVal"
				IndexVal.Value = index

				furniture:SetPrimaryPartCFrame(worldCFrame)

				trackFurnitureHealth(player, furniture)
			else
				table.insert(furnitureToRemove, index)
			end
		end
	end

	for _, indexPos in pairs(furnitureToRemove) do
		table.remove(_G.sessionData[player].Property[playerLot.Name][newProperty.Name].Furniture, indexPos)
	end
	
	Remotes.BuyProperty:FireClient(player, propertyName)
	Remotes.SetupPropertyOwner:FireClient(player, newProperty)
end

for _, lot in pairs(PurchaseableLots:GetChildren()) do
	if lot:FindFirstChild("Interact") then
		local ownerInPlot = false
		local regionPart = lot["Fake_Ground"]:Clone()
		
		regionPart.Name = "Region"
		regionPart.Transparency = 1
		regionPart.CanCollide = false
		regionPart.CanTouch = true
		regionPart.Position = lot["Fake_Ground"].Position
		regionPart.Parent = lot
		
		lot.Interact.PromptAttachment.ProximityPrompt.Triggered:connect(function(player)
			local MagnitudeCheck = player:DistanceFromCharacter(lot.Interact.Position)
			if MagnitudeCheck <= PROXIMITY_DISTANCE then
				givePropertyGui(player, lot)
			end
		end)

		local currentOwner = nil
		
		lot.Owner.Changed:connect(function()
			if lot.Owner.Value ~= nil and currentOwner == nil then
				currentOwner = lot.Owner.Value
				
				while lot.Owner.Value ~= nil do
					local character = lot.Owner.Value.Character
					if character 
						and character:FindFirstChild("HumanoidRootPart") 
						and isInsidePart(character.HumanoidRootPart.Position, regionPart) 
					then
						if not ownerInPlot then
							ownerInPlot = true
							giveEditGui(lot.Owner.Value, lot)
						end
					else
						if ownerInPlot then
							Remotes.EditProperty:FireClient(lot.Owner.Value, "RemoveGui")
							ownerInPlot = false
						end
					end
					task.wait(1)
				end
			elseif lot.Owner.Value == nil then
				currentOwner = nil
				ownerInPlot = false
			end
		end)
	end
end

Remotes.BuyProperty.OnServerEvent:connect(function(player, propertyName, propertyType)
	local price = PropertiesModule.Items[propertyType][propertyName].Price
	local levelRequired = PropertiesModule.Items[propertyType][propertyName].LevelRequired
	local distanceCheck = player:DistanceFromCharacter(player.Character.States.InShop.Interact.Value.Interact.Position)
	
	if _G.sessionData[player].Property[propertyType][propertyName] == nil  then
		if _G.sessionData[player].CivilianLevel["Level"] >= levelRequired then
			if PropertiesModule.Items[propertyType][propertyName].GamePassRequired then
				local success, hasPass = pcall(function()
					return MarketplaceService:UserOwnsGamePassAsync(player.UserId, PropertiesModule.Items[propertyType][propertyName].GamePassID)
				end)
				
				if success then
					if hasPass then
						_G.sessionData[player].Property[propertyType][propertyName] = {Colors = {Primary = BrickColor.new("White").Name, Secondary = BrickColor.new("Smoky grey").Name}, Furniture = {}}
						Remotes.Notification:FireClient(player, propertyName.." Purchased!", "You can now load this property at any available lot")
					else 
						MarketplaceService:PromptGamePassPurchase(player, PropertiesModule.Items[propertyType][propertyName].GamePassID)
					end
				end
			else
				if _G.sessionData[player].Cash >= price then
					ServerFunctions.CashTransaction(player, price)

					_G.sessionData[player].Property[propertyType][propertyName] = {Colors = {Primary = BrickColor.new("White").Name, Secondary = BrickColor.new("Smoky grey").Name}, Furniture = {}}
					Remotes.Notification:FireClient(player, propertyName.." Purchased!", "You can now load this property at any available lot")
					Remotes.BuyProperty:FireClient(player, propertyName)
				else
					Remotes.Notification:FireClient(player, "Insufficient Funds!", "You need $"..tostring(price - _G.sessionData[player].Cash).." more to buy this property")
				end
			end
		else
			Remotes.Notification:FireClient(player, "Level Too Low!", "You need to be Civilian Level "..tostring(levelRequired).." to buy this property")
		end
	end
end)

Remotes.LoadProperty.OnServerEvent:connect(function(player, propertyName, propertyType)
	local playerLot = ServerFunctions.FindLot(player)
	
	if playerLot ~= nil then
		if playerLot.PropertyPlaced:FindFirstChild(propertyName) == nil then
			initializeProperty(player, propertyName, propertyType, playerLot)
		else
			playerLot.Furniture:ClearAllChildren()
			playerLot.PropertyPlaced:ClearAllChildren()
		end
	else
		Remotes.PromptBuyProperty:FireClient(player, propertyName, propertyType)
	end
end)

Remotes.EditProperty.OnServerEvent:connect(function(player, action, target, mouseHit, furnitureSelected, rotateAngle)
	local playerLot = ServerFunctions.FindLot(player)
	
	if playerLot then
		local playerProperty = playerLot.PropertyPlaced:FindFirstChildOfClass("Model")
		
		if action == "Primary Color" then
			local colorSelected = target
			
			if not validPropertyColor(colorSelected) then
				colorSelected = BrickColor.new("White")
			end
			
			_G.sessionData[player].Property[playerLot.Name][playerProperty.Name].Colors.Primary = colorSelected.Name
			
			if playerProperty:FindFirstChild("Primary") then
				for _, part in pairs(playerProperty.Primary:GetChildren()) do
					part.BrickColor = colorSelected
				end
			end
		elseif action == "Secondary Color" then
			local colorSelected = target
			
			if not validPropertyColor(colorSelected) then
				colorSelected = BrickColor.new("White")
			end
			
			_G.sessionData[player].Property[playerLot.Name][playerProperty.Name].Colors.Secondary = colorSelected.Name
			
			if playerProperty:FindFirstChild("Secondary") then
				for _, part in pairs(playerProperty.Secondary:GetChildren()) do
					part.BrickColor = colorSelected
				end
			end
		elseif action == "Clear All" then
			Remotes.EditProperty:FireClient(player, "Clear All", furnitureSelected)
			playerLot.Furniture:ClearAllChildren()
			_G.sessionData[player].Property[playerLot.Name][playerProperty.Name].Furniture = {}			
		elseif action == "Remove Item" then
			if target and target:FindFirstChild("FurnitureOwner") and target.FurnitureOwner.Value == player then
				local distanceCheck = player:DistanceFromCharacter(mouseHit.p)
				
				if distanceCheck <= PROXIMITY_DISTANCE then
					local furnitureType = target.FurnitureType.Value
					local placementObjectSpaceCFrame = playerLot.Center.CFrame:ToObjectSpace(target.PrimaryPart.CFrame)
					local saveIndex = target.IndexVal.Value
					
					if saveIndex then
						local savedFurniture = _G.sessionData[player].Property[playerLot.Name][playerProperty.Name].Furniture[target.Name]
						
						table.remove(savedFurniture, saveIndex)
						if #savedFurniture == 0 then
							savedFurniture = nil
						end
					end
					
					target:Destroy()
					Remotes.EditProperty:FireClient(player, "Add", target.Name, furnitureType)
					
					for _, furniture in pairs(playerLot.Furniture:GetChildren()) do
						if target.Name == furniture.Name and furniture.IndexVal.Value > saveIndex then
							furniture.IndexVal.Value = furniture.IndexVal.Value - 1
						end
					end
				end
			end
		elseif action == "Place Item" then
			if target and hasAvailableFurniture(player, playerLot, furnitureSelected) then
				local distanceCheck = player:DistanceFromCharacter(mouseHit.p)
				
				if distanceCheck <= PROXIMITY_DISTANCE then
					if isInsidePart(mouseHit.p, playerLot["Fake_Ground"]) then
						local furniture = FurnitureModels[furnitureSelected]:Clone()
						local healthProperty = Instance.new("IntValue", furniture)
						local ownerProperty = Instance.new("ObjectValue", furniture)
						local furnitureType = Instance.new("StringValue", furniture)
						
						healthProperty.Name = "Health"
						ownerProperty.Name = "FurnitureOwner"
						ownerProperty.Value = player
						furnitureType.Name = "FurnitureType"
						furnitureType.Value = getFurnitureType(player, furnitureSelected)
						
						if FurnitureModule.Items[furnitureType.Value][furnitureSelected].Health ~= nil then
							healthProperty.Value = FurnitureModule.Items[furnitureType.Value][furnitureSelected].Health
						else
							healthProperty.Value = 150
						end
						
						local dropsCash = Instance.new("BoolValue", furniture)
						dropsCash.Name = "DropsCash"
						dropsCash.Value = true

						local selectionBox = script.SelectionBox:Clone()
						selectionBox.Adornee = furniture.Hitbox
						selectionBox.Parent = furniture.Hitbox
						furniture.Parent = playerLot.Furniture
						furniture:SetPrimaryPartCFrame(CFrame.new(mouseHit.p + Vector3.new(0, furniture.PrimaryPart.Size.Y / 2, 0)) * CFrame.Angles(0, math.rad(rotateAngle), 0))
						
						Remotes.EditProperty:FireClient(player, "Subtract", furnitureSelected, furnitureType.Value)
						
						if _G.sessionData[player].Property[playerLot.Name][playerProperty.Name].Furniture[furnitureSelected] == nil then
							_G.sessionData[player].Property[playerLot.Name][playerProperty.Name].Furniture[furnitureSelected] = {}
						end
						
						local placementObjectSpaceCFrame = playerLot.Center.CFrame:ToObjectSpace(furniture.PrimaryPart.CFrame)
						local savedFurniture = _G.sessionData[player].Property[playerLot.Name][playerProperty.Name].Furniture[furnitureSelected]
						
						table.insert(savedFurniture, tostring(placementObjectSpaceCFrame))
						
						local IndexVal = Instance.new("IntValue", furniture)
						IndexVal.Name = "IndexVal"
						IndexVal.Value = #savedFurniture
						
						trackFurnitureHealth(player, furniture)
					end
				end
			else
				Remotes.Notification:FireClient(player, "No More Remaining", "You placed all furniture of this type")
			end
		end
	end
end)
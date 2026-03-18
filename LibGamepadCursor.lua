-- Generic Gamepad Cursor Target Types
GAMEPAD_CURSOR_TARGET_TYPES =
{
    NONE = 0,
    INTERACTABLE = 1, -- Buttons, Sliders, etc.
    TEXT = 2,         -- Labels
}
local TRACKED_MOUSE_HANDLERS = {
	ON_MOUSE_ENTER = "OnMouseEnter",
	ON_MOUSE_EXIT = "OnMouseExit",
	ON_MOUSE_DOWN = "OnMouseDown",
	ON_MOUSE_UP = "OnMouseUp",
	ON_CLICKED = "OnClicked",
}
-- Friction factors: how much the cursor slows down when hovering
GAMEPAD_CURSOR_FRICTION_FACTORS =
{
    [GAMEPAD_CURSOR_TARGET_TYPES.NONE] = 1,
    [GAMEPAD_CURSOR_TARGET_TYPES.INTERACTABLE] = 0.5,
    [GAMEPAD_CURSOR_TARGET_TYPES.TEXT] = 0.8,
}

GAMEPAD_CURSOR_SPEED = 20
GAMEPAD_CURSOR_FRICTION_INTERPOLATION_RATE = 1

----------------------------
-- Generic Cursor Class ----
----------------------------

LibGamepadCursor = ZO_InitializingCallbackObject:Subclass()

function LibGamepadCursor:Initialize(control)
    self.control = control
	self.savedHandlers = {}
	self:CreateKeybinds()
    self:Reset()
end

function LibGamepadCursor:Reset()
    self.x, self.y = GuiRoot:GetCenter()
    self.frictionInterpolationFactor = 1
	
    if self.objectTypeUnderCursor then
        self:ResetObjectUnderCursor()
    else
        self.objectTypeUnderCursor = GAMEPAD_CURSOR_TARGET_TYPES.NONE
        self.objectUnderCursor = nil
    end
    self.control:SetAnchor(CENTER, GuiRoot, TOPLEFT, self.x, self.y)
    self.control:SetHidden(true)
	
    self:RefreshObjectUnderCursor()
end

function LibGamepadCursor:UpdateDirectionalInput()
    local cursorMoved = false
    -- Get input from both Left Stick and D-Pad
    local dx, dy = DIRECTIONAL_INPUT:GetXY(ZO_DI_LEFT_STICK)
    SetGamepadLeftStickConsumedByUI(true)
    if dx ~= 0 or dy ~= 0 then
        dx, dy = zo_clampLength2D(dx, dy, 1.0)
        local frameDelta = GetFrameDeltaNormalizedForTargetFramerate()
        local magnitude = frameDelta * self.frictionInterpolationFactor * GAMEPAD_CURSOR_SPEED
        dx = dx * magnitude
        dy = -dy * magnitude
        self.control:SetAnchor(CENTER, GuiRoot, TOPLEFT, self.x + dx, self.y + dy)
        local clampedX, clampedY = self.control:GetCenter()
        if clampedX ~= self.x or clampedY ~= self.y then
            self.x, self.y = clampedX, clampedY
            cursorMoved = true
        end
    end

    self:RefreshObjectUnderCursor()
    
    local targetFriction = GAMEPAD_CURSOR_FRICTION_FACTORS[self.objectTypeUnderCursor]
    self.frictionInterpolationFactor = zo_deltaNormalizedLerp(self.frictionInterpolationFactor, targetFriction, GAMEPAD_CURSOR_FRICTION_INTERPOLATION_RATE)

    if cursorMoved then
        self:OnCursorPositionChanged()
    end
	 SCENE_MANAGER:SetInUIMode(true)
end

function LibGamepadCursor:OnCursorPositionChanged()
    self:FireCallbacks("CursorPositionChanged", self.x, self.y)
end
function LibGamepadCursor:CreateKeybinds()
	self.keybinds = {
		alignment = KEYBIND_STRIP_ALIGN_CENTER,
		{
			name = "Select",
			keybind = "UI_SHORTCUT_PRIMARY", -- This is the 'A' button on Xbox / 'Cross' on PS
			callback = function()
				-- This is where we check what the cursor is touching
				--###############################
				-- gamepadCursor might need to be swapped to self
				--###############################
				--local target, targetType = self:GetObjectUnderCursor()

				--if targetType == GAMEPAD_CURSOR_TARGET_TYPES.INTERACTABLE and target then
					-- Safely trigger the button's behavior
					if self.savedHandlers[TRACKED_MOUSE_HANDLERS.ON_CLICKED] then self.savedHandlers[TRACKED_MOUSE_HANDLERS.ON_CLICKED](self.objectUnderCursor,1) end
					if self.savedHandlers[TRACKED_MOUSE_HANDLERS.ON_MOUSE_DOWN] then self.savedHandlers[TRACKED_MOUSE_HANDLERS.ON_MOUSE_DOWN](self.objectUnderCursor,1) end
					if self.savedHandlers[TRACKED_MOUSE_HANDLERS.ON_MOUSE_UP] then self.savedHandlers[TRACKED_MOUSE_HANDLERS.ON_MOUSE_UP](self.objectUnderCursor,1) end
				--end
			end,
		},
	}
end
function LibGamepadCursor:SetActive(active)
    self.control:SetHidden(not active)
    if active then
		SCENE_MANAGER:SetInUIMode(true)

		
        -- Activate the input listener
        DIRECTIONAL_INPUT:Activate(self, self.control)
        -- IMPORTANT: Set UI Mode to true to block character and camera movement
        KEYBIND_STRIP:AddKeybindButtonGroup( self.keybinds)
		 KEYBIND_STRIP:UpdateKeybindButtonGroup( self.keybinds)
     
        if not self.cursorId then
            self.cursorId = WINDOW_MANAGER:CreateCursor(self.x, self.y)
        end
    else
		KEYBIND_STRIP:RemoveKeybindButtonGroup( self.keybinds)
        -- Deactivate input listener and return to world mode
        DIRECTIONAL_INPUT:Deactivate(self)
        SCENE_MANAGER:SetInUIMode(false)
        if self.cursorId then
            WINDOW_MANAGER:DestroyCursor(self.cursorId)
            self.cursorId = nil
        end
    end

    self:RefreshObjectUnderCursor()
    self:FireCallbacks("CursorStateChanged", active)
    
    if active then
        self:OnCursorPositionChanged()
    end
end

function LibGamepadCursor:RefreshObjectUnderCursor()
    if self.control:IsHidden() then
        self:ResetObjectUnderCursor()
        return
    end

    WINDOW_MANAGER:UpdateCursorPosition(self.cursorId, self.x, self.y)
    local targetControl = WINDOW_MANAGER:GetControlAtCursor(self.cursorId)
    local objectType = GAMEPAD_CURSOR_TARGET_TYPES.NONE
    local isUnderCursor = true

    if targetControl then
        local controlType = targetControl:GetType()
        -- Detect interactable types
        if controlType == CT_BUTTON or controlType == CT_SLIDER then
            objectType = GAMEPAD_CURSOR_TARGET_TYPES.INTERACTABLE
            isUnderCursor = true
        -- Detect text labels
        elseif controlType == CT_LABEL then
            objectType = GAMEPAD_CURSOR_TARGET_TYPES.INTERACTABLE--TEXT
            isUnderCursor = true
        end

    end

    self:SetObjectUnderCursor(targetControl, objectType, isUnderCursor)
end

function LibGamepadCursor:SetObjectUnderCursor(object, objectType, isUnderCursor)
    local previousObjectType = self.objectTypeUnderCursor
    if isUnderCursor or objectType ~= previousObjectType or objectType ~= GAMEPAD_CURSOR_TARGET_TYPES.NONE then
        local previousObject = self.objectUnderCursor
        if (not isUnderCursor) or object ~= previousObject then
			if self.savedHandlers[TRACKED_MOUSE_HANDLERS.ON_MOUSE_EXIT] then self.savedHandlers[TRACKED_MOUSE_HANDLERS.ON_MOUSE_EXIT](previousObject) end
			self.savedHandlers = {}
            if isUnderCursor then
                self.objectUnderCursor = object
                self.objectTypeUnderCursor = objectType
				d("ObjectName: "..self.objectUnderCursor:GetName())
				for _, handlerName in pairs(TRACKED_MOUSE_HANDLERS) do
					local handler = self.objectUnderCursor:GetHandler(handlerName)
					if handler then 	
						self.savedHandlers[handlerName] = handler 
						d(handlerName.." Found")
					end
					
				end
				if self.savedHandlers[TRACKED_MOUSE_HANDLERS.ON_MOUSE_ENTER] then self.savedHandlers[TRACKED_MOUSE_HANDLERS.ON_MOUSE_ENTER](self.objectUnderCursor, self.control) end
            else
                self.objectUnderCursor = nil
                self.objectTypeUnderCursor = GAMEPAD_CURSOR_TARGET_TYPES.NONE
            end
			
            self:FireCallbacks("ObjectUnderCursorChanged", self.objectUnderCursor, self.objectTypeUnderCursor, previousObject, previousObjectType)
        end
    end
end

function LibGamepadCursor:ResetObjectUnderCursor()
    self:SetObjectUnderCursor(nil, GAMEPAD_CURSOR_TARGET_TYPES.NONE, false)
end

function LibGamepadCursor:GetObjectUnderCursor()
    if self.control:IsHidden() then
        return nil, GAMEPAD_CURSOR_TARGET_TYPES.NONE
    end
    return self.objectUnderCursor, self.objectTypeUnderCursor
end

local isOn = false
gamepadCursor = nil
local addonname = "LibGamepadCursor"
local function OnAddonLoaded(event, name)
	if name ~= addonname then
		return
	end
	EVENT_MANAGER:UnregisterForEvent(addonname, EVENT_ADD_ON_LOADED)
	
   	gamepadCursor = LibGamepadCursor:New(LibGamepadCursor_TopLevelGamepadCursor)

	SLASH_COMMANDS["/lgc"]=function()
		isOn = not isOn	
		gamepadCursor:SetActive(isOn)
	end
end
EVENT_MANAGER:RegisterForEvent(addonname, EVENT_ADD_ON_LOADED,OnAddonLoaded)
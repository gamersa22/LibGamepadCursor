-- Generic Gamepad Cursor Target Types
GAMEPAD_CURSOR_TARGET_TYPES =
{
    NONE = 0,
    INTERACTABLE = 1, -- Buttons, Sliders, etc.
    TEXT = 2,         -- Labels
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
end

function LibGamepadCursor:OnCursorPositionChanged()
    self:FireCallbacks("CursorPositionChanged", self.x, self.y)
end
local myKeybindDescriptor = {
    alignment = KEYBIND_STRIP_ALIGN_CENTER,
    {
        name = "Select",
        keybind = "UI_SHORTCUT_PRIMARY", -- This is the 'A' button on Xbox / 'Cross' on PS
        callback = function()
            -- This is where we check what the cursor is touching
			--###############################
			-- gamepadCursor might need to be swapped to self
			--###############################
            local target, targetType = gamepadCursor:GetObjectUnderCursor()

            if targetType == GAMEPAD_CURSOR_TARGET_TYPES.INTERACTABLE and target then
                -- Safely trigger the button's behavior
                local handler = target:GetHandler("OnMouseUp")
                if handler then
                    handler(target, 0, false)
                    PlaySound(SOUNDS.DIALOG_ACCEPT)
                end
            end
        end,
    },
}
function LibGamepadCursor:SetActive(active)
    self.control:SetHidden(not active)
    if active then
        -- Activate the input listener
        DIRECTIONAL_INPUT:Activate(self, self.control)
        -- IMPORTANT: Set UI Mode to true to block character and camera movement
        SCENE_MANAGER:SetInUIMode(true)
        KEYBIND_STRIP:AddKeybindButtonGroup(myKeybindDescriptor)
        if not self.cursorId then
            self.cursorId = WINDOW_MANAGER:CreateCursor(self.x, self.y)
        end
    else
        -- Deactivate input listener and return to world mode
        DIRECTIONAL_INPUT:Deactivate(self)
        SCENE_MANAGER:SetInUIMode(false)
        KEYBIND_STRIP:RemoveKeybindButtonGroup(myKeybindDescriptor)
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
    local isUnderCursor = false

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
            if isUnderCursor then
                self.objectUnderCursor = object
                self.objectTypeUnderCursor = objectType
				self.objectUnderCursor:GetHandler("OnMouseEnter")(self.control)
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
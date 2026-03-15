# LibGamepadCursor
This is bassed of the cursor from gamepad tails of tribute interal code.\
Atm you can't interact with controls, the cursor knows what cuntrol its above I just never worked out how to Interact properly.
## How to use
As this is only is testing phase use /lgc to toggle the cursor on and off.\
Or you can make your own with
```
yourCursor = LibGamepadCursor:New(LibGamepadCursor_TopLevelGamepadCursor)
yourCursor:SetActive(true)
```
## Know issues
 - If you move the cursor too fast, your character will move and the HUD regains focus

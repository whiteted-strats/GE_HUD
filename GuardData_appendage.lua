-- Needs to be added to Henrik's library

GuardData.metadata =
{
    ...
	
    
    -- 0xFF most of the time, 0x01,0x02, maybe other numbers, during the shooting.
    --   Maybe angle is fixed at 01, fired 02, FF idle?
    {["offset"] = 0x180, ["size"] = 0x1, ["type"] = "hex", ["name"] = "shooting_stage_flag"},
	-- Definitely is the end of the gun barrel: confirmed on HUD
	{["offset"] = 0x184, ["size"] = 0xC, ["type"] = "vector",	["name"] = "shot_origin"},
	-- Is very likely the unit direction of the effective bullet leaving the guard's gun
    {["offset"] = 0x190, ["size"] = 0xC, ["type"] = "vector",	["name"] = "bullet_dirc"}
    
}

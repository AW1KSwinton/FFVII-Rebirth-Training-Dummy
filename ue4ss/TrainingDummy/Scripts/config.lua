-- Training Dummy settings. Edit, then restart the game (UE4SS hot reload crashes this game).
return {
    -- How often the mod checks the battle, in milliseconds.
    tick_ms = 200,

    -- A dummy whose HP falls below this percentage is topped back up to 100%.
    -- Kept high to leave a large HP margin between checks (5 per second).
    refill_below_percent = 90,


    -- Hold the DPS and Healing dummies still, so they don't attack. They still take hits, stagger and recover as
    -- normal, and your attacks build ATB. The Tank dummy always fights back.
    passive_dps_dummy = true,
    passive_heal_dummy = true,

    -- Everyone's MP is refilled as it's spent, on all three courses. MP spent is still counted.
    unlimited_mp = true,

    -- Tank course: a party member whose HP falls below this percentage is refilled, so nobody dies. 0 turns it off.
    tank_refill_below_percent = 50,

    -- Healing course: which party members are patients held at 1 HP.
    --   "all"    = the whole party, including you
    --   "others" = everyone except the character you control
    heal_patients = "all",
    -- Seconds a healed patient keeps its HP before being dropped back to 1 HP,
    -- so the heal is visible on the HP bar.
    heal_reset_seconds = 1.5,

    -- Meters: rolling window for the "now" rate, in seconds.
    rolling_window_seconds = 5,

    -- The on-screen meter panel. Turn off to use only meters.json.
    -- Position in 1920x1080 units from the top left corner of the screen.
    overlay = true,
    overlay_x = 48,
    overlay_y = 48,

    -- Keys: clear the dummy's stagger now, reset the meters, show or hide the overlay.
    clear_stagger_key = "F6",
    reset_key = "F7",
    toggle_overlay_key = "F8",

    -- Write meters.json next to this mod for stream overlays and tests.
    write_json = true,

    -- Log what the mod sees (pawn, battle, enemies) to UE4SS.log.
    debug = false,
}

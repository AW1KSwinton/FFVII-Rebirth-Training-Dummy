-- Training Dummy settings. Edit, then restart the game (UE4SS hot reload crashes this game).
return {
    -- How often the mod checks the battle, in milliseconds.
    tick_ms = 200,

    -- A dummy whose HP falls below this percentage is topped back up to 100%.
    -- Kept high to leave a large HP margin between checks (5 per second).
    refill_below_percent = 90,

    -- Pin the DPS and Healing dummies in place with an endless Stop status.
    -- They still take hits and build stagger; the Tank dummy is never stopped.
    stop_dps_dummy = true,
    stop_heal_dummy = true,

    -- Healing course: which party members are patients held at 1 HP.
    --   "others" = everyone except the character you control
    --   "all"    = the whole party, including you
    heal_patients = "others",
    -- Seconds a healed patient keeps its HP before being dropped back to 1 HP,
    -- so the heal is visible on the HP bar.
    heal_reset_seconds = 1.5,

    -- Meters: rolling window for the "now" rate, in seconds.
    rolling_window_seconds = 5,

    -- On-screen meter text (top left). Turn off to use only meters.json.
    overlay = true,
    overlay_x = 40,
    overlay_y = 220,

    -- Keys: reset the meters, show or hide the overlay.
    reset_key = "F7",
    toggle_overlay_key = "F8",

    -- Write meters.json next to this mod for stream overlays and tests.
    write_json = true,

    -- Log what the mod sees (pawn, battle, enemies) to UE4SS.log.
    debug = false,
}

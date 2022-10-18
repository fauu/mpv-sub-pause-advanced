local UnpauseMode = {
  TEXT = 1,
  TIME = 2,
}

local options = {
  setup = "",
  ["min-sub-duration"] = 1,
  ["min-sub-text-length"] = 5, -- NOTE: Only in effect if length > `0`
  ["min-pause-duration"] = 0.5,
  ["unpause-base"] = 0.4,
  ["unpause-text-multiplier"] = 0.003,
  ["unpause-time-multiplier"] = 0.6,
  ["unpause-exponent"] = 1.25,
}
local cfg = {}
local state = {}

--- CONFIG UTILITIES -----------------------------------------------------------------------------------

local function sub_track_cfg(sub_track, sub_pos, key)
  local track_cfg = cfg[sub_track]
  if track_cfg == nil then
    return nil
  end
  if sub_pos == nil then
    if key == nil then
      return track_cfg
    else
      return track_cfg[key]
    end
  end
  local track_pos_cfg = track_cfg[sub_pos]
  if track_pos_cfg == nil then
    return nil
  end
  if key == nil then
    return track_pos_cfg
  end
  return track_pos_cfg[key]
end

--- SUB TRACK UTILITIES ----------------------------------------------------------------------------

local function sub_track_property(sub_track, property_base)
  local property = property_base
  if sub_track == 2 then
    property = "secondary-" .. property
  end
  return property
end

local function for_each_sub_track(cb)
  for sub_track=1,2 do
    cb(sub_track)
  end
end

--- SUB TEXT UTILITIES -----------------------------------------------------------------------------

local function calculate_sub_text_length(text)
  local _, len = text:gsub("[^\128-\193]", "")
  return len
end

local special_ass_codes = {"pos", "move", "kf", "fad"}

local function has_special_ass_code(s)
  for _, c in pairs(special_ass_codes) do
    -- PERF: Pre-create the patterns
    if s:find("%\\" .. c) then
      return true
    end
  end
  return false
end

local function suspected_special_sub(ass_text)
  -- Consider as special sub only if *all* lines have certain ASS codes
  for line in ass_text:gmatch("[^\r\n]+") do
    if not has_special_ass_code(line) then
      return false
    end
  end
  return true
end

--- VARIOUS SUB UTILITIES --------------------------------------------------------------------------

local function set_sub_visibility(sub_track, visible)
  -- NOTE: Limitation: Hiding primary sub also hides secondary sub
  mp.set_property_bool(sub_track_property(sub_track, "sub-visibility"), visible)
end

local function seek_to_sub_start(sub_track)
	local sub_start = mp.get_property_number(sub_track_property(sub_track, "sub-start"))
	if sub_start ~= nil then
    mp.set_property("time-pos", sub_start + mp.get_property_number("sub-delay"))
  end
end

--- PAUSE/UNPAUSE FUNCTIONS ------------------------------------------------------------------------

local function start_pause_duration(sub_track, mode, scale)
  local unscaled = cfg.unpause_base_secs
  if mode == UnpauseMode.TEXT then
    local text_length = state.curr_sub_text_length[sub_track]
    unscaled = unscaled + cfg.unpause_text_multiplier * text_length^cfg.unpause_exponent
  elseif mode == UnpauseMode.TIME then
    local time_length = state.curr_sub_time_length[sub_track]
    unscaled = unscaled + cfg.unpause_time_multiplier * time_length^cfg.unpause_exponent
  end
  return scale * unscaled
end

local function pause(sub_track)
  mp.set_property_bool("pause", true)
  for_each_sub_track(function (track)
    if sub_track_cfg(track, nil, "hide_while_playing")
      and not (
        track ~= sub_track
        and sub_track_cfg(track, nil, "hide_also_while_paused_for_other_track")
      ) then
        set_sub_visibility(track, true)
    end
  end)
end

local function unpause()
  if state.unpause_timer ~= nil then
    state.unpause_timer:kill()
  end

  -- NOTE: If both true, honors only first
  if state.replay_on_unpause[1] then
    seek_to_sub_start(1)
  elseif state.replay_on_unpause[2] then
    seek_to_sub_start(2)
  end
  state.replay_on_unpause = {false, false}

  mp.set_property_bool("pause", false)
end

local function unpause_after(duration)
  state.unpause_timer = mp.add_timeout(duration, unpause)
end

local function should_skip_because_special_sub(part_cfg)
  return not part_cfg.consider_special_subs
    and suspected_special_sub(mp.get_property("sub-text-ass"))
end

local function pause_wait_unpause(sub_track, part_cfg)
  local pause_duration =
    start_pause_duration(sub_track, part_cfg.unpause_mode, part_cfg.unpause_scale)
  if pause_duration >= cfg.min_pause_duration_secs then
    pause(sub_track)
    unpause_after(pause_duration)
  end
end

--- CORE EVENTS -----------------------------------------------------------------------------------

local function handle_sub_end_time(sub_track, sub_end_time)
  if not sub_end_time then
    return
  end
  if sub_end_time == state.curr_sub_end[sub_track] then
    -- Already handled this pause spot
    return
  end

  state.curr_sub_end[sub_track] = sub_end_time

  -- Skip if sub too short in terms of both time and text length
  local sub_start_time = mp.get_property_number(sub_track_property(sub_track, "sub-start"))
  if not sub_start_time then
    return
  end
  local sub_time_length = sub_end_time - sub_start_time
  if sub_time_length < cfg.min_sub_time_length_sec then
    return
  end
  state.curr_sub_time_length[sub_track] = sub_time_length
  local sub_text_length =
    calculate_sub_text_length(mp.get_property(sub_track_property(sub_track, "sub-text")))
  -- Ignore `0`, since image-based subs have the length of `0`
  if sub_text_length > 0 and sub_text_length < cfg.min_sub_text_length then
    return
  end
  state.curr_sub_text_length[sub_track] = sub_text_length

  -- Handle start pause
  local cfg_start = sub_track_cfg(sub_track, "start")
  if cfg_start ~= nil then
    if should_skip_because_special_sub(cfg_start) then
      goto skip
    end

    if cfg_start.unpause then
      pause_wait_unpause(sub_track, cfg_start)
    else
      pause(sub_track)
    end

    ::skip::
  end

  -- Handle end pause
  local cfg_end = sub_track_cfg(sub_track, "end")
  if cfg_end ~= nil then
    if cfg_end.on_request then
      goto skip
    end
    if should_skip_because_special_sub(cfg_end) then
      goto skip
    end

    state.pause_at_sub_end[sub_track] = true

    ::skip::
  end
end

local function handle_sub_end_reached(sub_track)
  if not state.pause_at_sub_end[sub_track] then
    return
  end

  state.pause_at_sub_end[sub_track] = false

  local cfg_end = sub_track_cfg(sub_track, "end")
  if cfg_end.unpause then
    pause_wait_unpause(sub_track, cfg_end)
  else
    pause(sub_track)
  end
end

local function handle_pause(_, paused)
  if not paused then
    if state.unpause_timer ~= nil then
      state.unpause_timer:kill()
      state.unpause_timer = nil
    end

    -- TODO: Honor manual visibility changes?
    for_each_sub_track(function (track)
      if sub_track_cfg(track, nil, "hide_while_playing") then
        set_sub_visibility(track, false)
      end
    end)
  end
end

local handle_sub_end_time_for_sub_track = {
  function(_, sub_end_time)
    handle_sub_end_time(1, sub_end_time)
  end,
  function(_, sub_end_time)
    handle_sub_end_time(2, sub_end_time)
  end,
}

local function handle_time_pos(_, time_pos)
	if time_pos == nil then
    return
  end

  for_each_sub_track(function (track)
    if state.curr_sub_end[track] then
      local sub_end_with_delay = state.curr_sub_end[track] + mp.get_property_number("sub-delay")
      if sub_end_with_delay - time_pos <= cfg.sub_end_delta then
        handle_sub_end_reached(track)
      end
    end
  end)
end

--- SECONDARY EVENTS -------------------------------------------------------------------------------

local function handle_request_pause_pressed()
  if mp.get_property_bool("pause") then
    unpause()
  elseif not state.enabled then
    pause()
  else
    state.pause_at_sub_end = {
      sub_track_cfg(1, "end", "on_request") or false,
      sub_track_cfg(2, "end", "on_request") or false,
    }
    if not state.pause_at_sub_end[1] and not state.pause_at_sub_end[2] then
      pause()
    else
      state.replay_on_unpause = {
        sub_track_cfg(1, "end", "replay") or false,
        sub_track_cfg(2, "end", "replay") or false,
      }
    end
  end
end

--- CORE FUNCTIONS ---------------------------------------------------------------------------------

local function replay_sub(sub_track)
  seek_to_sub_start(sub_track)
  unpause()
end

--- INIT/DEINIT ------------------------------------------------------------------------------------

local function init_state()
  state = {
    enabled = false,
    unpause_timer = nil,
    curr_sub_end = {nil, nil},
    curr_sub_time_length = {nil, nil},

    -- TODO: Both probably need to be cleared on seek or sth to invalidate possible pause request
    pause_at_sub_end = {false, false},
    replay_on_unpause = {false, false}
  }
end

local function reset_state()
  if state.unpause_timer ~= nil then
    state.unpause_timer:kill()
  end
  state.enabled = false
  state.unpause_timer = nil
  state.curr_sub_end = {nil, nil}
  state.curr_sub_time_length = {nil, nil}
  state.curr_sub_text_length = {nil, nil}
  state.pause_at_sub_end = {false, false}
  state.replay_on_unpause = {false, false}
end

local function deinit()
  mp.unobserve_property(handle_pause)
  for_each_sub_track(function (track)
    mp.unobserve_property(handle_sub_end_time_for_sub_track[track])
  end)
  mp.unobserve_property(handle_time_pos)
  reset_state()

  -- TODO: Honor manual visibility changes?
  for_each_sub_track(function (track)
    set_sub_visibility(track, true)
  end)
end

local function init()
  deinit()

  local paused = mp.get_property_bool("pause")

  for_each_sub_track(function (track)
    if sub_track_cfg(track) then
      state.enabled = true

      mp.observe_property("sub-end", "number", handle_sub_end_time_for_sub_track[track])
      if not paused and cfg[track].hide_while_playing then
        set_sub_visibility(track, false)
      end
    end
  end)
  if sub_track_cfg(1) or sub_track_cfg(2) then
    mp.observe_property("pause", "bool", handle_pause)
  end
  if sub_track_cfg(1, "end") or sub_track_cfg(2, "end") then
    mp.observe_property("time-pos", "number", handle_time_pos)
  end
end

local function handle_primary_sub_track()
  init()
end

local function handle_toggle()
  local state_str
  if state.enabled then
    -- Disable
    deinit()
    state.enabled = false
    state_str = "off"
  else
    -- Enable
    init()
    state.enabled = true -- NOTE: Don't move this outside the condition
    state_str = "on"
  end
  mp.osd_message("Subtitle pause " .. state_str, 3)
end

--- CONFIG PARSE -----------------------------------------------------------------------------------

local function parse_cfg()
  local new_cfg = {
    sub_end_delta = 0.1,
    min_sub_time_length_sec = options["min-sub-duration"],
    min_sub_text_length = options["min-sub-text-length"],
    min_pause_duration_secs = options["min-pause-duration"],
    unpause_base_secs = options["unpause-base"],
    unpause_text_multiplier = options["unpause-text-multiplier"],
    unpause_time_multiplier = options["unpause-time-multiplier"],
    unpause_exponent = options["unpause-exponent"],
  }

  for part in options.setup:gmatch("[%w%_-%!%.]+") do
    local c = {
      on_request = false,
      replay = false,
      unpause = false,
      unpause_mode = UnpauseMode.TEXT,
      unpause_scale = 1,
      consider_special_subs = false,
    }

    local segs = part:gmatch("[^%!]+")

    -- Parse first seg
    local first_seg = segs()
    local sub_track = 1
    if first_seg:find("2", 1) then
      sub_track = 2
    end
    local sub_pos = first_seg:gmatch("%d?(.+)")()
    if sub_pos ~= "start" and sub_pos ~= "end" then
      goto skip
    end

    if new_cfg[sub_track] == nil then
      new_cfg[sub_track] = {
        hide_while_playing = false,
        hide_also_while_paused_for_other_track = false,
      }
    end

    -- Parse rest segs
    for seg in segs do
      local subsegs = seg:gmatch("[^-]+")
      local main = subsegs()
      if main == "request" and sub_pos == "end" then
        c.on_request = true
        if subsegs() == "replay" then
          c.replay = true
        end
      elseif main == "unpause" then
        c.unpause = true
        for arg in subsegs do
          if arg == "time" then
            c.unpause_mode = UnpauseMode.TIME
          else
            local numarg = tonumber(arg)
            if numarg ~= nil then
              c.unpause_scale = numarg
            end
          end
        end
      elseif main == "hide" then
        new_cfg[sub_track].hide_while_playing = true
        if subsegs() == "more" and sub_track == 2 then
          new_cfg[sub_track].hide_also_while_paused_for_other_track = true
        end
      elseif main == "special" and sub_track == 1 then
        c.consider_special_subs = true
      end
    end

    new_cfg[sub_track][sub_pos] = c

    ::skip::
  end

  return new_cfg
end

--- MAIN ------------------------------------------------------------------------------------------

local function debug_dump(o)
  if type(o) == "table" then
    local s = "{ "
    for k, v in pairs(o) do
      if type(k) ~= "number" then
        k = '"' .. k.. '"'
      end
      s = s .. "[" .. k .. "] = " .. debug_dump(v) .. ","
    end
    return s .. "} "
  else
    return tostring(o)
  end
end

local function main()
  require("mp.options").read_options(options, "sub-pause")
  cfg = parse_cfg()
  print(debug_dump(cfg))
  init_state()
  mp.observe_property("current-tracks/sub/id", "number", handle_primary_sub_track)
  mp.add_key_binding("n", "toggle", handle_toggle)

  mp.add_forced_key_binding("MBTN_RIGHT", "request-pause", handle_request_pause_pressed)

  mp.add_key_binding("Ctrl+r", "replay", function() replay_sub(1) end)
  mp.add_key_binding(nil, "replay-secondary", function() replay_sub(2) end)
end

main()

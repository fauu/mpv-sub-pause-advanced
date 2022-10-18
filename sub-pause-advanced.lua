local UnpauseMode = {
  TEXT = 1,
  TIME = 2,
}

local options = {
  setup = ""
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

local function sub_text_length(text)
  local _, len = string.gsub(text, "[^\128-\193]", "")
  return len
end

local function suspected_sign_sub(ass_text)
  -- Consider as sign sub only if *all* lines have ASS escape sequences.
  for line in ass_text:gmatch("[^\r\n]+") do
    if not line:find("%{%\\%a") then
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
  local sub_start = mp.get_property_number(sub_track_property(sub_track, "sub-start"))
  local sub_end = mp.get_property_number(sub_track_property(sub_track, "sub-end"))
  if not sub_start or not sub_end then
    return 0 end

  local time_length = sub_end - sub_start
  if time_length < 0.2 then -- XXX: Configurable how
    return 0
  end
  local unscaled = 0
  local base = 0.4 -- TODO: Constants
  if mode == UnpauseMode.TEXT then
    local sub_text = mp.get_property(sub_track_property(sub_track, "sub-text"))
    local text_length = sub_text_length(sub_text)
    if text_length < 5 then --- XXX: Configurable how
      return 0
    end
    unscaled = base + (0.003 * (text_length * (text_length / 4)))
  elseif mode == UnpauseMode.TIME then
    unscaled = base + (0.6 * (time_length * (time_length / 4)))
  end
  return scale * unscaled
end

local function pause(for_sub_track)
  mp.set_property_bool("pause", true)
  for_each_sub_track(function (track)
    if sub_track_cfg(track, nil, "hide_while_playing")
      and not (
        track ~= for_sub_track
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

local function should_skip_because_sign_sub(part_cfg)
  return part_cfg.ignore_sign_subs and suspected_sign_sub(mp.get_property("sub-text-ass"))
end

local function pause_and_unpause(sub_track, part_cfg)
  local pause_duration = start_pause_duration(sub_track, part_cfg.unpause_mode, part_cfg.unpause_scale)
  if pause_duration > 0.1 then -- TODO: Constant
    pause(sub_track)
    unpause_after(pause_duration)
  end
end

--- CORE EVENTS -----------------------------------------------------------------------------------

local function handle_sub_end_time(sub_track, sub_end_time)
  if sub_end_time == nil then
    -- Just unpaused, no sub yet
    return
  end
  if sub_end_time == state.curr_sub_end[sub_track] then
    -- Already handled this pause spot
    return
  end

  local cfg_start = sub_track_cfg(sub_track, "start")
  if cfg_start ~= nil then
    if should_skip_because_sign_sub(cfg_start) then
      goto skip
    end

    if cfg_start.unpause then
      pause_and_unpause(sub_track, cfg_start)
    else
      pause(sub_track)
    end

    ::skip::
  end

  local cfg_end = sub_track_cfg(sub_track, "end")
  if cfg_end ~= nil then
    if cfg_end.on_request then
      goto skip
    end
    if should_skip_because_sign_sub(cfg_end) then
      goto skip
    end

    state.pause_at_sub_end[sub_track] = true

    ::skip::
  end

  state.curr_sub_end[sub_track] = sub_end_time
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

local function handle_sub_end_reached(sub_track)
  if state.pause_at_sub_end[sub_track] then
    local cfgend = sub_track_cfg(sub_track, "end")
    if cfgend.unpause then
      pause_and_unpause(sub_track, cfgend)
    else
      pause(sub_track)
    end
    state.pause_at_sub_end[sub_track] = false
  end
end

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

-- XXX: Pauses immediately if in between subs
local function handle_request_pause_pressed(info)
  local down = info.event == "down"
  if down then
    if mp.get_property_bool("pause") then
      unpause()
    elseif state.disabled then
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
    sub_end_delta = 0.1
  }

  for part in string.gmatch(options.setup, "[%w%_-%!%.]+") do
    local c = {
      on_request = false,
      replay = false,
      unpause = false,
      unpause_mode = UnpauseMode.TEXT,
      unpause_scale = 1,
      ignore_sign_subs = false,
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
      elseif main == "nosign" and sub_track == 1 then
        c.ignore_sign_subs = true
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

  -- XXX: Disable complex if not needed
  mp.add_forced_key_binding(
    "MBTN_RIGHT",
    "request-pause",
    handle_request_pause_pressed,
    {complex = true}
  )

  mp.add_key_binding("Ctrl+r", "replay", function() replay_sub(1) end)
  mp.add_key_binding(nil, "replay-secondary", function() replay_sub(2) end)
end

main()

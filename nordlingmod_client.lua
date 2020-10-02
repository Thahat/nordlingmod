nordlingmod = {
}

local log = radiant.log.create_logger('Nordling Mod Server')

local player_service_trace = nil

local function check_override_ui(players, player_id)
   -- Load ui mod
   if not player_id then
      player_id = _radiant.client.get_player_id()
   end
   
   local client_player = players[player_id]
   if client_player then
      if client_player.kingdom == "nordlingmod:kingdoms:nordlings" then
         -- hot load nordlingmod ui mod
         _radiant.res.apply_manifest("/nordlingmod/ui/manifest.json")
         log:always("Nordlings Selected: Applying UI")
      end
   end
end

local function trace_player_service()
   _radiant.call('stonehearth:get_service', 'player')
      :done(function(r)
         local player_service = r.result
         check_override_ui(player_service:get_data().players)
         player_service_trace = player_service:trace('nordlings ui change')
               :on_changed(function(o)
                     check_override_ui(player_service:get_data().players)
                  end)
         end)
end

radiant.events.listen(nordlingmod, 'radiant:init', function()
   radiant.events.listen(radiant, 'radiant:client:server_ready', function()
         trace_player_service()
      end)
   end)

return nordlingmod
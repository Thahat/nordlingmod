
local DefenseBuff = class()

function DefenseBuff:on_buff_added(entity, buff)
  local render_info = entity:add_component('render_info')
  local scale = buff:get_json().render_info.scale
  if not scale then
    return
  end
  render_info:set_scale(scale)

end

function DefenseBuff:on_buff_removed(entity, buff)
  local render_info = entity:add_component('render_info')
   render_info:set_scale(0.1)
  
end

return DefenseBuff

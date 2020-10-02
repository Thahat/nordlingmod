local CraftingJob = require 'stonehearth.jobs.crafting_job'

local HerbgeoClass = class()
radiant.mixin(HerbgeoClass, CraftingJob)

function HerbgeoClass:initialize()
   CraftingJob.initialize(self)
   self._sv.max_num_attended_hearthlings = 2
   self._sv.max_num_golems = {}
end

function HerbgeoClass:activate()
   CraftingJob.activate(self)

   if self._sv.is_current_class then
      self:_register_with_town()
   end

   self.__saved_variables:mark_changed()
end

function HerbgeoClass:restore()
   if self._sv.is_current_class then
      self:_register_with_town()
   end
end

function HerbgeoClass:promote(json_path, options)
   CraftingJob.promote(self, json_path, options)
   self._sv.max_num_golems = { golem = 0 }
   self._sv.max_num_attended_hearthlings = self._job_json.initial_num_attended_hearthlings or 2
   if self._sv.max_num_attended_hearthlings > 0 then
      self:_register_with_town()
   end
   self.__saved_variables:mark_changed()
end

function HerbgeoClass:increase_attended_hearthlings(args)
   self._sv.max_num_attended_hearthlings = args.max_num_attended_hearthlings
   self:_register_with_town() -- re-register with the town because number of max attended hearthlings is increased
   self.__saved_variables:mark_changed()
end

function HerbgeoClass:increase_max_golems(perk_json)
   self._sv.max_num_golems = { golem = perk_json.max_num_golems }
   self:_register_with_town()
   self.__saved_variables:mark_changed()
end

-- Registers the medic with the town
function HerbgeoClass:_register_with_town()
   local player_id = radiant.entities.get_player_id(self._sv._entity)
   -- Enforce golem limit.
   local town = stonehearth.town:get_town(player_id)
   if town then
      town:add_placement_slot_entity(self._sv._entity, self._sv.max_num_golems)
	  town:add_medic(self._sv._entity, self._sv.max_num_attended_hearthlings)
   end
end

-- Called when destroying this entity, we should alo remove ourselves
function HerbgeoClass:_unregister_with_town()
   local player_id = radiant.entities.get_player_id(self._sv._entity)
   local town = stonehearth.town:get_town(player_id)
   if town then
      town:remove_medic(self._sv._entity)
   end
end

function HerbgeoClass:_create_listeners()
   CraftingJob._create_listeners(self)
   self._on_heal_entity_listener = radiant.events.listen(self._sv._entity, 'stonehearth:healer:healed_entity', self, self._on_healed_entity)
end

function HerbgeoClass:_remove_listeners()
   CraftingJob._remove_listeners(self)
   if self._on_heal_entity_listener then
      self._on_heal_entity_listener:destroy()
      self._on_heal_entity_listener = nil
   end
end

function HerbgeoClass:_on_healed_entity(args)
   local exp = self._xp_rewards['heal_entity']
   if exp then
      self._job_component:add_exp(exp)
   end
end

-- Call when it's time to demote
function HerbgeoClass:demote()
   self:_unregister_with_town()

   CraftingJob.demote(self)
end

-- Called when destroying this entity
-- Note we could get destroyed without being demoted
-- So remove ourselves from town just in case
function HerbgeoClass:destroy()
   if self._sv.is_current_class then
      self:_unregister_with_town()
   end

   CraftingJob.destroy(self)
end
return HerbgeoClass

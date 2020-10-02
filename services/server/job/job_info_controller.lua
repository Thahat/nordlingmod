local JobInfoController = class()

-- Holds data about a certain class of job for a player

-- Initialized with information about the job, stored in the jobname_description.json file
-- While job_component.lua and jobname.lua hold job data for an entity, this controller
-- holds job data for a player: for example, a communal recipe list for a player's carpenters, or
-- order lists for those carpenters.

-- TODO: This is definitely useful for crafters so let's keep it generic in case it's useful for
-- other classes also.

local VERSIONS = {
   ZERO = 0,
   FIX_MANUALLY_UNLOCKED_MASON_RECIPES = 1,
   CRAFT_ORDER_LIST_PLAYER_ID = 2,
}

function JobInfoController:get_version()
   return VERSIONS.CRAFT_ORDER_LIST_PLAYER_ID
end

function JobInfoController:initialize()
   -- Saved variables
   self._sv.members = {}
   self._sv.num_members = 0
   self._sv.highest_level = 0
   self._sv.manually_unlocked = {}
   self._sv.player_id = nil
   self._sv.class_name = nil
   self._sv.description_url = nil
   self._sv.alias = nil
   self._sv.order_list = nil
   self._sv.is_combat_job = false

   -- UI variables
   self._sv.skin_class = nil
   self._sv.open_sound = nil
   self._sv.close_sound = nil
   self._sv.recipe_list = nil
   self._sv.roles = {}

   -- member variables
   self._recipe_list_location = nil

   self._craftable_recipes = {}
   self._log = radiant.log.create_logger('job_info_controller')
end

function JobInfoController:fixup_post_load(old_save_data)
   if old_save_data.version < VERSIONS.FIX_MANUALLY_UNLOCKED_MASON_RECIPES then
      if old_save_data.manually_unlocked then
         self._sv.manually_unlocked['signage_decoration:valor_statue'] = old_save_data.manually_unlocked['decoration:valor_statue']
         self._sv.manually_unlocked['signage_decoration:roadside_shrine'] = old_save_data.manually_unlocked['decoration:roadside_shrine']
         self._sv.manually_unlocked['signage_decoration:craftsman_statue'] = old_save_data.manually_unlocked['decoration:craftsman_statue']
      end
   end

   if old_save_data.version < VERSIONS.CRAFT_ORDER_LIST_PLAYER_ID then
      if old_save_data.order_list then
         self._fixup_player_id = true
      end
   end
end

function JobInfoController:create(info, player_id)
   self._sv.player_id = player_id
   self._sv.description_url = info.description
end

function JobInfoController:restore()
   if self._fixup_player_id then
      self._sv.order_list:set_player_id(self._sv.player_id)
   end
end

function JobInfoController:activate()
   if self._sv.description_url then
      self._description_json = radiant.resources.load_json(self._sv.description_url)
      if self._description_json then
         self._sv.alias = self._description_json.alias
         --TODO: after merge with i18n branch, check that name is still the user visible name here
         self._sv.class_name = self._description_json.display_name

         --Crafter specific init
         local crafter = self._description_json.crafter
         if crafter then
            if crafter.recipe_list then
               self._recipe_list_location  = crafter.recipe_list
            end
         end

         local workshop = self._description_json.workshop
         if workshop then
            self._sv.skin_class = workshop.skin_class
            self._sv.open_sound = workshop.open_sound
            self._sv.close_sound = workshop.close_sound

            --If we have a workshop, init the order list!
            if not self._sv.order_list then
               self._sv.order_list = radiant.create_controller('stonehearth:craft_order_list', self._sv.player_id)
            end
         end

         if self._description_json.roles then
            self._sv.roles = {}
            local split_roles = radiant.util.split_string(self._description_json.roles)
            for _, job_role in ipairs(split_roles) do
               self._sv.roles[job_role] = true
               if job_role == 'combat' then
                  self._sv.is_combat_job = true
               end
            end
         end
      end
   end

   if self._recipe_list_location  then
      self:_build_craftable_recipe_list(self._recipe_list_location )
   end

   self:_evaluate_highest_level()
end

function JobInfoController:post_activate()
   -- Tell anyone who cares which recipes are available. Done in post_activate() in case other 
   -- components start listening in activate().
   self:foreach_available_recipes(function(recipe_data)
         radiant.events.trigger(radiant, 'radiant:crafting:recipe_revealed', {recipe_data = recipe_data})
      end)
end

function JobInfoController:destroy()
   self:clear()
end

function JobInfoController:get_description_json()
   return self._description_json
end

-- === CRAFTER RELATED FUNCTIONS ===

function JobInfoController:get_order_list()
   return self._sv.order_list
end

function JobInfoController:get_recipe_list()
   return self._sv.recipe_list
end

function JobInfoController:foreach_available_recipes(fn)
   for _, recipe_data in pairs(self._craftable_recipes) do
      if not recipe_data.manual_unlock or self._sv.manually_unlocked[recipe_data.recipe_key] then
         fn(recipe_data)
      end
   end
end

function JobInfoController:queue_order_if_possible(product_uri, amount)
   -- if we can craft this product, queue it up and return true
   if not self._sv.order_list then
      return false
   end

   local recipe = self._craftable_recipes[product_uri]
   if not recipe then
      return false
   end

   if recipe.manual_unlock and not self._sv.manually_unlocked[recipe.recipe_key] then
      return false
   end

   -- TODO(yshan) do not block based on level requirement for now
   -- because the basic buildings require things like the lantern, which needs level 1 to craft.
   --if recipe.level_requirement > self._sv.highest_level then
      --return false
   --end

   local condition = {
      type = 'make',
      amount = amount
   }
   local recipe_copy = radiant.deep_copy(recipe)
   local workshop_uri = recipe_copy.workshop
   if workshop_uri then
      -- Need to fix this up because of inconsistencies with UI queuing craft orders VS actual craft orders
      recipe_copy.workshop = { uri = workshop_uri }
   end
   self._sv.order_list:add_order(self._sv.player_id, recipe_copy, condition)
   return true
end

-- Note this only clears the manual_lock flag, if there are other
-- unmet conditions, e.g. level_requirement, then the recipe will
-- remain locked until those conditions are met.
function JobInfoController:manually_unlock_recipe(recipe_key, ignore_missing) -- TODO: Allow user to unlock recipe from a json file
   if not self._sv.recipe_list then
      radiant.verify(false, "Attempting to manually unlock recipe %s when job %s does not have any recipes!", recipe_key, self._sv.alias)
      return false
   end
   local found_recipe = nil
   for category, category_data in pairs(self._sv.recipe_list) do
      if category_data.recipes then
         for recipe_short_key, recipe_data in pairs(category_data.recipes) do
            if recipe_data.recipe and recipe_data.recipe.recipe_key == recipe_key then
               found_recipe = recipe_data.recipe
               break
            end
         end
      end
      if found_recipe then
         break
      end
   end
   if not found_recipe then
      if not ignore_missing then
         radiant.verify(false, "Attempting to manually unlock recipe %s when job %s does not have such a recipe!", recipe_key, self._sv.alias)
      end
      return false
   end

   self._sv.manually_unlocked[recipe_key] = true
   self.__saved_variables:mark_changed()
   
   radiant.events.trigger(radiant, 'radiant:crafting:recipe_revealed', {recipe_data = found_recipe})

   return true
end

function JobInfoController:get_manually_unlocked()
   return self._sv.manually_unlocked
end

function JobInfoController:manually_unlock_crop(crop_key, ignore_missing) -- TODO: remove hardcoded 'stonehearth:jobs:farmer' and 'stonehearth:farmer:all_crops' to allow for mods
    local kingdom = stonehearth.player:get_kingdom(self._sv.player_id)
    if kingdom == "nordlingmod:kingdoms:nordlings" then
        if self._sv.alias ~= 'stonehearth:jobs:worker' then
            radiant.verify(false, "Attempting to manually unlock crop %s when job %s does not have crops!", crop_key, self._sv.alias)
            return false
        end
    else
        if self._sv.alias ~= 'stonehearth:jobs:farmer' then
            radiant.verify(false, "Attempting to manually unlock crop %s when job %s does not have crops!", crop_key, self._sv.alias)
            return false
        end
    end
   local found_crop = false

   local crop_list = radiant.resources.load_json('stonehearth:farmer:all_crops').crops
   for crop_key, crop_data in pairs(crop_list) do
         if crop_data then
            found_crop = true
            break
         end
      if found_crop then
         break
      end
   end
   if not found_crop then
      if not ignore_missing then
         radiant.verify(false, "Attempting to manually unlock crop %s when job %s does not have such a crop!", crop_key, self._sv.alias)
      end
      return false
   end

   local already_unlocked = self._sv.manually_unlocked[crop_key]
   if already_unlocked then
      return false
   end

   self._sv.manually_unlocked[crop_key] = true
   self.__saved_variables:mark_changed()
   return true
end

--- Build the list sent to the UI from the json
--  Load each recipe's data and add it to the table
function JobInfoController:_build_craftable_recipe_list(recipe_index_url)
   -- Note: this recipe list is recreated everytime we load the game.
   -- The reason it's in _sv is so we can easily send the recipe data to the client.
   self._sv.recipe_list = radiant.deep_copy(radiant.resources.load_json(recipe_index_url).craftable_recipes)

   for category, category_data in pairs(self._sv.recipe_list) do
      if category_data.recipes then
         for recipe_short_key, recipe_data in pairs(category_data.recipes) do
            local recipe_key = category .. ":" .. recipe_short_key
            if recipe_data.recipe == "" then
               --we've lost the recipe, for example, because it's been overridden by a mod
               self._sv.recipe_list[category].recipes[recipe_short_key] = nil
            else
               recipe_data.recipe = radiant.deep_copy(radiant.resources.load_json(recipe_data.recipe))
               self:_initialize_recipe_data(recipe_key, recipe_data.recipe)
            end
         end
      end
   end
   self.__saved_variables:mark_changed()
end

-- Prep the recipe data with any default values
function JobInfoController:_initialize_recipe_data(recipe_key, recipe_data)
   if not recipe_data.level_requirement then
      recipe_data.level_requirement = 0
   end
   recipe_data.recipe_key = recipe_key
   if recipe_data.produces then
      local uri = recipe_data.produces[1].item
      recipe_data.product_uri = uri

      local canonical = radiant.resources.convert_to_canonical_path(uri)
      radiant.verify(canonical, 'Crafter job %s has a recipe named "%s" that produces an item not in the manifest %s', self._sv.alias, recipe_key, uri)

      self._craftable_recipes[uri] = recipe_data
   end
end

-- Call whenever we promote someone to this job
function JobInfoController:add_member(entity)
   local entity_id = entity:get_id()
   if not self._sv.members[entity_id] then
      self._sv.members[entity_id] = entity
      self:_evaluate_highest_level()
      self.__saved_variables:mark_changed()

      if self:get_num_members() == 1 then
         radiant.events.trigger_async(stonehearth.job:get_jobs_controller(self._sv.player_id), 'stonehearth:job:job_presence_changed', { is_combat_job = self:is_combat_job()})
         self._log:info('Populated a job with no previous members.')
      end

   end
end

-- Call whenever we demote someone from this job
function JobInfoController:remove_member(entity_id)
   if self._sv.members[entity_id] then
      self._sv.members[entity_id] = nil
      self:_evaluate_highest_level()
      self.__saved_variables:mark_changed()

      if self:get_num_members() == 0 then
         radiant.events.trigger_async(stonehearth.job:get_jobs_controller(self._sv.player_id), 'stonehearth:job:job_presence_changed', { is_combat_job = self:is_combat_job() })
         self._log:info('Depopulated a job of its last member')
      end

   end
end

-- Call whenever someone levels up
-- Note: we could do this via events, but our heuristic is: if you can call a fn, call it!
-- The job_component already knows about the job_info_controller, so just call this on level up.
function JobInfoController:promote_member(entity)
   local entity_id = entity:get_id()
   if self._sv.members[entity_id] then
      self:_evaluate_highest_level()
   end
end

-- Clears this job info controller of game session specific information.
function JobInfoController:clear()
   if self._sv.order_list then
      self._sv.order_list:clear_all_orders()
   end
end

-- Calculate based on each member's highest level in THIS class
function JobInfoController:_evaluate_highest_level()
   local highest_level = 0
   local num_members = 0
   for id, entity in pairs(self._sv.members) do
      local job_component = entity:get_component('stonehearth:job')
      assert(job_component:get_job_uri() == self._sv.alias, 'entity job does not match job controller')
      local level = job_component:get_curr_job_controller():get_job_level()
      if level > highest_level then
         highest_level = level
      end
      num_members = num_members + 1
   end
   self._sv.highest_level = highest_level
   self._sv.num_members = num_members

   self.__saved_variables:mark_changed()
end

function JobInfoController:get_highest_level()
   return self._sv.highest_level
end

function JobInfoController:has_members()
   return next(self._sv.members) ~= nil
end

function JobInfoController:get_num_members()
   return self._sv.num_members
end

function JobInfoController:get_roles()
   return self._sv.roles
end

function JobInfoController:is_combat_job()
   return self._sv.is_combat_job
end

function JobInfoController:get_alias()
   return self._sv.alias
end

return JobInfoController

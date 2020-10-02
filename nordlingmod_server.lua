local log = radiant.log.create_logger('wouter, thanks to kaimonkey')

local JobComponent = require 'stonehearth.components.job.job_component'
if JobComponent then
  local old_level_up = JobComponent.level_up
  function JobComponent:level_up(skip_visual_effects)
    if self._sv.job_uri == "stonehearth:jobs:worker" and self._sv.curr_job_level == 0 then
      old_level_up(self, true)
    else
      old_level_up(self, skip_visual_effects)
    end
  end

  local old_promote = JobComponent.promote_to
  function JobComponent:promote_to(job_uri, options)
    if not options then
      options = {}
    end
    if job_uri == "stonehearth:jobs:worker" and not self:_call_job('get_job_level') then
      options.skip_visual_effects = true
    end
    old_promote(self, job_uri, options)
  end

else
  log:error("Couldn't Load Job Component")
end

local JobService = require 'stonehearth.services.server.job.job_service'
local old_get_job_info = JobService.get_job_info
function JobService:get_job_info(player_id, job_id)
    local kingdom = stonehearth.player:get_kingdom(player_id)
    if kingdom == "nordlingmod:kingdoms:nordlings" and job_id == "stonehearth:jobs:farmer" then
     return old_get_job_info(self, player_id, "stonehearth:jobs:worker")
   else
     return old_get_job_info(self, player_id, job_id)
  end
end
  log:error("Monkey Patched Job Service")
--e:get_component("stonehearth:job"):level_up()

local JobInfo = require 'stonehearth.services.server.job.job_info_controller'
local old_manually_unlock_crop = JobInfo.manually_unlock_crop
function JobInfo:manually_unlock_crop(crop_key, ignore_missing)
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
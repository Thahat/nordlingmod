RulerClass = class()
local CombatJob = require 'stonehearth.jobs.combat_job'
radiant.mixin(RulerClass, CombatJob)
return RulerClass
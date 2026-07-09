-- Which build this server is running. The checked-in values are the local
-- dev defaults; scripts/deploy-places.mjs overwrites this file while
-- building a deploy (git commit + timestamp) and restores it afterwards, so
-- every published place can say exactly which commit it runs (the future
-- dashboard reads this back through server heartbeats).
return {
	commit = "dev",
	builtAt = 0, -- unix seconds; 0 = not a pipeline build
}

-- Non-secret backend settings. The API key is loaded separately from Secret.lua.

return {
	baseUrl = "https://famana-backend-production.up.railway.app",
	requestTimeout = 10, -- informational; HttpService has its own internal timeout
}

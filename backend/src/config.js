// Centralised environment config with light validation.

function required(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

export const config = {
  databaseUrl: required("DATABASE_URL"),
  apiKey: required("API_KEY"),
  port: Number(process.env.PORT || 3000),
  // Railway/Postgres plugins require SSL; local dev usually does not.
  // Toggle with PGSSL=true if your host needs it.
  pgSsl: process.env.PGSSL === "true",
};

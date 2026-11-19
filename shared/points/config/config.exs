import Config
config :regent_agents, ash_domains: [RegentAgents]
config :ash, default_string_length_count: :codepoints

config :regent_points,
  generate_migrations: true,
  ash_domains: [RegentPoints],
  repo: RegentPoints.Repo

config :regent_points, RegentPoints.Repo,
  hostname: "127.0.0.1",
  port: 5432,
  database: "regent_points_dev",
  username: System.get_env("USER"),
  pool_size: 5

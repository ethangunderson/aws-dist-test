use Mix.Config

# Application name
app = System.get_env("APPLICATION_NAME")
env = System.get_env("ENVIRONMENT_NAME")
region = System.get_env("AWS_REGION")

# Locate awscli
aws = System.find_executable("aws")

cond do
  is_nil(app) ->
    raise "APPLICATION_NAME is unset!"
  is_nil(env) ->
    raise "ENVIRONMENT_NAME is unset!"
  is_nil(aws) ->
    raise "Unable to find `aws` executable!"
  :else ->
    :ok
end

# Pull database password from SSM
db_secret_name = "/#{app}/#{env}/database/password"
db_password =
  case System.cmd(aws, ["ssm", "get-parameter", "--region=#{region}", "--name=#{db_secret_name}", "--with-decryption"]) do
    {json, 0} ->
      %{"Parameter" => %{"Value" => password}} = Jason.decode!(json)
      password
    {output, status} ->
      raise "Unable to get database password, command exited with status #{status}:\n#{output}"
  end

config :engine, Engine.Repo,
  username: System.get_env("DATABASE_USER"),
  password: db_password,
  database: System.get_env("DATABASE_NAME"),
  hostname: System.get_env("DATABASE_HOST"),
  pool_size: 15

config :services, Services.Database, Engine.Database
config :services, Services.Todos, Engine.Todo

config :services, Services.Cluster,
  topologies: [
    ec2: [
      strategy: ClusterEC2.Strategy.Tags,
      config: [
        ec2_tagname: "distribution-group",
        ec2_tagvalue: "#{app}-#{env}",
        app_prefix: "distillery_example"
      ]
    ]
  ]

config :services, Services.Registry,
  log_level: :debug,
  broadcast_period: 100,
  max_silent_periods: 2,
  pool_size: 1,
  name: Services.Registry.PubSub

[
  import_deps: [:ash, :ash_postgres],
  plugins: [Spark.Formatter],
  inputs: ["{mix,.formatter}.exs", "{config,lib,dev,priv}/**/*.{ex,exs}"]
]

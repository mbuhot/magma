[
  import_deps: [:ash, :ash_postgres, :reactor, :oban],
  plugins: [Spark.Formatter],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]

spark_locals_without_parens = [
  max_attempts: 1,
  queue: 1,
  retention: 1,
  workflow: 1
]

[
  import_deps: [:ash, :ash_postgres, :reactor, :oban],
  plugins: [Spark.Formatter],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: spark_locals_without_parens,
  export: [locals_without_parens: spark_locals_without_parens]
]

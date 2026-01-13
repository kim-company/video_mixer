defmodule VideoMixer.MixProject do
  use Mix.Project

  @version "2.0.0"
  @link "https://github.com/kim-company/video_mixer"

  def project do
    [
      app: :video_mixer,
      version: @version,
      source_url: @link,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      compilers: [:unifex, :bundlex] ++ Mix.compilers(),
      deps: deps(),
      package: package(),
      description: "Mixes multiple video inputs to a single output using ffmpeg filters."
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:unifex, "~> 1.0"},
      {:telemetry, "~> 1.1"}
    ]
  end

  defp package do
    [
      maintainers: ["KIM Keep In Mind"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @link},
      files: [
        "lib",
        "c_src",
        "mix.exs",
        "README*",
        "LICENSE*",
        ".formatter.exs",
        "bundlex.exs"
      ]
    ]
  end
end

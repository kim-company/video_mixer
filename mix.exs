defmodule VideoMixer.MixProject do
  use Mix.Project

  @version "1.0.0"
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
      {:qex, "~> 0.5.1"},
      {:telemetry, "~> 1.1"},
      {:kim_q, "~> 1.0.0"}
    ]
  end

  defp package do
    [
      maintainers: ["KIM Keep In Mind"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @link}
    ]
  end
end

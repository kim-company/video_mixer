defmodule VideoMixer.BundlexProject do
  use Bundlex.Project

  def project do
    [
      natives: natives()
    ]
  end

  defp natives() do
    [
      mix: [
        sources: ["mix.c"],
        interface: :nif,
        preprocessor: Unifex,
        os_deps: [
          libavutil: :pkg_config,
          libavfilter: :pkg_config
        ]
      ]
    ]
  end
end

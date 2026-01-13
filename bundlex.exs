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
        linker_flags: linker_flags(),
        os_deps: [
          libavfilter: :pkg_config
        ]
      ]
    ]
  end

  defp linker_flags do
    case :os.type() do
      {:unix, :darwin} -> ["-Wl,-no_warn_duplicate_libraries"]
      _ -> []
    end
  end
end

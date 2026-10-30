# The formula for matthewsinclair/homebrew-hrdrcfg. Copy it to the tap's
# Formula/hrdrcfg.rb with tag and revision set to the release being published.
class Hrdrcfg < Formula
  desc "Open a project's Herdr space from the project's own config"
  homepage "https://github.com/matthewsinclair/hrdrcfg"
  url "https://github.com/matthewsinclair/hrdrcfg.git",
      tag:      "v@VERSION@",
      revision: "@REVISION@"
  license "MIT"

  depends_on "jq"
  depends_on "yq"
  on_linux do
    depends_on "zsh"
  end

  def install
    libexec.install "bin", "VERSION"
    bin.install_symlink libexec/"bin/hrdrcfg"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/hrdrcfg --version")
  end
end

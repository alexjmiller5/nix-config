# Check the generated Brewfile guard without touching App Store state.
require "tmpdir"
source = File.read(File.expand_path("../hosts/mac-mini.nix", __dir__))
guard = source[/homebrew.extraConfig = ''\n(.*?)\n  '';/m, 1]
abort "Missing Flighty receipt guard" unless guard
Dir.mktmpdir do |dir|
  receipt = "#{dir}/receipt"
  code = guard.gsub("/Applications/Flighty.app/Contents/_MASReceipt/receipt", receipt)
  ENV["HOMEBREW_BUNDLE_MAS_SKIP"] = "existing"
  eval(code)
  abort "Missing app was skipped" unless ENV["HOMEBREW_BUNDLE_MAS_SKIP"] == "existing"
  File.write(receipt, "synthetic")
  eval(code)
  abort "Installed app not skipped or previous skips lost" unless ENV["HOMEBREW_BUNDLE_MAS_SKIP"].split == ["existing", "1358823008"]
end
puts "Flighty receipt guard: passed"

# frozen_string_literal: true

require 'fileutils'

# Where `rake install` puts the command, and what it is called.
BINDIR = ENV['BINDIR'] || File.join(Dir.home, '.local', 'bin')
NAME   = ENV['NAME'] || 'pt'

# The launcher in bin/ resolves its own symlinks, so a link on PATH finds
# the checkout (and the sibling ruby-tui) no matter where it is called from.
LAUNCHER = File.expand_path('bin/pass-tui', __dir__)

desc 'Run the test suite'
task :test do
  ruby 'test/run.rb'
end

# Build an ahead-of-time binary with Spinel. Everything (this project and
# ruby-tui) is compiled in, so the result is standalone. The two load-path
# warnings are expected: Spinel has no runtime load path and uses -I at
# compile time instead.
desc 'Build a Spinel (AOT) binary into build/pass-tui'
task :spinel do
  FileUtils.mkdir_p('build')
  ruby_tui = ENV['RUBY_TUI_LIB'] || File.expand_path('../ruby-tui/lib', __dir__)
  sh "spinel bin/pass-tui -o build/pass-tui -I lib -I #{ruby_tui}"
end

# The default install is a link to the launcher: it needs Ruby and the
# sibling ruby-tui checkout, but it always runs the current sources, so it
# never needs rebuilding while you work on the app.
desc "Install `#{NAME}` on PATH as a link to bin/pass-tui"
task :install do
  FileUtils.mkdir_p(BINDIR)
  target = File.join(BINDIR, NAME)
  FileUtils.rm_f(target)
  File.symlink(LAUNCHER, target)
  puts "installed #{target} -> #{LAUNCHER}"
end

# Standalone alternative: compile with Spinel and drop the native binary on
# PATH. No Ruby or gems needed at run time, but it must be rebuilt after a
# change.
desc "Build the Spinel binary and install it as `#{NAME}` (standalone)"
task 'install:spinel' => :spinel do
  FileUtils.mkdir_p(BINDIR)
  target = File.join(BINDIR, NAME)
  FileUtils.rm_f(target)
  FileUtils.cp('build/pass-tui', target)
  FileUtils.chmod(0o755, target)
  puts "installed #{target} (native, standalone)"
end

desc "Remove `#{NAME}` from PATH"
task :uninstall do
  target = File.join(BINDIR, NAME)
  if File.exist?(target) || File.symlink?(target)
    FileUtils.rm_f(target)
    puts "removed #{target}"
  else
    puts "#{target} is not installed"
  end
end

task default: :test

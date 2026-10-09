# frozen_string_literal: true
#
# Minimal test harness -- stdlib only, so `ruby test/run.rb` works anywhere
# Ruby does. Same shape as the ruby-tui suite it borrows from.

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
$LOAD_PATH.unshift(ENV['RUBY_TUI_LIB'] || File.expand_path('../../ruby-tui/lib', __dir__))

require 'tui'
require 'pass_tui'
require 'stringio'
require 'tmpdir'
require 'fileutils'

module Harness
  class Failure < StandardError; end

  @passed = 0
  @failures = []
  @cases = 0

  class << self
    attr_reader :passed, :failures

    def test(name)
      @cases ||= 0
      @cases += 1
      yield
      @passed += 1
      puts "  \e[32m✓\e[0m #{name}"
    rescue Failure => e
      @failures << [name, e]
      puts "  \e[31m✗\e[0m #{name}\n      #{e.message}"
    rescue StandardError => e
      @failures << [name, e]
      puts "  \e[31m✗\e[0m #{name}\n      #{e.class}: #{e.message}"
      puts e.backtrace.first(5).map { |line| "        #{line}" }.join("\n")
    end

    def report!
      puts
      if @failures.empty?
        puts "\e[32m#{@passed}/#{@cases} tests passed\e[0m"
      else
        puts "\e[31m#{@failures.length} of #{@cases} tests failed\e[0m"
      end
    end

    def failed?
      !(@failures || []).empty?
    end
  end
end

def test(name, &block)
  Harness.test(name, &block)
end

def assert(condition, message = 'expected condition to be true')
  raise Harness::Failure, message unless condition
end

def assert_equal(expected, actual, message = nil)
  return if expected == actual

  raise Harness::Failure, message || "expected #{expected.inspect}, got #{actual.inspect}"
end

def assert_includes(haystack, needle, message = nil)
  return if haystack.include?(needle)

  raise Harness::Failure, message || "expected #{haystack.inspect} to include #{needle.inspect}"
end

def refute(condition, message = 'expected condition to be false')
  raise Harness::Failure, message if condition
end

# ---------------------------------------------------------------- helpers

TMP_DIRS = []

def tmp_dir(prefix = 'pass-tui')
  dir = Dir.mktmpdir(prefix)
  TMP_DIRS << dir
  dir
end

at_exit do
  TMP_DIRS.each do |dir|
    FileUtils.remove_entry(dir)
  rescue StandardError
    nil
  end
end

# Create a throwaway password-store directory with `*.gpg` files. Only the
# names matter for the tree; the content is what a fake `pass show` echoes.
def make_store_dir(entries = {})
  dir = tmp_dir('pass-tui-store')
  entries.each_key do |name|
    path = File.join(dir, "#{name}.gpg")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, entries[name].to_s)
  end
  dir
end

# A stand-in for the `pass` binary. Understands show / rm / edit / insert so
# the Store and the UI can be exercised without gpg.
def write_fake_pass(dir, entries)
  bin = File.join(dir, 'pass')
  script = +"#!/usr/bin/env ruby\n"
  script << "require 'fileutils'\n"
  script << "ENTRIES = #{entries.inspect}.freeze\n"
  script << <<~'RUBY'
    case ARGV[0]
    when 'show'
      name = ARGV[1]
      file = File.join(ENV.fetch('PASSWORD_STORE_DIR'), "#{name}.gpg")
      if File.exist?(file)
        print File.read(file)
      elsif ENTRIES.key?(name)
        print ENTRIES[name]
      else
        warn "pass: #{name}: not in the password store."
        exit 1
      end
    when 'rm'
      name = ARGV[-1]
      file = File.join(ENV.fetch('PASSWORD_STORE_DIR'), "#{name}.gpg")
      File.delete(file) if File.exist?(file)
    when 'insert'
      name = ARGV[-1]
      content = $stdin.read
      file = File.join(ENV.fetch('PASSWORD_STORE_DIR'), "#{name}.gpg")
      FileUtils.mkdir_p(File.dirname(file))
      File.write(file, content)
      log = ENV['FAKE_PASS_LOG']
      File.write(log, "#{name}\n#{content}", mode: 'a') if log
    when 'edit'
      # no-op
    when 'git'
      log = ENV['FAKE_PASS_LOG']
      File.write(log, "git #{ARGV[1..].join(' ')}\n", mode: 'a') if log
      exit 1 if ENV['FAKE_PASS_GIT_FAIL']
    else
      warn "pass: unknown command #{ARGV[0]}"
      exit 1
    end
  RUBY
  File.write(bin, script)
  File.chmod(0o755, bin)
  bin
end

class FakeClipboard
  attr_reader :text, :copies, :clears

  def initialize
    @text = nil
    @copies = []
    @clears = 0
  end

  def copy(text)
    @text = text
    @copies << text
    true
  end

  def clear
    @text = nil
    @clears += 1
    true
  end

  def available?
    true
  end
end

# Build a UI wired to a temporary store and clipboard.
def make_ui(entries, config: nil, clipboard: nil)
  dir = make_store_dir(entries)
  bin = write_fake_pass(tmp_dir('pass-tui-bin'), entries)
  config ||= PassTui::Config.new(path: File.join(tmp_dir('pass-tui-cfg'), 'config.yml'),
                                 store_dir: dir, editor: 'true')
  config.store_dir = dir
  store = PassTui::Store.new(dir, pass_bin: bin, editor: config.editor)
  PassTui::UI.new(config: config, store: store, clipboard: clipboard || FakeClipboard.new)
end

def attach_ui(ui, cols = 100, rows = 30)
  app = TUI::App.new(ui.root, out: StringIO.new, size: [cols, rows])
  ui.attach(app)
  app
end

def ui_lines(app)
  app.render_frame.lines.map { |line| plain(line) }
end

def ui_text(app)
  ui_lines(app).join("\n")
end

def ui_select(ui, name)
  ui.search.value = name
  ui.select_path(name)
  ui.flush_pending(force: true)
end

# Strip SGR escapes so tests can assert on the visible text.
def plain(str)
  str.gsub(/\e\[[0-9;?]*[a-zA-Z]/, '')
end

at_exit do
  Harness.report!
  exit(1) if Harness.failed?
end

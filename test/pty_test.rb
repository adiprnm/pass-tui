# frozen_string_literal: true
require_relative 'test_helper'
require 'pty'
require 'timeout'

puts 'pass-tui end to end in a pty'

# Runs the real entry point in a pseudo-terminal against a fake store and a
# fake clipboard, drives a few keys and asserts the terminal is restored.
test 'bin/pass-tui renders, takes keys and restores the terminal' do
  entries = {
    'web/example.com' => "s3cret\nuser: alice\n",
    'db'              => "rootpw\nuser: root\n"
  }
  store_dir = make_store_dir(entries)
  bin_dir = tmp_dir('pass-tui-path')
  write_fake_pass(bin_dir, entries)

  clip = File.join(bin_dir, 'wl-copy')
  File.write(clip, "#!/bin/sh\nif [ \"$1\" = \"--clear\" ]; then exit 0; fi\ncat > /dev/null\n")
  File.chmod(0o755, clip)

  config_path = File.join(tmp_dir('pass-tui-cfg'), 'config.json')
  File.write(config_path, JSON.pretty_generate(
                            'store_dir' => store_dir, 'editor' => 'true',
                            'clip_time' => 5, 'theme' => 'dark'
                          ))

  old_path = ENV['PATH']
  ENV['PATH'] = "#{bin_dir}#{File::PATH_SEPARATOR}#{old_path}"
  out = +''
  status = nil
  root = File.expand_path('..', __dir__)

  PTY.spawn('ruby', File.join(root, 'bin', 'pass-tui'), "--config=#{config_path}") do |reader, writer, pid|
    drain = Thread.new do
      loop { out << reader.readpartial(65_536) }
    rescue EOFError, Errno::EIO
    end

    sleep 1.0
    ['/', 'd', 'b', "\r", 'r', 'c', 'q'].each do |key|
      writer.print(key)
      writer.flush
      sleep 0.3
    end

    begin
      Timeout.timeout(10) { _, status = Process.wait2(pid) }
    rescue Timeout::Error
      Process.kill('KILL', pid)
      status = nil
    end
    drain.join(1)
  end

  text = plain(out)
  assert status && status.success?, "pass-tui must exit cleanly (got #{status.inspect})"
  assert_includes out, TUI::Term::ALT_ON
  assert_includes out, TUI::Term::ALT_OFF
  assert_includes out, TUI::Term::HIDE_CURSOR
  assert_includes out, TUI::Term::SHOW_CURSOR
  assert_includes text, 'Entries', 'the tree pane rendered'
  assert_includes text, 'rootpw', 'the search, reveal and detail path ran'
ensure
  ENV['PATH'] = old_path
end

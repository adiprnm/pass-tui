# frozen_string_literal: true
require_relative 'test_helper'

puts 'Clipboard'

# A fake wl-copy that logs its argv and stdin, so the copy/clear paths can be
# asserted without a real Wayland session.
def with_fake_clipboard
  dir = tmp_dir('pass-tui-clip')
  log = File.join(dir, 'log.txt')
  bin = File.join(dir, 'wl-copy')
  File.write(bin, <<~'SCRIPT')
    #!/usr/bin/env ruby
    File.open(ENV['FAKE_CLIP_LOG'], 'a') do |file|
      file.puts(ARGV.join(' '))
      file.puts($stdin.tty? ? '' : $stdin.read)
      file.puts('---')
    end
  SCRIPT
  File.chmod(0o755, bin)

  old_path = ENV['PATH']
  ENV['PATH'] = "#{dir}#{File::PATH_SEPARATOR}#{old_path}"
  ENV['FAKE_CLIP_LOG'] = log
  begin
    yield dir, log
  ensure
    ENV['PATH'] = old_path
    ENV['FAKE_CLIP_LOG'] = nil
  end
end

test 'a backend is detected from PATH' do
  with_fake_clipboard do |dir, _log|
    clip = PassTui::Clipboard.new(path_env: dir)
    assert clip.available?
    assert_equal 'wl-copy', clip.backend_name
  end
end

test 'copy pipes the secret to the tool' do
  with_fake_clipboard do |dir, log|
    PassTui::Clipboard.new(path_env: dir).copy("s3cret\nwith 'quote'")
    text = File.read(log)
    assert_includes text, 's3cret'
    assert_includes text, "with 'quote'"
  end
end

test 'clear asks wl-copy to clear' do
  with_fake_clipboard do |dir, log|
    PassTui::Clipboard.new(path_env: dir).clear
    assert_includes File.read(log), '--clear'
  end
end

test 'no backend means unavailable and copy raises' do
  clip = PassTui::Clipboard.new(path_env: tmp_dir('pass-tui-empty'))
  refute clip.available?

  begin
    clip.copy('x')
    assert false, 'expected PassTui::Clipboard::Error'
  rescue PassTui::Clipboard::Error
    assert true
  end
end

# frozen_string_literal: true
require_relative 'test_helper'

puts 'Store'

test 'entries scans .gpg files and skips hidden paths' do
  dir = make_store_dir('web/a' => 1, 'db' => 1)
  FileUtils.mkdir_p(File.join(dir, '.git'))
  File.write(File.join(dir, '.git', 'object.gpg'), '')
  store = PassTui::Store.new(dir)
  assert_equal %w[db web/a], store.entries
end

test 'show returns the decrypted content through pass' do
  entries = { 'web/a' => "secret\nuser: alice\n" }
  dir = make_store_dir(entries)
  bin = write_fake_pass(tmp_dir('pass-tui-bin'), entries)
  store = PassTui::Store.new(dir, pass_bin: bin)
  assert_equal "secret\nuser: alice\n", store.show('web/a')
end

test 'show raises on an unknown entry' do
  dir = make_store_dir({})
  bin = write_fake_pass(tmp_dir('pass-tui-bin'), {})
  store = PassTui::Store.new(dir, pass_bin: bin)

  begin
    store.show('nope')
    assert false, 'expected PassTui::Store::Error'
  rescue PassTui::Store::Error => error
    assert_includes error.message, 'not in the password store'
  end
end

test 'remove deletes the file through pass' do
  entries = { 'db' => "pw\n" }
  dir = make_store_dir(entries)
  bin = write_fake_pass(tmp_dir('pass-tui-bin'), entries)
  store = PassTui::Store.new(dir, pass_bin: bin)
  store.remove('db')
  refute File.exist?(File.join(dir, 'db.gpg'))
end

test 'the store environment carries the dir, editor and visual' do
  store = PassTui::Store.new('/tmp/store', editor: 'nvim')
  env = store.env
  assert_equal '/tmp/store', env['PASSWORD_STORE_DIR']
  assert_equal 'nvim', env['EDITOR']
  assert_equal 'nvim', env['VISUAL']
  assert_equal '0', env['GIT_TERMINAL_PROMPT']
end

test 'sync pulls and pushes through pass git' do
  dir = make_store_dir('db' => "pw\n")
  FileUtils.mkdir_p(File.join(dir, '.git'))
  bin = write_fake_pass(tmp_dir('pass-tui-bin'), {})
  log = File.join(tmp_dir('pass-tui-log'), 'git.log')
  ENV['FAKE_PASS_LOG'] = log
  store = PassTui::Store.new(dir, pass_bin: bin)

  assert store.git?
  store.sync

  assert_includes File.read(log), "git pull --rebase\n"
  assert_includes File.read(log), "git push\n"
ensure
  ENV.delete('FAKE_PASS_LOG')
end

test 'sync raises when pass git fails' do
  dir = make_store_dir('db' => "pw\n")
  FileUtils.mkdir_p(File.join(dir, '.git'))
  bin = write_fake_pass(tmp_dir('pass-tui-bin'), {})
  ENV['FAKE_PASS_GIT_FAIL'] = '1'
  store = PassTui::Store.new(dir, pass_bin: bin)

  begin
    store.sync
    assert false, 'expected PassTui::Store::Error'
  rescue PassTui::Store::Error
    assert true
  ensure
    ENV.delete('FAKE_PASS_GIT_FAIL')
  end
end

test 'sync refuses a store that is not a git repository' do
  dir = make_store_dir('db' => "pw\n")
  bin = write_fake_pass(tmp_dir('pass-tui-bin'), {})
  store = PassTui::Store.new(dir, pass_bin: bin)

  refute store.git?
  begin
    store.sync
    assert false, 'expected PassTui::Store::Error'
  rescue PassTui::Store::Error => error
    assert_includes error.message, 'not a git repository'
  end
end

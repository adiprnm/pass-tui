# frozen_string_literal: true
require_relative 'test_helper'

puts 'Config'

test 'store_dir expands ~ and falls back to the default' do
  config = PassTui::Config.new(path: File.join(tmp_dir, 'config.json'))
  config.store_dir = '~/store'
  assert_equal File.expand_path('~/store'), config.store_dir
  config.store_dir = ''
  assert_equal PassTui::Config.default_store_dir, config.store_dir
end

test 'clip_time refuses non-positive values' do
  config = PassTui::Config.new(path: File.join(tmp_dir, 'config.json'))
  config.clip_time = '30'
  assert_equal 30, config.clip_time
  config.clip_time = '0'
  assert_equal PassTui::Config.default_clip_time, config.clip_time
  config.clip_time = '-4'
  assert_equal PassTui::Config.default_clip_time, config.clip_time
end

test 'editor falls back when blank and theme normalises' do
  config = PassTui::Config.new(path: File.join(tmp_dir, 'config.json'))
  config.editor = '  '
  assert_equal PassTui::Config.default_editor, config.editor
  config.editor = 'nvim'
  assert_equal 'nvim', config.editor
  config.theme = 'PLAIN'
  assert_equal 'plain', config.theme
end

test 'save writes JSON and load reads it back' do
  path = File.join(tmp_dir('pass-tui-cfg'), 'config.json')
  saved = PassTui::Config.new(path: path, store_dir: '/tmp/a', clip_time: 7,
                              editor: 'micro', theme: 'plain')
  saved.save
  assert File.file?(path), 'the config file is written'
  assert_includes File.read(path), 'store_dir'

  loaded = PassTui::Config.load(path)
  assert_equal File.expand_path('/tmp/a'), loaded.store_dir
  assert_equal 7, loaded.clip_time
  assert_equal 'micro', loaded.editor
  assert_equal 'plain', loaded.theme
end

test 'a broken config file falls back to the defaults' do
  path = File.join(tmp_dir, 'config.json')
  File.write(path, '{ this is not json')
  config = PassTui::Config.load(path)
  assert config.clip_time.positive?, 'defaults survive a broken file'
end

test 'a missing config file keeps the env-seeded defaults' do
  config = PassTui::Config.load(File.join(tmp_dir, 'nope.json'))
  assert_equal PassTui::Config.default_store_dir, config.store_dir
end

puts 'Shell'

test 'escape single-quotes a value for /bin/sh' do
  assert_equal "'plain'", PassTui::Shell.escape('plain')
  assert_equal "'it'\\''s'", PassTui::Shell.escape("it's")
end

test 'command quotes the binary and every argument' do
  assert_equal "'pass' 'show' 'a b'", PassTui::Shell.command('pass', ['show', 'a b'])
end

test 'ok? understands both $? shapes' do
  assert PassTui::Shell.ok?(0)
  refute PassTui::Shell.ok?(256)
  refute PassTui::Shell.ok?(nil)
end

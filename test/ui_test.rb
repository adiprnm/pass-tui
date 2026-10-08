# frozen_string_literal: true
require_relative 'test_helper'

puts 'UI'

UI_ENTRIES = {
  'web/example.com' => "s3cret\nuser: alice\nurl: https://example.com\n",
  'web/other.org'   => "hunter2\nuser: bob\n",
  'db'              => "rootpw\nuser: root\n",
  'notes'           => "just a password\n"
}.freeze

test 'the tree and the detail pane render' do
  ui = make_ui(UI_ENTRIES)
  app = attach_ui(ui)
  text = ui_text(app)

  assert_includes text, 'Entri'
  assert_includes text, 'web'
  assert_includes text, 'db'
  assert_includes text, 'Detail'
  assert_includes text, '4 entri'
end

test 'selecting an entry loads it and masks the password' do
  ui = make_ui(UI_ENTRIES)
  app = attach_ui(ui)
  ui_select(ui, 'web/example.com')
  text = ui_text(app)

  assert_includes text, 'Password'
  assert_includes text, 'Username'
  assert_includes text, 'URL'
  assert_includes text, 'alice'
  assert_includes text, 'https://example.com'
  assert_includes text, '••••••'
  refute text.include?('s3cret'), 'the password stays masked'
end

test 'every field is wrapped in its own fieldset' do
  ui = make_ui(UI_ENTRIES)
  app = attach_ui(ui)
  ui_select(ui, 'web/example.com')
  lines = ui_lines(app)

  password_top = lines.find { |line| line.include?('Password') && line.include?('╭') }
  user_top = lines.find { |line| line.include?('User') && line.include?('╭') }
  assert password_top, 'the password field has a bordered legend'
  assert user_top, 'the user field has a bordered legend'
  assert_includes password_top, 'r reveal'
  assert_includes user_top, 'u copy'
end

test 'reveal toggles the password on and off' do
  ui = make_ui(UI_ENTRIES)
  app = attach_ui(ui)
  ui_select(ui, 'web/example.com')

  ui.toggle_reveal
  assert_includes ui_text(app), 's3cret'

  ui.toggle_reveal
  refute ui_text(app).include?('s3cret')
end

test 'copy password and copy user reach the clipboard' do
  clip = FakeClipboard.new
  ui = make_ui(UI_ENTRIES, clipboard: clip)
  attach_ui(ui)
  ui_select(ui, 'web/example.com')

  ui.copy_password
  assert_equal 's3cret', clip.text

  ui.copy_user
  assert_equal 'alice', clip.text
end

test 'a folder expands and collapses' do
  ui = make_ui(UI_ENTRIES)
  attach_ui(ui)

  node = ui.tree_view.rows.first.node
  assert node.folder?, 'the first row is the web folder'
  refute ui.tree_view.rows.any? { |row| row.node.path == 'web/example.com' },
         'the folder starts collapsed'

  ui.toggle_folder(node)
  assert ui.tree_view.rows.any? { |row| row.node.path == 'web/example.com' }

  ui.toggle_folder(node)
  refute ui.tree_view.rows.any? { |row| row.node.path == 'web/example.com' }
end

test 'search filters the tree to matching entries' do
  ui = make_ui(UI_ENTRIES)
  app = attach_ui(ui)
  ui.search.value = 'other'
  text = ui_text(app)

  assert_includes text, 'web/other.org'
  refute text.include?('web/example.com')
end

test 'delete removes the entry after confirmation' do
  ui = make_ui(UI_ENTRIES)
  attach_ui(ui)
  ui_select(ui, 'web/other.org')

  ui.confirm_delete
  assert ui.modal?, 'the confirmation dialog is up'
  assert ui.instance_variable_get(:@confirm_yes).focused?, 'Hapus is focused by default'

  ui.perform_delete
  refute ui.tree_view.rows.any? { |row| row.node.path == 'web/other.org' }
  assert ui.status.include?('Dihapus')
end

test 'creating an entry stores the username and password' do
  ui = make_ui(UI_ENTRIES)
  attach_ui(ui)

  ui.create_entry(name: 'web/new', username: 'carol', password: 'p@ss word')
  file = File.join(ui.store.dir, 'web/new.gpg')
  assert File.file?(file), 'the entry file is written'
  assert_equal "username:carol\npassword:p@ss word\n", File.read(file)
  assert ui.status.include?('dibuat')
end

test 'a new entry with an empty username still writes both lines' do
  ui = make_ui(UI_ENTRIES)
  attach_ui(ui)

  ui.create_entry(name: 'plain', username: '', password: 'only')
  assert_equal "username:\npassword:only\n", File.read(File.join(ui.store.dir, 'plain.gpg'))
end

test 'a created entry is selected and shown in the detail card' do
  ui = make_ui(UI_ENTRIES)
  app = attach_ui(ui)

  ui.create_entry(name: 'web/new', username: 'carol', password: 'p@ss')
  text = ui_text(app)
  assert_includes text, 'web/new'
  assert_includes text, 'Username'
  assert_includes text, 'carol'
  assert_includes text, '••••'
  refute text.include?('p@ss'), 'the new password stays masked'
end

test 'new entry names are validated' do
  ui = make_ui(UI_ENTRIES)
  assert_equal true, ui.send(:validate_new_name, 'brand/new')
  assert_equal 'sudah ada', ui.send(:validate_new_name, 'db')
  assert_equal 'wajib diisi', ui.send(:validate_new_name, '   ')
  assert_equal 'tidak boleh ada ..', ui.send(:validate_new_name, '../x')
end

test 'settings save to the config file and switch the store' do
  config = PassTui::Config.new(path: File.join(tmp_dir('pass-tui-cfg'), 'config.json'),
                               store_dir: make_store_dir('a' => "pw\n"), editor: 'true')
  new_dir = make_store_dir('b' => "pw\n")
  ui = make_ui(UI_ENTRIES, config: config)
  attach_ui(ui)

  ui.save_settings(store_dir: new_dir, clip_time: '9', editor: 'nano', theme: 'dark')

  assert File.file?(config.path), 'the config file is written'
  assert_equal File.expand_path(new_dir), config.store_dir
  assert_equal 9, config.clip_time
  assert_equal 'nano', config.editor
  assert_equal File.expand_path(new_dir), ui.store.dir
ensure
  PassTui::Theme.install(:vault)
end

test 'the help dialog opens and closes' do
  ui = make_ui(UI_ENTRIES)
  app = attach_ui(ui)

  ui.open_dialog(PassTui::UI::DIALOG_HELP)
  assert ui.modal?
  assert_includes ui_text(app), 'Bantuan'

  ui.close_modal
  refute ui.modal?
end

test 'the layout fits exactly at several sizes' do
  ui = make_ui(UI_ENTRIES)
  [[60, 16], [80, 24], [120, 34]].each do |cols, rows|
    app = TUI::App.new(ui.root, out: StringIO.new, size: [cols, rows])
    ui.attach(app)
    lines = ui_lines(app)
    assert_equal rows, lines.length, "#{cols}x#{rows} row count"
    lines.each { |line| assert_equal cols, line.length, "#{cols}x#{rows} width" }
  end
end

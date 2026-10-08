# frozen_string_literal: true
#
# UI -- the pass-tui application: a two-column layout with an expandable
# entry tree on the left and, on the right, a record card whose fields are
# drawn as fieldsets (a bordered box with a legend naming the field).
#
#   ui  = PassTui::UI.new
#   ui.run                     # interactive
#
# The UI never talks to the terminal directly; it builds a component tree
# and hands it to a TUI::App. That is also what makes it testable: the same
# tree can be rendered off-screen with TUI.render.

require 'tui'

require_relative 'tree_view'
require_relative 'fieldset'

module PassTui
  class UI
    HINTS = ' ↑↓ pilih · enter buka · / cari · ? bantuan · q keluar '
    DEBOUNCE = 0.35

    DIALOG_CONFIRM  = 0
    DIALOG_NEW      = 1
    DIALOG_SETTINGS = 2
    DIALOG_HELP     = 3

    HELP = [
      ['Navigasi', :subtitle],
      ['  ↑/↓  j/k      pindah entri', :text],
      ['  →/l  enter    buka / tutup folder', :text],
      ['  ←/h           tutup folder', :text],
      ['  /             cari entri', :text],
      ['  tab           pindah fokus', :text],
      ['', :text],
      ['Aksi', :subtitle],
      ['  enter         reveal password / buka folder', :text],
      ['  r             reveal password', :text],
      ['  c             salin password (auto-clear)', :text],
      ['  u             salin user', :text],
      ['  n             entri baru (form username + password)', :text],
      ['  e             edit entri (pakai $EDITOR)', :text],
      ['  d             hapus entri', :text],
      ['  s             settings', :text],
      ['  ctrl-d/u      scroll detail', :text],
      ['  q / ctrl-c    keluar', :text]
    ].freeze

    attr_reader :root, :tree_view, :search, :config, :store, :clipboard, :status

    def initialize(config: Config.load, store: nil, clipboard: nil)
      @config = config
      @store = store || Store.new(config.store_dir, editor: config.editor)
      @clipboard = clipboard || Clipboard.new
      @entries = []
      @tree = Tree.new
      @collapsed = Set.new
      @entry_cache = {}
      @revealed = nil
      @pending = nil
      @pending_at = 0.0
      @clip_at = nil
      @clip_label = nil
      @pending_delete = nil
      @active_dialog = nil
      @status = 'Siap.'
      @attached = false

      build
      reload
      message('Siap.')
      self
    end

    # ---------------------------------------------------------------- setup

    def build
      @root = TUI::Layout::Box.new(title: 'pass-tui', title_style: :brand,
                                   title_right_style: :brand_path, footer: HINTS)

      @left_box = TUI::Layout::Box.new(title: 'Entri')
      left = TUI::Layout::Stack.new(direction: :vertical)
      @search = TUI::Input.new(placeholder: 'cari entri…', padding: 1,
                               hint_cursor_style: :placeholder)
      @search.on(TUI::Events::CHANGE) { refresh_rows }
      @search.on(TUI::Events::SUBMIT) { @ui&.focus(@tree_view) }

      @tree_view = PassTui::Widgets::TreeView.new
      @tree_view.on(TUI::Events::CHANGE) { |node, _i| on_tree_change(node) }
      @tree_view.on(TUI::Events::SELECT) { |node, _i| on_tree_select(node) }
      @tree_view.on(:expand) { |node| expand_folder(node) }
      @tree_view.on(:collapse) { |node| collapse_folder(node) }

      left.add(@search, size: TUI.auto)
      left.add(@tree_view, size: TUI.flex(1))
      @left_box.add(left)

      @detail_box = TUI::Layout::Box.new(title: 'Detail')
      @detail_header = TUI::Layout::Stack.new(direction: :horizontal)
      @field_stack = TUI::Layout::Stack.new(direction: :vertical, gap: 0)
      @detail_viewport = TUI::Layout::Viewport.new(@field_stack)

      right = TUI::Layout::Stack.new(direction: :vertical)
      right.add(@detail_header, size: TUI.fixed(1))
      right.add(TUI::Layout::Divider.new(orientation: :horizontal, style: :rule), size: TUI.fixed(1))
      right.add(@detail_viewport, size: TUI.flex(1))
      @detail_box.add(right)

      columns = TUI::Layout::Stack.new(direction: :horizontal)
      columns.add(@left_box, size: TUI.fixed(40))
      columns.add(@detail_box, size: TUI.flex(1))

      @dialogs = TUI::Panes.new
      @dialogs.add(build_confirm_dialog)  # 0
      @dialogs.add(build_new_dialog)      # 1
      @dialogs.add(build_settings_dialog) # 2
      @dialogs.add(build_help_dialog)     # 3

      @overlay = TUI::Layout::Overlay.new(columns, @dialogs)
      @overlay.hide
      @root.add(@overlay)
      self
    end

    def build_confirm_dialog
      box = TUI::Layout::Box.new(title: 'Konfirmasi')
      stack = TUI::Layout::Stack.new(direction: :vertical, gap: 1)
      @confirm_label = TUI::Label.new('', style: :text, align: :center)

      row = TUI::Layout::Stack.new(direction: :horizontal, gap: 2)
      @confirm_yes = TUI::Button.new('Hapus')
      @confirm_no = TUI::Button.new('Batal')
      @confirm_yes.on(TUI::Events::PRESS) { perform_delete }
      @confirm_no.on(TUI::Events::PRESS) { close_modal }
      row.add(TUI::Layout::Center.new(@confirm_yes), size: TUI.flex(1))
      row.add(TUI::Layout::Center.new(@confirm_no), size: TUI.flex(1))

      hint = TUI::Label.new('y / enter hapus · n / esc batal', style: :hint, align: :center)
      stack.add(TUI::Layout::Spacer.new, size: TUI.fixed(1))
      stack.add(@confirm_label, size: TUI.fixed(1))
      stack.add(row, size: TUI.fixed(1))
      stack.add(hint, size: TUI.fixed(1))
      box.add(stack)
      box
    end

    def build_new_dialog
      box = TUI::Layout::Box.new(title: 'Entri Baru')
      stack = TUI::Layout::Stack.new(direction: :vertical, gap: 1)

      @new_form = TUI::Form.new(label_width: 10)
      @new_name = @new_form.text(:name, 'Nama', required: true, width: 36,
                                 placeholder: 'web/contoh.com',
                                 validate: method(:validate_new_name))
      @new_form.text(:username, 'Username', width: 36, placeholder: 'nama pengguna')
      @new_form.password(:password, 'Password', width: 36, required: true)
      @new_form.button('Simpan')
      @new_form.on(TUI::Events::SUBMIT) { |values| create_entry(values) }

      hint = TUI::Label.new('disimpan langsung lewat pass (gpg)', style: :hint, align: :center)
      stack.add(@new_form, size: TUI.auto)
      stack.add(hint, size: TUI.fixed(1))
      box.add(stack)
      box
    end

    def build_settings_dialog
      box = TUI::Layout::Box.new(title: 'Settings')
      stack = TUI::Layout::Stack.new(direction: :vertical, gap: 1)

      @settings_form = TUI::Form.new(label_width: 12)
      @settings_form.text(:store_dir, 'Store dir', width: 40, required: true)
      @settings_form.text(:clip_time, 'Clip detik', width: 8)
      @settings_form.text(:editor, 'Editor', width: 24)
      @theme_field = @settings_form.radio(:theme, 'Tema', options: PassTui::Theme::NAMES,
                                          orientation: :horizontal)
      @theme_radio = @theme_field.editor
      @settings_form.button('Simpan')
      @settings_form.on(TUI::Events::SUBMIT) { |values| save_settings(values) }

      hint = TUI::Label.new("config: #{Config.default_path}", style: :hint)
      stack.add(@settings_form, size: TUI.auto)
      stack.add(hint, size: TUI.fixed(1))
      box.add(stack)
      box
    end

    def build_help_dialog
      box = TUI::Layout::Box.new(title: 'Bantuan')
      stack = TUI::Layout::Stack.new(direction: :vertical)
      HELP.each { |entry| stack.add(TUI::Label.new(entry[0], style: entry[1]), size: TUI.fixed(1)) }
      stack.add(TUI::Label.new('', style: :text), size: TUI.fixed(1))
      stack.add(TUI::Label.new('esc untuk menutup', style: :hint, align: :center), size: TUI.fixed(1))
      box.add(stack)
      box
    end

    def attach(app)
      return self if @attached

      @attached = true
      @ui = app
      bind_keys
      app.every(0.1) { tick }
      app.focus(@tree_view)
      self
    end

    def run(out: $stdout)
      app = TUI::App.new(@root, out: out)
      attach(app)
      begin
        app.run
      ensure
        clear_clipboard
      end
    end

    # ---------------------------------------------------------------- input

    def bind_keys
      return unless @ui

      @ui.on_key('/') { focus_search }
      @ui.on_key('?') { open_dialog(DIALOG_HELP) }
      @ui.on_key(:escape) { on_escape }
      @ui.on_key('c') { copy_password }
      @ui.on_key('u') { copy_user }
      @ui.on_key('r') { toggle_reveal }
      @ui.on_key('n') do
        if @active_dialog == DIALOG_CONFIRM
          close_modal
        else
          new_entry
        end
      end
      @ui.on_key('y') { perform_delete if @active_dialog == DIALOG_CONFIRM }
      @ui.on_key('e') { edit_entry }
      @ui.on_key('d') { confirm_delete }
      @ui.on_key('s') { open_settings }
      @ui.on_key(:ctrl_d) { @detail_viewport.scroll_by(5) }
      @ui.on_key(:ctrl_u) { @detail_viewport.scroll_by(-5) }
      @ui.on_key('q') { @ui.quit }
      @ui.on_key(:ctrl_c) { @ui.quit }
      self
    end

    # ---------------------------------------------------------------- model

    def reload
      @entries = @store.entries
      @tree = Tree.new(@entries)
      @collapsed = Set.new(@tree.folder_paths)
      @entry_cache.clear
      @revealed = nil
      @left_box.title_right = "#{@entries.length} entri"
      refresh_rows
      self
    end

    def refresh_rows(select: nil)
      filter = @search.value
      @tree_view.filtering = !filter.to_s.strip.empty?
      rows = @tree.rows(collapsed: @collapsed, filter: filter)
      previous = select || @tree_view.selected_path
      @tree_view.set_rows(rows)
      @tree_view.select_path(previous) if previous
      schedule_detail
      self
    end

    def select_path(path)
      @tree_view.select_path(path)
      flush_pending(force: true) if current_path == path
      self
    end

    # --------------------------------------------------------------- detail

    def on_tree_change(_node)
      @revealed = nil
      schedule_detail
    end

    def on_tree_select(node)
      return if node.nil?

      if node.folder?
        toggle_folder(node)
      else
        toggle_reveal_for(node)
      end
    end

    def toggle_folder(node)
      if @collapsed.include?(node.path)
        @collapsed.delete(node.path)
      else
        @collapsed.add(node.path)
      end
      refresh_rows(select: node.path)
    end

    def expand_folder(node)
      return unless node && node.folder?

      @collapsed.delete(node.path)
      refresh_rows(select: node.path)
    end

    # Reveal an entry's ancestors so it is visible after a reload.
    def expand_to(name)
      parts = name.to_s.split('/')
      return if parts.length < 2

      parts.first(parts.length - 1).each_with_index do |_part, index|
        @collapsed.delete(parts[0..index].join('/'))
      end
    end

    def collapse_folder(node)
      return unless node && node.folder?

      @collapsed.add(node.path)
      refresh_rows(select: node.path)
    end

    def toggle_reveal
      return if modal?

      node = selected_leaf
      return message('Pilih entri dulu') unless node

      toggle_reveal_for(node)
    end

    def toggle_reveal_for(node)
      @revealed = @revealed == node.path ? nil : node.path
      flush_pending(force: true) unless @entry_cache.key?(node.path)
      update_detail
      self
    end

    def schedule_detail
      node = @tree_view.selected_node
      @pending = node && node.leaf? ? node.path : nil
      @pending_at = now
      @revealed = nil unless @revealed == @pending
      update_detail
      self
    end

    def flush_pending(force: false)
      return self if @pending.nil?
      return self if !force && (now - @pending_at) < DEBOUNCE

      path = @pending
      @pending = nil
      load_entry(path)
      update_detail if current_path == path
      self
    end

    def load_entry(path)
      return self if @entry_cache.key?(path)

      begin
        content = @store.show(path)
        @entry_cache[path] = Entry.parse(path, content)
      rescue Store::Error => error
        @entry_cache[path] = :error
        message("Gagal membuka #{path}: #{first_line(error.message)}")
      end
      self
    end

    # Rebuild the right-hand record card out of fieldsets.
    def update_detail
      @field_stack.clear_children
      @detail_viewport.scroll_to(0)

      node = @tree_view.selected_node
      if node.nil?
        @detail_box.title_right = nil
        set_header(nil, '')
        add_placeholder('Tidak ada entri', 'Tekan n untuk membuat entri baru')
        return self
      end

      crumb = breadcrumb(node.path)
      if node.folder?
        @detail_box.title_right = "#{@tree.count(node)} entri"
        set_header(crumb[0], "#{crumb[1]}/")
        add_folder_fields(node)
        return self
      end

      @detail_box.title_right = node.name
      set_header(crumb[0], crumb[1])
      entry = @entry_cache[node.path]
      if entry.nil?
        add_placeholder('Membuka…', 'entri sedang didekripsi')
      elsif entry == :error
        add_placeholder('Gagal membuka entri', 'lihat status di bawah')
      else
        add_entry_fields(entry, node)
      end
      self
    end

    # -------------------------------------------------------------- actions

    def focus_search
      return if modal?

      @ui&.focus(@search)
      self
    end

    def on_escape
      if modal?
        close_modal
      else
        @search.value = '' unless @search.value.empty?
        @ui&.focus(@tree_view)
      end
      self
    end

    def copy_password
      return if modal?

      node = selected_leaf
      return message('Pilih entri dulu') unless node

      entry = loaded_entry(node)
      return unless entry

      copy_to_clipboard(entry.password, "Password #{node.name}")
    end

    def copy_user
      return if modal?

      node = selected_leaf
      return message('Pilih entri dulu') unless node

      entry = loaded_entry(node)
      return unless entry

      user = entry.user
      return message("Tidak ada field user di #{node.name}") if user.nil? || user.empty?

      copy_to_clipboard(user, "User #{node.name}")
    end

    def new_entry
      return if modal?

      reset_new_form
      open_dialog(DIALOG_NEW)
      @ui&.focus(@new_name.editor)
      self
    end

    def create_entry(values)
      name = values[:name].to_s.strip
      return if name.empty?

      username = values[:username].to_s.strip
      password = values[:password].to_s
      content = "username:#{username}\npassword:#{password}\n"

      close_modal
      begin
        @store.insert(name, content)
      rescue Store::Error => error
        return message("Gagal membuat #{name}: #{first_line(error.message)}")
      end
      reload
      expand_to(name)
      refresh_rows(select: name)
      flush_pending(force: true)
      message("#{name} dibuat")
    end

    def edit_entry
      return if modal?

      node = selected_leaf
      return message('Pilih entri dulu') unless node

      begin
        with_suspended { @store.edit(node.path) }
      rescue Store::Error => error
        return message("Gagal edit #{node.path}: #{first_line(error.message)}")
      end
      @entry_cache.delete(node.path)
      @entries = @store.entries
      @tree = Tree.new(@entries)
      refresh_rows(select: node.path)
      flush_pending(force: true)
      message("#{node.path} disimpan")
    end

    def confirm_delete
      return if modal?

      node = selected_leaf
      return message('Pilih entri dulu') unless node

      @pending_delete = node.path
      @confirm_label.text = "Hapus #{node.path}?"
      open_dialog(DIALOG_CONFIRM)
      @confirm_yes.focus!
      self
    end

    def perform_delete
      name = @pending_delete
      return unless name

      close_modal
      begin
        @store.remove(name)
      rescue Store::Error => error
        return message("Gagal hapus #{name}: #{first_line(error.message)}")
      end
      @entry_cache.delete(name)
      reload
      message("Dihapus: #{name}")
    end

    def open_settings
      return if modal?

      set_field(@settings_form, :store_dir, @config.store_dir)
      set_field(@settings_form, :clip_time, @config.clip_time.to_s)
      set_field(@settings_form, :editor, @config.editor)
      @settings_form.fields.each { |field| field.error = nil }
      @theme_radio.select(PassTui::Theme::NAMES.index(@config.theme) || 0, notify: false)
      open_dialog(DIALOG_SETTINGS)
      self
    end

    def save_settings(values)
      @config.store_dir = values[:store_dir]
      @config.clip_time = values[:clip_time]
      @config.editor = values[:editor]
      @config.theme = values[:theme] if values[:theme]
      begin
        @config.save
      rescue StandardError => error
        return message("Gagal menyimpan config: #{error.message}")
      end
      PassTui::Theme.install(@config.theme.to_sym)
      @store = Store.new(@config.store_dir, editor: @config.editor)
      close_modal
      reload
      message('Settings disimpan')
    end

    # ---------------------------------------------------------------- modal

    def modal?
      @overlay.shown?
    end

    def open_dialog(index)
      @active_dialog = index
      @dialogs.set_active(index)
      @overlay.show
      @ui&.focus_first
      self
    end

    def close_modal
      @active_dialog = nil
      @overlay.hide
      @ui&.focus(@tree_view)
      self
    end

    # ----------------------------------------------------------------- misc

    def tick
      flush_pending
      expire_clipboard
      self
    end

    def message(text)
      @status = text
      @detail_box.footer = text
      self
    end

    def clear_clipboard
      return self if @clip_at.nil?

      begin
        @clipboard.clear
      rescue StandardError
        # best effort
      end
      @clip_at = nil
      update_clip_indicator
      self
    end

    private

    # --- building the record card

    def set_header(prefix, name)
      @detail_header.clear_children
      if prefix.to_s.empty?
        @detail_header.add(TUI::Label.new(" #{name}", style: :title), size: TUI.flex(1))
      else
        @detail_header.add(TUI::Label.new(" #{prefix} › ", style: :muted), size: TUI.auto)
        @detail_header.add(TUI::Label.new(name.to_s, style: :title), size: TUI.flex(1))
      end
    end

    def add_field(title, lines, hint: nil, border: :field_border, legend: :legend,
                  value_style: :value, hint_style: :hint)
      field = PassTui::Widgets::Fieldset.build(title: title, lines: lines, hint: hint,
                                               border: border, legend: legend,
                                               value_style: value_style, hint_style: hint_style)
      @field_stack.add(field, size: TUI.auto)
    end

    def add_placeholder(title, hint)
      @field_stack.add(TUI::Label.new('', style: :text), size: TUI.fixed(1))
      @field_stack.add(TUI::Label.new(title, style: :title, align: :center), size: TUI.fixed(1))
      @field_stack.add(TUI::Label.new(hint, style: :hint, align: :center), size: TUI.fixed(1))
    end

    def add_folder_fields(node)
      add_field('Ringkasan', ["#{@tree.count(node)} entri di dalamnya"])
      children = node.children
      names = children.first(8).map { |child| child.folder? ? "#{child.name}/" : child.name }
      add_field('Isi', names, value_style: :muted) unless names.empty?
      return unless children.length > 8

      add_field('Lainnya', ["+#{children.length - 8} entri lagi"], value_style: :hint)
    end

    def add_entry_fields(entry, node)
      if entry.password.empty?
        add_field('Password', ['(kosong)'], hint: 'r reveal',
                  legend: :legend_secret, value_style: :sealed)
      elsif @revealed == node.path
        add_field('Password', [entry.password], hint: 'r hide',
                  border: :danger, legend: :danger, value_style: :danger, hint_style: :danger)
      else
        add_field('Password', [mask(entry.password)], hint: 'r reveal',
                  legend: :legend_secret, value_style: :sealed)
      end

      entry.fields.each do |key, value|
        add_field(field_label(key), [value], hint: field_hint(key), legend: field_legend(key))
      end

      add_field('Catatan', entry.notes, legend: :legend_note, value_style: :muted) unless entry.notes.empty?
    end

    def mask(secret)
      '•' * secret.length
    end

    def field_label(key)
      down = key.to_s.downcase
      return 'Username' if down == 'username' || down == 'user' || down == 'login'
      return 'Email' if down == 'email'
      return 'URL' if Entry::URL_KEYS.include?(down)

      key.to_s.split(/[_-]/).map { |part| part.capitalize }.join(' ')
    end

    def field_legend(key)
      down = key.to_s.downcase
      return :legend_user if Entry::USER_KEYS.include?(down)
      return :legend_url if Entry::URL_KEYS.include?(down)

      :legend_meta
    end

    def field_hint(key)
      return 'u copy' if Entry::USER_KEYS.include?(key.to_s.downcase)

      nil
    end

    def breadcrumb(path)
      parts = path.to_s.split('/')
      name = parts.pop
      [parts.join(' › '), name]
    end

    def update_clip_indicator
      @root.title_right = @clip_at ? 'clipboard terisi' : nil
      self
    end

    # --- selection helpers

    def current_path
      @tree_view.selected_path
    end

    def selected_leaf
      node = @tree_view.selected_node
      node && node.leaf? ? node : nil
    end

    def loaded_entry(node)
      flush_pending(force: true)
      entry = @entry_cache[node.path]
      if entry.is_a?(Entry)
        entry
      else
        message("Entri #{node.path} belum bisa dibuka") unless entry == :error
        nil
      end
    end

    def copy_to_clipboard(text, label)
      begin
        @clipboard.copy(text)
      rescue Clipboard::Error, StandardError => error
        return message("Clipboard gagal: #{first_line(error.message)}")
      end
      @clip_at = now
      @clip_label = label
      update_clip_indicator
      message("#{label} disalin · dikosongkan dalam #{@config.clip_time}s")
    end

    def expire_clipboard
      return if @clip_at.nil?
      return if (now - @clip_at) < @config.clip_time

      clear_clipboard
      message('Clipboard dikosongkan')
    end

    def with_suspended
      Editing.suspend
      yield
    ensure
      Editing.resume
    end

    def reset_new_form
      @new_form.fields.each { |field| field.error = nil }
      @new_form.fields.each do |field|
        field.editor.value = '' if field.editor.respond_to?(:value=)
      end
    end

    def set_field(form, name, value)
      field = form.fields.find { |candidate| candidate.name == name }
      field.editor.value = value.to_s if field
    end

    def validate_new_name(value)
      name = value.to_s.strip
      return 'wajib diisi' if name.empty?
      return 'awalan / tidak valid' if name.start_with?('/')
      return 'tidak boleh ada ..' if name.include?('..')
      return 'sudah ada' if @store.entries.include?(name)

      true
    end

    def first_line(text)
      text.to_s.lines.first.to_s.strip
    end

    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end

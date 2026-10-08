# frozen_string_literal: true
#
# Config -- pass-tui's own settings, kept out of pass itself.
#
# The settings live in a small JSON file (by default
# ~/.config/pass-tui/config.json) and are edited either by hand or from the
# in-app Settings dialog (key `s`).
#
#   config = PassTui::Config.load
#   config.store_dir   # => "/home/me/.password-store"
#   config.clip_time   # => 45
#   config.editor      # => "nvim"
#
# Precedence on first run: env vars (PASSWORD_STORE_DIR,
# PASSWORD_STORE_CLIP_TIME, VISUAL/EDITOR) seed the defaults, then the file
# overrides them once it exists.
#
# JSON rather than YAML: Spinel ships a json package but no YAML, and the
# file is a flat map of strings and numbers either way.

require 'json'
require 'fileutils'

module PassTui
  class Config
    FILENAME = 'config.json'

    attr_reader :path, :store_dir, :clip_time, :editor, :theme

    class << self
      def default_path
        base = ENV['XDG_CONFIG_HOME']
        base = File.join(Dir.home, '.config') if base.nil? || base.empty?
        File.join(base, 'pass-tui', FILENAME)
      end

      def default_store_dir
        env = ENV['PASSWORD_STORE_DIR']
        return File.expand_path(env) if env && !env.empty?

        File.join(Dir.home, '.password-store')
      end

      def default_editor
        env = ENV['VISUAL']
        env = ENV['EDITOR'] if env.nil? || env.empty?
        env && !env.empty? ? env : 'vi'
      end

      def default_clip_time
        seconds = ENV['PASSWORD_STORE_CLIP_TIME'].to_i
        seconds.positive? ? seconds : 45
      end

      def load(path = default_path)
        config = new(path: path)
        config.apply_file
        config
      end
    end

    def initialize(path: nil, store_dir: nil, clip_time: nil, editor: nil, theme: nil)
      @path = path || self.class.default_path
      @store_dir = store_dir || self.class.default_store_dir
      @clip_time = clip_time || self.class.default_clip_time
      @editor = editor || self.class.default_editor
      @theme = theme || 'vault'
    end

    # Read the file on top of the defaults. A missing or broken file is not
    # an error: the env-seeded defaults are already usable.
    def apply_file
      return self unless File.file?(@path)

      data = JSON.parse(File.read(@path))
      self.store_dir = data['store_dir'] if data['store_dir']
      self.clip_time = data['clip_time'] if data['clip_time']
      self.editor = data['editor'] if data['editor']
      self.theme = data['theme'] if data['theme']
      self
    rescue StandardError
      self
    end

    def store_dir=(value)
      value = value.to_s.strip
      @store_dir = value.empty? ? self.class.default_store_dir : File.expand_path(value)
    end

    def clip_time=(value)
      seconds = value.to_i
      @clip_time = seconds.positive? ? seconds : self.class.default_clip_time
    end

    def editor=(value)
      value = value.to_s.strip
      @editor = value.empty? ? self.class.default_editor : value
    end

    def theme=(value)
      value = value.to_s.strip.downcase
      @theme = value.empty? ? 'vault' : value
    end

    def to_h
      { 'store_dir' => @store_dir, 'clip_time' => @clip_time,
        'editor' => @editor, 'theme' => @theme }
    end

    def save(path = @path)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(to_h))
      self
    end
  end
end

# frozen_string_literal: true
#
# Clipboard -- copy text to the system clipboard using whatever tool the
# session provides. The first backend found on PATH wins.
#
#   clipboard.copy('secret')
#   clipboard.clear        # the auto-clear timer calls this
#
# Spinel has no Open3/IO.popen, so the text reaches the tool's stdin
# through `printf '%s' <quoted> | tool` run by /bin/sh. The value is
# single-quoted by PassTui::Shell, so secrets with quotes or newlines are
# safe.

require_relative 'shell'

module PassTui
  class Clipboard
    class Error < StandardError; end

    Backend = Struct.new(:bin, :args, :clear_args)

    BACKENDS = [
      Backend.new('wl-copy', [], ['--clear']),                 # Wayland
      Backend.new('xclip', ['-selection', 'clipboard'], nil),  # X11
      Backend.new('xsel', ['--clipboard', '--input'], nil),    # X11
      Backend.new('pbcopy', [], nil)                           # macOS
    ].freeze

    def initialize(path_env: ENV['PATH'])
      @path_env = path_env
      @backend = BACKENDS.find { |backend| which(backend.bin) }
    end

    def available?
      !@backend.nil?
    end

    def backend_name
      @backend && @backend.bin
    end

    def copy(text)
      raise Error, 'tidak ada tool clipboard (wl-copy/xclip/xsel/pbcopy)' unless @backend

      producer = "printf '%s' #{Shell.escape(text)}"
      run(Shell.pipeline(producer, @backend.bin, @backend.args))
      true
    end

    # Empty the selection. wl-copy needs an explicit --clear, the others
    # just get an empty copy.
    def clear
      return false unless @backend

      if @backend.clear_args
        run(Shell.command(@backend.bin, @backend.clear_args))
      else
        run(Shell.pipeline("printf ''", @backend.bin, @backend.args))
      end
      true
    end

    private

    def run(command)
      ok = system('sh', '-c', command)
      raise Error, "clipboard gagal (#{@backend.bin})" unless ok
    end

    def which(bin)
      return false if @path_env.nil?

      @path_env.split(File::PATH_SEPARATOR).any? do |dir|
        next false if dir.empty?

        path = File.join(dir, bin)
        File.executable?(path) && !File.directory?(path)
      end
    end
  end
end

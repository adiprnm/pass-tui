# frozen_string_literal: true
#
# Store -- the bridge to `pass`. We never touch gpg ourselves: decrypting,
# encrypting, editing and deleting all go through the CLI, which keeps
# gpg-agent, pinentry and the .gpg-id rules working exactly as the user
# configured them.
#
# Reading the entry *names* is just a filesystem walk, so the tree can be
# drawn without decrypting anything. Capturing output is done with
# backticks (Spinel has no Open3); the command line is single-quoted by
# PassTui::Shell, and PASSWORD_STORE_DIR/EDITOR are passed through the
# environment because Spinel's `system` takes no env Hash.

require_relative 'shell'

module PassTui
  class Store
    class Error < StandardError; end

    attr_reader :dir
    attr_accessor :editor

    def initialize(dir, pass_bin: 'pass', editor: nil)
      @dir = File.expand_path(dir.to_s)
      @pass_bin = pass_bin
      @editor = editor
    end

    def exist?
      File.directory?(@dir)
    end

    # Sorted entry names relative to the store, without the .gpg suffix.
    def entries
      return [] unless exist?

      prefix = Regexp.escape(@dir)
      Dir.glob(File.join(@dir, '**', '*.gpg')).map do |path|
        path.sub(/\A#{prefix}\/?/, '').sub(/\.gpg\z/, '')
      end.reject { |name| hidden?(name) }.sort
    end

    def show(name)
      capture('show', name)
    end

    def remove(name)
      capture('rm', '-f', name)
    end

    # Create an entry from content we already have, without an editor:
    # `pass insert -m` reads the plaintext from stdin. The content is
    # single-quoted so the password and username pass through untouched.
    def insert(name, content)
      producer = "printf '%s' #{Shell.escape(content)}"
      command = "#{Shell.pipeline(producer, @pass_bin, ['insert', '-m', '-f', name])} 2>&1"
      status = nil
      output = with_env do
        result = `#{command}`
        status = $?
        result
      end
      raise Error, output.to_s.strip unless Shell.ok?(status)

      true
    end

    # True when the store is a git repository, i.e. `pass git ...` will
    # work. `pass` creates `.git` as a directory (a file marks a worktree).
    def git?
      File.exist?(File.join(@dir, '.git'))
    end

    # Run `pass git <args>` and return its output. `pass` auto-commits each
    # insert/edit/rm, so the local history is already current.
    #
    # The store environment goes on the command line rather than into the
    # process environment (see capture_isolated): sync runs on a background
    # thread while the foreground may still be running `pass show`, and two
    # threads mutating ENV would race.
    def git(*args)
      capture_isolated('git', *args)
    end

    # Sync with the remote: rebase the local history on top of the remote,
    # then push. This is the documented `pass` multi-machine workflow.
    def sync
      raise Error, 'not a git repository' unless git?

      pull = capture_isolated('git', 'pull', '--rebase')
      push = capture_isolated('git', 'push')
      { pull: pull, push: push }
    end

    # Interactive commands run in the foreground and expect the caller to
    # have suspended the TUI, because they are about to hand the terminal to
    # $EDITOR (or to pinentry).
    def edit(name)
      interactive { system(@pass_bin, 'edit', name) }
    end

    def env
      base = { 'PASSWORD_STORE_DIR' => @dir }
      # Keep git from blocking the TUI on a credential prompt; a failed
      # fetch then surfaces as an error instead of a frozen interface.
      base['GIT_TERMINAL_PROMPT'] = '0'
      unless @editor.to_s.empty?
        base['EDITOR'] = @editor.to_s
        base['VISUAL'] = @editor.to_s
      end
      base
    end

    private

    def capture(*args)
      status = nil
      output = with_env do
        result = `#{Shell.command(@pass_bin, args)} 2>&1`
        status = $?
        result
      end
      raise Error, output.to_s.strip unless Shell.ok?(status)

      output
    end

    # Like capture, but the pass environment is prefixed onto the shell
    # command instead of written to ENV, so it is safe to call from a
    # background thread. Values are single-quoted by Shell.escape.
    def capture_isolated(*args)
      assignments = env.map { |key, value| "#{key}=#{Shell.escape(value)}" }.join(' ')
      output = `#{assignments} #{Shell.command(@pass_bin, args)} 2>&1`
      status = $?
      raise Error, output.to_s.strip unless Shell.ok?(status)

      output
    end

    def interactive
      with_env do
        ok = yield
        raise Error, 'pass command failed' unless ok
      end
      true
    end

    # Set the pass environment for the duration of the block, restoring it
    # afterwards (a nil restore deletes the variable).
    def with_env
      values = env
      saved = {}
      values.each_key { |key| saved[key] = ENV[key] }
      values.each { |key, value| ENV[key] = value }
      begin
        yield
      ensure
        saved.each { |key, value| ENV[key] = value }
      end
    end

    def hidden?(name)
      name.split('/').any? { |segment| segment.start_with?('.') }
    end
  end
end

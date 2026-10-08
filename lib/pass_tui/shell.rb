# frozen_string_literal: true
#
# Shell -- the little bit of shell plumbing pass-tui needs, kept in one
# place so it stays Spinel-friendly.
#
# Spinel has no Open3 and no Shellwords, and its `system` takes no env
# Hash, but it does support backticks (with interpolation), multi-argument
# `system`, `$?` and ENV assignment. These helpers build a safely quoted
# command line for the backtick path and interpret `$?`, which is a
# Process::Status on CRuby but a plain Integer under Spinel.

module PassTui
  module Shell
    module_function

    # Single-quote a value for /bin/sh, escaping embedded single quotes.
    def escape(value)
      "'" + value.to_s.gsub("'") { "'\\''" } + "'"
    end

    def command(bin, args)
      parts = [escape(bin)]
      args.each { |arg| parts << escape(arg) }
      parts.join(' ')
    end

    def pipeline(producer, bin, args)
      "#{producer} | #{command(bin, args)}"
    end

    # $? is an Integer under Spinel and a Process::Status on CRuby.
    def ok?(status)
      return false if status.nil?

      status.is_a?(Integer) ? status.zero? : status.success?
    end
  end
end

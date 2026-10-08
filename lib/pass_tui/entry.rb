# frozen_string_literal: true
#
# Entry -- the decrypted content of one password-store entry.
#
# pass-tui writes entries in a labelled form, one field per line:
#
#   username:carol
#   password:s3cret
#
# The classic pass layout (the bare password on the first line, then
# `key: value` metadata) is still understood, so entries made by pass or
# other tools keep working:
#
#   s3cret
#   user: alice
#   url: https://example.com
#
# Rule: if any line is a `password:` field it *is* the password; otherwise
# the first line is. Everything else is either a field or a note.

module PassTui
  class Entry
    PASSWORD_KEY = 'password'
    USER_KEYS = %w[user username login email].freeze
    URL_KEYS = %w[url website uri link].freeze

    attr_reader :name, :password, :fields, :notes

    def initialize(name:, password: '', fields: [], notes: [])
      @name = name
      @password = password
      @fields = fields
      @notes = notes
    end

    def self.parse(name, content)
      lines = content.to_s.split("\n")

      index = lines.index { |line| field_key(line) == PASSWORD_KEY }
      if index
        password = split_field(lines[index])[1]
        rest = []
        lines.each_with_index do |line, i|
          rest << line unless i == index
        end
      else
        password = lines.shift.to_s
        rest = lines
      end

      fields = []
      notes = []
      rest.each do |line|
        pair = split_field(line)
        if pair
          fields << pair
        else
          notes << line
        end
      end

      new(name: name, password: password, fields: fields, notes: notes)
    end

    # `key: value` -> [key, value], or nil when the line is not a field.
    # A bare URL (`https://...`) is a note, not a field named "https".
    def self.split_field(line)
      return nil if line.match?(%r{\A[a-z][a-z0-9+.\-]*://}i)

      match = line.match(/\A([^:]+):\s?(.*)\z/)
      return nil unless match

      key = match[1].strip
      return nil if key.empty? || key.include?(' ')

      [key, match[2]]
    end

    def self.field_key(line)
      pair = split_field(line)
      pair && pair[0].downcase
    end

    def field(key)
      pair = @fields.find { |candidate, _value| candidate.downcase == key.to_s.downcase }
      pair && pair[1]
    end

    def user
      key = USER_KEYS.find { |candidate| field(candidate) }
      key && field(key)
    end

    def url
      key = URL_KEYS.find { |candidate| field(candidate) }
      key && field(key)
    end

    def masked_password
      '*' * @password.length
    end

    def empty_password?
      @password.empty?
    end
  end
end

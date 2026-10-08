# frozen_string_literal: true
#
# Theme -- pass-tui's palette, in the spirit of todotui.
#
# The chrome stays graphite grey and the *data* carries the colour, so the
# eye lands on the credential rather than the frame. One warm accent (amber)
# marks focus, the selected row's marker and folders; the credential's
# vocabulary gets one stable colour per field kind:
#
#   user      green   (79)     the account name
#   url       blue    (109)    where it goes
#   password  amber   (214)    the secret, while sealed
#   revealed  red     (203)    -- the one bold move: an exposed password
#   notes     grey    (245)
#   extra     soft    (179)    any other key
#
# `vault` layers this on ruby-tui's :dark; `plain` keeps the vocabulary
# meaningful through weight instead of hue (bold / underline / reverse).
#
#   PassTui::Theme.install(:vault)   # colour + attributes
#   PassTui::Theme.install(:plain)   # attributes only

module PassTui
  module Theme
    NAMES = %w[vault plain].freeze

    DARK = {
      # Body text takes the terminal's own foreground, so values always read.
      text:          {},
      value:         {},
      field:         {},

      # Chrome: graphite.
      border:        { fg: 238 },
      field_border:  { fg: 238 },
      rule:          { fg: 238 },
      label:         { fg: 243 },
      muted:         { fg: 243 },
      dim:           { fg: 245 },
      hint:          { fg: 243 },
      header:        { fg: 243 },
      placeholder:   { fg: 243 },
      track:         { fg: 238 },
      thumb:         { fg: 245 },

      title:         { fg: 231, bold: true },
      brand:         { fg: 231, bold: true },
      brand_path:    { fg: 243 },
      subtitle:      { fg: 245, bold: true },
      legend:        { fg: 245, bold: true },

      # The one warm accent.
      accent:        { fg: 214, bold: true },
      folder:        { fg: 214 },
      border_focus:  { fg: 244 },
      marker:        { fg: 214, bg: 236, bold: true },

      selection:     { fg: 231, bg: 236 },
      selection_dim: { fg: 250, bg: 236 },
      cursor:        { reverse: true },

      # The vault vocabulary.
      legend_user:   { fg: 79, bold: true },
      legend_url:    { fg: 109, bold: true },
      legend_secret: { fg: 214, bold: true },
      legend_note:   { fg: 245 },
      legend_meta:   { fg: 179 },
      sealed:        { fg: 243 },
      secret:        { fg: 203, bold: true },
      danger:        { fg: 203, bold: true },

      tab_active:    { fg: 231, bold: true },
      tab_inactive:  { fg: 243 }
    }.freeze

    PLAIN = {
      label:         { dim: true },
      muted:         { dim: true },
      dim:           { dim: true },
      hint:          { dim: true },
      header:        { dim: true },
      placeholder:   { dim: true },
      border:        { dim: true },
      field_border:  { dim: true },
      rule:          { dim: true },
      track:         { dim: true },
      thumb:         { bold: true },

      title:         { bold: true },
      brand:         { bold: true },
      brand_path:    { dim: true },
      subtitle:      { bold: true },
      legend:        { bold: true },

      accent:        { bold: true },
      folder:        { bold: true },
      border_focus:  { bold: true },
      marker:        { reverse: true },

      selection:     { reverse: true },
      selection_dim: { reverse: true },
      cursor:        { reverse: true },

      legend_user:   { bold: true },
      legend_url:    { underline: true },
      legend_secret: { bold: true },
      legend_note:   { dim: true },
      legend_meta:   { dim: true },
      sealed:        { dim: true },
      secret:        { bold: true, reverse: true },
      danger:        { bold: true, reverse: true },

      tab_active:    { bold: true },
      tab_inactive:  { dim: true }
    }.freeze

    def self.install(name = :vault)
      name = name.respond_to?(:to_sym) ? name.to_sym : name
      name = :vault unless NAMES.include?(name.to_s) # `dark` maps to :vault
      base = name == :plain ? :plain : :dark
      TUI::Theme.install(base)

      styles = base == :plain ? PLAIN : DARK
      # Style.define takes the opts hash positionally: forwarding it with
      # **opts is a construct Spinel refuses to compile.
      styles.each { |style_name, opts| TUI::Style.define(style_name, opts) }
      self
    end
  end
end

PassTui::Theme.install(:vault)

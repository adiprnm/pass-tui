# frozen_string_literal: true
#
# Editing -- lend the terminal to a child process (an editor, or `pass`
# driving pinentry) and take it back afterwards.
#
# TUI::Term.session put the terminal into the alternate screen and raw
# mode. Before an editor runs we leave both, so the editor sees a normal
# terminal; afterwards we re-enter. The session's own restore still wins at
# exit, because it saved the tty state before raw mode was ever switched on.

module PassTui
  module Editing
    module_function

    def suspend(out = $stdout)
      TUI::Term.write(out, TUI::Term::SHOW_CURSOR + TUI::Term::ALT_OFF + TUI::Style::RESET)
      TUI::Term.flush(out)
      system('stty sane 2>/dev/null')
      nil
    end

    def resume(out = $stdout)
      system('stty raw -echo 2>/dev/null')
      TUI::Term.write(out, TUI::Term::ALT_ON + TUI::Term::HIDE_CURSOR + TUI::Term::CLEAR)
      TUI::Term.flush(out)
      nil
    end
  end
end

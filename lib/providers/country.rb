require 'env'

module Providers
  # The country code in the spelling a source expects.
  #
  # The European Union writes Greece as EL, ISO 3166 writes it as GR. Every
  # other country carries the same two letters in both conventions. A
  # provider converts the code with this module into the convention its
  # source follows, so the user can set either spelling.
  module Country
    ISO_ALIASES = { 'EL' => 'GR' }.freeze
    EU_ALIASES = ISO_ALIASES.invert.freeze

    # The setting `COUNTRY` that every provider shares, in upper case. It
    # is an empty string when unset, so the provider that needs it can
    # name it in its validation.
    def self.from_env
      Env['COUNTRY'].to_s.upcase
    end

    # The code as ISO 3166 writes it, in upper case.
    def self.iso(code)
      upcased = code.to_s.strip.upcase

      ISO_ALIASES.fetch(upcased, upcased)
    end

    # The code as the European Union writes it, in upper case.
    def self.eu(code)
      upcased = code.to_s.strip.upcase

      EU_ALIASES.fetch(upcased, upcased)
    end
  end
end

# frozen_string_literal: true

require "json"

module JwtAuthClient
  # Adapter handed to Faraday's :json response middleware.
  #
  # Faraday (<= 2.14) calls `decoder.parse(body, options_hash)` with a positional
  # options hash, which `json` >= 3.0 no longer accepts. Forwarding the options as
  # keywords keeps response parsing working on both json 2.x and 3.x.
  module JsonDecoder
    module_function

    def parse(body, options = {})
      ::JSON.parse(body, **options)
    end
  end
end

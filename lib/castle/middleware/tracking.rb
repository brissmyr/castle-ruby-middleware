# frozen_string_literal: true

require 'castle/middleware/request_config'

module Castle
  module Middleware
    class Tracking
      attr_reader :app

      def initialize(app)
        @app = app
      end

      def call(env)
        env['castle'] = RequestConfig.new

        req = Rack::Request.new(env)

        # [status, headers, body]
        app_result = app.call(env)

        # Find a matching event from the config
        mapping = Middleware.event_mapping.find_by_rack_request(app_result, req)

        return app_result if mapping.nil?

        event_properties = self.class.collect_event_properties(req.params, mapping.properties)

        # Extract headers from request into a string
        headers = ::Castle::Extractors::Headers.new(req).call

        # Read client ID from cookies
        client_id = ::Castle::Extractors::ClientId.new(req).call(app_result, '__cid')

        # Send request as configured
        Middleware.configuration.transport.(
          {
            user_id: env['castle'].user_id,
            traits: env['castle'].traits,
            name: mapping.event,
            properties: (env['castle'].props || {}).merge(event_properties)
          },
          {
            headers: headers,
            client_id: client_id,
            ip: req.ip
          }
        )

        app_result
      end

      class << self
        def collect_event_properties(request_params, properties_map)
          flat_params = Middleware::ParamsFlattener.(request_params)

          event_properties = properties_map.each_with_object({}) do |(property, param), hash|
            hash[property] = flat_params[param]
          end

          # Convert password to a boolean
          # TODO: Check agains list of known password field names
          if event_properties.key?(:password)
            event_properties[:password] = !event_properties[:password].to_s.empty?
          end

          event_properties
        end
      end
    end
  end
end

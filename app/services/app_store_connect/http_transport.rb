require "net/http"

module AppStoreConnect
  # Sends one HTTPS request and returns the status and the raw body. A network failure
  # raises Client::TransientError, so the caller can retry it.
  class HttpTransport
    Response = Struct.new(:status, :body)

    NETWORK_ERRORS = [
      Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, SocketError, EOFError,
      Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ETIMEDOUT, OpenSSL::SSL::SSLError
    ].freeze

    def initialize(open_timeout: 10, read_timeout: 30)
      @open_timeout = open_timeout
      @read_timeout = read_timeout
    end

    def call(method, url, headers:, body: nil)
      uri = URI(url)
      request = Net::HTTP.const_get(method.to_s.capitalize).new(uri, headers)
      request.body = body if body
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                                                     open_timeout: @open_timeout, read_timeout: @read_timeout) do |http|
        http.request(request)
      end
      Response.new(response.code.to_i, response.body.to_s)
    rescue *NETWORK_ERRORS => e
      raise Client::TransientError, "Network error: #{e.class}"
    end
  end
end

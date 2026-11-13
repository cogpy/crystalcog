# Minimal HS256 JSON Web Tokens for the Pygmalion platform services
# (Paphos backend and Galatea frontend server).

require "json"
require "base64"
require "openssl/hmac"
require "crypto/subtle"

module PygmalionPlatform
  module JWT
    class Error < Exception
    end

    def self.encode(payload : Hash(String, JSON::Any::Type) | Hash(String, JSON::Any), secret : String) : String
      header = segment({"alg" => "HS256", "typ" => "JWT"}.to_json)
      body = segment(payload.to_json)
      "#{header}.#{body}.#{sign("#{header}.#{body}", secret)}"
    end

    # Verify the signature (and `exp`, when present) and return the claims.
    def self.decode(token : String, secret : String) : JSON::Any
      parts = token.split('.')
      raise Error.new("malformed token") unless parts.size == 3

      expected = sign("#{parts[0]}.#{parts[1]}", secret)
      unless Crypto::Subtle.constant_time_compare(expected.to_slice, parts[2].to_slice)
        raise Error.new("bad signature")
      end

      header = JSON.parse(Base64.decode_string(parts[0]))
      raise Error.new("unsupported alg") unless header["alg"]?.try(&.as_s?) == "HS256"

      claims = JSON.parse(Base64.decode_string(parts[1]))
      if exp = claims["exp"]?.try(&.as_i64?)
        raise Error.new("token expired") if Time.utc.to_unix >= exp
      end
      claims
    rescue ex : Base64::Error | JSON::ParseException
      raise Error.new("malformed token: #{ex.message}")
    end

    private def self.segment(json : String) : String
      Base64.urlsafe_encode(json, padding: false)
    end

    private def self.sign(data : String, secret : String) : String
      Base64.urlsafe_encode(OpenSSL::HMAC.digest(:sha256, secret, data), padding: false)
    end
  end
end

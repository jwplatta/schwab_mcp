# frozen_string_literal: true

require "json"

module SchwabMCP
  class Redactor
    ACCOUNT_NUMBER_PATTERN = /\b\d{8,9}\b/
    HASH_VALUE_PATTERN = /\b[A-Za-z0-9]{20,}\b/
    BEARER_TOKEN_PATTERN = /Bearer\s+[A-Za-z0-9\.\-_]+/i
    ACCOUNT_FIELDS = %w[
      accountNumber
      accountId
      account_number
      account_id
      hashValue
      hash_value
    ].freeze
    NON_SENSITIVE_FIELDS = %w[
      cusip
      orderId
      order_id
      legId
      leg_id
      strikePrice
      strike_price
      quantity
      daysToExpiration
      days_to_expiration
      expirationDate
      expiration_date
      price
      netChange
      net_change
      mismarkedQuantity
      mismarked_quantity
    ].freeze
    REDACTED_PLACEHOLDER = '[REDACTED]'
    REDACTED_ACCOUNT_PLACEHOLDER = '[REDACTED_ACCOUNT]'
    REDACTED_HASH_PLACEHOLDER = '[REDACTED_HASH]'
    REDACTED_TOKEN_PLACEHOLDER = '[REDACTED_TOKEN]'

    class << self
      # Main entry point for redacting any data structure
      # @param data [Object] Data to redact (Hash, Array, String, or other)
      # @return [Object] Redacted copy of the data
      def redact(data)
        case data
        when Hash
          redact_hash(data)
        when Array
          redact_array(data)
        when String
          redact_string(data)
        else
          data
        end
      end

      # Redact a JSON response from Schwab API
      # @param response_body [String] Raw response body from API
      # @return [String] Pretty-formatted redacted JSON
      def redact_api_response(response_body)
        return response_body unless response_body.is_a?(String)

        begin
          parsed = JSON.parse(response_body)
          redacted = redact(parsed)
          JSON.pretty_generate(redacted)
        rescue JSON::ParserError
          # If parsing fails, redact as string
          redact_string(response_body)
        end
      end

      # Redact formatted text that might contain sensitive data
      # @param text [String] Formatted text to redact
      # @return [String] Redacted text
      def redact_formatted_text(text)
        return text unless text.is_a?(String)
        redacted = text.dup
        redacted.gsub!(BEARER_TOKEN_PATTERN, "Bearer #{REDACTED_TOKEN_PLACEHOLDER}")

        # Redact account numbers in specific text patterns
        redacted.gsub!(/Account\s+ID:\s*\d{8,9}/i, "Account ID: #{REDACTED_ACCOUNT_PLACEHOLDER}")
        redacted.gsub!(/Account\s+Number:\s*\d{8,9}/i, "Account Number: #{REDACTED_ACCOUNT_PLACEHOLDER}")
        redacted.gsub!(/Account:\s*\d{8,9}/i, "Account: #{REDACTED_ACCOUNT_PLACEHOLDER}")

        # Redact account numbers in log patterns like "account_number: 123456789"
        redacted.gsub!(/account[_\s]*number[_\s]*[:\=]\s*\d{8,9}/i, "account_number: #{REDACTED_ACCOUNT_PLACEHOLDER}")
        redacted.gsub!(/account[_\s]*id[_\s]*[:\=]\s*\d{8,9}/i, "account_id: #{REDACTED_ACCOUNT_PLACEHOLDER}")

        # Redact long hashes (40+ hex chars) in URLs/logs (e.g., Schwab account hashes)
        # Example: /accounts/4996EA061B4878E8D0B9063DF74925E5688F475BE00AF6A0A41E1FC4A2510CA0/
        redacted.gsub!(/\b[0-9a-fA-F]{40,}\b/, REDACTED_HASH_PLACEHOLDER)

        redacted
      end

      # Redact a log message that might contain sensitive data
      # @param message [String] Log message to redact
      # @return [String] Redacted log message
      def redact_log_message(message)
        return message unless message.is_a?(String)

        redact_formatted_text(message)
      end

      # Redact an MCP tool response before sending to client
      # @param response [Hash] MCP tool response
      # @return [Hash] Redacted response
      def redact_mcp_response(response)
        return response unless response.is_a?(Hash)

        redacted = redact(response)

        # Also redact any content in the response content field
        if redacted.dig("content")
          case redacted["content"]
          when String
            redacted["content"] = redact_formatted_text(redacted["content"])
          when Array
            redacted["content"] = redacted["content"].map do |item|
              if item.is_a?(Hash) && item["text"]
                item["text"] = redact_formatted_text(item["text"])
              end
              item
            end
          end
        end

        redacted
      end

      private

      # Redact a hash/object recursively
      # @param hash [Hash] Hash to redact
      # @return [Hash] Redacted copy of hash
      def redact_hash(hash)
        return hash unless hash.is_a?(Hash)

        redacted = {}

        hash.each do |key, value|
          key_str = key.to_s.downcase

          # Check if this is a known non-sensitive field
          if NON_SENSITIVE_FIELDS.any? { |field| key_str.include?(field.downcase) }
            redacted[key] = value
          # Check if this is a known account-related field
          elsif ACCOUNT_FIELDS.any? { |field| key_str.include?(field.downcase) }
            redacted[key] = redact_account_field(value)
          else
            redacted[key] = redact(value)
          end
        end

        redacted
      end

      # Redact an array recursively
      # @param array [Array] Array to redact
      # @return [Array] Redacted copy of array
      def redact_array(array)
        return array unless array.is_a?(Array)

        array.map { |item| redact(item) }
      end

      # Redact a string value
      # @param string [String] String to redact
      # @return [String] Redacted string
      def redact_string(string)
        return string unless string.is_a?(String)

        redacted = string.dup

        # Redact bearer tokens
        redacted.gsub!(BEARER_TOKEN_PATTERN, "Bearer #{REDACTED_TOKEN_PLACEHOLDER}")

        # Redact JSON-embedded account data (specific patterns)
        redacted.gsub!(/"hashValue":\s*"[^"]+"/i, "\"hashValue\": \"#{REDACTED_HASH_PLACEHOLDER}\"")
        redacted.gsub!(/"accountNumber":\s*"?\d{8,9}"?/i, "\"accountNumber\": \"#{REDACTED_ACCOUNT_PLACEHOLDER}\"")
        redacted.gsub!(/"account_id":\s*"?\d{8,9}"?/i, "\"account_id\": \"#{REDACTED_ACCOUNT_PLACEHOLDER}\"")

        redacted
      end

      # Redact a field that is known to contain account information
      # @param value [Object] Value to redact
      # @return [Object] Redacted value
      def redact_account_field(value)
        case value
        when String
          if value.match?(ACCOUNT_NUMBER_PATTERN) && value.length.between?(8, 9)
            REDACTED_ACCOUNT_PLACEHOLDER
          elsif value.length > 20 && value.match?(/\A[A-Za-z0-9]+\z/)
            REDACTED_HASH_PLACEHOLDER
          else
            value
          end
        when Integer
          if value.to_s.length.between?(8, 9)
            REDACTED_ACCOUNT_PLACEHOLDER
          else
            value
          end
        else
          redact(value)
        end
      end
    end
  end
end

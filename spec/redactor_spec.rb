# frozen_string_literal: true

require "spec_helper"
require "schwab_mcp/redactor"

RSpec.describe SchwabMCP::Redactor do
  describe ".redact" do
    context "with hash data containing account information" do
      it "redacts account numbers and hash values" do
        data = {
          "accountNumber" => "123456789",
          "account_id" => "987654321",
          "hashValue" => "abc123def456ghi789jkl012mno345pqr678stu901vwx234yz",
          "cusip" => "12345678",
          "orderId" => "987654321"
        }

        result = described_class.redact(data)

        expect(result["accountNumber"]).to eq("[REDACTED_ACCOUNT]")
        expect(result["account_id"]).to eq("[REDACTED_ACCOUNT]")
        expect(result["hashValue"]).to eq("[REDACTED_HASH]")
        expect(result["cusip"]).to eq("12345678")
        expect(result["orderId"]).to eq("987654321")
      end

      it "handles nested account data structures" do
        data = {
          "securitiesAccount" => {
            "accountNumber" => "123456789",
            "positions" => [
              {
                "instrument" => {
                  "cusip" => "87654321",
                  "symbol" => "SPY"
                }
              }
            ]
          }
        }

        result = described_class.redact(data)

        expect(result["securitiesAccount"]["accountNumber"]).to eq("[REDACTED_ACCOUNT]")
        expect(result["securitiesAccount"]["positions"][0]["instrument"]["cusip"]).to eq("87654321")
        expect(result["securitiesAccount"]["positions"][0]["instrument"]["symbol"]).to eq("SPY")
      end
    end

    context "with array data" do
      it "redacts account numbers in array elements" do
        data = [
          { "accountNumber" => "123456789" },
          { "cusip" => "87654321" },
          { "hashValue" => "abc123def456ghi789jkl012mno345pqr678stu901vwx234yz" }
        ]

        result = described_class.redact(data)

        expect(result[0]["accountNumber"]).to eq("[REDACTED_ACCOUNT]")
        expect(result[1]["cusip"]).to eq("87654321")
        expect(result[2]["hashValue"]).to eq("[REDACTED_HASH]")
      end
    end

    context "with string data" do
      it "redacts JSON-embedded account data" do
        json_string = '{"accountNumber": "123456789", "hashValue": "abc123def456"}'

        result = described_class.redact(json_string)

        expect(result).to include('"accountNumber": "[REDACTED_ACCOUNT]"')
        expect(result).to include('"hashValue": "[REDACTED_HASH]"')
      end

      it "redacts bearer tokens" do
        token_string = "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"

        result = described_class.redact(token_string)

        expect(result).to eq("Authorization: Bearer [REDACTED_TOKEN]")
      end
    end
  end

  describe ".redact_api_response" do
    it "returns pretty-formatted redacted JSON" do
      response_body = '{"accountNumber":"123456789","cusip":"87654321"}'

      result = described_class.redact_api_response(response_body)

      expect(result).to be_a(String)
      expect(result).to include("[REDACTED_ACCOUNT]")
      expect(result).to include("87654321")
      expect(result).to include("\n")
    end

    it "handles invalid JSON gracefully" do
      invalid_response = "Error: Invalid request"

      result = described_class.redact_api_response(invalid_response)

      expect(result).to eq(invalid_response)
    end
  end

  describe ".redact_formatted_text" do
    it "redacts account numbers in log text patterns" do
      text = "Account ID: 123456789 and Account Number: 987654321"

      result = described_class.redact_formatted_text(text)

      expect(result).to eq("Account ID: [REDACTED_ACCOUNT] and Account Number: [REDACTED_ACCOUNT]")
    end

    it "redacts bearer tokens in log text" do
      text = "Authorization header: Bearer abc123def456"

      result = described_class.redact_formatted_text(text)

      expect(result).to eq("Authorization header: Bearer [REDACTED_TOKEN]")
    end

    it "does not redact random numbers or non-sensitive data" do
      text = "CUSIP: 12345678, Order ID: 987654321, Strike: 12345678"

      result = described_class.redact_formatted_text(text)

      expect(result).to eq(text)
    end
  end

  describe "real-world Schwab API examples" do
    it "handles typical Schwab account response" do
      schwab_response = {
        "securitiesAccount" => {
          "accountNumber" => "123456789",
          "type" => "CASH",
          "currentBalances" => {
            "cashBalance" => 10000.00,
            "buyingPower" => 10000.00
          },
          "positions" => [
            {
              "instrument" => {
                "assetType" => "OPTION",
                "cusip" => "0SPY..YM40005000",
                "symbol" => "SPY_071425C500",
                "description" => "SPDR S&P 500 ETF Trust Jul 14 2025 $500 Call"
              },
              "longQuantity" => 1.0,
              "marketValue" => 150.00
            }
          ]
        }
      }

      result = described_class.redact(schwab_response)

      expect(result["securitiesAccount"]["accountNumber"]).to eq("[REDACTED_ACCOUNT]")
      expect(result["securitiesAccount"]["type"]).to eq("CASH")
      expect(result["securitiesAccount"]["currentBalances"]["cashBalance"]).to eq(10000.00)
      expect(result["securitiesAccount"]["positions"][0]["instrument"]["cusip"]).to eq("0SPY..YM40005000")
      expect(result["securitiesAccount"]["positions"][0]["instrument"]["symbol"]).to eq("SPY_071425C500")
    end

    it "handles typical Schwab order response" do
      order_response = {
        "orderId" => "987654321",
        "status" => "FILLED",
        "accountNumber" => "123456789",
        "orderLegCollection" => [
          {
            "orderId" => "987654321",
            "legId" => 1,
            "instrument" => {
              "cusip" => "0SPY..YM40005000",
              "symbol" => "SPY_071425C500"
            },
            "quantity" => 1
          }
        ]
      }

      result = described_class.redact(order_response)

      expect(result["orderId"]).to eq("987654321")
      expect(result["accountNumber"]).to eq("[REDACTED_ACCOUNT]")
      expect(result["orderLegCollection"][0]["orderId"]).to eq("987654321")
      expect(result["orderLegCollection"][0]["legId"]).to eq(1)
      expect(result["orderLegCollection"][0]["instrument"]["cusip"]).to eq("0SPY..YM40005000")
    end
  end

  describe ".redact_log_message" do
    it "redacts account numbers in log messages" do
      log_message = "Processing request for account_number: 123456789"

      result = described_class.redact_log_message(log_message)

      expect(result).to include("[REDACTED_ACCOUNT]")
      expect(result).not_to include("123456789")
    end
  end

  describe ".redact_mcp_response" do
    it "redacts account data in MCP response content" do
      mcp_response = {
        "content" => [
          {
            "type" => "text",
            "text" => "Account details: Account ID: 123456789, Balance: $10000"
          }
        ]
      }

      result = described_class.redact_mcp_response(mcp_response)

      expect(result["content"][0]["text"]).to include("[REDACTED_ACCOUNT]")
      expect(result["content"][0]["text"]).not_to include("123456789")
    end

    it "handles string content in MCP responses" do
      mcp_response = {
        "content" => "Account Number: 123456789"
      }

      result = described_class.redact_mcp_response(mcp_response)

      expect(result["content"]).to include("[REDACTED_ACCOUNT]")
    end
  end
end

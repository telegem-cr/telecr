# spec/spec_helper.cr - Test helper for Telecr

require "spec"
require "webmock"
require "../src/telecr"

# Configure WebMock to prevent real HTTP requests during tests
WebMock.enable!
WebMock.disable_net_connect!

# Helper to load fixture data
def fixture(name : String) : String
  File.read(File.join(__DIR__, "fixtures", "#{name}.json"))
end

# Helper to create a mock Telegram response
def mock_telegram_response(method : String, result : Hash(String, JSON::Any))
  WebMock.stub(:post, "https://api.telegram.org/botTEST_TOKEN/#{method}")
    .to_return(body: {
      ok: true,
      result: result
    }.to_json)
end

# Helper to create a mock error response
def mock_telegram_error(method : String, error_code : Int32, description : String)
  WebMock.stub(:post, "https://api.telegram.org/botTEST_TOKEN/#{method}")
    .to_return(status: error_code, body: {
      ok: false,
      error_code: error_code,
      description: description
    }.to_json)
end

# Helper to create a test bot instance
def test_bot(token : String = "TEST_TOKEN")
  Telecr::Core::Bot.new(token)
end

# Helper to create a test context
def test_context(update_data : Hash(String, JSON::Any), bot : Telecr::Core::Bot)
  update = Telecr::Types::Update.new(update_data)
  Telecr::Core::Context.new(update, bot)
end

# Run before each test
Spec.before_each do
  WebMock.reset
end

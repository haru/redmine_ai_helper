require File.expand_path("../../test_helper", __FILE__)

class TransportTest < ActiveSupport::TestCase
  def test_available_transports
    transports = RedmineAiHelper::Transport.available_transports
    assert_not_nil transports
    assert transports.is_a?(Array)
    assert_includes transports, 'stdio'
    assert_includes transports, 'http'
  end

  def test_create_stdio_transport
    config = { 'transport' => 'stdio', 'command' => 'node', 'args' => ['server.js'] }
    assert_raises(NotImplementedError) do
      RedmineAiHelper::Transport.create(config)
    end
  end

  def test_create_http_transport
    config = { 'transport' => 'http', 'url' => 'http://localhost:3000' }
    assert_raises(NotImplementedError) do
      RedmineAiHelper::Transport.create(config)
    end
  end

  def test_create_with_legacy_config
    # Legacy stdio config without explicit transport type
    stdio_config = { 'command' => 'node', 'args' => ['server.js'] }
    assert_raises(NotImplementedError) do
      RedmineAiHelper::Transport.create(stdio_config)
    end
  end

  def test_valid_config_stdio
    config = { 'transport' => 'stdio', 'command' => 'node' }
    assert RedmineAiHelper::Transport.valid_config?(config)
  end

  def test_valid_config_http
    config = { 'transport' => 'http', 'url' => 'http://localhost:3000' }
    assert RedmineAiHelper::Transport.valid_config?(config)
  end

  def test_invalid_config
    config = { 'transport' => 'invalid' }
    assert_equal false, RedmineAiHelper::Transport.valid_config?(config)
  end

  def test_determine_type_stdio
    config = { 'command' => 'node', 'args' => ['server.js'] }
    type = RedmineAiHelper::Transport.determine_type(config)
    assert_equal 'stdio', type
  end

  def test_determine_type_http
    config = { 'url' => 'http://localhost:3000' }
    type = RedmineAiHelper::Transport.determine_type(config)
    assert_equal 'http', type
  end

  def test_determine_type_explicit
    config = { 'transport' => 'http', 'url' => 'http://localhost:3000' }
    type = RedmineAiHelper::Transport.determine_type(config)
    assert_equal 'http', type
  end

  def test_determine_type_defaults_to_stdio
    config = { 'command' => 'echo' }  # Provide minimal valid config
    type = RedmineAiHelper::Transport.determine_type(config)
    assert_equal 'stdio', type
  end

  def test_create_with_unsupported_transport
    config = { 'transport' => 'unsupported' }
    assert_raises(NotImplementedError) do
      RedmineAiHelper::Transport.create(config)
    end
  end

  def test_valid_config_with_empty_hash
    config = {}
    # Empty config should be invalid
    assert_equal false, RedmineAiHelper::Transport.valid_config?(config)
  end

  def test_valid_config_with_nil
    assert_equal false, RedmineAiHelper::Transport.valid_config?(nil)
  end

  def test_available_transports_includes_expected_types
    transports = RedmineAiHelper::Transport.available_transports
    assert transports.include?('stdio')
    assert transports.include?('http')
  end
end
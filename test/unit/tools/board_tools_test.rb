require File.expand_path("../../../test_helper", __FILE__)

class BoardToolsTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :enumerations, :users, :issue_categories, :versions, :custom_fields, :boards, :messages

  def setup
    @provider = RedmineAiHelper::Tools::BoardTools.new
    @project = Project.find(1)
    @board = @project.boards.first
    @message = @board.messages.first
  end

  def test_list_boards_success
    response = @provider.list_boards(project_id: @project.id)
    assert_equal @project.boards.count, response.size
  end

  def test_list_boards_project_not_found
    assert_raises(RuntimeError, "Project not found") do
      @provider.list_boards(project_id: 999)
    end
  end

  def test_board_info_success
    response = @provider.board_info(board_id: @board.id)
    assert_equal @board.id, response[:id]
    assert_equal @board.name, response[:name]
  end

  def test_board_info_not_found
    assert_raises(RuntimeError, "Board not found") do
      @provider.board_info(board_id: 999)
    end
  end

  def test_read_message_success
    response = @provider.read_message(message_id: @message.id)
    assert_equal @message.id, response[:id]
    assert_equal @message.content, response[:content]
  end

  def test_read_message_not_found
    assert_raises(RuntimeError, "Message not found") do
      @provider.read_message(message_id: 999)
    end
  end

  def test_generate_board_url
    response = @provider.generate_board_url(board_id: @board.id)
    assert_match(%r{boards/\d+}, response[:url])
  end

  def test_generate_board_url_no_board_id
    assert_raises(ArgumentError) do
      @provider.generate_board_url(project_id: @project.id)
    end
  end

  def test_generate_message_url_no_message_id
    assert_raises(ArgumentError) do
      @provider.generate_message_url(board_id: @board.id)
    end
  end

  def test_generate_message_url
    response = @provider.generate_message_url(message_id: @message.id)
    assert_match(%r{/boards/\d+/topics/\d+}, response[:url])
  end

  context "read_message with attachments" do
    setup do
      attachment = Attachment.find(1)
      attachment.container = @message
      attachment.save!
      @message.reload
    end

    should "include attachments with type field in message data" do
      @provider.stubs(:image_attachment_paths).returns([])
      Attachment.any_instance.stubs(:image?).returns(true)

      response = @provider.read_message(message_id: @message.id)

      assert response[:attachments].is_a?(Array)
      assert response[:attachments].length > 0
      attachment_data = response[:attachments].first
      assert_equal "image", attachment_data[:type]
      assert attachment_data.key?(:id)
      assert attachment_data.key?(:filename)
      assert attachment_data.key?(:content_type)
    end

    should "include type nil for non-image attachments" do
      @provider.stubs(:image_attachment_paths).returns([])
      Attachment.any_instance.stubs(:image?).returns(false)

      response = @provider.read_message(message_id: @message.id)

      attachment_data = response[:attachments].first
      assert_nil attachment_data[:type]
    end

    should "not include disk_path in attachments" do
      @provider.stubs(:image_attachment_paths).returns([])

      response = @provider.read_message(message_id: @message.id)

      response[:attachments].each do |attachment_data|
        assert_not_includes attachment_data.keys, :disk_path,
          "Attachment data must not contain disk_path for security reasons"
      end
    end

    should "return RubyLLM::Content when message has image attachments" do
      image_path = File.join(Dir.tmpdir, "test_board_image.png")
      File.write(image_path, "fake png content")
      @provider.stubs(:image_attachment_paths).returns([image_path])

      response = @provider.read_message(message_id: @message.id)

      assert_instance_of RubyLLM::Content, response
      assert_includes response.text, @message.subject
      assert_equal 1, response.attachments.size
    ensure
      File.delete(image_path) if File.exist?(image_path)
    end

    should "return Hash when message has no image attachments" do
      @provider.stubs(:image_attachment_paths).returns([])

      response = @provider.read_message(message_id: @message.id)

      assert_instance_of Hash, response
      assert_equal @message.id, response[:id]
    end
  end
end

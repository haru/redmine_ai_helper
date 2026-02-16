require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/util/attachment_image_helper"

class RedmineAiHelper::Util::AttachmentImageHelperTest < ActiveSupport::TestCase
  class TestClass
    include RedmineAiHelper::Util::AttachmentImageHelper
  end

  setup do
    @helper = TestClass.new
  end

  context "image_attachment_paths" do
    should "return disk paths for image attachments" do
      attachment = mock("attachment")
      attachment.stubs(:image?).returns(true)
      attachment.stubs(:diskfile).returns("/path/to/files/image.png")
      File.stubs(:exist?).with("/path/to/files/image.png").returns(true)

      container = mock("container")
      container.stubs(:respond_to?).with(:attachments).returns(true)
      container.stubs(:attachments).returns([attachment])

      result = @helper.image_attachment_paths(container)

      assert_equal ["/path/to/files/image.png"], result
    end

    should "exclude non-image files" do
      image_attachment = mock("image_attachment")
      image_attachment.stubs(:image?).returns(true)
      image_attachment.stubs(:diskfile).returns("/path/to/files/image.png")
      File.stubs(:exist?).with("/path/to/files/image.png").returns(true)

      text_attachment = mock("text_attachment")
      text_attachment.stubs(:image?).returns(false)

      container = mock("container")
      container.stubs(:respond_to?).with(:attachments).returns(true)
      container.stubs(:attachments).returns([image_attachment, text_attachment])

      result = @helper.image_attachment_paths(container)

      assert_equal ["/path/to/files/image.png"], result
    end

    should "exclude files that do not exist on disk" do
      existing_attachment = mock("existing_attachment")
      existing_attachment.stubs(:image?).returns(true)
      existing_attachment.stubs(:diskfile).returns("/path/to/files/existing.png")
      File.stubs(:exist?).with("/path/to/files/existing.png").returns(true)

      missing_attachment = mock("missing_attachment")
      missing_attachment.stubs(:image?).returns(true)
      missing_attachment.stubs(:diskfile).returns("/path/to/files/missing.jpg")
      File.stubs(:exist?).with("/path/to/files/missing.jpg").returns(false)

      container = mock("container")
      container.stubs(:respond_to?).with(:attachments).returns(true)
      container.stubs(:attachments).returns([existing_attachment, missing_attachment])

      result = @helper.image_attachment_paths(container)

      assert_equal ["/path/to/files/existing.png"], result
    end

    should "return empty array when container has no attachments" do
      container = mock("container")
      container.stubs(:respond_to?).with(:attachments).returns(true)
      container.stubs(:attachments).returns([])

      result = @helper.image_attachment_paths(container)

      assert_equal [], result
    end

    should "return empty array when container does not respond to attachments" do
      container = mock("container")
      container.stubs(:respond_to?).with(:attachments).returns(false)

      result = @helper.image_attachment_paths(container)

      assert_equal [], result
    end

    should "return multiple image paths when multiple images exist" do
      attachment1 = mock("attachment1")
      attachment1.stubs(:image?).returns(true)
      attachment1.stubs(:diskfile).returns("/path/to/files/image1.png")
      File.stubs(:exist?).with("/path/to/files/image1.png").returns(true)

      attachment2 = mock("attachment2")
      attachment2.stubs(:image?).returns(true)
      attachment2.stubs(:diskfile).returns("/path/to/files/image2.jpg")
      File.stubs(:exist?).with("/path/to/files/image2.jpg").returns(true)

      container = mock("container")
      container.stubs(:respond_to?).with(:attachments).returns(true)
      container.stubs(:attachments).returns([attachment1, attachment2])

      result = @helper.image_attachment_paths(container)

      assert_equal ["/path/to/files/image1.png", "/path/to/files/image2.jpg"], result
    end
  end
end

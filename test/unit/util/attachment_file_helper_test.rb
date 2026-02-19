require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/util/attachment_file_helper"

class RedmineAiHelper::Util::AttachmentFileHelperTest < ActiveSupport::TestCase
  class TestClass
    include RedmineAiHelper::Util::AttachmentFileHelper
  end

  setup do
    @helper = TestClass.new
    AiHelperSetting.delete_all
    @setting = AiHelperSetting.find_or_create
    @setting.update!(attachment_send_enabled: true, attachment_max_size_mb: 100)
  end

  # Helper to create a mock attachment with a given filename
  def mock_attachment(filename, disk_path: nil, exists: true, filesize: 1.megabyte)
    attachment = mock("attachment_#{filename}")
    attachment.stubs(:filename).returns(filename)
    disk_path ||= "/path/to/files/#{filename}"
    attachment.stubs(:diskfile).returns(disk_path)
    attachment.stubs(:filesize).returns(filesize)
    File.stubs(:exist?).with(disk_path).returns(exists)
    attachment
  end

  context "supported_attachment_paths" do
    should "return disk paths for image attachments" do
      attachment = mock_attachment("image.png")

      container = mock("container")
      container.stubs(:respond_to?).with(:attachments).returns(true)
      container.stubs(:attachments).returns([attachment])

      result = @helper.supported_attachment_paths(container)

      assert_equal ["/path/to/files/image.png"], result
    end

    should "return disk paths for various image formats" do
      %w[jpg jpeg png gif webp bmp].each do |ext|
        attachment = mock_attachment("image.#{ext}")

        container = mock("container")
        container.stubs(:respond_to?).with(:attachments).returns(true)
        container.stubs(:attachments).returns([attachment])

        result = @helper.supported_attachment_paths(container)

        assert_equal ["/path/to/files/image.#{ext}"], result, "Failed for extension: #{ext}"
      end
    end

    should "return disk paths for PDF files" do
      attachment = mock_attachment("document.pdf")

      container = mock("container")
      container.stubs(:respond_to?).with(:attachments).returns(true)
      container.stubs(:attachments).returns([attachment])

      result = @helper.supported_attachment_paths(container)

      assert_equal ["/path/to/files/document.pdf"], result
    end

    should "return disk paths for text and document files" do
      %w[txt md csv json xml].each do |ext|
        attachment = mock_attachment("file.#{ext}")

        container = mock("container")
        container.stubs(:respond_to?).with(:attachments).returns(true)
        container.stubs(:attachments).returns([attachment])

        result = @helper.supported_attachment_paths(container)

        assert_equal ["/path/to/files/file.#{ext}"], result, "Failed for extension: #{ext}"
      end
    end

    should "return disk paths for code files" do
      %w[rb py js html css ts tsx jsx java c cpp h hpp cs go rs sh bash zsh yml yaml toml].each do |ext|
        attachment = mock_attachment("code.#{ext}")

        container = mock("container")
        container.stubs(:respond_to?).with(:attachments).returns(true)
        container.stubs(:attachments).returns([attachment])

        result = @helper.supported_attachment_paths(container)

        assert_equal ["/path/to/files/code.#{ext}"], result, "Failed for extension: #{ext}"
      end
    end

    should "return disk paths for audio files" do
      %w[mp3 wav m4a ogg flac].each do |ext|
        attachment = mock_attachment("audio.#{ext}")

        container = mock("container")
        container.stubs(:respond_to?).with(:attachments).returns(true)
        container.stubs(:attachments).returns([attachment])

        result = @helper.supported_attachment_paths(container)

        assert_equal ["/path/to/files/audio.#{ext}"], result, "Failed for extension: #{ext}"
      end
    end

    should "exclude unsupported file extensions" do
      supported = mock_attachment("image.png")
      exe_file = mock_attachment("malware.exe")
      zip_file = mock_attachment("archive.zip")
      mp4_file = mock_attachment("video.mp4")
      mov_file = mock_attachment("video.mov")

      container = mock("container")
      container.stubs(:respond_to?).with(:attachments).returns(true)
      container.stubs(:attachments).returns([supported, exe_file, zip_file, mp4_file, mov_file])

      result = @helper.supported_attachment_paths(container)

      assert_equal ["/path/to/files/image.png"], result
    end

    should "exclude files that do not exist on disk" do
      existing = mock_attachment("existing.pdf")
      missing = mock_attachment("missing.pdf", exists: false)

      container = mock("container")
      container.stubs(:respond_to?).with(:attachments).returns(true)
      container.stubs(:attachments).returns([existing, missing])

      result = @helper.supported_attachment_paths(container)

      assert_equal ["/path/to/files/existing.pdf"], result
    end

    should "return empty array when container has no attachments" do
      container = mock("container")
      container.stubs(:respond_to?).with(:attachments).returns(true)
      container.stubs(:attachments).returns([])

      result = @helper.supported_attachment_paths(container)

      assert_equal [], result
    end

    should "return empty array when container does not respond to attachments" do
      container = mock("container")
      container.stubs(:respond_to?).with(:attachments).returns(false)

      result = @helper.supported_attachment_paths(container)

      assert_equal [], result
    end

    should "return multiple file paths for mixed file types" do
      image = mock_attachment("screenshot.png")
      pdf = mock_attachment("report.pdf")
      code = mock_attachment("script.rb")

      container = mock("container")
      container.stubs(:respond_to?).with(:attachments).returns(true)
      container.stubs(:attachments).returns([image, pdf, code])

      result = @helper.supported_attachment_paths(container)

      assert_equal ["/path/to/files/screenshot.png", "/path/to/files/report.pdf", "/path/to/files/script.rb"], result
    end

    should "handle case-insensitive extensions" do
      attachment = mock_attachment("IMAGE.PNG")

      container = mock("container")
      container.stubs(:respond_to?).with(:attachments).returns(true)
      container.stubs(:attachments).returns([attachment])

      result = @helper.supported_attachment_paths(container)

      assert_equal ["/path/to/files/IMAGE.PNG"], result
    end
  end

  context "image_attachment_paths (backward compatibility alias)" do
    should "return the same result as supported_attachment_paths" do
      image = mock_attachment("image.png")
      pdf = mock_attachment("report.pdf")

      container = mock("container")
      container.stubs(:respond_to?).with(:attachments).returns(true)
      container.stubs(:attachments).returns([image, pdf])

      supported_result = @helper.supported_attachment_paths(container)
      alias_result = @helper.image_attachment_paths(container)

      assert_equal supported_result, alias_result
    end
  end

  context "attachment_file_type" do
    should "return 'image' for image files" do
      %w[jpg jpeg png gif webp bmp].each do |ext|
        attachment = mock_attachment("file.#{ext}")
        assert_equal "image", @helper.send(:attachment_file_type, attachment), "Failed for extension: #{ext}"
      end
    end

    should "return 'audio' for audio files" do
      %w[mp3 wav m4a ogg flac].each do |ext|
        attachment = mock_attachment("file.#{ext}")
        assert_equal "audio", @helper.send(:attachment_file_type, attachment), "Failed for extension: #{ext}"
      end
    end

    should "return 'document' for document files" do
      %w[pdf txt md csv json xml].each do |ext|
        attachment = mock_attachment("file.#{ext}")
        assert_equal "document", @helper.send(:attachment_file_type, attachment), "Failed for extension: #{ext}"
      end
    end

    should "return 'code' for code files" do
      %w[rb py js html css ts tsx jsx java c cpp h hpp cs go rs sh bash zsh yml yaml toml].each do |ext|
        attachment = mock_attachment("file.#{ext}")
        assert_equal "code", @helper.send(:attachment_file_type, attachment), "Failed for extension: #{ext}"
      end
    end

    should "return nil for unsupported files" do
      %w[exe zip tar gz mp4 mov avi dll so].each do |ext|
        attachment = mock_attachment("file.#{ext}")
        assert_nil @helper.send(:attachment_file_type, attachment), "Expected nil for extension: #{ext}"
      end
    end
  end

  context "supported_file?" do
    should "return true for supported extensions" do
      %w[png pdf rb mp3 txt].each do |ext|
        attachment = mock_attachment("file.#{ext}")
        assert @helper.send(:supported_file?, attachment), "Expected true for extension: #{ext}"
      end
    end

    should "return false for unsupported extensions" do
      %w[exe zip mp4 tar dll].each do |ext|
        attachment = mock_attachment("file.#{ext}")
        refute @helper.send(:supported_file?, attachment), "Expected false for extension: #{ext}"
      end
    end
  end

  context "supported_attachment_paths with attachment settings" do
    should "return empty array when attachment_send_enabled is false" do
      @setting.update!(attachment_send_enabled: false)
      attachment = mock_attachment("image.png", filesize: 1.megabyte)

      container = mock("container")
      container.stubs(:respond_to?).with(:attachments).returns(true)
      container.stubs(:attachments).returns([attachment])

      result = @helper.supported_attachment_paths(container)
      assert_equal [], result
    end

    should "return file paths when attachment_send_enabled is true" do
      @setting.update!(attachment_send_enabled: true, attachment_max_size_mb: 3)
      attachment = mock_attachment("image.png", filesize: 1.megabyte)

      container = mock("container")
      container.stubs(:respond_to?).with(:attachments).returns(true)
      container.stubs(:attachments).returns([attachment])

      result = @helper.supported_attachment_paths(container)
      assert_equal ["/path/to/files/image.png"], result
    end

    should "exclude files exceeding attachment_max_size_mb" do
      @setting.update!(attachment_send_enabled: true, attachment_max_size_mb: 2)
      small_file = mock_attachment("small.png", filesize: 1.megabyte)
      large_file = mock_attachment("large.png", filesize: 3.megabytes)

      container = mock("container")
      container.stubs(:respond_to?).with(:attachments).returns(true)
      container.stubs(:attachments).returns([small_file, large_file])

      result = @helper.supported_attachment_paths(container)
      assert_equal ["/path/to/files/small.png"], result
    end

    should "include files at exactly the max size limit" do
      @setting.update!(attachment_send_enabled: true, attachment_max_size_mb: 2)
      exact_file = mock_attachment("exact.png", filesize: 2.megabytes)

      container = mock("container")
      container.stubs(:respond_to?).with(:attachments).returns(true)
      container.stubs(:attachments).returns([exact_file])

      result = @helper.supported_attachment_paths(container)
      assert_equal ["/path/to/files/exact.png"], result
    end

    should "combine size filtering with extension filtering" do
      @setting.update!(attachment_send_enabled: true, attachment_max_size_mb: 2)
      small_supported = mock_attachment("file.png", filesize: 1.megabyte)
      large_supported = mock_attachment("file2.png", filesize: 3.megabytes)
      small_unsupported = mock_attachment("file.exe", filesize: 1.megabyte)

      container = mock("container")
      container.stubs(:respond_to?).with(:attachments).returns(true)
      container.stubs(:attachments).returns([small_supported, large_supported, small_unsupported])

      result = @helper.supported_attachment_paths(container)
      assert_equal ["/path/to/files/file.png"], result
    end
  end
end
